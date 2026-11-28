import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// A renderer whose jobs wait until [release] and then fail, like the jobs of a renderer that is disposed while they
/// are in flight.
class _FailingRenderer extends Renderer {
  final Completer<void> release = Completer<void>();
  int tileJobs = 0;
  int labelJobs = 0;

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) async {
    ++tileJobs;
    await release.future;
    throw StateError('renderer disposed');
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async {
    ++labelJobs;
    await release.future;
    throw StateError('renderer disposed');
  }

  @override
  String getRenderKey() => 'failing';

  @override
  bool supportLabels() => true;
}

Future<void> _until(bool Function() condition) async {
  for (int i = 0; i < 200 && !condition(); ++i) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('a tile job failing after the queue is disposed reports no error', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _FailingRenderer renderer = _FailingRenderer();
      MapModel mapModel = MapModel(renderer: renderer);
      TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(256, 256);
      queue.setPosition(MapPosition(43.74, 7.42, 15));
      await _until(() => renderer.tileJobs > 0);
      queue.dispose();
      renderer.release.complete();
      await Future.delayed(const Duration(milliseconds: 100));
      await mapModel.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('a label job failing after the queue is disposed reports no error', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _FailingRenderer renderer = _FailingRenderer();
      MapModel mapModel = MapModel(renderer: renderer);
      LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
      queue.setSize(256, 256);
      queue.setPosition(MapPosition(43.74, 7.42, 15));
      await _until(() => renderer.labelJobs > 0);
      queue.dispose();
      renderer.release.complete();
      await Future.delayed(const Duration(milliseconds: 100));
      await mapModel.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
