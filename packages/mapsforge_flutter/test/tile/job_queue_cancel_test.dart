import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class _Held {
  final JobRequest request;

  final Completer<JobResult> completer = Completer<JobResult>();

  _Held(this.request);

  bool get cancelled => request.isCancelled?.call() ?? false;
}

/// Holds every request until the test answers it. [dropCancelled] does what the reader lane of the [DatastoreRenderer]
/// does with requests whose job was cancelled before they were sent.
class _HoldingRenderer extends Renderer {
  /// Answers every request at once if true.
  bool instant = false;

  final List<_Held> held = [];

  /// Every request received, in the order received.
  final List<JobRequest> received = [];

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) {
    received.add(jobRequest);
    if (instant) return Future.value(_picture());
    _Held request = _Held(jobRequest);
    held.add(request);
    return request.completer.future;
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) {
    received.add(jobRequest);
    if (instant) return Future.value(JobResult.normalLabels(RenderInfoCollection([])));
    _Held request = _Held(jobRequest);
    held.add(request);
    return request.completer.future;
  }

  static JobResult _picture() {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return JobResult.normal(TilePicture.fromPicture(recorder.endRecording()));
  }

  /// Drops the held requests whose job was cancelled.
  void dropCancelled() {
    held.removeWhere((request) {
      if (!request.cancelled) return false;
      request.completer.completeError(JobCancelledException(request.request.tile));
      return true;
    });
  }

  /// Answers the held requests, a picture for tiles and empty labels for label blocks.
  void answer({bool Function(_Held)? where}) {
    List<_Held> answered = held.where(where ?? (_) => true).toList();
    held.removeWhere(answered.contains);
    for (_Held request in answered) {
      request.completer.complete(request.request.rightLower == null ? _picture() : JobResult.normalLabels(RenderInfoCollection([])));
    }
  }

  @override
  String getRenderKey() => 'holding';

  @override
  bool supportLabels() => true;
}

