import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_painter.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';

void main() {
  const Size screen = Size(400, 800);

  setUp(() => MapsforgeSettingsMgr().setDeviceScaleFactor(2.75));
  tearDown(() => MapsforgeSettingsMgr().setDeviceScaleFactor(1));

  group('LabelPainter.visibleBoundary', () {
    /// Pumps the real [TransformWidget] and returns a function that maps a screen point (logical pixels, relative
    /// to the map view) to the absolute map pixel that [LabelPainter] paints there.
    Future<Mappoint Function(Offset)> pumpTransform(WidgetTester tester, MapPosition mapPosition) async {
      // the label set's center usually differs from the current position (the labels are not recomputed for
      // every move), the painter draws relative to the former and TransformWidget shifts by the difference
      Mappoint mapCenter = mapPosition.getCenter().offsetAbsolute(37, -53);
      Key key = UniqueKey();
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(TransformWidget(mapPosition: mapPosition, screensize: screen, mapCenter: mapCenter, child: SizedBox.expand(key: key)));
      RenderBox canvas = tester.renderObject(find.byKey(key));
      Offset viewOrigin = tester.getTopLeft(find.byType(TransformWidget));
      return (Offset screenPoint) {
        Offset local = canvas.globalToLocal(viewOrigin + screenPoint);
        return Mappoint(mapCenter.x + local.dx, mapCenter.y + local.dy);
      };
    }

    final List<Offset> screenPoints = [
      Offset.zero,
      Offset(screen.width, 0),
      Offset(0, screen.height),
      Offset(screen.width, screen.height),
      Offset(screen.width / 2, 0),
      Offset(screen.width / 2, screen.height),
      Offset(0, screen.height / 2),
      Offset(screen.width, screen.height / 2),
      Offset(screen.width / 2, screen.height / 2),
    ];

    final Map<String, MapPosition> cases = {
      'north-up': MapPosition(46, 18, 15),
      'pinch in around an off-center focal point': MapPosition(46, 18, 15).scaleAround(const Offset(200, 720), 1.8),
      'pinch out around a corner': MapPosition(46, 18, 15).scaleAround(const Offset(50, 100), 0.6),
      'scale without focal point': MapPosition(46, 18, 15).scaleAround(null, 1.5),
      'rotated': MapPosition(46, 18, 15, 0, 35),
      'rotated pinch in': MapPosition(46, 18, 15, 0, 35).scaleAround(const Offset(200, 720), 1.8),
      'rotated scale without focal point': MapPosition(46, 18, 15, 0, 300).scaleAround(null, 0.7),
    };

    cases.forEach((String name, MapPosition mapPosition) {
      testWidgets('contains everything TransformWidget puts on screen: $name', (WidgetTester tester) async {
        Mappoint Function(Offset) toMap = await pumpTransform(tester, mapPosition);
        MapRectangle visible = LabelPainter.visibleBoundary(mapPosition, screen);
        for (Offset screenPoint in screenPoints) {
          expect(visible.contains(toMap(screenPoint)), isTrue, reason: 'screen point $screenPoint -> ${toMap(screenPoint)} not in $visible');
        }
      });

      testWidgets('does not reach far beyond the screen: $name', (WidgetTester tester) async {
        Mappoint Function(Offset) toMap = await pumpTransform(tester, mapPosition);
        MapRectangle visible = LabelPainter.visibleBoundary(mapPosition, screen);
        Mappoint center = toMap(Offset(screen.width / 2, screen.height / 2));
        // padding is 10% of the half size; a north-up view is a rectangle, a rotated one its circumscribed square
        double beyond = mapPosition.rotationRadian == 0 ? 1.3 : 2;
        for (Offset screenPoint in screenPoints.take(4)) {
          Mappoint corner = toMap(screenPoint);
          Mappoint outside = Mappoint(center.x + (corner.x - center.x) * beyond, center.y + (corner.y - center.y) * beyond);
          expect(visible.contains(outside), isFalse, reason: '$outside beyond corner $corner is in $visible');
        }
      });
    });
  });

  group('LabelPainter.cullBoundary', () {
    MapPosition mapPosition = MapPosition(46, 18, 15);
    PixelProjection projection = mapPosition.projection;

    RenderInfoWay<RenderinstructionCaption> wayCaption(Mappoint from, Mappoint to, String caption) {
      Way way = Way(0, const [], [
        [projection.pixelToLatLong(from.x, from.y), projection.pixelToLatLong(to.x, to.y)],
      ], null);
      return RenderInfoWay(WayProperties(way, projection), RenderinstructionCaption(0), caption: caption);
    }

    test('a way caption sticking into the view from outside is not culled', () {
      MapRectangle visible = LabelPainter.visibleBoundary(mapPosition, screen);
      // a short way just right of the view; its caption is centered on the way and wider than the gap
      RenderInfoWay renderInfo = wayCaption(Mappoint(visible.right + 10, visible.top + 300), Mappoint(visible.right + 12, visible.top + 300), 'Some long caption text');
      expect(renderInfo.getBoundaryAbsolute().intersects(visible), isFalse, reason: 'the geometry alone should be outside');
      expect(LabelPainter.cullBoundary(renderInfo, projection, false).intersects(visible), isTrue);
      expect(LabelPainter.cullBoundary(renderInfo, projection, true).intersects(visible), isTrue);
    });

    test('a way caption well outside the view is culled', () {
      MapRectangle visible = LabelPainter.visibleBoundary(mapPosition, screen);
      RenderInfoWay renderInfo = wayCaption(Mappoint(visible.right + 1000, visible.top + 300), Mappoint(visible.right + 1002, visible.top + 300), 'Some long caption text');
      expect(LabelPainter.cullBoundary(renderInfo, projection, false).intersects(visible), isFalse);
      expect(LabelPainter.cullBoundary(renderInfo, projection, true).intersects(visible), isFalse);
    });

    test('a node label reaches the same distance in every direction on a rotated map', () {
      NodeProperties node = NodeProperties(PointOfInterest(0, const [Tag('name', 'x')], projection.pixelToLatLong(5000, 5000)), projection);
      RenderInfoNode renderInfo = RenderInfoNode(node, RenderinstructionCaption(0), caption: 'Some long caption text');
      MapRectangle northUp = LabelPainter.cullBoundary(renderInfo, projection, false);
      MapRectangle rotated = LabelPainter.cullBoundary(renderInfo, projection, true);
      expect(northUp.toString(), equals(renderInfo.getBoundaryAbsolute().toString()));
      expect(northUp.getWidth(), greaterThan(northUp.getHeight()));
      expect(rotated.getWidth(), equals(rotated.getHeight()));
      expect(rotated.getWidth(), greaterThanOrEqualTo(northUp.getWidth()));
      Mappoint anchor = node.getCoordinatesAbsolute();
      expect(rotated.getCenter().x, closeTo(anchor.x, 1e-6));
      expect(rotated.getCenter().y, closeTo(anchor.y, 1e-6));
    });
  });
}
