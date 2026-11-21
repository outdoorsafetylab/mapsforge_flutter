import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/marker.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:rxdart/rxdart.dart';

/// View state of one map: the current position, the renderers that draw it, and the streams for gestures and render changes.
///
/// A [MapModel] does not own its [Renderer]s. The same renderer, and the [Datastore] behind it, can be attached to several map models.
/// [dispose] therefore does not call [Renderer.dispose]. Dispose the renderer where it was created, after every map model that uses it is gone.
class MapModel extends ChangeNotifier {
  final List<Renderer> _renderers = [];

  MapPosition? _lastPosition;

  /// Lowest and highest zoom level this map accepts.
  final ZoomlevelRange zoomlevelRange;

  /// Inform a listener about the last known position even if he was not listening at the time, hence using the [BehaviorSubject].
  final Subject<MapPosition> _positionSubject = BehaviorSubject<MapPosition>();

  final Subject<Object> _manualMoveSubject = PublishSubject<Object>();

  final Subject<TapEvent?> _tapSubject = PublishSubject();

  final Subject<TapEvent?> _longTapSubject = PublishSubject();

  final Subject<TapEvent?> _doubleTapSubject = PublishSubject();

  final Subject<DragNdropEvent> _dragNdropSubject = PublishSubject();

  final Subject<RenderChangedEvent> _renderChangedSubject = PublishSubject();

  /// When using the context menu we often needs the markers which are tapped. To simplify that we register/unregister datastores to the map.
  final Set<MarkerDatastore> _markerDatastores = {};

  @Deprecated("Since 4.0.1. Use MapModel itself instead of MapModel.rotationNotifier for listening to map-changes")
  final ValueNotifier<double> rotationNotifier = ValueNotifier<double>(0.0);

  /// Current rotation in degrees, or 0 when no position has been set. Normalized to -180..180 by [setPosition].
  double get rotationDeg => _lastPosition?.rotation ?? 0.0;

  /// [renderer] is stored and not owned. See [dispose].
  MapModel({required Renderer renderer, this.zoomlevelRange = const ZoomlevelRange.standard()}) {
    _renderers.add(renderer);
  }

  bool _disposed = false;

  /// Closes the position and gesture streams and disposes marker datastores registered with [registerMarkerDatastore].
  ///
  /// Renderers passed to the constructor or [addRenderer] are not disposed. A renderer may still serve another [MapModel],
  /// and disposing it here would shut down its isolate while other maps, or tile jobs already in flight, still read from it.
  /// Call [Renderer.dispose] separately once no map model uses that renderer anymore.
  @override
  Future<void> dispose() async {
    _disposed = true;
    super.dispose();
    await _positionSubject.close();
    await _manualMoveSubject.close();
    await _tapSubject.close();
    await _longTapSubject.close();
    await _doubleTapSubject.close();
    await _dragNdropSubject.close();
    _renderers.clear();
    rotationNotifier.dispose();
    for (var datastore in List.of(_markerDatastores)) {
      datastore.dispose();
    }
    _markerDatastores.clear();
  }

  /// Adds another renderer. The model does not take ownership; see [dispose].
  void addRenderer(Renderer renderer) {
    _renderers.add(renderer);
  }

  /// Renderers attached to this map, in the order they were added. Not owned by this model.
  List<Renderer> get renderers => _renderers;

  /// Renderers from [renderers] that produce a separate label layer.
  Iterable<Renderer> get labelRenderers => _renderers.where((test) => test.supportLabels());

  /// Markers from the registered datastores that contain [event].
  List<Marker> getTappedMarkers(TapEvent event) {
    List<Marker> tappedMarkers = [];
    for (var datastore in _markerDatastores) {
      tappedMarkers.addAll(datastore.getTappedMarkers(event));
    }
    return tappedMarkers;
  }

  /// Stores [position], emits it on [positionStream], updates [rotationNotifier], and notifies listeners.
  ///
  /// Ignored after [dispose].
  void setPosition(MapPosition position) {
    // Late gesture or animation callbacks must not fail on the closed subjects.
    if (_disposed) return;
    _lastPosition = position;
    _positionSubject.add(position);
    rotationNotifier.value = _normalize180(position.rotation);
    notifyListeners();
  }

  double _normalize180(double deg) {
    deg = deg % 360;
    if (deg >= 180) deg -= 360;
    if (deg < -180) deg += 360;
    return deg;
  }

  /// Last position passed to [setPosition], or null before the first call.
  MapPosition? get lastPosition => _lastPosition;

  /// Emits every [setPosition], including the latest value for a listener that subscribes later.
  Stream<MapPosition> get positionStream => _positionSubject.stream;

  /// A stream which triggers an event if the user starts to move the map. This can be used to switch off automatic movements
  Stream<Object> get manualMoveStream => _manualMoveSubject.stream;

  /// A stream which triggers an event if the user taps at the map. Sending a null value down the stream means that the listener is not
  /// entitled to handle the event anymore. This is currently being used to hide the context menu.
  Stream<TapEvent?> get tapStream => _tapSubject.stream;

