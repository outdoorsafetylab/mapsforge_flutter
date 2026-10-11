import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:test/test.dart';

/// The elevations of contour lines (texts along ways showing "ele") can be drawn smaller than the other texts, and
/// the contour rules (by their category) can follow a lower zoomlevel, see [MapsforgeSettingsMgr.elevationPathTextScale]
/// and [MapsforgeSettingsMgr.contourZoomOffset].
void main() {
  final settings = MapsforgeSettingsMgr();

  tearDown(() {
    settings.setFontScaleFactor(1);
    settings.elevationPathTextScale = 1;
    settings.contourZoomOffset = 0;
    settings.contourCategory = 'contour';
  });

  Way wayWith(List<Tag> tags) => Way(0, tags, [
    [const LatLong(24, 121), const LatLong(24.01, 121.01)],
  ], null);

  final contour = wayWith(const [Tag('contour', 'yes'), Tag('ele', '2000'), Tag('name', 'n')]);
  final path = wayWith(const [Tag('highway', 'path'), Tag('name', 'n')]);

  List<Renderinstruction> instructionsFor(Rendertheme theme, int zoomlevel, Way way) =>
      theme.prepareZoomlevel(zoomlevel).matchOpenWay(Tile(0, 0, zoomlevel, 0), way);

  group('elevationPathTextScale', () {
    const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule e="way" k="contour" v="*">
    <pathText k="ele" font-size="10" stroke-width="2" repeat-gap="80" repeat-start="20"/>
    <pathText k="name" font-size="10" stroke-width="2" repeat-gap="80" repeat-start="20"/>
    <caption k="ele" font-size="10"/>
  </rule>
</rendertheme>''';

    test('scales the font of the elevations along ways only, on top of the font scale', () {
      settings.setFontScaleFactor(2);
      settings.elevationPathTextScale = 0.5;
      final rendertheme = RenderThemeBuilder.createFromString(theme);
      final pathTexts = instructionsFor(rendertheme, 15, contour).whereType<RenderinstructionPolylineText>().toList();
      final elevation = pathTexts.singleWhere((ri) => ri.isElevationText);
      final name = pathTexts.singleWhere((ri) => !ri.isElevationText);
      // captions of ways are drawn on closed ways only
      final caption = rendertheme.prepareZoomlevel(15).matchClosedWay(Tile(0, 0, 15, 0), contour).whereType<RenderinstructionCaption>().single;

      expect(elevation.fontSize, 10);
      expect(name.fontSize, 20);
      expect(caption.fontSize, 20);
      // only the font: the stroke and where the texts are repeated stay as they are
      expect(elevation.strokeWidth, name.strokeWidth);
      expect(elevation.repeatGap, name.repeatGap);
      expect(elevation.repeatStart, name.repeatStart);
    });
  });

  group('contourZoomOffset', () {
    // the contour lines and their elevations get denser from zoomlevel to zoomlevel; a path is drawn and named
    // alongside, inside the same zoomlevel ranges
    const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule cat="contour" e="way" k="*" v="*">
    <rule e="way" k="contour" v="*" zoom-min="14" zoom-max="14">
      <line stroke="#000014" stroke-width="1"/>
      <pathText k="ele" font-size="14"/>
    </rule>
    <rule e="way" k="contour" v="*" zoom-min="15" zoom-max="15">
      <line stroke="#000015" stroke-width="1"/>
      <pathText k="ele" font-size="15"/>
      <pathText k="name" font-size="15"/>
    </rule>
  </rule>
  <rule e="way" k="highway" v="path" zoom-min="15" zoom-max="15">
    <line stroke="#000115" stroke-width="1"/>
    <pathText k="name" font-size="10"/>
  </rule>
</rendertheme>''';

    List<int> lineColors(List<Renderinstruction> instructions) =>
        instructions.whereType<RenderinstructionPolyline>().map((ri) => ri.strokeColor & 0xffffff).toList();
    List<double> textSizes(List<Renderinstruction> instructions) =>
        instructions.whereType<RenderinstructionPolylineText>().map((ri) => ri.fontSize).toList();

    test('with 1 the contour rules are taken one zoomlevel below, all other rules at the zoomlevel', () {
      settings.contourZoomOffset = 1;
      final rendertheme = RenderThemeBuilder.createFromString(theme);

      final at15 = instructionsFor(rendertheme, 15, contour);
      expect(lineColors(at15), [0x14]);
      expect(textSizes(at15), [14]);
      // prepared for the zoomlevel rendered
      expect(at15.whereType<RenderinstructionPolylineText>().single.zoomlevel, 15);

      final at16 = instructionsFor(rendertheme, 16, contour);
      expect(lineColors(at16), [0x15]);
      expect(textSizes(at16), [15, 15]);

      expect(instructionsFor(rendertheme, 14, contour), isEmpty);

      // the path keeps its zoomlevel
      expect(lineColors(instructionsFor(rendertheme, 15, path)), [0x115]);
      expect(textSizes(instructionsFor(rendertheme, 15, path)), [10]);
      expect(instructionsFor(rendertheme, 16, path), isEmpty);
    });

    test('the category is the one set, nothing follows an unknown one', () {
      settings.contourZoomOffset = 1;
      settings.contourCategory = 'elevation';
      final rendertheme = RenderThemeBuilder.createFromString(theme);
      expect(lineColors(instructionsFor(rendertheme, 15, contour)), [0x15]);
      expect(instructionsFor(rendertheme, 16, contour), isEmpty);
    });

    test('with 0 every rule is taken at its zoomlevel', () {
      final rendertheme = RenderThemeBuilder.createFromString(theme);
      expect(lineColors(instructionsFor(rendertheme, 15, contour)), [0x15]);
      expect(textSizes(instructionsFor(rendertheme, 15, contour)), [15, 15]);
      expect(lineColors(instructionsFor(rendertheme, 14, contour)), [0x14]);
      expect(instructionsFor(rendertheme, 16, contour), isEmpty);
    });
  });
}
