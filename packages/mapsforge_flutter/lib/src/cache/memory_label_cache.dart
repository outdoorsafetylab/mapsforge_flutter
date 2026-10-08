import 'package:ecache/ecache.dart';
import 'package:mapsforge_flutter/src/cache/tile_cache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

///
/// This is a memory-only implementation of the [TileBitmapCache]. It stores the bitmaps in memory.
/// We use a factory and remember all active instances. This way we can easily purge caches if needed.
///
/// A [LabelView] makes a cache of its own unless it is given one. Like a [TileCache], one cache can serve the views
/// that show the same renderer one after another; whoever creates a cache disposes it, a view never disposes a cache
/// it was given.
///
class MemoryLabelCache {
  static final List<MemoryLabelCache> _instances = [];

  late LruCache<Tile, RenderInfoCollection> _cache;

  /// [capacity] is in blocks of labels, each of which covers 5 x 5 tiles.
  factory MemoryLabelCache.create({int capacity = 500}) {
    MemoryLabelCache result = MemoryLabelCache._(capacity);
    _instances.add(result);
    return result;
  }

  static void purgeAllCaches() {
    for (MemoryLabelCache cache in _instances) {
      cache.purgeAll();
    }
  }

  static void purgeCachesByBoundary(BoundingBox boundingBox) {
    for (MemoryLabelCache cache in _instances) {
      cache.purgeByBoundary(boundingBox);
    }
  }

  MemoryLabelCache._(int capacity) {
    _cache = LruCache<Tile, RenderInfoCollection>(capacity: capacity, name: "MemoryLabelCache");
  }

  void dispose() {
    _cache.dispose();
    _instances.remove(this);
  }

  void purgeAll() {
    _cache.clear();
  }

  void purgeByBoundary(BoundingBox boundingBox) {
    _cache.clear();
    // _cache.storage.keys
    //     .where((RenderInfoCollection tile) {
    //       if (tile.getBoundingBox().intersects(boundingBox)) {
    //         return true;
    //       }
    //       return false;
    //     })
    //     .forEach((tile) {
    //       _cache.remove(tile);
    //     });
  }

  /// Labels that could not be produced are not kept, so the next request produces them again.
  Future<RenderInfoCollection> getOrProduce(Tile leftUpper, Tile rightLower, Future<RenderInfoCollection> Function(Tile) producer) async {
    try {
      return await _cache.getOrProduce(leftUpper, producer);
    } catch (_) {
      forgetFailure(_cache, leftUpper);
      rethrow;
    }
  }

  RenderInfoCollection? get(Tile tile) {
    try {
      return _cache.get(tile);
    } catch (error) {
      // Exception: Cannot get a value from a producer since the value is a future and the get() method is synchronously
      // a value is still in progress, return null
      return null;
    }
  }
}