  /// A stream which triggers an event if the user long taps at the map. Sending a null value down the stream means that the listener is not
  /// entitled to handle the event anymore. This is currently being used to hide the context menu.
  Stream<TapEvent?> get longTapStream => _longTapSubject.stream;

  /// A stream which triggers an event if the user double-taps at the map. Sending a null value down the stream means that the listener is not
  /// entitled to handle the event anymore. This is currently being used to hide the context menu.
  Stream<TapEvent?> get doubleTapStream => _doubleTapSubject.stream;

  /// Emits [dragNdrop] events for the start, move, cancel, and finish of a drag.
  Stream<DragNdropEvent> get dragNdropStream => _dragNdropSubject.stream;

  /// Listens to [RenderChangedEvent] events.
  /// @see [RenderChangedEvent]
  Stream<RenderChangedEvent> get renderChangedStream => _renderChangedSubject.stream;

  /// Reports that the user started moving the map. Listeners use this to stop automatic movement. Ignored after [dispose].
  void manualMove(Object object) {
    if (_disposed) return;
    _manualMoveSubject.add(object);
  }

  /// sets or clears a tap event. Clearing a tap event usually means that the context menu should not be shown anymore
  void tap(TapEvent? event) {
    if (_disposed) return;
    _tapSubject.add(event);
  }

  /// Sets or clears a long-tap. A null [event] means the listener should stop handling it, usually by hiding the context menu. Ignored after [dispose].
  void longTap(TapEvent? event) {
    if (_disposed) return;
    _longTapSubject.add(event);
  }

  /// Sets or clears a double-tap. A null [event] means the listener should stop handling it, usually by hiding the context menu. Ignored after [dispose].
  void doubleTap(TapEvent? event) {
    if (_disposed) return;
    _doubleTapSubject.add(event);
  }

  /// Reports one step of a drag-and-drop gesture. Ignored after [dispose].
  void dragNdrop(DragNdropEvent event) {
    if (_disposed) return;
    _dragNdropSubject.add(event);
  }

  /// Triggers a [RenderChangedEvent] event.
  /// @see [RenderChangedEvent]
  void renderChanged(RenderChangedEvent event) {
    _renderChangedSubject.add(event);
  }

  /// Zooms in by one level around the current center. No effect at [ZoomlevelRange.zoomlevelMax] or before a position is set.
  void zoomIn() {
    if (_lastPosition!.zoomlevel == zoomlevelRange.zoomlevelMax) return;
    MapPosition newPosition = _lastPosition!.zoomIn();
    setPosition(newPosition);
  }

  /// Zooms in by one level, keeping [latitude] and [longitude] fixed on screen. No effect at [ZoomlevelRange.zoomlevelMax].
  void zoomInAround(double latitude, double longitude) {
    if (_lastPosition!.zoomlevel == zoomlevelRange.zoomlevelMax) return;
    MapPosition newPosition = _lastPosition!.zoomInAround(latitude, longitude);
    setPosition(newPosition);
  }

  /// Zooms out by one level around the current center. No effect at [ZoomlevelRange.zoomlevelMin].
  void zoomOut() {
    if (_lastPosition!.zoomlevel == zoomlevelRange.zoomlevelMin) return;
    MapPosition newPosition = _lastPosition!.zoomOut();
    setPosition(newPosition);
  }

  /// Jumps to [zoomLevel], clamped to [zoomlevelRange], keeping the current center. No effect when the level does not change.
  void zoomTo(int zoomLevel) {
    zoomLevel = zoomlevelRange.ensureBounds(zoomLevel);
    if (zoomLevel == _lastPosition!.zoomlevel) return;
    MapPosition newPosition = _lastPosition!.zoomTo(zoomLevel);
    setPosition(newPosition);
  }

  /// Jumps to [zoomLevel], clamped to [zoomlevelRange], keeping [latitude] and [longitude] fixed on screen.
  void zoomToAround(double latitude, double longitude, int zoomLevel) {
    zoomLevel = zoomlevelRange.ensureBounds(zoomLevel);
    MapPosition newPosition = _lastPosition!.zoomToAround(latitude, longitude, zoomLevel);
    setPosition(newPosition);
  }

  /// Selects the next higher indoor level of the current position.
  void indoorLevelUp() {
    MapPosition newPosition = _lastPosition!.indoorLevelUp();
    setPosition(newPosition);
  }

  /// Selects the next lower indoor level of the current position.
  void indoorLevelDown() {
    MapPosition newPosition = _lastPosition!.indoorLevelDown();
    setPosition(newPosition);
  }

  /// Selects indoor [level] without changing the geographic position.
  void setIndoorLevel(int level) {
    MapPosition newPosition = _lastPosition!.withIndoorLevel(level);
    setPosition(newPosition);
  }

