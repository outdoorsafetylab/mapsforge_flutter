import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:test/test.dart';

/// Tests for three parsing defects that showed up with real-world themes
/// (e.g. the Elevate / OpenAndroMaps family):
///
/// 1. a `<rule>` without render instructions whose only subrules have an
///    inverted zoom range used to fail the `Rule` constructor's assertion;
/// 2. a parent rule was widened to match everything when a child repeated
///    its key, so the parent's other children were applied to every way;
/// 3. `<stylemenu>` was ignored, so the rules of every category were loaded.
void main() {
  const String header = '<?xml version="1.0" encoding="UTF-8"?>\n<rendertheme xmlns="http://mapsforge.org/rendertheme" version="6">';
  const String footer = '</rendertheme>';

  List<Renderinstruction> matchOpenWay(Rendertheme theme, int zoomlevel, List<Tag> tags) {
    Way way = Way(0, tags, [
      [const LatLong(0, 0), const LatLong(0, 1)],
    ], null);
    return theme.prepareZoomlevel(zoomlevel).matchOpenWay(Tile(0, 0, zoomlevel, 0), way);
  }

  group('rules that can never match', () {
    test('a parent whose subrules all have an inverted zoom range is dropped, not asserted', () {
      // zoom-max 12 on the child is below zoom-min 13 inherited from the parent
      Rendertheme theme = RenderThemeBuilder.createFromString('''$header
  <rule e="way" k="highway" v="path" zoom-min="13">
    <rule e="way" k="*" v="*" zoom-max="12">
      <line stroke="#FF0000" stroke-width="1"/>
    </rule>
  </rule>
  <rule e="way" k="highway" v="track">
    <line stroke="#00FF00" stroke-width="1"/>
  </rule>
$footer''');
      expect(theme.rulesList.length, 1);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "path")]), isEmpty);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "track")]).length, 1);
    });

    test('a parent keeps its remaining subrules when one has an inverted zoom range', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('''$header
  <rule e="way" k="highway" v="path" zoom-min="13">
    <rule e="way" k="*" v="*" zoom-max="12">
      <line stroke="#FF0000" stroke-width="1"/>
    </rule>
    <rule e="way" k="*" v="*" zoom-min="15">
      <line stroke="#0000FF" stroke-width="1"/>
    </rule>
  </rule>
$footer''');
      expect(theme.rulesList.length, 1);
      expect(theme.rulesList.first.subRules.length, 1);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "path")]), isEmpty);
      expect(matchOpenWay(theme, 16, [const Tag("highway", "path")]).length, 1);
    });
  });

  group('rule matching', () {
    test('a parent without render instructions is not widened when a child repeats its key', () {
      // Before the fix the parent matched every way, so the "*" child painted the casing on every way of the map.
      Rendertheme theme = RenderThemeBuilder.createFromString('''$header
  <rule e="way" k="aerialway" v="*">
    <rule e="way" k="*" v="*">
      <line stroke="#000000" stroke-width="4"/>
    </rule>
    <rule e="way" k="aerialway" v="cable_car|gondola">
      <line stroke="#FFFFFF" stroke-width="2"/>
    </rule>
  </rule>
$footer''');
      expect(matchOpenWay(theme, 14, [const Tag("highway", "path")]), isEmpty);
      expect(matchOpenWay(theme, 14, [const Tag("aerialway", "cable_car")]).length, 2);
      expect(matchOpenWay(theme, 14, [const Tag("aerialway", "zip_line")]).length, 1);
    });
  });

  group('stylemenu', () {
    const String menu = '''
  <stylemenu id="menu" defaultvalue="hiking" defaultlang="en">
    <layer id="contours" enabled="true">
      <name lang="en" value="Contour lines"/>
      <cat id="contour"/>
    </layer>
    <layer id="borders" enabled="false">
      <cat id="border"/>
    </layer>
    <layer id="base" visible="false">
      <cat id="water"/>
    </layer>
    <layer id="hiking" parent="base" visible="true">
      <name lang="en" value="Hiking"/>
      <name lang="de" value="Wandern"/>
      <cat id="hike"/>
      <overlay id="contours"/>
      <overlay id="borders"/>
    </layer>
    <layer id="city" parent="base" visible="true">
      <cat id="city"/>
      <overlay id="borders"/>
    </layer>
  </stylemenu>''';
    const String rules = '''
  <rule e="way" k="natural" v="water" cat="water">
    <line stroke="#0000FF" stroke-width="1"/>
  </rule>
  <rule e="way" k="highway" v="path" cat="hike">
    <line stroke="#FF0000" stroke-width="1"/>
  </rule>
  <rule e="way" k="highway" v="residential" cat="city">
    <line stroke="#888888" stroke-width="1"/>
  </rule>
  <rule e="way" k="contour_ext" v="*" cat="contour">
    <line stroke="#A06000" stroke-width="1"/>
  </rule>
  <rule e="way" k="boundary" v="*" cat="border">
    <line stroke="#FF00FF" stroke-width="1"/>
  </rule>
  <rule e="way" k="highway" v="*">
    <rule e="way" k="*" v="*" cat="city">
      <line stroke="#000000" stroke-width="3"/>
    </rule>
    <rule e="way" k="*" v="*">
      <line stroke="#FFFFFF" stroke-width="1"/>
    </rule>
  </rule>''';

    test('parses layers, inheritance from parent and titles', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$menu$rules$footer');
      RenderthemeStyleMenu? styleMenu = theme.styleMenu;
      expect(styleMenu, isNotNull);
      expect(styleMenu!.id, "menu");
      expect(styleMenu.defaultValue, "hiking");
      expect(styleMenu.visibleLayers.map((l) => l.id), ["hiking", "city"]);
      RenderthemeStyleLayer hiking = styleMenu.getLayer("hiking")!;
      expect(hiking.categories, {"water", "hike"});
      expect(hiking.overlays.map((o) => o.id), ["contours", "borders"]);
      expect(hiking.getTitle("de", styleMenu), "Wandern");
      expect(hiking.getTitle("fr", styleMenu), "Hiking");
      expect(styleMenu.categoriesFor("hiking"), {"water", "hike", "contour"});
      expect(styleMenu.categoriesFor("hiking", enabledOverlays: {"borders"}), {"water", "hike", "contour", "border"}, reason: "adds to the theme default");
      expect(styleMenu.categoriesFor("hiking", disabledOverlays: {"contours"}), {"water", "hike"});
      expect(styleMenu.categoriesFor("hiking", enabledOverlays: {"contours"}, disabledOverlays: {"contours"}), {"water", "hike"}, reason: "disabled wins");
      expect(styleMenu.categoriesFor("nosuchstyle"), isNull);
    });

    test('the default style loads only the rules of its enabled categories', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$menu$rules$footer');
      expect(matchOpenWay(theme, 14, [const Tag("natural", "water")]).length, 1);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "path")]).length, 2);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "residential")]).length, 1, reason: "cat city is off, cat-less fallback stays");
      expect(matchOpenWay(theme, 14, [const Tag("contour_ext", "elevation_medium")]).length, 1);
      expect(matchOpenWay(theme, 14, [const Tag("boundary", "administrative")]), isEmpty, reason: "overlay borders is not enabled");
    });

    test('styleId and enabledOverlays select another style', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$menu$rules$footer', styleId: "city", enabledOverlays: {"borders"});
      expect(matchOpenWay(theme, 14, [const Tag("highway", "path")]).length, 2, reason: "cat hike is off, the two highway=* children stay");
      expect(matchOpenWay(theme, 14, [const Tag("highway", "residential")]).length, 3);
      expect(matchOpenWay(theme, 14, [const Tag("contour_ext", "elevation_medium")]), isEmpty);
      expect(matchOpenWay(theme, 14, [const Tag("boundary", "administrative")]).length, 1);
    });

    test('a style whose overlays switch every rule off builds an empty theme', () {
      const String contourRule = '''
  <rule e="way" k="contour_ext" v="*" cat="contour">
    <line stroke="#A06000" stroke-width="1"/>
  </rule>''';
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$menu$contourRule$footer');
      expect(matchOpenWay(theme, 14, [const Tag("contour_ext", "elevation_medium")]).length, 1);
      theme = RenderThemeBuilder.createFromString('$header$menu$contourRule$footer', disabledOverlays: {"contours"});
      expect(theme.rulesList, isEmpty);
      expect(matchOpenWay(theme, 14, [const Tag("contour_ext", "elevation_medium")]), isEmpty);
    });

    test('the stylemenu may follow the rules', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$rules$menu$footer');
      expect(matchOpenWay(theme, 14, [const Tag("boundary", "administrative")]), isEmpty);
    });

    test('an unknown style is an error', () {
      expect(() => RenderThemeBuilder.createFromString('$header$menu$rules$footer', styleId: "nosuchstyle"), throwsException);
    });

    test('a theme without stylemenu uses every rule', () {
      Rendertheme theme = RenderThemeBuilder.createFromString('$header$rules$footer');
      expect(theme.styleMenu, isNull);
      expect(matchOpenWay(theme, 14, [const Tag("highway", "residential")]).length, 3);
      expect(matchOpenWay(theme, 14, [const Tag("boundary", "administrative")]).length, 1);
    });
  });
}
