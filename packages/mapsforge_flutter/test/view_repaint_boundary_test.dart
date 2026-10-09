import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_painter.dart';
import 'package:mapsforge_flutter/src/tile/tile_painter.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

/// Renders empty tiles and no labels.
class _EmptyRenderer extends Renderer {
  @override
  Future<JobResult> executeJob(JobRequest jobRequest) async {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    return JobResult.normal(TilePicture.fromPicture(recorder.endRecording()));
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async => JobResult.normalLabels(RenderInfoCollection([]));

  @override
  String getRenderKey() => 'empty';

  @override
  bool supportLabels() => true;
}

void main() {
  testWidgets('tiles and labels are painted in layers of their own', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _EmptyRenderer renderer = _EmptyRenderer();
      MapModel mapModel = MapModel(renderer: renderer);
      mapModel.setPosition(MapPosition(46, 18, 16));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              TileView(mapModel: mapModel, renderer: renderer),
              LabelView(mapModel: mapModel, renderer: renderer),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      List<RenderCustomPaint> painters = tester.allRenderObjects.whereType<RenderCustomPaint>().toList();
      RenderCustomPaint tiles = painters.singleWhere((RenderCustomPaint p) => p.foregroundPainter is TilePainter);
      RenderCustomPaint labels = painters.singleWhere((RenderCustomPaint p) => p.foregroundPainter is LabelPainter);
      // a sibling repainting (a marker, a scale bar) must not paint them again
      expect(tiles.parent, isA<RenderRepaintBoundary>());
      expect(labels.parent, isA<RenderRepaintBoundary>());

      await tester.pumpWidget(const SizedBox());
      await mapModel.dispose();
    });
  });
}
