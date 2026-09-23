import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/map_display.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/render_context.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/render_info.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/wayproperties.dart';

///
/// In the terminal window run
///
///```
/// flutter packages pub run build_runner build --delete-conflicting-outputs
///```
///
class RenderInfoWay<T extends Renderinstruction> extends RenderInfo<T> {
  final WayProperties wayProperties;

  /// Extra vertical offset the painter adds to the anchor of a label placed at the way's centre; `null` for
  /// renderinfos that follow the way (their boundary stays the way's bounding box).
  final double? centerAnchorDy;

  RenderInfoWay(this.wayProperties, super.renderInstruction, {super.caption}) : centerAnchorDy = null;

  /// A label drawn around the way's centre (caption, symbol, icon): it collides with the box it is painted in,
  /// not with the way's geometry. [anchorDy] must match what the painter adds to the centre.
  RenderInfoWay.centered(this.wayProperties, super.renderInstruction, {super.caption, required double anchorDy}) : centerAnchorDy = anchorDy;

  @override
  void render(RenderContext renderContext) {
    shapePainter!.renderWay(this, renderContext, wayProperties);
  }

  /// Returns if MapElementContainers clash with each other
  ///
  /// @param other element to test against
  /// @return true if they overlap
  @override
  bool clashesWith(RenderInfo other) {
    // if either of the elements is always drawn, the elements do not clash
    if (MapDisplay.ALWAYS == renderInstruction.display || MapDisplay.ALWAYS == other.renderInstruction.display) {
      return false;
    }
    return getBoundaryAbsolute().intersects(other.getBoundaryAbsolute());
  }

  @override
  bool intersects(MapRectangle other) {
    return getBoundaryAbsolute().intersects(other);
  }

  @override
  MapRectangle getBoundaryAbsolute() {
    if (boundaryAbsolute != null) return boundaryAbsolute!;
    final anchorDy = centerAnchorDy;
    if (anchorDy == null) {
      boundaryAbsolute = wayProperties.getBoundaryAbsolute();
    } else {
      // The box the label is painted in, not the way's geometry: a long name on a small area reaches far beyond
      // the area, and a large area must not clash with labels far from its centre.
      Mappoint center = wayProperties.centerAbsolute;
      boundaryAbsolute = renderInstruction.getBoundary(this).shift(Mappoint(center.x, center.y + anchorDy));
    }
    return boundaryAbsolute!;
  }
}
