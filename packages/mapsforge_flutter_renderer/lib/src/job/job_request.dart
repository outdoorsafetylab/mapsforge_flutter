import 'package:mapsforge_flutter_core/model.dart';

/// Request object for tile rendering operations.
///
/// This class encapsulates the parameters needed to render a map tile,
/// including the primary tile coordinates and optional multi-tile rendering
/// support for larger areas or higher resolution output.
///
/// Key features:
/// - Single tile rendering support
/// - Multi-tile rendering with tile ranges
/// - Zoom level and indoor level validation
/// - Immutable request parameters
class JobRequest {
  /// Primary tile to render, or upper-left tile for multi-tile rendering.
  final Tile tile;

  /// Optional lower-right tile for multi-tile rendering areas.
  ///
  /// When specified, defines a rectangular area from the primary tile
  /// to this tile for batch rendering operations.
  final Tile? rightLower;

  /// Asked before the request is sent to the reader: true if the job which made the request no longer needs it. The
  /// request is then dropped and completes with a [JobCancelledException]. Null for requests which are never dropped.
  final bool Function()? isCancelled;

  /// The order of the request among the waiting requests of the same kind (tiles or labels), lower first. Requests of
  /// the same order are sent in the order they arrived.
  final int order;

  /// Creates a new job request for tile rendering.
  ///
  /// [tile] Primary tile coordinates to render
  /// [rightLower] Optional lower-right tile for multi-tile rendering
  ///
  /// Throws AssertionError if multi-tile parameters have mismatched zoom or indoor levels
  JobRequest(this.tile, [this.rightLower]) : isCancelled = null, order = 0 {
    assert(rightLower == null || tile.zoomLevel == rightLower!.zoomLevel, 'Multi-tile rendering requires matching zoom levels');
    assert(rightLower == null || tile.indoorLevel == rightLower!.indoorLevel, 'Multi-tile rendering requires matching indoor levels');
  }

  /// Creates a job request which waits for the reader in the given [order] and is dropped if [isCancelled] returns true
  /// before it is sent, see [isCancelled] and [order].
  JobRequest.scheduled(this.tile, {this.rightLower, this.isCancelled, this.order = 0}) {
    assert(rightLower == null || tile.zoomLevel == rightLower!.zoomLevel, 'Multi-tile rendering requires matching zoom levels');
    assert(rightLower == null || tile.indoorLevel == rightLower!.indoorLevel, 'Multi-tile rendering requires matching indoor levels');
  }
}

//////////////////////////////////////////////////////////////////////////////

/// A [JobRequest] dropped before it reached the reader because the job which made it was cancelled, or because the
/// renderer was disposed. Not an error: nobody needs the result any more.
class JobCancelledException implements Exception {
  final Tile tile;

  const JobCancelledException(this.tile);

  @override
  String toString() => 'JobCancelledException: $tile';
}
