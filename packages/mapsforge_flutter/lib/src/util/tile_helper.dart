import 'dart:math';
import 'dart:ui';

import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/tile/tile_dimension.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';

class TileHelper {
  /// Tiles prepared around the visible ones, so that a small move does not show empty space.
  static const int margin = 1;

  /// The tiles a view of [screensize] (physical pixels) needs for [mapViewPosition]: `left`..`bottom` are the
  /// tiles of [visibleArea], `minLeft`..`minBottom` add [margin] tiles around them.
  static TileDimension calculateTiles({required MapPosition mapViewPosition, required MapSize screensize}) {
    final session = PerformanceProfiler().startSession(category: "TileDimension");
    MapRectangle visible = visibleArea(mapViewPosition, screensize.width, screensize.height);
    PixelProjection projection = mapViewPosition.projection;
    double mapsize = projection.mapsize.toDouble();
    int tileLeft = projection.pixelXToTileX(min(max(visible.left, 0), mapsize));
    int tileRight = projection.pixelXToTileX(min(max(visible.right, 0), mapsize));
    int tileTop = projection.pixelYToTileY(min(max(visible.top, 0), mapsize));
    int tileBottom = projection.pixelYToTileY(min(max(visible.bottom, 0), mapsize));
    int maxTileNumber = Tile.getMaxTileNumber(mapViewPosition.zoomlevel);
    session.complete();

    return TileDimension(
      minLeft: max(tileLeft - margin, 0),
      minRight: min(tileRight + margin, maxTileNumber),
      minTop: max(tileTop - margin, 0),
      minBottom: min(tileBottom + margin, maxTileNumber),
      left: tileLeft,
      right: tileRight,
      top: tileTop,
      bottom: tileBottom,
    );
  }

  /// The area of the map (in absolute pixel coordinates of the current zoom level) that a view of [width] x [height]
  /// physical pixels shows.
  ///
  /// Derived from the transform chain of [TransformWidget]: the canvas is scaled by 1/deviceScaleFactor, pinch-zoomed
  /// by [MapPosition.scale] around the screen point [MapPosition.focalPoint] (which stays put on screen) and rotated
  /// around the screen center. Inverting that for the screen rectangle gives, in unrotated map pixels, a rectangle of
  /// the view's size / scale whose center is displaced from the map center by
  /// (focalPoint - screenCenter) * (1 - 1 / scale) * deviceScaleFactor; a rotated view turns that displacement along
  /// and is covered by the circumscribed square.
  static MapRectangle visibleArea(MapPosition mapPosition, double width, double height) {
    double deviceScaleFactor = MapsforgeSettingsMgr().getDeviceScaleFactor();
    double scale = mapPosition.scale;
    double halfWidth = width / scale / 2;
    double halfHeight = height / scale / 2;
    // the focal point is in logical pixels
    Offset screenCenter = Offset(width / deviceScaleFactor / 2, height / deviceScaleFactor / 2);
    // Without a focal point TransformWidget scales around the screen center shifted by half the (still unscaled)
    // canvas, which amounts to a focal point at screenCenter * (1 + 1 / deviceScaleFactor).
    Offset focalPoint = mapPosition.focalPoint ?? screenCenter * (1 + 1 / deviceScaleFactor);
    Offset shift = (focalPoint - screenCenter) * (1 - 1 / scale) * deviceScaleFactor;
    double rotation = mapPosition.rotationRadian;
    if (rotation != 0) {
      // the screen is rotated by +rotation, so the map under it is turned back by -rotation
      double cosine = cos(-rotation);
      double sine = sin(-rotation);
      shift = Offset(shift.dx * cosine - shift.dy * sine, shift.dx * sine + shift.dy * cosine);
      halfWidth = halfHeight = sqrt(halfWidth * halfWidth + halfHeight * halfHeight);
    }
    Mappoint center = mapPosition.getCenter();
    double centerX = center.x + shift.dx;
    double centerY = center.y + shift.dy;
    return MapRectangle(centerX - halfWidth, centerY - halfHeight, centerX + halfWidth, centerY + halfHeight);
  }

  static BoundingBox calculateBoundingBoxOfScreen({required MapPosition mapPosition, required Size screensize}) {
    Mappoint center = mapPosition.getCenter();
    double halfWidth = screensize.width / 2;
    double halfHeight = screensize.height / 2;
    if (mapPosition.rotation > 2) {
      // we rotate. Use the max side for both width and height
      halfWidth = max(halfWidth, halfHeight);
      halfHeight = halfWidth;
    }
    int degreeDiff = 45 - ((mapPosition.rotation) % 90 - 45).round().abs();
    if (degreeDiff > 5) {
      // rising from 0 to 45, then falling to 0 at 90°
      halfWidth *= 1.2;
      halfHeight *= 1.2;
    }
    double minLatitude = mapPosition.projection.pixelYToLatitude(center.y + halfHeight);
    double minLongitude = mapPosition.projection.pixelXToLongitude(center.x - halfWidth);
    double maxLatitude = mapPosition.projection.pixelYToLatitude(center.y - halfHeight);
    double maxLongitude = mapPosition.projection.pixelXToLongitude(center.x + halfWidth);
    BoundingBox result = BoundingBox(minLatitude, minLongitude, maxLatitude, maxLongitude);
    return result;
  }
}
