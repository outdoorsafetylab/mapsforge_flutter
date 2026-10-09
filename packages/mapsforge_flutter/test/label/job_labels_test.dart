import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';

/// A label with a fixed box, colliding like [RenderInfoNode].
class _Box extends RenderInfo<Renderinstruction> {
  final MapRectangle box;

  final String name;

  _Box(this.name, double left, double top, double right, double bottom, {int priority = 0, bool always = false})
    : box = MapRectangle(left, top, right, bottom),
      super(
        RenderinstructionCaption(0)
          ..priority = priority
          ..display = always ? MapDisplay.ALWAYS : MapDisplay.IFSPACE,
        caption: name,
      );

  @override
  void render(RenderContext renderContext) {}

  @override
  bool clashesWith(RenderInfo other) {
    if (MapDisplay.ALWAYS == renderInstruction.display || MapDisplay.ALWAYS == other.renderInstruction.display) return false;
    return box.intersects(other.getBoundaryAbsolute());
  }

  @override
  bool intersects(MapRectangle other) => box.intersects(other);

  @override
  MapRectangle getBoundaryAbsolute() => box;

  @override
  String toString() => name;
}

List<String> names(List<RenderInfo> labels) => [for (RenderInfo label in labels) (label as _Box).name]..sort();

/// Answers each label request when the test says so, with the labels [labelsFor] gives for the block.
class _BlockRenderer extends Renderer {
  final List<RenderInfo> Function(Tile leftUpper) labelsFor;

  final Map<Tile, Completer<void>> pending = {};

  /// The blocks asked for, as (left upper, right lower).
  final List<(Tile, Tile?)> requests = [];

  _BlockRenderer(this.labelsFor);

  /// Lets the request for the block at [leftUpper] finish.
  void deliver(Tile leftUpper) => pending[leftUpper]!.complete();

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) => throw UnimplementedError();

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async {
    requests.add((jobRequest.tile, jobRequest.rightLower));
    Completer<void> completer = pending.putIfAbsent(jobRequest.tile, () => Completer<void>());
    await completer.future;
    return JobResult.normalLabels(RenderInfoCollection(labelsFor(jobRequest.tile)));
  }

  @override
  String getRenderKey() => 'blocks';

  @override
  bool supportLabels() => true;
}

