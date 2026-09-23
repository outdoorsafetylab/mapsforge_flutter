import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';
import 'package:mapsforge_flutter_rendertheme/src/renderinstruction/base_src_mixin.dart';
import 'package:test/test.dart';

/// Labels on ways (area names, symbols, icons) are painted around the way's centre and must collide with that box,
/// not with the way's geometry; node labels must collide where the painters put them (anchor + dy).
void main() {
  const int zoom = 16;
  final projection = PixelProjection(zoom);

  // dy values are multiplied by the device scale factor at parse time (1.0 here).
  const theme = '''
<rendertheme xmlns="http://mapsforge.org/renderTheme" version="6">
  <rule e="way" k="landuse" v="park">
    <caption k="name" font-size="10" priority="10"/>
  </rule>
  <rule e="way" k="landuse" v="cemetery">
    <caption k="name" font-size="10" priority="5"/>
  </rule>
  <rule e="way" k="landuse" v="garden">
    <caption k="name" font-size="10" dy="30"/>
  </rule>
  <rule e="way" k="amenity" v="parking">
    <symbol src="file:parking.svg" position="below" dy="30"/>
  </rule>
  <rule e="way" k="highway" v="path">
    <line stroke="#000000" stroke-width="1"/>
  </rule>
  <rule e="node" k="place" v="village">
    <caption k="name" font-size="10"/>
  </rule>
  <rule e="node" k="natural" v="peak">
    <caption k="name" font-size="10" dy="30"/>
  </rule>
</rendertheme>''';

  late RenderthemeZoomlevel level;

  setUpAll(() {
    level = RenderThemeBuilder.createFromString(theme).prepareZoomlevel(zoom);
  });

  /// A closed square way of [halfPx] map pixels around the map pixel ([x], [y]).
  Way square(double x, double y, double halfPx, List<Tag> tags, {ILatLong? labelPosition}) {
    ILatLong ll(double px, double py) => LatLong(projection.pixelYToLatitude(py), projection.pixelXToLongitude(px));
    final ring = [
      ll(x - halfPx, y - halfPx),
      ll(x + halfPx, y - halfPx),
      ll(x + halfPx, y + halfPx),
      ll(x - halfPx, y + halfPx),
      ll(x - halfPx, y - halfPx),
    ];
    return Way(0, tags, [ring], labelPosition);
  }

  List<RenderInfo> labelsOfWay(Way way) {
    final collection = LayerContainerCollection(level.maxLevels);
    final wayProperties = WayProperties(way, projection);
    for (final ri in level.matchClosedWay(Tile(0, 0, zoom, 0), way)) {
      ri.matchWay(collection.getLayer(0), wayProperties);
    }
    collection.reduce();
    return collection.labels.renderInfos;
  }

  RenderInfo labelOfNode(double x, double y, List<Tag> tags) {
    final poi = PointOfInterest(
      0,
      TagCollection(tags: tags),
      LatLong(projection.pixelYToLatitude(y), projection.pixelXToLongitude(x)),
    );
    final collection = LayerContainerCollection(level.maxLevels);
    for (final ri in level.matchNode(0, poi)) {
      ri.matchNode(collection.getLayer(0), NodeProperties(poi, projection));
    }
    collection.reduce();
    return collection.labels.renderInfos.single;
  }

  const double cx = 100000, cy = 100000;

  /// MapRectangle has no value equality.
  Matcher sameBox(MapRectangle r) => isA<MapRectangle>()
      .having((b) => b.left, 'left', closeTo(r.left, 1e-6))
      .having((b) => b.top, 'top', closeTo(r.top, 1e-6))
      .having((b) => b.right, 'right', closeTo(r.right, 1e-6))
      .having((b) => b.bottom, 'bottom', closeTo(r.bottom, 1e-6));

  /// The instruction's dy for this zoom level (the theme value, scaled for the level).
  double dyOf(RenderInfo info) => (info.renderInstruction as BaseSrcMixin).dy;

  test('two small areas far apart whose long names overlap clash', () {
    final a = labelsOfWay(
      square(cx, cy, 5, const [Tag('landuse', 'park'), Tag('name', 'A very long park name')]),
    ).single;
    final b = labelsOfWay(
      square(cx + 60, cy, 5, const [Tag('landuse', 'park'), Tag('name', 'Another long park name')]),
    ).single;
    // The geometries are 50 px apart…
    expect(
      (a as RenderInfoWay).wayProperties.getBoundaryAbsolute().intersects(
        (b as RenderInfoWay).wayProperties.getBoundaryAbsolute(),
      ),
      isFalse,
    );
    // …but the painted names overlap.
    expect(a.clashesWith(b), isTrue);
    expect(b.clashesWith(a), isTrue);
  });

  test('a large area does not clash with a node label far from its centre', () {
    final area = labelsOfWay(square(cx, cy, 500, const [Tag('landuse', 'park'), Tag('name', 'Big park')])).single;
    final village = labelOfNode(cx + 300, cy + 300, const [Tag('place', 'village'), Tag('name', 'Village')]);
    // The node lies inside the area's bounding box, far from the area's name.
    expect(
      (area as RenderInfoWay).wayProperties.getBoundaryAbsolute().contains(village.getBoundaryAbsolute().getCenter()),
      isTrue,
    );
    expect(area.clashesWith(village), isFalse);
    expect(village.clashesWith(area), isFalse);
  });

  test('a way caption collides where it is painted: centre + dy, boundary incl. dy', () {
    final label =
        labelsOfWay(square(cx, cy, 5, const [Tag('landuse', 'garden'), Tag('name', 'Garden')])).single as RenderInfoWay;
    final centre = label.wayProperties.centerAbsolute;
    expect(dyOf(label), greaterThan(0));
    final expected = label.renderInstruction.getBoundary(label).shift(Mappoint(centre.x, centre.y + dyOf(label)));
    expect(label.getBoundaryAbsolute(), sameBox(expected));
  });

  test('a way symbol collides at the unshifted centre (its painter adds no dy to the anchor)', () {
    final label = labelsOfWay(square(cx, cy, 5, const [Tag('amenity', 'parking')])).single as RenderInfoWay;
    final centre = label.wayProperties.centerAbsolute;
    expect(dyOf(label), greaterThan(0));
    expect(label.getBoundaryAbsolute(), sameBox(label.renderInstruction.getBoundary(label).shift(centre)));
  });

  test('a node caption collides at anchor + dy; without dy the box is unchanged', () {
    final peak = labelOfNode(cx, cy, const [Tag('natural', 'peak'), Tag('name', 'Peak')]);
    final anchor = (peak as RenderInfoNode).nodeProperties.getCoordinatesAbsolute();
    expect(dyOf(peak), greaterThan(0));
    expect(
      peak.getBoundaryAbsolute(),
      sameBox(peak.renderInstruction.getBoundary(peak).shift(Mappoint(anchor.x, anchor.y + dyOf(peak)))),
    );

    final village = labelOfNode(cx, cy, const [Tag('place', 'village'), Tag('name', 'Village')]);
    final v = (village as RenderInfoNode).nodeProperties.getCoordinatesAbsolute();
    expect(dyOf(village), 0);
    expect(village.getBoundaryAbsolute(), sameBox(village.renderInstruction.getBoundary(village).shift(v)));
  });

  test('the anchor dy decides a clash: a label under the painted name clashes, the single-dy box would miss it', () {
    final peak = labelOfNode(cx, cy, const [Tag('natural', 'peak'), Tag('name', 'Peak')]);
    final dy = dyOf(peak);
    final box = peak.renderInstruction.getBoundary(peak); // already contains dy once
    expect(dy, greaterThan(box.bottom - box.top), reason: 'dy must exceed the label height for this layout');
    // The painters draw the peak's name centred at anchor + 2 dy; put a village name right there.
    final village = labelOfNode(cx, cy + 2 * dy, const [Tag('place', 'village'), Tag('name', 'Peak')]);
    final singleDy = box.shift((peak as RenderInfoNode).nodeProperties.getCoordinatesAbsolute());
    expect(singleDy.intersects(village.getBoundaryAbsolute()), isFalse);
    expect(peak.clashesWith(village), isTrue);
    expect(village.clashesWith(peak), isTrue);
  });

  test('renderinfos that follow the way keep the geometry as boundary', () {
    final way = square(cx, cy, 50, const [Tag('landuse', 'park'), Tag('name', 'P')]);
    final wayProperties = WayProperties(way, projection);
    final following = RenderInfoWay(wayProperties, level.matchClosedWay(Tile(0, 0, zoom, 0), way).first);
    expect(following.getBoundaryAbsolute(), sameBox(wayProperties.getBoundaryAbsolute()));
  });

  test('a label position is the centre from the first call on', () {
    final labelAt = LatLong(projection.pixelYToLatitude(cy + 40), projection.pixelXToLongitude(cx + 40));
    final wayProperties = WayProperties(
      square(cx, cy, 50, const [Tag('landuse', 'park')], labelPosition: labelAt),
      projection,
    );
    final expected = projection.latLonToPixel(labelAt);
    expect(wayProperties.getCenterAbsolute(projection), expected);
    expect(wayProperties.getCenterAbsolute(projection), expected);
    expect(wayProperties.centerAbsolute, expected);

    final plain = WayProperties(square(cx, cy, 50, const [Tag('landuse', 'park')]), projection);
    expect(plain.centerAbsolute, plain.getBoundaryAbsolute().getCenter());
  });

  test('collisionFreeOrdered keeps only the higher-priority of two overlapping area names', () {
    final park = labelsOfWay(
      square(cx, cy, 5, const [Tag('landuse', 'park'), Tag('name', 'Overlapping name one')]),
    ).single;
    final cemetery = labelsOfWay(
      square(cx + 40, cy, 5, const [Tag('landuse', 'cemetery'), Tag('name', 'Overlapping name two')]),
    ).single;
    final collection = RenderInfoCollection([cemetery, park])..collisionFreeOrdered();
    expect(collection.renderInfos, [park]);
  });
}
