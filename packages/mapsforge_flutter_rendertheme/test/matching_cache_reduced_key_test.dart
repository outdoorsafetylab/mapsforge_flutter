import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/anymatcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/matcher/attributematcher.dart';
import 'package:mapsforge_flutter_rendertheme/src/rule/positiverule.dart';
import 'package:test/test.dart';

/// A rule for each kind of matcher: key and value, key only, value only, negation.
const String theme = '''<?xml version="1.0" encoding="UTF-8"?>
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="5">
  <rule e="node" k="amenity" v="cafe">
    <circle fill="#000000" radius="1" />
  </rule>
  <rule e="node" k="name" v="*">
    <circle fill="#000000" radius="2" />
  </rule>
  <rule e="node" k="*" v="summit">
    <circle fill="#000000" radius="3" />
  </rule>
  <rule e="node" k="access" v="~|no">
    <circle fill="#000000" radius="4" />
  </rule>
  <rule e="way" k="highway" v="primary">
    <line stroke="#000000" stroke-width="1" />
  </rule>
  <rule e="way" k="name" v="*">
    <line stroke="#000000" stroke-width="2" />
  </rule>
  <rule e="way" k="*" v="summit">
    <line stroke="#000000" stroke-width="3" />
  </rule>
  <rule e="way" k="access" v="~|no">
    <line stroke="#000000" stroke-width="4" />
  </rule>
  <rule e="way" k="landuse" v="forest">
    <area fill="#00FF00" />
  </rule>
  <rule e="way" k="name" v="*" closed="yes">
    <area fill="#0000FF" />
  </rule>
</rendertheme>
''';

/// An instruction without its serial number, which differs between two themes built from the same XML.
String describe(Renderinstruction instruction) => instruction.toString().replaceAll(RegExp(r', serial: \d+'), '');

/// An open way (a line) and a closed one (a ring) with [tags].
Way open(List<Tag> tags) => Way(0, tags, const [
  [LatLong(0, 0), LatLong(0, 0.001)],
], null);

Way closed(List<Tag> tags) => Way(0, tags, const [
  [LatLong(0, 0), LatLong(0, 0.001), LatLong(0.001, 0.001), LatLong(0, 0)],
], null);

/// Looks at the value of `name`, which no built-in matcher does.
class _NameIsX implements AttributeMatcher {
  @override
  bool isCoveredByAttributeMatcher(AttributeMatcher attributeMatcher) => false;

  @override
  bool matchesTagList(ITagCollection tags) => (tags as TagCollection).tags.any((Tag tag) => tag.key == 'name' && tag.value == 'x');
}

PointOfInterest poi(List<Tag> tags) => PointOfInterest(0, TagCollection(tags: tags), const LatLong(0, 0));

