import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class LabelPainter extends CustomPainter {
  final LabelJobQueue labelJobQueue;

  LabelPainter(this.labelJobQueue) : super(repaint: labelJobQueue);

  @override
  void paint(Canvas canvas, Size size) {
    UiCanvas uiCanvas = UiCanvas(canvas, size);
    LabelSet labelSet = labelJobQueue.labelSet;
    Mappoint center = labelSet.getCenter();
    PixelProjection projection = labelSet.mapPosition.projection;
    UiRenderContext renderContext = UiRenderContext(
      canvas: uiCanvas,
      reference: center,
      projection: projection,
      rotationRadian: labelSet.mapPosition.rotationRadian,
    );
    MapRectangle visible = visibleBoundary(labelSet.mapPosition, size);
    bool rotated = labelSet.mapPosition.rotationRadian != 0;
    for (RenderInfoCollection renderInfoCollection in labelSet.renderInfos) {
      for (var renderInfo in renderInfoCollection.renderInfos) {
        // The label set covers blocks of 5x5 tiles around the view, most of which are off-screen.
        // Painting a caption is expensive (paragraph layout), so skip everything outside the view.
        if (!cullBoundary(renderInfo, projection, rotated).intersects(visible)) continue;
        renderInfo.render(renderContext);
      }
    }
  }

  /// The area of the map (in absolute pixel coordinates of the current zoom level) that is visible on screen.
  ///
  /// [size] is the size of the painter in logical pixels; see [TileHelper.visibleArea]. The result is padded a bit
  /// since label boundaries are estimates.
  static MapRectangle visibleBoundary(MapPosition mapPosition, Size size) {
    double deviceScaleFactor = MapsforgeSettingsMgr().getDeviceScaleFactor();
    MapRectangle visible = TileHelper.visibleArea(mapPosition, size.width * deviceScaleFactor, size.height * deviceScaleFactor);
    double padding = max(visible.getWidth(), visible.getHeight()) / 2 * 0.1;
    return MapRectangle(visible.left - padding, visible.top - padding, visible.right + padding, visible.bottom + padding);
  }

  /// The area (in absolute map pixels) that painting [renderInfo] can touch, for the visibility check.
  ///
  /// A node's boundary is the label box around the node, which is what gets painted on a north-up map. A way's
  /// boundary is the way's geometry, but its caption or symbol is painted around the way's center and a path text
  /// along the way, all of which can stick out of the geometry by the label's own size. On a [rotated] map labels
  /// are counter-rotated around their anchor, so they are covered by the box's reach in every direction.
  static MapRectangle cullBoundary(RenderInfo renderInfo, PixelProjection projection, bool rotated) {
    MapRectangle boundary = renderInfo.getBoundaryAbsolute();
    if (renderInfo is RenderInfoNode) {
      if (!rotated) return boundary;
      Mappoint anchor = renderInfo.nodeProperties.getCoordinatesAbsolute();
      double reach = max((boundary.left - anchor.x).abs(), (boundary.right - anchor.x).abs()) + max((boundary.top - anchor.y).abs(), (boundary.bottom - anchor.y).abs());
      return MapRectangle(anchor.x - reach, anchor.y - reach, anchor.x + reach, anchor.y + reach);
    }
    if (renderInfo is RenderInfoWay) {
      MapRectangle label = renderInfo.renderInstruction.getBoundary(renderInfo);
      double reach = max(label.left.abs(), label.right.abs()) + max(label.top.abs(), label.bottom.abs());
      Mappoint anchor = renderInfo.wayProperties.getCenterAbsolute(projection);
      return MapRectangle(
        min(boundary.left, anchor.x) - reach,
        min(boundary.top, anchor.y) - reach,
        max(boundary.right, anchor.x) + reach,
        max(boundary.bottom, anchor.y) + reach,
      );
    }
    return boundary;
  }

  @override
  bool shouldRepaint(covariant LabelPainter oldDelegate) {
    if (oldDelegate.labelJobQueue.labelSet != labelJobQueue.labelSet) return true;
    return false;
  }
}
