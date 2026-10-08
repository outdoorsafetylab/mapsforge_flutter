import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_dimension.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

/// Records the tiles it is asked for and renders nothing.
class _RecordingRenderer extends Renderer {
  final Set<Tile> tiles = {};

  /// Upper left tiles of the label blocks asked for.
  final Set<Tile> labelBlocks = {};

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) async {
    tiles.add(jobRequest.tile);
    return JobResult.unsupported();
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) async {
    labelBlocks.add(jobRequest.tile);
    return JobResult.normalLabels(RenderInfoCollection([]));
  }

  @override
  String getRenderKey() => 'recording';

  @override
  bool supportLabels() => false;
}

void main() {
  const Size screen = Size(400, 800);
  const double deviceScaleFactor = 2.75;
  final double tileSize = MapsforgeSettingsMgr().tileSize;

  setUp(() => MapsforgeSettingsMgr().setDeviceScaleFactor(deviceScaleFactor));
  tearDown(() => MapsforgeSettingsMgr().setDeviceScaleFactor(1));

  /// The view size the tile job queue gets: physical pixels.
  MapSize physical(Size size) => MapSize(width: size.width * deviceScaleFactor, height: size.height * deviceScaleFactor);

  group('TileHelper.calculateTiles', () {
    /// Pumps the real [TransformWidget] and returns a function that maps a screen point (logical pixels) to the
    /// absolute map pixel shown there.
    Future<Mappoint Function(Offset)> pumpTransform(WidgetTester tester, MapPosition mapPosition) async {
      Mappoint mapCenter = mapPosition.getCenter();
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
      for (double x = 0; x <= screen.width; x += screen.width / 4)
        for (double y = 0; y <= screen.height; y += screen.height / 8) Offset(x, y),
    ];

    final Map<String, MapPosition> cases = {
      'north-up': MapPosition(46, 18, 17),
      'pinch out around a corner': MapPosition(46, 18, 17).scaleAround(const Offset(50, 100), 0.6),
      'pinch in around an off-center focal point': MapPosition(46, 18, 17).scaleAround(const Offset(200, 720), 1.8),
      'rotated': MapPosition(46, 18, 17, 0, 35),
      'rotated pinch out': MapPosition(46, 18, 17, 0, 300).scaleAround(const Offset(300, 200), 0.7),
    };

    cases.forEach((String name, MapPosition mapPosition) {
      testWidgets('shows only prepared tiles: $name', (WidgetTester tester) async {
        Mappoint Function(Offset) toMap = await pumpTransform(tester, mapPosition);
        TileDimension dimension = TileHelper.calculateTiles(mapViewPosition: mapPosition, screensize: physical(screen));
        for (Offset screenPoint in screenPoints) {
          Mappoint point = toMap(screenPoint);
          int tileX = (point.x / tileSize).floor();
          int tileY = (point.y / tileSize).floor();
          expect(tileX, inInclusiveRange(dimension.left, dimension.right), reason: 'screen point $screenPoint in $dimension');
          expect(tileY, inInclusiveRange(dimension.top, dimension.bottom), reason: 'screen point $screenPoint in $dimension');
        }
      });
    });

    test('a north-up portrait view prepares its own tiles plus one around them', () {
      TileDimension dimension = TileHelper.calculateTiles(mapViewPosition: MapPosition(46, 18, 17), screensize: physical(screen));
      // 1100 x 2200 physical pixels are 5 x 9 tiles, or one more where the edges cut a tile
      expect(dimension.right - dimension.left + 1, inInclusiveRange(5, 6));
      expect(dimension.bottom - dimension.top + 1, inInclusiveRange(9, 10));
      expect(dimension.left - dimension.minLeft, TileHelper.margin);
      expect(dimension.minRight - dimension.right, TileHelper.margin);
      expect(dimension.top - dimension.minTop, TileHelper.margin);
      expect(dimension.minBottom - dimension.bottom, TileHelper.margin);
    });

    test('stays within the map at its edge', () {
      TileDimension dimension = TileHelper.calculateTiles(mapViewPosition: MapPosition(85, -180, 3), screensize: physical(screen));
      expect(dimension.minLeft, 0);
      expect(dimension.minTop, 0);
      expect(dimension.minRight, lessThanOrEqualTo(Tile.getMaxTileNumber(3)));
    });
  });

  group('TileJobQueue', () {
    testWidgets('a rotation that shows more of the map prepares the missing tiles', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _RecordingRenderer renderer = _RecordingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
        MapSize size = physical(screen);
        queue.setSize(size.width, size.height);
        MapPosition northUp = MapPosition(46, 18, 17);
        queue.setPosition(northUp);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        int northUpTiles = renderer.tiles.length;
        expect(northUpTiles, greaterThan(0));

        MapPosition rotated = MapPosition(46, 18, 17, 0, 45);
        queue.setPosition(rotated);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        TileDimension needed = TileHelper.calculateTiles(mapViewPosition: rotated, screensize: size);
        for (int x = needed.left; x <= needed.right; ++x) {
          for (int y = needed.top; y <= needed.bottom; ++y) {
            expect(renderer.tiles.contains(Tile(x, y, 17, 0)), isTrue, reason: 'tile $x/$y of the rotated view');
          }
        }
        expect(renderer.tiles.length, greaterThan(northUpTiles));
        queue.dispose();
        mapModel.dispose();
      });
    });

    testWidgets('a small rotation within the prepared tiles prepares nothing new', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _RecordingRenderer renderer = _RecordingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        TileJobQueue queue = TileJobQueue(mapModel: mapModel, renderer: renderer);
        MapSize size = physical(screen);
        queue.setSize(size.width, size.height);
        queue.setPosition(MapPosition(46, 18, 17, 0, 45));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        int prepared = renderer.tiles.length;

        queue.setPosition(MapPosition(46, 18, 17, 0, 40));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(renderer.tiles.length, prepared);
        queue.dispose();
        mapModel.dispose();
      });
    });
  });

  group('LabelJobQueue', () {
    /// Upper left tiles of the 5 x 5 blocks covering the tiles [dimension] shows.
    Set<Tile> blocks(TileDimension dimension, int zoomlevel) => {
      for (int y = (dimension.top / 5).floor() * 5; y <= dimension.bottom; y += 5)
        for (int x = (dimension.left / 5).floor() * 5; x <= dimension.right; x += 5) Tile(x, y, zoomlevel, 0),
    };

    testWidgets('a rotation that shows more of the map retrieves the missing label blocks', (WidgetTester tester) async {
      await tester.runAsync(() async {
        _RecordingRenderer renderer = _RecordingRenderer();
        MapModel mapModel = MapModel(renderer: renderer);
        LabelJobQueue queue = LabelJobQueue(mapModel: mapModel, renderer: renderer);
        MapSize size = physical(screen);
        queue.setSize(size.width, size.height);
        MapPosition northUp = MapPosition(46, 18, 17);
        MapPosition rotated = MapPosition(46, 18, 17, 0, 45);
        Set<Tile> northUpBlocks = blocks(TileHelper.calculateTiles(mapViewPosition: northUp, screensize: size), 17);
        Set<Tile> rotatedBlocks = blocks(TileHelper.calculateTiles(mapViewPosition: rotated, screensize: size), 17);
        // precondition: the rotated view needs blocks the north-up one does not
        expect(rotatedBlocks.difference(northUpBlocks), isNotEmpty);

        queue.setPosition(northUp);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(renderer.labelBlocks, northUpBlocks);

        queue.setPosition(rotated);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(renderer.labelBlocks.containsAll(rotatedBlocks), isTrue);
        queue.dispose();
        mapModel.dispose();
      });
    });
  });
}