  /// Sets the scale around a focal point.
  ///
  /// [focalPoint] The point to scale around.
  /// [scale] The new scale value. Must be greater than 0.
  /// A scale of 1 means no action,
  /// 0..1 means zoom-out (you will see more area on screen since at pinch-to-zoom the fingers are moved towards each other)
  /// >1 means zoom-in.
  /// Scaling is different from zooming. Scaling is used during pinch-to-zoom gesture to scale the current area.
  /// Zooming triggers new tile-images. Scaling does not.
  void scaleAround(Offset? focalPoint, double scale) {
    MapPosition newPosition = _lastPosition!.scaleAround(focalPoint, scale);
    setPosition(newPosition);
  }

  /// Moves the center to [latitude] and [longitude]. Requires a position to be set already.
  void moveTo(double latitude, double longitude) {
    MapPosition newPosition = _lastPosition!.moveTo(latitude, longitude);
    setPosition(newPosition);
  }

  /// Sets the map rotation to [rotation] degrees clockwise.
  void rotateTo(double rotation) {
    MapPosition newPosition = _lastPosition!.rotateTo(rotation);
    setPosition(newPosition);
  }

  /// Adds [rotationDelta] degrees clockwise to the current rotation.
  void rotateBy(double rotationDelta) {
    MapPosition newPosition = _lastPosition!.rotateBy(rotationDelta);
    setPosition(newPosition);
  }

  /// Moves the center to [latitude] and [longitude] and sets the rotation to [rotation] degrees clockwise.
  void moveRotateTo(double latitude, double longitude, double rotation) {
    MapPosition newPosition = _lastPosition!.moveRotateTo(latitude, longitude, rotation);
    setPosition(newPosition);
  }

  /// Sets the center to absolute map pixels [x] and [y]. Requires a position to be set already.
  void setCenter(double x, double y) {
    MapPosition newPosition = _lastPosition!.setCenter(x, y);
    setPosition(newPosition);
  }

  /// Shifts the center by [dx] and [dy] pixels.
  void moveCenter(double dx, double dy) {
    MapPosition newPosition = _lastPosition!.moveCenter(dx, dy);
    setPosition(newPosition);
  }

  /// Registers [datastore] so [getTappedMarkers] can search it. [dispose] disposes every datastore still registered.
  void registerMarkerDatastore(MarkerDatastore datastore) {
    _markerDatastores.add(datastore);
  }

  /// Removes [datastore] from this map. The caller keeps ownership and must dispose it.
  void unregisterMarkerDatastore(MarkerDatastore datastore) {
    _markerDatastores.remove(datastore);
  }
}

/////////////////////////////////////////////////////////////////////////////

/// Event which is triggered when the user taps at the map
class TapEvent implements ILatLong {
  // The position of the event in lat direction (north-south)
  @override
  final double latitude;

  // The position of the event in lon direction (east-west)
  @override
  final double longitude;

  final PixelProjection projection;

  /// The point of the event in absolute mappixels
  final Mappoint mappoint;

  const TapEvent({required this.latitude, required this.longitude, required this.projection, required this.mappoint});

  LatLong get latLong => LatLong(latitude, longitude);

  @override
  String toString() {
    return 'TapEvent{latitude: $latitude, longitude: $longitude, mappoint: $mappoint}';
  }
}

//////////////////////////////////////////////////////////////////////////////

class DragNdropEvent extends TapEvent {
  final DragNdropEventType type;

  DragNdropEvent({required super.latitude, required super.longitude, required super.projection, required super.mappoint, required this.type});
}

//////////////////////////////////////////////////////////////////////////////

enum DragNdropEventType {
  /// Drag'n'drop started
  start,

  /// Drag'n'drop cancelled, for example because the user moved outside of the view
  cancel,

  /// Drag'n'drop moved
  move,

  /// Drag'n'drop finished
  finish,
}

//////////////////////////////////////////////////////////////////////////////

enum TapEventListener {
  /// listen to single tap events
  singleTap,

  /// listen to double tap events
  doubleTap,

  /// listen to long tap events
  longTap;

  Stream<TapEvent?> getStream(MapModel mapModel) {
    switch (this) {
      case TapEventListener.singleTap:
        return mapModel.tapStream;
      case TapEventListener.doubleTap:
        return mapModel.doubleTapStream;
      case TapEventListener.longTap:
        return mapModel.longTapStream;
    }
  }

  /// Send a close-event to the listener (the listener receives null as parameter)
  void sendCloseRequest(MapModel mapModel) {
    switch (this) {
      case TapEventListener.singleTap:
        return mapModel._tapSubject.add(null);
      case TapEventListener.doubleTap:
        return mapModel._doubleTapSubject.add(null);
      case TapEventListener.longTap:
        return mapModel._longTapSubject.add(null);
    }
  }
}

//////////////////////////////////////////////////////////////////////////////

/// Event which is triggered when a part of the render area (hence a part of the map) has been changed so that a rerender is required.
/// This forces eventual caches to revalidate and redraw the screen if the
/// currently shown area is affected.
/// This may occur if a [MultimapDatastore] adds or removes datastores or if the user changes the desired [StyleMenuLayer].
class RenderChangedEvent {
  final BoundingBox boundingBox;

  RenderChangedEvent(this.boundingBox);
}
