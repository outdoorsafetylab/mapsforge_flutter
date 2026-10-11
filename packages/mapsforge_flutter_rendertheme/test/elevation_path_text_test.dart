import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:test/test.dart';

/// The elevations of contour lines (texts along ways showing "ele") can be drawn smaller than the other texts and
/// follow the rules of a lower zoomlevel, see [MapsforgeSettingsMgr.elevationPathTextScale] and
/// [MapsforgeSettingsMgr.elevationPathTextZoomOffset].
void main() {
  final settings = MapsforgeSettingsMgr();

  tearDown(() {
    settings.setFontScaleFactor(1);
    settings.elevationPathTextScale = 1;
    settings.elevationPathTextZoomOffset = 0;
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

  group('elevationPathTextZoomOffset', () {
    // the elevations get denser from zoomlevel to zoomlevel, the lines are drawn differently at each
    const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule e="way" k="contour" v="*">
    <rule e="way" k="*" v="*" zoom-min="14" zoom-max="14">
      <line stroke="#000014" stroke-width="1"/>
      <pathText k="ele" font-size="14"/>
    </rule>
    <rule e="way" k="*" v="*" zoom-min="15" zoom-max="15">
      <line stroke="#000015" stroke-width="1"/>
      <pathText k="ele" font-size="15"/>
      <pathText k="name" font-size="15"/>
    </rule>
  </rule>
  <rule e="way" k="highway" v="path" zoom-min="15">
    <pathText k="name" font-size="10"/>
  </rule>
</rendertheme>''';

    List<int> lineColors(List<Renderinstruction> instructions) =>
        instructions.whereType<RenderinstructionPolyline>().map((ri) => ri.strokeColor & 0xffffff).toList();
    List<double> elevationSizes(List<Renderinstruction> instructions) =>
        instructions.whereType<RenderinstructionPolylineText>().where((ri) => ri.isElevationText).map((ri) => ri.fontSize).toList();
    List<double> nameSizes(List<Renderinstruction> instructions) =>
        instructions.whereType<RenderinstructionPolylineText>().where((ri) => !ri.isElevationText).map((ri) => ri.fontSize).toList();

    test('with 1 the elevations come from the rules one zoomlevel below, all else from the rules of the zoomlevel', () {
      settings.elevationPathTextZoomOffset = 1;
      final rendertheme = RenderThemeBuilder.createFromString(theme);

      final at15 = instructionsFor(rendertheme, 15, contour);
      expect(lineColors(at15), [0x15]);
      expect(elevationSizes(at15), [14]);
      expect(nameSizes(at15), [15]);
      // prepared for the zoomlevel rendered
      expect(at15.whereType<RenderinstructionPolylineText>().every((ri) => ri.zoomlevel == 15), isTrue);

      // a rule holding only the zoomlevel below brings its elevations, nothing else
      final at16 = instructionsFor(rendertheme, 16, contour);
      expect(lineColors(at16), isEmpty);
      expect(elevationSizes(at16), [15]);
      expect(nameSizes(at16), isEmpty);

      final at14 = instructionsFor(rendertheme, 14, contour);
      expect(lineColors(at14), [0x14]);
      expect(elevationSizes(at14), isEmpty);

      // other texts along ways keep their zoomlevel
      expect(nameSizes(instructionsFor(rendertheme, 15, path)), [10]);
      expect(instructionsFor(rendertheme, 14, path), isEmpty);
    });

    test('with 0 every instruction follows the rules of its zoomlevel', () {
      final rendertheme = RenderThemeBuilder.createFromString(theme);

      final at15 = instructionsFor(rendertheme, 15, contour);
      expect(lineColors(at15), [0x15]);
      expect(elevationSizes(at15), [15]);
      expect(nameSizes(at15), [15]);
      final at14 = instructionsFor(rendertheme, 14, contour);
      expect(lineColors(at14), [0x14]);
      expect(elevationSizes(at14), [14]);
      expect(instructionsFor(rendertheme, 16, contour), isEmpty);
    });
  });
}
