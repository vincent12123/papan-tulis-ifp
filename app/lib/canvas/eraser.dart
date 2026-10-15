import 'dart:ui';

import 'shapes.dart';
import 'stroke.dart';

/// Whether an eraser circle at [center] with [radius] touches [item].
/// Strokes and shapes are erased whole (SPEC 5.1); pictures are not erased
/// (they are removed with Pilih) and neither is the page background.
bool eraserTouchesItem(PageItem item, Offset center, double radius) =>
    switch (item) {
      Stroke() => eraserTouches(item, center, radius),
      ShapeItem() => _touchesPolyline(
        shapeOutline(item),
        item.width,
        item.bounds,
        center,
        radius,
      ),
      ImageItem() ||
      GraphItem() ||
      TextItem() ||
      SolidItem() ||
      PeragaItem() ||
      QuizItem() ||
      TableItem() ||
      ChartItem() => false,
    };

/// Whether an eraser circle at [center] with [radius] touches [stroke]:
/// anywhere on its centerline, widened by half the pen width.
bool eraserTouches(Stroke stroke, Offset center, double radius) {
  if (stroke.points.isEmpty) return false;
  return _touchesPolyline(
    [for (final p in stroke.points) Offset(p.x, p.y)],
    stroke.width,
    stroke.bounds,
    center,
    radius,
  );
}

bool _touchesPolyline(
  List<Offset> points,
  double width,
  Rect bounds,
  Offset center,
  double radius,
) {
  if (points.isEmpty) return false;
  final reach = radius + width / 2;
  if (!bounds.inflate(radius).contains(center)) return false;
  if (points.length == 1) return (points.first - center).distance <= reach;
  for (var i = 0; i < points.length - 1; i++) {
    if (_distanceToSegment(center, points[i], points[i + 1]) <= reach) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
