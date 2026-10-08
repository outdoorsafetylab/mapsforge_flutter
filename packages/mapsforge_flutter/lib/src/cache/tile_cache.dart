import 'package:ecache/ecache.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

/// The rendered tiles of a [TileView], by tile.
///
/// A view makes a cache of its own unless it is given one. Give the same cache to the views that show the same renderer
/// one after another, e.g. a map that is rebuilt whenever its page comes back, and a view built again shows the tiles
/// the previous one rendered instead of rendering them again. Whoever creates a cache disposes it, once no view uses it
/// any more: a view never disposes a cache it was given.
///
/// Evicted tiles are disposed, so keep [capacity] well above the number of tiles one view shows at a time.
class TileCache {
  final LruCache<Tile, TilePicture?> _cache;

  TileCache({int capacity = 2000})
    : _cache = LruCache<Tile, TilePicture?>(
        onEvict: (tile, picture) {
          picture?.dispose();
        },
        capacity: capacity,
        name: "TileCache",
      );

  /// Returns the tile if it has been rendered. Throws while it is still being rendered.
  TilePicture? get(Tile tile) => _cache.get(tile);

  /// Returns the tile, rendering it with [producer] if nobody has yet. A tile that could not be rendered is not kept,
  /// so the next request renders it again.
  Future<TilePicture?> getOrProduce(Tile tile, Future<TilePicture?> Function(Tile) producer) async {
    try {
      return await _cache.getOrProduce(tile, producer);
    } catch (_) {
      forgetFailure(_cache, tile);
      rethrow;
    }
  }

  /// Disposes all tiles.
  void clear() => _cache.clear();

  /// Disposes all tiles.
  void dispose() => _cache.dispose();
}

/// ecache keeps a failed production and answers every later request for [key] with the same error. Removes [key] if
/// that is what the cache holds for it, so the next request produces it again.
void forgetFailure<K, V>(DefaultCache<K, V> cache, K key) {
  Entry<K, V>? entry = cache.storage.get(key)?.entry;
  if (entry is ProducerEntry<K, V> && entry.completer.isCompleted) {
    cache.remove(key);
  }
}
