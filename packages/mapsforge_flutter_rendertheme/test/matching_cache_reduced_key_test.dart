import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
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
</rendertheme>
''';

/// An instruction without its serial number, which differs between two themes built from the same XML.
String describe(Renderinstruction instruction) => instruction.toString().replaceAll(RegExp(r', serial: \d+'), '');

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
}
