import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

/// Counts the jobs it is given and renders empty tiles.
class _CountingRenderer extends Renderer {
  int tileJobs = 0;

  int labelJobs = 0;

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) async {
    ++tileJobs;
    ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return JobResult.normal(TilePicture.fromPicture(recorder.endRecording()));
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async {
    ++labelJobs;
    return JobResult.normalLabels(RenderInfoCollection([]));
  }

  @override
  String getRenderKey() => 'counting';

  @override
  bool supportLabels() => true;
}

/// Whether the graphics of [picture] have been released.
bool disposed(TilePicture picture) => picture.getPicture()!.debugDisposed;

void main() {
  const double width = 1080;
  const double height = 2340;
  final MapPosition position = MapPosition(46, 18, 17);
  const Duration settle = Duration(milliseconds: 300);

  group('TileCache', () {
    testWidgets('a view built again shows the tiles the previous one rendered', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _CountingRenderer renderer = _CountingRenderer();
        TileCache cache = TileCache();
        MapModel mapModel = MapModel(renderer: renderer);

        TileJobQueue first = TileJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        first.setSize(width, height);
        first.setPosition(position);
        await Future<void>.delayed(settle);
        int rendered = renderer.tileJobs;
        expect(rendered, greaterThan(0));
        Map<Tile, TilePicture> shown = Map.of(first.tileSet!.images);
        expect(shown, hasLength(rendered));
        first.dispose();

        // the cache outlives the queue that filled it: its tiles are not disposed
        expect(shown.values.where(disposed), isEmpty);

        TileJobQueue second = TileJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        second.setSize(width, height);
        second.setPosition(position);
        await Future<void>.delayed(settle);
        expect(renderer.tileJobs, rendered);
        expect(second.tileSet!.images, shown);
        second.dispose();
        expect(shown.values.where(disposed), isEmpty);

        cache.dispose();
        expect(shown.values.every(disposed), isTrue);
        await mapModel.dispose();
      });
    });

    test('a tile that could not be rendered is rendered again on the next request', () async {
      TileCache cache = TileCache();
      Tile tile = Tile(1, 2, 3, 0);
      await expectLater(cache.getOrProduce(tile, (_) async => throw StateError('isolate disposed')), throwsStateError);
      TilePicture? picture = await cache.getOrProduce(tile, (_) async => null);
      expect(picture, isNull);
      cache.dispose();
    });

    test('a request in progress is shared, not repeated', () async {
      TileCache cache = TileCache();
      Tile tile = Tile(1, 2, 3, 0);
      int produced = 0;
      Future<TilePicture?> producer(Tile _) async {
        ++produced;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return null;
      }

      await Future.wait([cache.getOrProduce(tile, producer), cache.getOrProduce(tile, producer)]);
      expect(produced, 1);
      cache.dispose();
    });
  });

  group('MemoryLabelCache', () {
    testWidgets('a view built again shows the labels the previous one retrieved', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _CountingRenderer renderer = _CountingRenderer();
        MemoryLabelCache cache = MemoryLabelCache.create();
        MapModel mapModel = MapModel(renderer: renderer);
        mapModel.setPosition(position);

        LabelJobQueue first = LabelJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        first.setSize(width, height);
        first.setPosition(position);
        await Future<void>.delayed(settle);
        int retrieved = renderer.labelJobs;
        expect(retrieved, greaterThan(0));
        expect(first.labelSet.renderInfos, hasLength(retrieved));
        first.dispose();

        LabelJobQueue second = LabelJobQueue(mapModel: mapModel, renderer: renderer, cache: cache);
        second.setSize(width, height);
        second.setPosition(position);
        await Future<void>.delayed(settle);
        expect(renderer.labelJobs, retrieved);
        expect(second.labelSet.renderInfos, hasLength(retrieved));
        second.dispose();

        cache.dispose();
        await mapModel.dispose();
      });
    });

    test('labels that could not be retrieved are retrieved again on the next request', () async {
      MemoryLabelCache cache = MemoryLabelCache.create();
      Tile leftUpper = Tile(0, 0, 3, 0);
      Tile rightLower = Tile(4, 4, 3, 0);
      await expectLater(cache.getOrProduce(leftUpper, rightLower, (_) async => throw StateError('isolate disposed')), throwsStateError);
      RenderInfoCollection labels = await cache.getOrProduce(leftUpper, rightLower, (_) async => RenderInfoCollection([]));
      expect(labels.renderInfos, isEmpty);
      cache.dispose();
    });

    testWidgets('two live views keep labels of their own', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _CountingRenderer renderer = _CountingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        MapPosition elsewhere = MapPosition(47, 19, 17);

        LabelJobQueue one = LabelJobQueue(mapModel: mapModel, renderer: renderer);
        LabelJobQueue other = LabelJobQueue(mapModel: mapModel, renderer: renderer);
        one.setSize(width, height);
        other.setSize(width, height);
        one.setPosition(position);
        other.setPosition(elsewhere);
        await Future<void>.delayed(settle);
        expect(one.labelSet.mapPosition, position);
        expect(other.labelSet.mapPosition, elsewhere);

        // disposing one view leaves the other one's labels alone
        other.dispose();
        one.setPosition(MapPosition(46, 18, 16));
        await Future<void>.delayed(settle);
        expect(one.labelSet.mapPosition.zoomlevel, 16);
        expect(one.labelSet.renderInfos, isNotEmpty);
        one.dispose();
        await mapModel.dispose();
      });
    });
  });
}
