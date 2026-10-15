import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import 'stroke.dart';

/// Lower streamline than the library default so the ink stays under the
/// finger on a large panel (REQ-01: tanpa jeda yang terasa).
StrokeOptions strokeOptions(Stroke stroke, {required bool complete}) {
  return StrokeOptions(
    size: stroke.width * 2,
    thinning: 0.55,
    smoothing: 0.5,
    streamline: 0.3,
    simulatePressure: !stroke.hasPressure,
    isComplete: complete,
  );
}

/// Outline polygon points of [stroke]; empty when the stroke has no points.
List<Offset> strokeOutline(Stroke stroke, {required bool complete}) {
  if (stroke.points.isEmpty) return const [];
  final input = [
    for (final p in stroke.points)
      PointVector(p.x, p.y, stroke.hasPressure ? p.pressure : null),
  ];
  return getStroke(input, options: strokeOptions(stroke, complete: complete));
}

/// Filled path for [stroke]. A single-point stroke (a tap) becomes a dot.
Path buildStrokePath(Stroke stroke, {required bool complete}) {
  if (stroke.points.isEmpty) return Path();
  if (stroke.isDot) {
    final p = stroke.points.first;
    return Path()..addOval(
      Rect.fromCircle(center: Offset(p.x, p.y), radius: stroke.width / 2),
    );
  }
  final outline = strokeOutline(stroke, complete: complete);
  final path = Path();
  if (outline.isEmpty) return path;
  path.moveTo(outline.first.dx, outline.first.dy);
  // Quadratic curves through midpoints give a smooth outline.
  for (var i = 0; i < outline.length - 1; i++) {
    final a = outline[i];
    final b = outline[i + 1];
    path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
  path.close();
  return path;
}

/// Completed strokes never change, so their path is computed once.
Path completedStrokePath(Stroke stroke) =>
    stroke.cachedPath ??= buildStrokePath(stroke, complete: true);
