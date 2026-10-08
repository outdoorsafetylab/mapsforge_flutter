import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/cache.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/util/datastore_reader_impl.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';

import '../test_asset_bundle.dart';

/// Counts the reader isolates a renderer starts.
class _CountingRenderer extends DatastoreRenderer {
  _CountingRenderer(super.datastore, super.rendertheme) : super(useIsolateReader: true);

  final List<IsolateDatastoreReader> readers = [];

  int started = 0;

  @override
  Future<IsolateDatastoreReader> createIsolateReader(Datastore datastore) async {
    ++started;
    IsolateDatastoreReader reader = await super.createIsolateReader(datastore);
    readers.add(reader);
    return reader;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SymbolCacheMgr().symbolCache = FileSymbolCache();
    SymbolCacheMgr().symbolCache.addLoader("jar:", ImageBundleLoader(bundle: TestAssetBundle("test/cache")));
  });

  MemoryDatastore createDatastore() {
    MemoryDatastore datastore = MemoryDatastore();
    datastore.addPoi(PointOfInterest(0, TagCollection(tags: [const Tag('place', 'suburb'), const Tag('name', 'TestSuburb')]), const LatLong(46, 17.998)));
    datastore.addWay(
      Way(
        0,
        [const Tag('name', 'TestWay'), const Tag('railway', 'rail')],
        [
          [const LatLong(45.95, 17.95), const LatLong(46.05, 18.05)],
        ],
        null,
      ),
    );
    return datastore;
  }

  List<Tile> tiles(int count) {
    int zoomlevel = 16;
    int x = MercatorProjection.fromZoomlevel(zoomlevel).longitudeToTileX(18);
    int y = MercatorProjection.fromZoomlevel(zoomlevel).latitudeToTileY(46);
    return List.generate(count, (i) => Tile(x + i % 2, y + i ~/ 2, zoomlevel, 0));
  }

  testWidgets('jobs started together share one reader isolate', (WidgetTester tester) async {
    await tester.runAsync(() async {
      Rendertheme renderTheme = await RenderThemeBuilder.createFromFile("test/datastore_renderer/defaultrender.xml");
      _CountingRenderer renderer = _CountingRenderer(createDatastore(), renderTheme);

      // the tile job queue runs several jobs at once
      List<JobResult> results = await Future.wait([for (Tile tile in tiles(4)) renderer.executeJob(JobRequest(tile))]);

      expect(renderer.started, 1);
      expect(results.every((result) => result.picture != null), isTrue);
      for (JobResult result in results) {
        result.picture!.dispose();
      }
      renderer.dispose();
    });
  });

  testWidgets('dispose stops the reader isolate and no job starts another one', (WidgetTester tester) async {
    await tester.runAsync(() async {
      Rendertheme renderTheme = await RenderThemeBuilder.createFromFile("test/datastore_renderer/defaultrender.xml");
      _CountingRenderer renderer = _CountingRenderer(createDatastore(), renderTheme);
      Tile tile = tiles(1).first;
      JobResult result = await renderer.executeJob(JobRequest(tile));
      result.picture?.dispose();
      IsolateDatastoreReader reader = renderer.readers.single;
      RenderthemeZoomlevel level = renderTheme.prepareZoomlevel(tile.zoomLevel);
      expect(await reader.read(tile, level), isNotNull);

      renderer.dispose();
      // the reader is disposed asynchronously: it first lets the isolate dispose its datastore
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await expectLater(reader.read(tile, level), throwsStateError);
      await expectLater(renderer.executeJob(JobRequest(tile)), throwsStateError);
      expect(renderer.started, 1);
    });
  });
}
