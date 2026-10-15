import 'dart:math';
import 'dart:ui';

import 'stroke.dart';

/// Outline of [shape] as a path to stroke.
Path shapePath(ShapeItem shape) {
  final p = shape.points;
  final path = Path();
  switch (shape.type) {
    case ShapeType.garis:
      path
        ..moveTo(p[0].dx, p[0].dy)
        ..lineTo(p[1].dx, p[1].dy);
    case ShapeType.persegi:
      path.addRect(Rect.fromPoints(p[0], p[1]));
    case ShapeType.lingkaran:
      path.addOval(Rect.fromPoints(p[0], p[1]));
    case ShapeType.segitiga:
      final corners = trianglePoints(shape);
      path.addPolygon(corners, true);
    case ShapeType.panah:
      path
        ..moveTo(p[0].dx, p[0].dy)
        ..lineTo(p[1].dx, p[1].dy);
      final dir = p[1] - p[0];
      if (dir.distance > 0) {
        final head = max(shape.width * 4, 16.0);
        final angle = atan2(dir.dy, dir.dx);
        for (final side in const [-0.45, 0.45]) {
          final a = angle + pi + side;
          path
            ..moveTo(p[1].dx, p[1].dy)
            ..lineTo(p[1].dx + cos(a) * head, p[1].dy + sin(a) * head);
        }
      }
  }
  return path;
}

/// Three corners of a triangle: either the stored ones, or (from a dragged
/// rectangle) apex top-center with the base along the bottom.
List<Offset> trianglePoints(ShapeItem shape) {
  if (shape.points.length == 3) return shape.points;
  final r = Rect.fromPoints(shape.points[0], shape.points[1]);
  return [r.topCenter, r.bottomRight, r.bottomLeft];
}

/// Points along the shape outline, for eraser hit tests.
List<Offset> shapeOutline(ShapeItem shape) {
  final p = shape.points;
  switch (shape.type) {
    case ShapeType.garis:
    case ShapeType.panah:
      return [p[0], p[1]];
    case ShapeType.persegi:
      final r = Rect.fromPoints(p[0], p[1]);
      return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft];
    case ShapeType.segitiga:
      final t = trianglePoints(shape);
      return [...t, t.first];
    case ShapeType.lingkaran:
      final r = Rect.fromPoints(p[0], p[1]);
      return [
        for (var i = 0; i <= 48; i++)
          Offset(
            r.center.dx + r.width / 2 * cos(i * pi / 24),
            r.center.dy + r.height / 2 * sin(i * pi / 24),
          ),
      ];
  }
}

/// A recognized shape: its type and the points to store.
typedef RecognizedShape = ({ShapeType type, List<Offset> points});

/// Turns a freehand stroke into a neat shape when it clearly is one
/// (P-07 "Otomatis"): a line, a rectangle, a circle/ellipse, or a triangle.
/// Returns null when the drawing does not match, so it stays as drawn.
RecognizedShape? recognizeShape(List<InkPoint> input) {
  if (input.length < 3) return null;
  final pts = [for (final p in input) Offset(p.x, p.y)];
  var box = Rect.fromPoints(pts.first, pts.first);
  for (final p in pts) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  final diag = sqrt(box.width * box.width + box.height * box.height);
  if (diag < 24) return null;

  var length = 0.0;
  for (var i = 1; i < pts.length; i++) {
    length += (pts[i] - pts[i - 1]).distance;
  }
  final ends = (pts.last - pts.first).distance;

  // Nearly straight: a line.
  if (ends / length > 0.92) {
    return (type: ShapeType.garis, points: [pts.first, pts.last]);
  }

  // Shapes must be closed: the end comes back near the start.
  if (ends > diag * 0.25) return null;

  final closed = [...pts, pts.first];
  final simplified = _simplify(closed, diag * 0.07);
  // Drop the repeated closing point and merge corners that are very close.
  final corners = <Offset>[];
  for (final p in simplified.take(simplified.length - 1)) {
    if (corners.isEmpty || (p - corners.last).distance > diag * 0.15) {
      corners.add(p);
    }
  }
  if (corners.length > 1 &&
      (corners.first - corners.last).distance < diag * 0.15) {
    corners.removeLast();
  }

  if (corners.length == 3) {
    return (type: ShapeType.segitiga, points: corners);
  }
  if (corners.length == 4 && _isRectangular(corners, box)) {
    return (type: ShapeType.persegi, points: [box.topLeft, box.bottomRight]);
  }
  if (_isRound(pts, box)) {
    return (type: ShapeType.lingkaran, points: [box.topLeft, box.bottomRight]);
  }
  return null;
}

/// Corners lie near the bounding box corners.
bool _isRectangular(List<Offset> corners, Rect box) {
  final targets = [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft];
  final tolerance = box.shortestSide * 0.35;
  return targets.every(
    (t) => corners.any((c) => (c - t).distance <= tolerance),
  );
}

/// Points stay close to the ellipse inscribed in the bounding box.
bool _isRound(List<Offset> pts, Rect box) {
  if (box.shortestSide < 8) return false;
  final rx = box.width / 2, ry = box.height / 2;
  var error = 0.0;
  for (final p in pts) {
    final dx = (p.dx - box.center.dx) / rx;
    final dy = (p.dy - box.center.dy) / ry;
    error += (sqrt(dx * dx + dy * dy) - 1).abs();
  }
  return error / pts.length < 0.12;
}

/// Ramer–Douglas–Peucker polyline simplification.
List<Offset> _simplify(List<Offset> pts, double epsilon) {
  if (pts.length < 3) return pts;
  var maxDist = 0.0;
  var index = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distanceToLine(pts[i], pts.first, pts.last);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }
  if (maxDist <= epsilon) return [pts.first, pts.last];
  final left = _simplify(pts.sublist(0, index + 1), epsilon);
  final right = _simplify(pts.sublist(index), epsilon);
  return [...left.take(left.length - 1), ...right];
}

double _distanceToLine(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distance;
  if (len == 0) return (p - a).distance;
  return ((ab.dx * (a.dy - p.dy)) - (ab.dy * (a.dx - p.dx))).abs() / len;
}
