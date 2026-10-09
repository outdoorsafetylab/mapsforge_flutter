import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_painter.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// A view to display the tiles. The view updates itself whenever the [MapPosition] changes and new tiles are available.
class TileView extends StatefulWidget {
  final MapModel mapModel;

  final Renderer renderer;

  /// Where the view keeps the tiles it renders. Pass one to keep them beyond the view, see [TileCache]; the view does
  /// not dispose it. Null makes a cache of the view's own. Cannot be changed on a live view.
  final TileCache? cache;

  const TileView({super.key, required this.mapModel, required this.renderer, this.cache});

  @override
  State<TileView> createState() => _TileViewState();
}

//////////////////////////////////////////////////////////////////////////////

class _TileViewState extends State<TileView> {
  late final TileJobQueue jobQueue;

  @override
  void initState() {
    super.initState();
    jobQueue = TileJobQueue(mapModel: widget.mapModel, renderer: widget.renderer, cache: widget.cache);
  }

  @override
  void dispose() {
    jobQueue.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapModel != widget.mapModel) {
      throw Exception("MapModel cannot be changed, recreate all classes which uses MapModel.");
    }
    if (oldWidget.cache != widget.cache) {
      throw Exception("TileCache cannot be changed, recreate the view.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        /// Multiply the mappixels of the view with the scalefactor because the images will be shrinked by that factor in [TransformWidget].
        jobQueue.setSize(
          constraints.maxWidth * MapsforgeSettingsMgr().getDeviceScaleFactor(),
          constraints.maxHeight * MapsforgeSettingsMgr().getDeviceScaleFactor(),
        );
        // use notifier instead of stream because it should be faster
        return ListenableBuilder(
          listenable: widget.mapModel,
          builder: (BuildContext context, Widget? child) {
            MapPosition? position = widget.mapModel.lastPosition;
            //print("Position change $position for renderer ${widget.renderer.getRenderKey()}");
            if (position == null) {
              return const SizedBox();
            }
            jobQueue.setPosition(position);
            return TransformWidget(
              mapCenter: position.getCenter(),
              mapPosition: position,
              screensize: Size(constraints.maxWidth, constraints.maxHeight),
              child: child!,
            );
            //            }
            // We do not have a position yet or we wait for processing of the first tiles
            //          return const SizedBox.expand();
          },
          // A layer of its own: painting the tiles is expensive, and without it every repaint of anything else in
          // the same layer (a marker, a scale bar redrawn on every compass event) painted them again as well.
          child: RepaintBoundary(
            child: CustomPaint(foregroundPainter: TilePainter(jobQueue), child: const SizedBox.expand()),
          ),
        );
      },
    );
  }
}
