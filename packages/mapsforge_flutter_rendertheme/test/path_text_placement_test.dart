import 'dart:math';

import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:mapsforge_flutter_rendertheme/src/renderinstruction/font_width_helper.dart';
import 'package:test/test.dart';

/// Texts along ways (pathText) are placed as Java mapsforge places them: windows of the text's width at repeatStart
/// and every repeatGap + width, accepted when no corner exceeds 45° and – the text being drawn straight – the way
/// stays close to the window's chord.
void main() {
  LineSegmentPath pathOf(List<Mappoint> points) {
    final path = LineSegmentPath();
    for (int i = 1; i < points.length; i++) {
      path.segments.add(LineSegment(points[i - 1], points[i]));
    }
    return path;
  }

  /// A path of two 100 px segments meeting at a corner of [degrees] (positive turns one way, negative the other).
  LineSegmentPath bent(double degrees) {
    final r = degrees * pi / 180;
    return pathOf([const Mappoint(1000, 1000), const Mappoint(1100, 1000), Mappoint(1100 + 100 * cos(r), 1000 + 100 * sin(r))]);
  }

  Matcher near(Mappoint p) => isA<Mappoint>().having((m) => m.x, 'x', closeTo(p.x, 1e-6)).having((m) => m.y, 'y', closeTo(p.y, 1e-6));

  group('LineSegment', () {
    test('angleTo is signed and takes the directions into account', () {
      final east = LineSegment(const Mappoint(100, 100), const Mappoint(110, 100));
      LineSegment towards(double degrees) {
        final r = degrees * pi / 180;
        return LineSegment(const Mappoint(100, 100), Mappoint(100 + 10 * cos(r), 100 + 10 * sin(r)));
      }

      expect(east.angleTo(east), closeTo(0, 1e-9));
      expect(east.angleTo(towards(10)), closeTo(-10, 1e-9));
      expect(east.angleTo(towards(-10)), closeTo(10, 1e-9));
      // a 2° bend across the vertical, where the undirected theta jumps from +90° to -90°
      expect(towards(89).angleTo(towards(91)).abs(), closeTo(2, 1e-9));
      // a reversal is not a straight line
      expect(east.angleTo(towards(180)).abs(), closeTo(180, 1e-9));
    });

    test('getTheta of a vertical segment follows its direction, wherever it lies', () {
      expect(LineSegment(const Mappoint(20, 5), const Mappoint(20, 10)).getTheta(), pi / 2);
      expect(LineSegment(const Mappoint(20, 10), const Mappoint(20, 5)).getTheta(), -pi / 2);
      expect(LineSegment(const Mappoint(5, 20), const Mappoint(5, 30)).getTheta(), pi / 2);
    });
  });

  group('LineSegmentPath.textPositions', () {
    test('a straight way: a window at repeatStart, then every repeatGap + width while it fits', () {
      final chords = pathOf([const Mappoint(0, 0), const Mappoint(300, 0)]).textPositions(50, 10, 100, 5);
      expect(chords, hasLength(2));
      expect(chords[0].start, near(const Mappoint(10, 0)));
      expect(chords[0].end, near(const Mappoint(60, 0)));
      expect(chords[1].start, near(const Mappoint(160, 0)));
      expect(chords[1].end, near(const Mappoint(210, 0)));
    });

    test('a way exactly as long as repeatStart + width gets its text', () {
      expect(pathOf([const Mappoint(0, 0), const Mappoint(60, 0)]).textPositions(50, 10, 100, 5), hasLength(1));
      expect(pathOf([const Mappoint(0, 0), const Mappoint(59, 0)]).textPositions(50, 10, 100, 5), isEmpty);
    });

    test('the last window counts even when the way is made of several short segments', () {
      // three collinear segments, the text only fits over all of them
      final path = pathOf([const Mappoint(0, 0), const Mappoint(40, 0), const Mappoint(80, 0), const Mappoint(120, 0)]);
      expect(path.textPositions(100, 10, 100, 5), hasLength(1));
    });

    test('corners up to 45° are accepted, sharper ones are not, whichever way the way turns', () {
      for (final sign in [1, -1]) {
        expect(bent(30.0 * sign).textPositions(100, 50, 1000, 100), hasLength(1), reason: 'turn ${30 * sign}°');
        expect(bent(60.0 * sign).textPositions(100, 50, 1000, 100), isEmpty, reason: 'turn ${60 * sign}°');
      }
    });

    test('a slight bend across the vertical is accepted, a reversal is not', () {
      Mappoint towards(Mappoint from, double degrees) => Mappoint(from.x + 100 * cos(degrees * pi / 180), from.y + 100 * sin(degrees * pi / 180));
      const start = Mappoint(1000, 1000);
      final bend = towards(start, 89);
      expect(pathOf([start, bend, towards(bend, 91)]).textPositions(100, 50, 1000, 100), hasLength(1));
      final turn = towards(start, 0);
      expect(pathOf([start, turn, towards(turn, 180)]).textPositions(100, 50, 1000, 100), isEmpty);
    });

    test('a window starting or ending on a vertex of a straight way is not a corner', () {
      final starting = pathOf([const Mappoint(0, 0), const Mappoint(0, 35), const Mappoint(0, 200)]);
      expect(starting.textPositions(103, 35, 1000, 1), hasLength(1));
      final ending = pathOf([const Mappoint(0, 0), const Mappoint(0, 138), const Mappoint(0, 200)]);
      expect(ending.textPositions(103, 35, 1000, 1), hasLength(1));
    });

    test('a gentle arc is dropped when it bulges further from the chord than allowed', () {
      // five segments on a circle of radius 100, 8° each (corners of 8°); the middle vertices are 5.79 px off the chord
      final points = [for (int i = 0; i <= 5; i++) Mappoint(100 * cos(i * 8 * pi / 180), 100 * sin(i * 8 * pi / 180))];
      final arc = pathOf(points);
      expect(arc.textPositions(arc.length(), 0, 1000, 5), isEmpty);
      expect(arc.textPositions(arc.length(), 0, 1000, 6), hasLength(1));
    });
  });

  group('FontWidthHelper.getBoundaryForPathText', () {
    final helper = FontWidthHelper();

    test('digits are narrow, CJK characters take a full em, others keep 0.9 em', () {
      expect(helper.getBoundaryForPathText('2000', MapFontStyle.NORMAL, 10, 1).width, closeTo(4 * 6.3 + 2, 1e-9));
      expect(helper.getBoundaryForPathText('雪山', MapFontStyle.NORMAL, 10, 1).width, closeTo(2 * 10 + 2, 1e-9));
      expect(helper.getBoundaryForPathText('A1', MapFontStyle.NORMAL, 10, 1).width, closeTo(9 + 6.3 + 2, 1e-9));
      expect(helper.getBoundaryForPathText('2000', MapFontStyle.NORMAL, 10, 1).height, 12);
    });

    test('bold is 10 % wider, before the stroke is added', () {
      expect(helper.getBoundaryForPathText('2000', MapFontStyle.BOLD, 10, 1).width, closeTo(4 * 6.3 * 1.1 + 2, 1e-9));
    });
  });

  group('pathText collision box', () {
    const int zoom = 16;
    final projection = PixelProjection(zoom);
    const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule e="way" k="contour" v="*">
    <pathText k="ele" font-size="10" stroke-width="1"/>
  </rule>
</rendertheme>''';
    late RenderthemeZoomlevel level;

    setUpAll(() {
      level = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(zoom);
    });

    const double cx = 100000, cy = 100000;

    /// The pathText labels of a straight way through (cx, cy) heading [degrees], 200 px long.
    List<RenderInfo> labelsAlong(double degrees) {
      final r = degrees * pi / 180;
      ILatLong ll(double px, double py) => LatLong(projection.pixelYToLatitude(py), projection.pixelXToLongitude(px));
      final way = Way(
        0,
        const [Tag('contour', 'yes'), Tag('ele', '2000')],
        [
          [ll(cx - 100 * cos(r), cy - 100 * sin(r)), ll(cx + 100 * cos(r), cy + 100 * sin(r))],
        ],
        null,
      );
      final collection = LayerContainerCollection(level.maxLevels);
      final wayProperties = WayProperties(way, projection);
      for (final ri in level.matchOpenWay(Tile(0, 0, zoom, 0), way)) {
        ri.matchWay(collection.getLayer(0), wayProperties);
      }
      collection.reduce();
      return collection.clashingInfoCollection.renderInfos;
    }

    test('the box is centred on the middle of the window the text is drawn on', () {
      final label = labelsAlong(0).first;
      final instruction = label.renderInstruction as RenderinstructionPolylineText;
      final width = instruction.getEstimatedPathTextBoundary('2000', instruction.strokeWidth).width;
      // the first window starts at repeatStart from the way's start (cx - 100)
      final middle = cx - 100 + instruction.repeatStart + width / 2;
      expect(label.getBoundaryAbsolute().getCenter().x, closeTo(middle, 1e-3));
      expect(label.getBoundaryAbsolute().getCenter().y, closeTo(cy, 1e-3));
    });

    test('the box holds the rotated text at any angle', () {
      for (final degrees in [0.0, 30.0, 45.0, 90.0, -90.0]) {
        final label = labelsAlong(degrees).first as RenderInfoNode;
        final instruction = label.renderInstruction as RenderinstructionPolylineText;
        final size = instruction.getEstimatedPathTextBoundary('2000', instruction.strokeWidth);
        final box = instruction.getBoundary(label);
        final t = label.rotateRadians;
        for (final (dx, dy) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]) {
          final x = dx * size.width / 2 * cos(t) - dy * size.height / 2 * sin(t);
          final y = dx * size.width / 2 * sin(t) + dy * size.height / 2 * cos(t);
          expect(x, inInclusiveRange(box.left - 1e-9, box.right + 1e-9), reason: '$degrees° corner ($dx, $dy)');
          expect(y, inInclusiveRange(box.top - 1e-9, box.bottom + 1e-9), reason: '$degrees° corner ($dx, $dy)');
        }
        if (degrees.abs() == 90) {
          // upright text: the box is taller than wide
          expect(box.getHeight(), greaterThan(box.getWidth()), reason: '$degrees°');
        }
      }
    });
  });
}