void main() {
  final Tile left = Tile(0, 0, 10, 0);
  final Tile right = Tile(5, 0, 10, 0);
  final MapRectangle everywhere = const MapRectangle(-1e6, -1e6, 1e6, 1e6);

  group('JobLabels', () {
    test('of two overlapping labels across a block border only the higher priority one stays', () {
      JobLabels labels = JobLabels(everywhere);
      labels.addAll({
        left: RenderInfoCollection([_Box('low', 0, 0, 20, 10, priority: 1)]),
      });
      expect(names(labels.labels), ['low']);
      labels.addAll({
        right: RenderInfoCollection([_Box('high', 10, 0, 30, 10, priority: 2)]),
      });
      expect(names(labels.labels), ['high']);
    });

    test('labels displayed always stay even when they overlap', () {
      JobLabels labels = JobLabels(everywhere);
      labels.addAll({
        left: RenderInfoCollection([_Box('one', 0, 0, 20, 10, always: true)]),
        right: RenderInfoCollection([_Box('other', 10, 0, 30, 10, priority: 5)]),
      });
      expect(names(labels.labels), ['one', 'other']);
    });

    test('the order the blocks arrive in does not matter', () {
      // same priority, same top and left, no position to tell A and B apart: who comes first decides about C
      Map<Tile, RenderInfoCollection> blocks = {
        Tile(0, 0, 10, 0): RenderInfoCollection([_Box('A', 0, 0, 10, 10)]),
        Tile(5, 0, 10, 0): RenderInfoCollection([_Box('B', 0, 0, 20, 10)]),
        Tile(0, 5, 10, 0): RenderInfoCollection([_Box('C', 15, 0, 25, 10)]),
      };
      List<Tile> order = blocks.keys.toList();
      List<List<Tile>> permutations = [
        for (Tile first in order)
          for (Tile second in order)
            if (second != first) [first, second, ...order.where((Tile tile) => tile != first && tile != second)],
      ];
      expect(permutations, hasLength(6));
      for (List<Tile> permutation in permutations) {
        JobLabels oneByOne = JobLabels(everywhere);
        for (Tile tile in permutation) {
          oneByOne.addAll({tile: blocks[tile]!});
        }
        // the block with the topmost, then leftmost left upper tile wins ties
        expect(names(oneByOne.labels), ['A', 'C'], reason: 'arrival order $permutation');
      }
    });

    test('within a block the labels keep their order', () {
      JobLabels labels = JobLabels(everywhere);
      labels.addAll({
        left: RenderInfoCollection([_Box('B', 0, 0, 20, 10), _Box('A', 0, 0, 10, 10), _Box('C', 15, 0, 25, 10)]),
      });
      expect(names(labels.labels), ['B']);
    });

    test('a label read by two blocks is shown once', () {
      JobLabels labels = JobLabels(everywhere);
      labels.addAll({
        left: RenderInfoCollection([_Box('road', 100, 0, 140, 10)]),
        right: RenderInfoCollection([_Box('road', 100, 0, 140, 10)]),
      });
      expect(names(labels.labels), ['road']);
    });

    test('labels outside the job area take no part', () {
      JobLabels labels = JobLabels(const MapRectangle(0, 0, 100, 100));
      labels.addAll({
        left: RenderInfoCollection([_Box('inside', 90, 0, 110, 10, priority: 1), _Box('outside', 150, 0, 170, 10, priority: 2)]),
        right: RenderInfoCollection([_Box('beyond', 95, 0, 200, 10, priority: 3)]),
      });
      // 'beyond' reaches into the area and wins over 'inside', 'outside' does not touch the area
      expect(names(labels.labels), ['beyond']);
    });

    test('the blocks are not changed', () {
      RenderInfoCollection one = RenderInfoCollection([_Box('low', 0, 0, 20, 10, priority: 1), _Box('far', 500, 0, 520, 10)]);
      RenderInfoCollection other = RenderInfoCollection([_Box('high', 10, 0, 30, 10, priority: 2)]);
      JobLabels labels = JobLabels(const MapRectangle(0, 0, 100, 100));
      labels.addAll({left: one, right: other});
      expect(names(labels.labels), ['high']);
      expect(names(one.renderInfos), ['far', 'low']);
      expect(names(other.renderInfos), ['high']);
    });

    test('blocks arriving after the job was aborted are dropped', () {
      JobLabels labels = JobLabels(everywhere);
      labels.addAll({
        left: RenderInfoCollection([_Box('first', 0, 0, 10, 10)]),
      });
      labels.abort();
      expect(
        labels.addAll({
          right: RenderInfoCollection([_Box('late', 100, 0, 110, 10)]),
        }),
        isFalse,
      );
      expect(names(labels.labels), ['first']);
    });
  });

  group('LabelJobQueue', () {
    // a view of 300 x 300 pixels centered on the border between two blocks, horizontally in the middle of a block
    const int zoom = 17;
    const double size = 300;
    final double tileSize = MapsforgeSettingsMgr().tileSize;
    final PixelProjection projection = PixelProjection(zoom);
    const int blockX = 5000;
    const int blockY = 7000;
    final double centerX = (blockX + 2.5) * tileSize;
    final double centerY = blockY * tileSize;
    final ILatLong center = projection.pixelToLatLong(centerX, centerY);
    final MapPosition position = MapPosition(center.latitude, center.longitude, zoom);
    final Tile above = Tile(blockX, blockY - 5, zoom, 0);
    final Tile below = Tile(blockX, blockY, zoom, 0);
    const Duration settle = Duration(milliseconds: 50);

    test('blocks arriving one after another are collided with each other, the cached blocks stay as they are', () async {
      _BlockRenderer renderer = _BlockRenderer(
        (Tile leftUpper) => [
          leftUpper == above
              ? _Box('above', centerX - 20, centerY - 15, centerX + 20, centerY + 5, priority: 1)
              : _Box('below', centerX - 20, centerY - 5, centerX + 20, centerY + 15, priority: 2),
        ],
      );
      MapModel mapModel = MapModel(renderer: renderer);
      MemoryLabelCache cache = MemoryLabelCache.create();
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
      queue.setSize(size, size);
      queue.setPosition(position);
      await Future<void>.delayed(settle);
      expect(renderer.pending.keys, unorderedEquals([above, below]));

      renderer.deliver(above);
      await Future<void>.delayed(settle);
      expect(names(queue.labelSet.labels), ['above']);
      renderer.deliver(below);
      await Future<void>.delayed(settle);
      expect(names(queue.labelSet.labels), ['below']);
      expect(names(cache.get(above)!.renderInfos), ['above']);
      expect(names(cache.get(below)!.renderInfos), ['below']);

      queue.dispose();
      cache.dispose();
      await mapModel.dispose();
    });

    test('a block arriving after the view was rotated is shown', () async {
      _BlockRenderer renderer = _BlockRenderer(
        (Tile leftUpper) => [
          leftUpper == above
              ? _Box('above', centerX - 20, centerY - 60, centerX + 20, centerY - 40)
              : _Box('below', centerX - 20, centerY + 40, centerX + 20, centerY + 60),
        ],
      );
      MapModel mapModel = MapModel(renderer: renderer);
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(size, size);
      queue.setPosition(position);
      await Future<void>.delayed(settle);
      renderer.deliver(above);
      await Future<void>.delayed(settle);
      JobLabels jobLabels = queue.labelSet.jobLabels;

      MapPosition rotated = MapPosition(center.latitude, center.longitude, zoom, 0, 10);
      queue.setPosition(rotated);
      expect(queue.labelSet.mapPosition, rotated);
      expect(queue.labelSet.jobLabels, same(jobLabels), reason: 'the rotation keeps the job');
      expect(names(queue.labelSet.labels), ['above']);

      renderer.deliver(below);
      await Future<void>.delayed(settle);
      expect(queue.labelSet.mapPosition, rotated);
      expect(names(queue.labelSet.labels), ['above', 'below']);

      queue.dispose();
      await mapModel.dispose();
    });

    test('a view reaching beyond the job tiles starts another job, even if the blocks cover it', () async {
      _BlockRenderer renderer = _BlockRenderer((Tile leftUpper) => const []);
      MapModel mapModel = MapModel(renderer: renderer);
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(size, size);
      queue.setPosition(position);
      await Future<void>.delayed(settle);
      JobLabels jobLabels = queue.labelSet.jobLabels;
      // the visible tiles are the two around the border, the job's tiles one more on each side
      expect(jobLabels.area.top, (blockY - 2) * tileSize);
      expect(jobLabels.area.bottom, (blockY + 2) * tileSize);

      // pinching out to show 2.4 tiles around the center stays within the blocks, not within the job's tiles
      MapPosition pinched = position.scaleAround(const Offset(size / 2, size / 2), size / (4.8 * tileSize));
      queue.setPosition(pinched);
      expect(queue.labelSet.mapPosition, pinched);
      expect(queue.labelSet.jobLabels, isNot(same(jobLabels)));
      expect(jobLabels.aborted, isTrue);
      await Future<void>.delayed(settle);
      expect(renderer.pending.keys, unorderedEquals([above, below]), reason: 'no other blocks were needed');

      queue.dispose();
      await mapModel.dispose();
    });
  });

  group('label blocks', () {
    Future<List<(Tile, Tile?)>> requestsAt(int zoom) async {
      _BlockRenderer renderer = _BlockRenderer((Tile leftUpper) => const []);
      MapModel mapModel = MapModel(renderer: renderer);
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(1080, 1900);
      queue.setPosition(MapPosition(25.05, 121.5, zoom));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      queue.dispose();
      await mapModel.dispose();
      return renderer.requests;
    }

    test('are 3 x 3 tiles up to zoom 13 and 5 x 5 above', () async {
      for (int zoom in [10, 11, 12, 13, 14, 15, 17]) {
        int range = zoom <= 13 ? 3 : 5;
        expect(LabelJobQueue.rangeAt(zoom), range);
        List<(Tile, Tile?)> requests = await requestsAt(zoom);
        expect(requests, isNotEmpty);
        for (final (Tile leftUpper, Tile? rightLower) in requests) {
          expect(leftUpper.tileX % range, 0, reason: 'z$zoom $leftUpper');
          expect(leftUpper.tileY % range, 0, reason: 'z$zoom $leftUpper');
          expect(rightLower!.tileX - leftUpper.tileX, range - 1, reason: 'z$zoom');
          expect(rightLower.tileY - leftUpper.tileY, range - 1, reason: 'z$zoom');
        }
      }
    });
  });
}