void main() {
  const double width = 1080;
  const double height = 2340;
  final MapPosition position = MapPosition(46, 18, 17);
  // the view moved a little: most of its tiles and label blocks are the same as at [position]
  final MapPosition nearby = MapPosition(46.0002, 18.0002, 17);
  // the view moved far: none of its tiles or label blocks are the same as at [position]
  final MapPosition far = MapPosition(10, 18, 17);
  final int farTileY = position.projection.latitudeToTileY(10);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  /// Answers every request until none is left, also the ones made while answering.
  Future<void> answerAll(_HoldingRenderer renderer) async {
    await settle();
    while (renderer.held.isNotEmpty) {
      renderer.answer();
      await settle();
    }
  }

  group('TileJobQueue', () {
    /// The number of tiles a view at [at] shows when nothing is cancelled.
    Future<int> tilesAt(MapPosition at) async {
      _HoldingRenderer renderer = _HoldingRenderer()..instant = true;
      MapModel mapModel = MapModel(renderer: renderer);
      TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(width, height);
      queue.setPosition(at);
      await settle();
      int count = queue.tileSet!.images.length;
      queue.dispose();
      await mapModel.dispose();
      return count;
    }

    testWidgets('dropped tiles are not kept in the cache', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        TileCache cache = TileCache();
        MapModel mapModel = MapModel(renderer: renderer);
        TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        List<Tile> dropped = [for (_Held request in renderer.held) request.request.tile];
        expect(dropped, isNotEmpty);

        queue.setPosition(far);
        expect(renderer.held.every((request) => request.cancelled), isTrue);
        renderer.dropCancelled();
        await settle();
        for (Tile tile in dropped) {
          expect(cache.get(tile), isNull);
        }
        await answerAll(renderer);
        expect(queue.tileSet!.images, hasLength(await tilesAt(far)));
        expect(queue.tileSet!.images.keys.every((tile) => (tile.tileY - farTileY).abs() < 10), isTrue);

        queue.dispose();
        cache.dispose();
        await mapModel.dispose();
      });
    });

    testWidgets('a tile the new job waited for in a dropped request of the old job is produced again', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        List<_Held> old = List.of(renderer.held);

        queue.setPosition(nearby);
        // one request of the old job is answered, its place in the task queue goes to the new job, which waits for the
        // tiles the old job still waits for
        renderer.answer(where: (request) => request == old.first);
        await settle();
        Set<Tile> shared = {for (_Held request in old.skip(1)) request.request.tile};
        expect(renderer.held.where((request) => request.cancelled).map((request) => request.request.tile).toSet(), shared);

        renderer.dropCancelled();
        await settle();
        // the new job asked for these tiles again
        expect(renderer.held.map((request) => request.request.tile).toSet().intersection(shared), isNotEmpty);
        await answerAll(renderer);
        expect(queue.tileSet!.images.keys, containsAll(shared));
        expect(queue.tileSet!.images, hasLength(await tilesAt(nearby)));

        queue.dispose();
        await mapModel.dispose();
      });
    });

    testWidgets('after scaling kept the job, moving the map cancels every request of that job', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        int requested = renderer.received.length;

        // pinching in shows less than the prepared tiles
        MapPosition scaled = position.scaleAround(null, 1.2);
        queue.setPosition(scaled);
        await settle();
        // scaling within the prepared tiles keeps the job and makes no new requests
        expect(queue.tileSet!.mapPosition, scaled);
        expect(renderer.held.where((request) => request.cancelled), isEmpty);
        expect(renderer.received, hasLength(requested));

        queue.setPosition(far);
        expect(renderer.held.every((request) => request.cancelled), isTrue);
        renderer.dropCancelled();
        await answerAll(renderer);
        // none of the tiles still queued for the first job reached the renderer
        expect(renderer.received.skip(requested).every((request) => (request.tile.tileY - farTileY).abs() < 10), isTrue);
        expect(queue.tileSet!.images, hasLength(await tilesAt(far)));

        queue.dispose();
        await mapModel.dispose();
      });
    });
  });

  group('LabelJobQueue', () {
    /// The number of label blocks a view at [at] shows when nothing is cancelled.
    Future<int> blocksAt(MapPosition at) async {
      _HoldingRenderer renderer = _HoldingRenderer()..instant = true;
      MapModel mapModel = MapModel(renderer: renderer);
      mapModel.setPosition(at);
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(width, height);
      queue.setPosition(at);
      await settle();
      int count = queue.labelSet.jobLabels.blockCount;
      queue.dispose();
      await mapModel.dispose();
      return count;
    }

    testWidgets('dropped label blocks are not kept in the cache', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        MemoryLabelCache cache = MemoryLabelCache.create();
        MapModel mapModel = MapModel(renderer: renderer);
        mapModel.setPosition(position);
        LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        List<Tile> dropped = [for (_Held request in renderer.held) request.request.tile];
        expect(dropped, isNotEmpty);

        queue.setPosition(far);
        expect(renderer.held.every((request) => request.cancelled), isTrue);
        renderer.dropCancelled();
        await settle();
        for (Tile tile in dropped) {
          expect(cache.get(tile), isNull);
        }
        await answerAll(renderer);
        expect(queue.labelSet.jobLabels.blockCount, await blocksAt(far));

        queue.dispose();
        cache.dispose();
        await mapModel.dispose();
      });
    });

    testWidgets('a block the new job waited for in a dropped request of the old job is retrieved again', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        mapModel.setPosition(position);
        LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        List<_Held> old = List.of(renderer.held);
        expect(old.length, greaterThan(1));

        queue.setPosition(nearby);
        renderer.answer(where: (request) => request == old.first);
        await settle();
        Set<Tile> shared = {for (_Held request in old.skip(1)) request.request.tile};
        expect(renderer.held.where((request) => request.cancelled).map((request) => request.request.tile).toSet(), shared);

        renderer.dropCancelled();
        await settle();
        expect(renderer.held.map((request) => request.request.tile).toSet().intersection(shared), isNotEmpty);
        await answerAll(renderer);
        expect(queue.labelSet.jobLabels.blockCount, await blocksAt(nearby));

        queue.dispose();
        await mapModel.dispose();
      });
    });

    testWidgets('after scaling kept the job, moving the map cancels every request of that job', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _HoldingRenderer renderer = _HoldingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        mapModel.setPosition(position);
        LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
        queue.setSize(width, height);
        queue.setPosition(position);
        await settle();
        int requested = renderer.received.length;
        JobLabels labels = queue.labelSet.jobLabels;

        // pinching in shows less than the prepared tiles
        MapPosition scaled = position.scaleAround(null, 1.2);
        queue.setPosition(scaled);
        await settle();
        expect(queue.labelSet.jobLabels, same(labels));
        expect(renderer.held.where((request) => request.cancelled), isEmpty);
        expect(renderer.received, hasLength(requested));

        queue.setPosition(far);
        expect(renderer.held.every((request) => request.cancelled), isTrue);
        renderer.dropCancelled();
        await answerAll(renderer);
        expect(renderer.received.skip(requested).every((request) => (request.tile.tileY - farTileY).abs() < 10), isTrue);
        expect(queue.labelSet.jobLabels.blockCount, await blocksAt(far));

        queue.dispose();
        await mapModel.dispose();
      });
    });
  });
}
