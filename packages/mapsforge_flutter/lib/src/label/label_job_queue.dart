import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter/src/tile/tile_dimension.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/task_queue.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class LabelJobQueue extends ChangeNotifier {
  final MapModel mapModel;

  MapSize? _size;

  final MemoryLabelCache _cache;

  /// Whether this queue made [_cache] and so disposes it.
  final bool _ownsCache;

  _CurrentJob? _currentJob;

  late final StreamSubscription<RenderChangedEvent> _renderChangedSubscription;

  /// The labels are retrieved in blocks of [rangeAt] x [rangeAt] tiles, one request per block.
  ///
  /// At low zoom a block of 5 x 5 tiles covers so much ground that reading it takes many seconds (on a Pixel 5 at zoom
  /// 11 the first labels showed after 5 to 8 seconds, all of them after 11 to 17), so up to [smallBlockMaxZoom] the
  /// blocks are 3 x 3 (the first labels after less than a second, all after 3 to 9). Above, the 5 x 5 blocks stay:
  /// there one request is not what makes filling the view slow.
  static int rangeAt(int zoomlevel) => zoomlevel <= smallBlockMaxZoom ? 3 : 5;

  /// The highest zoom level with blocks of 3 x 3 tiles, see [rangeAt].
  static const int smallBlockMaxZoom = 13;

  /// Parallel task queue for tile loading optimization
  late final TaskQueue _taskQueue;

  /// Maximum number of concurrent tile loading operations
  static const int _maxConcurrentTiles = 4;

  final Renderer renderer;

  /// Keeps the labels in [cache] if given, and leaves it to its owner to dispose. See [MemoryLabelCache].
  LabelJobQueue({required this.mapModel, required this.renderer, MemoryLabelCache? cache})
    : _cache = cache ?? MemoryLabelCache.create(),
      _ownsCache = cache == null {
    _taskQueue = ParallelTaskQueue(_maxConcurrentTiles);

    _renderChangedSubscription = mapModel.renderChangedStream.listen((RenderChangedEvent event) {
      // simple approach, clear all
      _cache.purgeAll();
      _CurrentJob? myJob = _currentJob;
      if (myJob != null) {
        _currentJob?.abort();
        unawaited(
          _positionEvent(myJob.labelSet.mapPosition, myJob.tileDimension).catchError((error) {
            print(error);
          }),
        );
      }
    });
  }

  LabelSet get labelSet => _currentJob!.labelSet;

  void setPosition(MapPosition position) {
    if (_currentJob?.labelSet.mapPosition == position) {
      return;
    }
    if (_currentJob?.labelSet.mapPosition.latitude == position.latitude &&
        _currentJob?.labelSet.mapPosition.longitude == position.longitude &&
        _currentJob?.labelSet.mapPosition.zoomlevel == position.zoomlevel &&
        _currentJob?.labelSet.mapPosition.indoorLevel == position.indoorLevel &&
        _coversVisible(_currentJob!.tileDimension, TileHelper.calculateTiles(mapViewPosition: position, screensize: _size!), position.zoomlevel)) {
      // do not recalculate for rotation or scaling as long as the job covers the view, blocks still arriving go to the
      // same labels
      LabelSet labelSet = LabelSet(center: _currentJob!.labelSet.center, mapPosition: position, jobLabels: _currentJob!.labelSet.jobLabels);
      _CurrentJob myJob = _CurrentJob(_currentJob!.tileDimension, labelSet);
      _currentJob = myJob;
      _emitLabelSetBatched(_currentJob!.labelSet);
      return;
    }
    TileDimension tileDimension = TileHelper.calculateTiles(mapViewPosition: position, screensize: _size!);
    // if (_currentJob?.tileDimension.contains(tileDimension) ?? false) {
    //   if (_currentJob!._done) {
    //     _emitLabelSetBatched(_currentJob!.labelSet);
    //   } else {
    //     // same information to draw, previous job is still running
    //     return;
    //   }
    // }
    _currentJob?.abort();
    unawaited(_positionEvent(position, tileDimension));
  }

  @override
  void dispose() {
    super.dispose();
    _currentJob?.abort();
    _renderChangedSubscription.cancel();
    // remove all jobs without throwing exceptions
    _taskQueue.clear();
    _taskQueue.cancel();
    if (_ownsCache) _cache.dispose();
  }

  /// Sets the current size of the mapview so that we know which and how many tiles we need for the whole view
  void setSize(double width, double height) {
    if (_size == null || _size!.width != width || _size!.height != height) {
      _size = MapSize(width: width, height: height);
      if (mapModel.lastPosition != null) {
        TileDimension tileDimension = TileHelper.calculateTiles(mapViewPosition: mapModel.lastPosition!, screensize: _size!);
        _currentJob?.abort();
        unawaited(_positionEvent(mapModel.lastPosition!, tileDimension));
      }
      return;
    }
    _size = MapSize(width: width, height: height);
  }

  MapSize? getSize() => _size;

  /// Whether the job prepared for [prepared] covers every tile [needed] shows: its blocks of [rangeAt] x [rangeAt]
  /// tiles were read for them, and its labels were merged over them (the tiles of [prepared] plus the margin, see
  /// [JobLabels.area]).
  bool _coversVisible(TileDimension prepared, TileDimension needed, int zoomlevel) {
    int range = rangeAt(zoomlevel);
    return prepared.coversVisible(needed) &&
        (prepared.left / range).floor() * range <= needed.left &&
        (prepared.right / range).floor() * range + range - 1 >= needed.right &&
        (prepared.top / range).floor() * range <= needed.top &&
        (prepared.bottom / range).floor() * range + range - 1 >= needed.bottom;
  }

  Future<void> _positionEvent(MapPosition position, TileDimension tileDimension) async {
    final session = PerformanceProfiler().startSession(category: "LabelJobQueue");
    double tileSize = position.projection.tileSize;
    MapRectangle area = MapRectangle(
      tileDimension.minLeft * tileSize,
      tileDimension.minTop * tileSize,
      (tileDimension.minRight + 1) * tileSize,
      (tileDimension.minBottom + 1) * tileSize,
    );
    LabelSet labelSet = LabelSet(center: position.getCenter(), mapPosition: position, jobLabels: JobLabels(area));
    _CurrentJob myJob = _CurrentJob(tileDimension, labelSet);
    _currentJob = myJob;
    // blocks start at multiples of the range
    int maxTileNbr = Tile.getMaxTileNumber(position.zoomlevel);
    int range = rangeAt(position.zoomlevel);
    List<Tile> missingTiles = [];
    Map<Tile, RenderInfoCollection> cached = {};
    for (int top = (tileDimension.top / range).floor() * range; top <= tileDimension.bottom; top += range) {
      for (int left = (tileDimension.left / range).floor() * range; left <= tileDimension.right; left += range) {
        Tile leftUpper = Tile(left, top, position.zoomlevel, position.indoorLevel);
        try {
          RenderInfoCollection? collection = _cache.get(leftUpper);
          if (collection != null) {
            cached[leftUpper] = collection;
          } else {
            missingTiles.add(leftUpper);
          }
        } catch (e) {
          missingTiles.add(leftUpper);
        }
      }
    }
    if (myJob.aborted) return;
    if (labelSet.jobLabels.addAll(cached)) {
      _emitLabelSetBatched(labelSet);
    }
    for (Tile tile in missingTiles) {
      unawaited(_taskQueue.add(() => _produceLabel(myJob, tile.tileX, tile.tileY, position, maxTileNbr)));
    }
    unawaited(
      _taskQueue.add(() async {
        myJob._done = true;
      }),
    );
    session.complete();
  }

  Future<void> _produceLabel(_CurrentJob myJob, int left, int top, MapPosition position, int maxTileNbr) async {
    if (myJob.aborted) return;
    Tile leftUpper = Tile(left, top, position.zoomlevel, position.indoorLevel);
    int range = rangeAt(position.zoomlevel);
    Tile rightLower = Tile(min(left + range - 1, maxTileNbr), min(top + range - 1, maxTileNbr), position.zoomlevel, position.indoorLevel);
    try {
      RenderInfoCollection collection = await _cache.getOrProduce(leftUpper, rightLower, (Tile tile) async {
        JobResult result = await renderer.retrieveLabels(JobRequest(leftUpper, rightLower));
        if (result.renderInfo == null) throw Exception("No renderInfo for $tile from renderer ${renderer.getRenderKey()}");
        return result.renderInfo!;
      });
      // a label set made for this job later on (rotation, scaling) shares its labels, so it shows this block too
      if (myJob.labelSet.jobLabels.addAll({leftUpper: collection})) {
        _emitLabelSetBatched(myJob.labelSet);
      }
    } on TimeoutException {
      // job cancelled, ignore this error
    }
  }

  /// Emit tile set with batching to reduce stream emissions
  void _emitLabelSetBatched(LabelSet labelSet) {
    notifyListeners();
  }
}

//////////////////////////////////////////////////////////////////////////////

class _CurrentJob {
  final TileDimension tileDimension;

  final LabelSet labelSet;

  bool _done = false;

  _CurrentJob(this.tileDimension, this.labelSet);

  /// Aborts every label set made for this job, see [JobLabels.abort].
  void abort() => labelSet.jobLabels.abort();

  bool get aborted => labelSet.jobLabels.aborted;
}
