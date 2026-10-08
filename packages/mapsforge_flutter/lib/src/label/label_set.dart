import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/spatial_boundary_index.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

class LabelSet {
  final Mappoint center;

  final MapPosition mapPosition;

  /// The labels of the job this set belongs to. Sets made for the same job (see [LabelJobQueue.setPosition]) share it.
  final JobLabels jobLabels;

  LabelSet({required this.center, required this.mapPosition, required this.jobLabels});

  Mappoint getCenter() => center;

  /// The labels to paint, collision-free across blocks.
  List<RenderInfo> get labels => jobLabels.labels;
}

/// The label blocks one job of a [LabelJobQueue] has received so far, and their labels merged into one collision-free
/// list.
///
/// Every block was made collision-free on its own when it was read, but labels of neighbouring blocks may still
/// overlap. Each time a block arrives, the labels of all blocks received so far that touch [area] are collided again,
/// with the same rule as [RenderInfoCollection.collisionFreeOrdered] but in a total order (priority, then the block's
/// position, then the label's place in its block), so the result does not depend on the order the blocks arrive in.
/// The blocks themselves are left alone: they are cached and shared with other views.
class JobLabels {
  /// The job's tiles (the visible ones plus the margin), in absolute pixels. Labels outside take no part.
  final MapRectangle area;

  /// The blocks received so far, by their left upper tile.
  final Map<Tile, RenderInfoCollection> _blocks = {};

  List<RenderInfo> _labels = const [];

  bool _aborted = false;

  JobLabels(this.area);

  /// The labels to paint, collision-free across blocks.
  List<RenderInfo> get labels => _labels;

  /// The number of blocks received so far.
  int get blockCount => _blocks.length;

  /// Whether the job was abandoned; blocks arriving afterwards are dropped.
  bool get aborted => _aborted;

  void abort() => _aborted = true;

  /// Adds the blocks and merges. Returns whether anything changed.
  bool addAll(Map<Tile, RenderInfoCollection> blocks) {
    if (_aborted) return false;
    bool added = false;
    blocks.forEach((Tile leftUpper, RenderInfoCollection block) {
      if (_blocks.containsKey(leftUpper)) return;
      _blocks[leftUpper] = block;
      added = true;
    });
    if (added) _merge();
    return added;
  }

  void _merge() {
    final session = PerformanceProfiler().startSession(category: "JobLabels.merge");
    List<_Candidate> candidates = [];
    _blocks.forEach((Tile leftUpper, RenderInfoCollection block) {
      List<RenderInfo> infos = block.renderInfos;
      for (int ordinal = 0; ordinal < infos.length; ++ordinal) {
        RenderInfo info = infos[ordinal];
        MapRectangle boundary = info.getBoundaryAbsolute();
        if (!boundary.intersects(area)) continue;
        candidates.add(_Candidate(info, boundary, leftUpper, ordinal));
      }
    });
    candidates.sort(_Candidate.compare);
    final SpatialBoundaryIndex<RenderInfo> spatialIndex = SpatialBoundaryIndex(cellSize: 16.0);
    List<RenderInfo> output = [];
    for (_Candidate candidate in candidates) {
      if (!spatialIndex.hasCollision(candidate.info, candidate.boundary)) {
        output.add(candidate.info);
        spatialIndex.add(candidate.info, candidate.boundary);
      }
    }
    _labels = output;
    session.complete();
  }
}

class _Candidate {
  final RenderInfo info;

  final MapRectangle boundary;

  final Tile block;

  final int ordinal;

  _Candidate(this.info, this.boundary, this.block, this.ordinal);

  /// Priority (highest first), then the block (top to bottom, left to right), then the place in the block.
  static int compare(_Candidate a, _Candidate b) {
    int result = b.info.renderInstruction.priority.compareTo(a.info.renderInstruction.priority);
    if (result != 0) return result;
    result = a.block.tileY.compareTo(b.block.tileY);
    if (result != 0) return result;
    result = a.block.tileX.compareTo(b.block.tileX);
    if (result != 0) return result;
    return a.ordinal.compareTo(b.ordinal);
  }
}