void main() {
  final List<PointOfInterest> pois = [
    poi(const [Tag('amenity', 'cafe'), Tag('name', 'Foo')]),
    poi(const [Tag('amenity', 'cafe'), Tag('name', 'Bar')]),
    poi(const [Tag('amenity', 'cafe')]),
    poi(const [Tag('amenity', 'cafe'), Tag('name', 'Foo'), Tag('ele', '100')]),
    // a name that happens to be a value some rule looks for
    poi(const [Tag('amenity', 'bar'), Tag('name', 'summit')]),
    poi(const [Tag('amenity', 'bar'), Tag('name', 'cafe')]),
    poi(const [Tag('amenity', 'bar'), Tag('name', 'Foo')]),
    poi(const [Tag('natural', 'summit'), Tag('name', 'Foo')]),
    poi(const [Tag('access', 'yes'), Tag('name', 'Foo')]),
    poi(const [Tag('access', 'no'), Tag('name', 'Foo')]),
    poi(const [Tag('access', 'private')]),
    // the indoor level check reads the values of level and repeat_on
    poi(const [Tag('amenity', 'cafe'), Tag('level', '1')]),
    poi(const [Tag('amenity', 'cafe'), Tag('level', '2')]),
    poi(const [Tag('amenity', 'cafe'), Tag('repeat_on', '0;1')]),
  ];

  test('cached instructions are the ones the rules give for the tags', () {
    RenderthemeZoomlevel cached = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
    for (int indoorLevel in [0, 1, 2]) {
      // match every POI through one cache, in both orders, against a fresh level per POI
      for (List<PointOfInterest> order in [pois, pois.reversed.toList()]) {
        for (PointOfInterest pointOfInterest in order) {
          RenderthemeZoomlevel fresh = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
          expect(
            cached.matchNode(indoorLevel, pointOfInterest).map(describe).toList(),
            fresh.matchNode(indoorLevel, pointOfInterest).map(describe).toList(),
            reason: '${pointOfInterest.tags} on level $indoorLevel',
          );
        }
      }
    }
  });

  test('features that differ only in tags no rule looks at share a cache entry', () {
    RenderthemeZoomlevel level = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
    List<Renderinstruction> foo = level.matchNode(0, pois[0]);
    expect(level.matchNode(0, pois[1]), same(foo), reason: 'another name');
    expect(level.matchNode(0, pois[3]), same(foo), reason: 'another tag no rule looks at');
    expect(level.matchNode(0, pois[2]), isNot(same(foo)), reason: 'no name at all');
    expect(level.matchNode(0, pois[4]), isNot(same(level.matchNode(0, pois[6]))), reason: 'a name a rule looks for');
    expect(level.matchNode(0, pois[11]), isNot(same(level.matchNode(0, pois[12]))), reason: 'another level');
  });

  final List<List<Tag>> wayTags = [
    const [Tag('highway', 'primary'), Tag('name', 'Foo')],
    const [Tag('highway', 'primary'), Tag('name', 'Bar')],
    const [Tag('highway', 'primary')],
    const [Tag('highway', 'residential'), Tag('name', 'summit')],
    const [Tag('highway', 'residential'), Tag('name', 'primary')],
    const [Tag('highway', 'residential'), Tag('name', 'Foo')],
    const [Tag('landuse', 'forest'), Tag('name', 'Foo')],
    const [Tag('landuse', 'forest')],
    const [Tag('access', 'no'), Tag('name', 'Foo')],
    const [Tag('access', 'private'), Tag('name', 'Foo')],
    const [Tag('highway', 'primary'), Tag('level', '1')],
    const [Tag('highway', 'primary'), Tag('level', '2')],
  ];

  test('cached instructions for open and closed ways are the ones the rules give for the tags', () {
    RenderthemeZoomlevel cached = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
    for (int indoorLevel in [0, 1, 2]) {
      Tile tile = Tile(0, 0, 16, indoorLevel);
      for (List<List<Tag>> order in [wayTags, wayTags.reversed.toList()]) {
        for (List<Tag> tags in order) {
          RenderthemeZoomlevel fresh = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(16);
          expect(
            cached.matchOpenWay(tile, open(tags)).map(describe).toList(),
            fresh.matchOpenWay(tile, open(tags)).map(describe).toList(),
            reason: 'open $tags on level $indoorLevel',
          );
          expect(
            cached.matchClosedWay(tile, closed(tags)).map(describe).toList(),
            fresh.matchClosedWay(tile, closed(tags)).map(describe).toList(),
            reason: 'closed $tags on level $indoorLevel',
          );
        }
      }
    }
    Tile tile = Tile(0, 0, 16, 0);
    expect(cached.matchOpenWay(tile, open(wayTags[1])), same(cached.matchOpenWay(tile, open(wayTags[0]))), reason: 'another name');
    expect(cached.matchClosedWay(tile, closed(wayTags[1])), same(cached.matchClosedWay(tile, closed(wayTags[0]))), reason: 'another name');
  });

  test('with a matcher it does not know the cache is keyed by all tags', () {
    List<RenderinstructionNode> circle = RenderThemeBuilder.createFromString(
      theme,
    ).prepareZoomlevel(16).matchNode(0, pois[0]).cast<RenderinstructionNode>().take(1).toList();
    RenderthemeZoomlevel level = RenderthemeZoomlevel(
      rulesList: [
        PositiveRule(
          keyMatcher: _NameIsX(),
          valueMatcher: const AnyMatcher(),
          zoomlevelRange: const ZoomlevelRange(0, 25),
          subRules: const [],
          renderinstructionNodes: circle,
          renderinstructionOpenWays: const [],
          renderinstructionClosedWays: const [],
        ),
      ],
      maxLevels: 1,
    );
    expect(level.matchNode(0, poi(const [Tag('name', 'x')])), hasLength(1));
    expect(level.matchNode(0, poi(const [Tag('name', 'y')])), isEmpty);
  });
}
