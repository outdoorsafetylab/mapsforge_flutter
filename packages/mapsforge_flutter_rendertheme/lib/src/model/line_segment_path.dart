import 'dart:math';

import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/line_segment.dart';

/// A list of Linesegments which consists of segments in screen-pixels.
class LineSegmentPath {
  /// The sharpest corner (in degrees) a text may span, as in Java mapsforge.
  static const double maxTextCornerAngle = 45;

  /// Segments shorter than this (in pixels) are ignored when placing texts.
  static const double minTextSegmentLength = 0.5;

  final List<LineSegment> segments = [];

  MapRectangle? _bounds;

  /// Creates a new LineString that consists of only the part between startDistance and endDistance.
  LineSegmentPath extractPart(double startDistance, double endDistance) {
    LineSegmentPath result = LineSegmentPath();

    for (int i = 0; i < segments.length; startDistance -= segments.elementAt(i).length(), endDistance -= segments.elementAt(i).length(), i++) {
      LineSegment segment = segments.elementAt(i);

      // Skip first segments that we don't need
      double length = segment.length();
      if (length < startDistance) {
        continue;
      }

      Mappoint? startPoint, endPoint;
      if (startDistance >= 0) {
        // This will be our starting point
        startPoint = segment.pointAlongLineSegment(startDistance);
      }
      if (endDistance < length) {
        // this will be our ending point
        endPoint = segment.pointAlongLineSegment(endDistance);
      }

      if (startPoint != null && endPoint == null) {
        // This ist the starting segment, end will come in a later segment
        result.segments.add(LineSegment(startPoint, segment.end));
      } else if (startPoint == null && endPoint == null) {
        // Center segment between start and end segment, add completely
        result.segments.add(segment);
      } else if (startPoint == null && endPoint != null) {
        // End segment, start was in earlier segment
        result.segments.add(LineSegment(segment.start, endPoint));
      } else if (startPoint != null && endPoint != null) {
        // Start and end on same segment
        result.segments.add(LineSegment(startPoint, endPoint));
      }

      if (endPoint != null) break;
    }

    return result;
  }

  MapRectangle getBounds() {
    if (_bounds != null) return _bounds!;

    double minX = double.maxFinite;
    double minY = double.maxFinite;
    double maxX = double.minPositive;
    double maxY = double.minPositive;

    for (LineSegment segment in segments) {
      minX = min(minX, min(segment.start.x, segment.end.x));
      minY = min(minY, min(segment.start.y, segment.end.y));
      maxX = max(maxX, max(segment.start.x, segment.end.x));
      maxY = max(maxY, max(segment.start.y, segment.end.y));
    }
    _bounds = MapRectangle(minX, minY, maxX, maxY);
    return _bounds!;
  }

  /// Interpolates on the segment and returns the coordinate of the interpolation result.
  /// Returns null if distance is < 0 or > length().
  Mappoint? interpolate(double distance) {
    if (distance < 0) {
      return null;
    }

    for (LineSegment segment in segments) {
      double length = segment.length();
      if (distance <= length) {
        return segment.pointAlongLineSegment(distance);
      }
      distance -= length;
    }
    return null;
  }

  double length() {
    double result = 0;
    for (LineSegment segment in segments) {
      result += segment.length();
    }
    return result;
  }

  /// Where texts of [textWidth] go along this path. As in Java mapsforge's `WayDecorator.renderText`, a window of
  /// [textWidth] is tried at [repeatStart] and then every [repeatGap] + [textWidth] while it fits, and is used when
  /// none of its corners exceeds [maxTextCornerAngle]. The text is drawn straight, so a window is also dropped when
  /// one of its points lies further than [maxDeviation] from the window's chord.
  ///
  /// Returns the chord of every window used; the text belongs centred on it.
  List<LineSegment> textPositions(double textWidth, double repeatStart, double repeatGap, double maxDeviation) {
    final List<LineSegment> result = [];
    if (textWidth <= 0) return result;
    final double pathLength = length();
    for (double pos = repeatStart; pos + textWidth <= pathLength; pos += repeatGap + textWidth) {
      // extractPart() yields a zero-length segment when the window starts or ends on a vertex; it has no direction
      // and would read as a corner
      final List<LineSegment> part = extractPart(pos, pos + textWidth).segments.where((segment) => segment.length() >= minTextSegmentLength).toList();
      if (part.isEmpty) continue;
      if (!_cornersWithin(part, maxTextCornerAngle)) continue;
      final LineSegment chord = LineSegment(part.first.start, part.last.end);
      if (chord.length() < minTextSegmentLength) continue;
      if (_deviationFrom(chord, part) > maxDeviation) continue;
      result.add(chord);
    }
    return result;
  }

  static bool _cornersWithin(List<LineSegment> part, double maxAngle) {
    for (int i = 1; i < part.length; i++) {
      if (part[i - 1].angleTo(part[i]).abs() > maxAngle) return false;
    }
    return true;
  }

  /// The largest distance of a point of [part] from the line through [chord].
  static double _deviationFrom(LineSegment chord, List<LineSegment> part) {
    final double dx = chord.end.x - chord.start.x;
    final double dy = chord.end.y - chord.start.y;
    final double length = chord.length();
    double result = 0;
    for (LineSegment segment in part) {
      final Mappoint point = segment.end;
      result = max(result, ((point.x - chord.start.x) * dy - (point.y - chord.start.y) * dx).abs() / length);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LineSegmentPath && runtimeType == other.runtimeType && segments == other.segments;

  @override
  int get hashCode => segments.hashCode;
}
