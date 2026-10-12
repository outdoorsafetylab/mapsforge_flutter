import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/cache.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/job/reader_lane.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';

import '../test_asset_bundle.dart';

/// A task the test finishes when it wants to.
class _Task {
  final JobRequest request;

  final Completer<int> completer = Completer<int>();

  bool started = false;

  _Task(this.request);

  Future<int> run() {
    started = true;
    return completer.future;
  }
}

/// A datastore whose reads wait until the test releases them.
class _GatedDatastore extends MemoryDatastore {
  final List<Tile> tilesRead = [];

  final List<Tile> labelsRead = [];

  final Completer<void> gate = Completer<void>();

  @override
  Future<DatastoreBundle> readMapDataSingle(Tile tile) async {
    tilesRead.add(tile);
    await gate.future;
    return super.readMapDataSingle(tile);
  }

  @override
  Future<DatastoreBundle> readLabels(Tile upperLeft, Tile lowerRight) async {
    labelsRead.add(upperLeft);
    await gate.future;
    // the memory datastore reads single tiles only
    return super.readMapDataSingle(upperLeft);
  }
}

void main() {
  Tile tile(int x) => Tile(x, 0, 10, 0);

  /// Lets the lane start what it can.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ReaderLane', () {
    test('runs at most its slots at the same time', () async {
      ReaderLane lane = ReaderLane(2);
      List<_Task> tasks = [for (int i = 0; i < 5; ++i) _Task(JobRequest(tile(i)))];
      List<Future<int>> results = [for (_Task task in tasks) lane.run(task.request, task.run)];
      await settle();
      expect(tasks.where((task) => task.started), hasLength(2));
      expect(lane.running, 2);
      expect(lane.waiting, 3);

      for (int i = 0; i < 5; ++i) {
        tasks[i].completer.complete(i);
        await settle();
        expect(lane.running, lessThanOrEqualTo(2));
      }
      expect(await Future.wait(results), [0, 1, 2, 3, 4]);
      expect(lane.running, 0);
    });

    test('sends the waiting requests by order, the ones of the same order as they arrived', () async {
      ReaderLane lane = ReaderLane(1);
      List<int> started = [];
      _Task blocker = _Task(JobRequest(tile(0)));
      Future<int> first = lane.run(blocker.request, blocker.run);
      List<Future<int>> results = [];
      for (final (x, order) in [(1, 3), (2, 1), (3, 2), (4, 1), (5, 0)]) {
        results.add(
          lane.run(JobRequest.scheduled(tile(x), order: order), () async {
            started.add(x);
            return x;
          }),
        );
      }
      blocker.completer.complete(0);
      await first;
      await Future.wait(results);
      expect(started, [5, 2, 4, 3, 1]);
    });

    test('requests without order or isCancelled are sent as they arrived and never dropped', () async {
      ReaderLane lane = ReaderLane(1);
      List<int> started = [];
      List<Future<int>> results = [
        for (int x = 0; x < 4; ++x)
          lane.run(JobRequest(tile(x)), () async {
            started.add(x);
            return x;
          }),
      ];
      expect(await Future.wait(results), [0, 1, 2, 3]);
      expect(started, [0, 1, 2, 3]);
    });

    test('a request cancelled while waiting is dropped, a request arriving later is sent', () async {
      ReaderLane lane = ReaderLane(1);
      bool cancelled = false;
      _Task blocker = _Task(JobRequest(tile(0)));
      Future<int> first = lane.run(blocker.request, blocker.run);
      _Task old1 = _Task(JobRequest.scheduled(tile(1), isCancelled: () => cancelled));
      _Task old2 = _Task(JobRequest.scheduled(tile(2), isCancelled: () => cancelled, order: 5));
      Future<int> dropped1 = lane.run(old1.request, old1.run);
      Future<int> dropped2 = lane.run(old2.request, old2.run);
      await settle();
      cancelled = true;
      _Task fresh = _Task(JobRequest.scheduled(tile(3), isCancelled: () => false));
      Future<int> sent = lane.run(fresh.request, fresh.run);

      // both cancelled requests are dropped as soon as the lane looks at its waiting requests, not only when they are next
      await expectLater(dropped1, throwsA(isA<JobCancelledException>()));
      await expectLater(dropped2, throwsA(isA<JobCancelledException>()));
      expect(lane.waiting, 1);
      blocker.completer.complete(0);
      await first;
      await settle();
      expect(fresh.started, isTrue);
      fresh.completer.complete(3);
      expect(await sent, 3);
      expect(old1.started, isFalse);
      expect(old2.started, isFalse);
    });

    test('a request cancelled before it arrives is never sent', () async {
      ReaderLane lane = ReaderLane(1);
      _Task task = _Task(JobRequest.scheduled(tile(0), isCancelled: () => true));
      await expectLater(lane.run(task.request, task.run), throwsA(isA<JobCancelledException>()));
      expect(task.started, isFalse);
    });

    test('a failed request frees its slot and passes its error on', () async {
      ReaderLane lane = ReaderLane(1);
      Future<int> failed = lane.run(JobRequest(tile(0)), () async => throw StateError('isolate disposed'));
      Future<int> next = lane.run(JobRequest(tile(1)), () async => 1);
      await expectLater(failed, throwsStateError);
      expect(await next, 1);
      expect(lane.running, 0);
    });

    test('dispose completes the waiting requests, the running ones run to their end', () async {
      ReaderLane lane = ReaderLane(1);
      _Task running = _Task(JobRequest(tile(0)));
      _Task waiting = _Task(JobRequest(tile(1)));
      Future<int> first = lane.run(running.request, running.run);
      Future<int> second = lane.run(waiting.request, waiting.run);
      await settle();
      lane.dispose();
      await expectLater(second, throwsA(isA<JobCancelledException>()));
      await expectLater(lane.run(JobRequest(tile(2)), () async => 2), throwsA(isA<JobCancelledException>()));
      running.completer.complete(0);
      expect(await first, 0);
      expect(waiting.started, isFalse);
    });
  });

  group('DatastoreRenderer', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SymbolCacheMgr().symbolCache = FileSymbolCache();
      SymbolCacheMgr().symbolCache.addLoader("jar:", ImageBundleLoader(bundle: TestAssetBundle("test/cache")));
    });

    List<Tile> tiles(int count) {
      int zoomlevel = 16;
      int x = MercatorProjection.fromZoomlevel(zoomlevel).longitudeToTileX(18);
      int y = MercatorProjection.fromZoomlevel(zoomlevel).latitudeToTileY(46);
      return List.generate(count, (i) => Tile(x + i, y, zoomlevel, 0));
    }

    testWidgets('tiles and labels have their own slots, cancelled tiles do not reach the reader', (WidgetTester tester) async {
      await tester.runAsync(() async {
        Rendertheme renderTheme = await RenderThemeBuilder.createFromFile("test/datastore_renderer/defaultrender.xml");
        _GatedDatastore datastore = _GatedDatastore();
        DatastoreRenderer renderer = DatastoreRenderer(datastore, renderTheme, tileSlots: 2, labelSlots: 1);
        bool cancelled = false;
        List<Tile> requested = tiles(4);
        // the outcome of each request, a result or the error it failed with
        List<Future<Object>> tileResults = [
          for (Tile tile in requested)
            renderer
                .executeJob(JobRequest.scheduled(tile, isCancelled: () => cancelled))
                .then<Object>((result) => result, onError: (Object error) => error),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(datastore.tilesRead, requested.take(2));

        // the tile slots are full, the labels still reach the reader
        Future<JobResult> labels = renderer.retrieveLabels(JobRequest(requested.first, requested.last));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(datastore.labelsRead, [requested.first]);

        cancelled = true;
        datastore.gate.complete();
        List<Object> outcomes = await Future.wait(tileResults);
        expect(outcomes.take(2), everyElement(isA<JobResult>()));
        expect(outcomes.skip(2), everyElement(isA<JobCancelledException>()));
        expect(datastore.tilesRead, requested.take(2));
        expect((await labels).renderInfo, isNotNull);
        for (Object outcome in outcomes.take(2)) {
          (outcome as JobResult).picture?.dispose();
        }
        renderer.dispose();
      });
    });

    testWidgets('dispose completes the tiles still waiting for the reader', (WidgetTester tester) async {
      await tester.runAsync(() async {
        Rendertheme renderTheme = await RenderThemeBuilder.createFromFile("test/datastore_renderer/defaultrender.xml");
        _GatedDatastore datastore = _GatedDatastore();
        DatastoreRenderer renderer = DatastoreRenderer(datastore, renderTheme, tileSlots: 1);
        List<Tile> requested = tiles(3);
        List<Future<Object>> results = [
          for (Tile tile in requested) renderer.executeJob(JobRequest(tile)).then<Object>((result) => result, onError: (Object error) => error),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 50));
        renderer.dispose();
        expect(await Future.wait(results.skip(1)), everyElement(isA<JobCancelledException>()));
        expect(datastore.tilesRead, [requested.first]);
        // the first read keeps running after dispose, its result does not matter here
        datastore.gate.complete();
        Object first = await results.first;
        if (first is JobResult) first.picture?.dispose();
      });
    });
  });
}
