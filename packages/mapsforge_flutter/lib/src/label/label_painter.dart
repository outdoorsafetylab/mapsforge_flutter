import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class LabelPainter extends CustomPainter {
  final LabelSet labelSet;

  LabelPainter(this.labelSet);

  @override
  void paint(Canvas canvas, Size size) {
    UiCanvas uiCanvas = UiCanvas(canvas, size);
    Mappoint center = labelSet.getCenter();
    PixelProjection projection = labelSet.mapPosition.projection;
    UiRenderContext renderContext = UiRenderContext(
      canvas: uiCanvas,
      reference: center,
      projection: projection,
      rotationRadian: labelSet.mapPosition.rotationRadian,
    );
    MapRectangle visible = _visibleBoundary(size);
    for (RenderInfoCollection renderInfoCollection in labelSet.renderInfos) {
      for (var renderInfo in renderInfoCollection.renderInfos) {
        // The label set covers blocks of 5x5 tiles around the view, most of which are off-screen.
        // Painting a caption is expensive (paragraph layout), so skip everything outside the view.
        if (!renderInfo.getBoundaryAbsolute().intersects(visible)) continue;
        renderInfo.render(renderContext);
      }
    }
  }

  /// The area of the map (in absolute pixel coordinates of the current zoom level) that is visible on screen.
  ///
  /// [size] is the size of this painter in logical pixels. The parent [TransformWidget] scales the canvas by
  /// 1/deviceScaleFactor, applies the pinch-zoom scale and rotates around the center of the screen, so the
  /// visible area is a rectangle of size * deviceScaleFactor / scale map pixels around the current map center.
  /// A rotated view is covered by its circumscribed square; the estimated text boundaries are padded a bit.
  MapRectangle _visibleBoundary(Size size) {
    MapPosition mapPosition = labelSet.mapPosition;
    double factor = MapsforgeSettingsMgr().getDeviceScaleFactor() / mapPosition.scale;
    double halfWidth = size.width * factor / 2;
    double halfHeight = size.height * factor / 2;
    if (mapPosition.rotationRadian != 0) {
      halfWidth = halfHeight = sqrt(halfWidth * halfWidth + halfHeight * halfHeight);
    }
    double padding = max(halfWidth, halfHeight) * 0.1;
    Mappoint center = mapPosition.getCenter();
    return MapRectangle(center.x - halfWidth - padding, center.y - halfHeight - padding, center.x + halfWidth + padding, center.y + halfHeight + padding);
  }

  @override
  bool shouldRepaint(covariant LabelPainter oldDelegate) {
    if (oldDelegate.labelSet != labelSet) return true;
    return false;
  }
}
