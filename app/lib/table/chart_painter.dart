import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';
import 'table_data.dart';

/// Draws a chart made from a table (REQ-21): Garis, Batang (grouped when
/// there are several series), or Titik. Each series has its own color and
/// marker shape, and the legend names it, so series are never told apart by
/// color alone.
void paintChart(Canvas canvas, ChartItem item) {
  final r = item.rect;
  final u = (r.shortestSide / 16).clamp(8.0, 40.0);
  final data = TableData(item.cells);
  final card = RRect.fromRectAndRadius(r, Radius.circular(u * 0.4));
  canvas.drawRRect(card, Paint()..color = AppColors.surface);
  canvas.drawRRect(
    card,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.border,
  );

  // Legend along the top.
  var lx = r.left + u;
  final legendY = r.top + u * 1.1;
  for (var i = 0; i < data.series.length; i++) {
    final color = _color(i);
    _marker(canvas, i, Offset(lx + u * 0.4, legendY), u * 0.35, color);
    final w = _text(
      canvas,
      data.series[i].title,
      Offset(lx + u * 1.1, legendY),
      u * 0.8,
      AppColors.text,
      maxWidth: r.width / data.series.length - u * 1.5,
    );
    lx += u * 1.1 + w + u;
  }

  final plot = Rect.fromLTRB(
    r.left + u * 3.4,
    r.top + u * 2.4,
    r.right - u,
    r.bottom - u * 2.2,
  );
  if (plot.width <= 0 || plot.height <= 0) return;

  final values = [
    for (final s in data.series)
      for (final v in s.values) ?v,
  ];
  final bars = item.kind == ChartKind.batang || !data.numericX;
  var lo = values.isEmpty ? 0.0 : values.reduce(math.min);
  var hi = values.isEmpty ? 1.0 : values.reduce(math.max);
  if (bars) {
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
  }
  final y = niceAxis(lo, hi);
  double py(double v) =>
      plot.bottom - (v - y.min) / (y.max - y.min) * plot.height;

  final grid = Paint()
    ..strokeWidth = 1
    ..color = ChartColors.grid;
  final axis = Paint()
    ..strokeWidth = 2
    ..color = AppColors.textMuted;
  for (var v = y.min; v <= y.max + y.step / 2; v += y.step) {
    final yy = py(v);
    canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
    _text(
      canvas,
      axisLabel(v, y.step),
      Offset(plot.left - u * 0.3, yy),
      u * 0.7,
      AppColors.textMuted,
      alignRight: true,
    );
  }
  canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
  final zero = py(0).clamp(plot.top, plot.bottom);
  canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), axis);

  if (values.isEmpty) {
    _text(
      canvas,
      'Belum ada angka di tabel',
      plot.center,
      u * 0.8,
      AppColors.textMuted,
      center: true,
    );
    return;
  }

  if (bars) {
    _paintBars(canvas, data, plot, u, py);
  } else {
    _paintXY(canvas, data, plot, u, py, lines: item.kind == ChartKind.garis);
  }
}

void _paintBars(
  Canvas canvas,
  TableData data,
  Rect plot,
  double u,
  double Function(double) py,
) {
  final n = data.labels.length;
  final slot = plot.width / n;
  final group = slot * 0.75;
  final barW = group / data.series.length;
  final base = py(0).clamp(plot.top, plot.bottom);
  for (var row = 0; row < n; row++) {
    final left = plot.left + row * slot + (slot - group) / 2;
    for (var s = 0; s < data.series.length; s++) {
      final v = data.series[s].values[row];
      if (v == null) continue;
      final top = py(v);
      canvas.drawRect(
        Rect.fromLTRB(
          left + s * barW + barW * 0.08,
          math.min(top, base),
          left + (s + 1) * barW - barW * 0.08,
          math.max(top, base),
        ),
        Paint()..color = _color(s),
      );
    }
    _text(
      canvas,
      data.labels[row],
      Offset(plot.left + (row + 0.5) * slot, plot.bottom + u * 0.9),
      u * 0.7,
      AppColors.text,
      center: true,
      maxWidth: slot,
    );
  }
}

void _paintXY(
  Canvas canvas,
  TableData data,
  Rect plot,
  double u,
  double Function(double) py, {
  required bool lines,
}) {
  final xs = [for (final v in data.x) ?v];
  final x = niceAxis(xs.reduce(math.min), xs.reduce(math.max));
  double px(double v) => plot.left + (v - x.min) / (x.max - x.min) * plot.width;
  for (var v = x.min; v <= x.max + x.step / 2; v += x.step) {
    _text(
      canvas,
      axisLabel(v, x.step),
      Offset(px(v), plot.bottom + u * 0.9),
      u * 0.7,
      AppColors.textMuted,
      center: true,
    );
  }
  for (var s = 0; s < data.series.length; s++) {
    final points = <Offset>[
      for (var row = 0; row < data.x.length; row++)
        if (data.x[row] != null && data.series[s].values[row] != null)
          Offset(px(data.x[row]!), py(data.series[s].values[row]!)),
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    final color = _color(s);
    if (lines && points.length > 1) {
      canvas.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, u * 0.15)
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
    for (final p in points) {
      _marker(canvas, s, p, lines ? u * 0.25 : u * 0.35, color);
    }
  }
}

Color _color(int series) =>
    ChartColors.series[series % ChartColors.series.length];

/// Circle, square, triangle, diamond, cross: one shape per series.
void _marker(Canvas canvas, int series, Offset c, double r, Color color) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  switch (series % 5) {
    case 0:
      canvas.drawCircle(c, r, paint);
    case 1:
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * 0.9), paint);
    case 2:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.1)
          ..lineTo(c.dx + r, c.dy + r * 0.8)
          ..lineTo(c.dx - r, c.dy + r * 0.8)
          ..close(),
        paint,
      );
    case 3:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..lineTo(c.dx + r * 1.2, c.dy)
          ..lineTo(c.dx, c.dy + r * 1.2)
          ..lineTo(c.dx - r * 1.2, c.dy)
          ..close(),
        paint,
      );
    default:
      final line = paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.6;
      canvas
        ..drawLine(c - Offset(r, r), c + Offset(r, r), line)
        ..drawLine(c - Offset(r, -r), c + Offset(r, -r), line);
  }
}

/// Paints [text] vertically centered at [at]; returns its width.
double _text(
  Canvas canvas,
  String text,
  Offset at,
  double size,
  Color color, {
  bool center = false,
  bool alignRight = false,
  double? maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: color, fontFamily: 'Roboto'),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(size, maxWidth ?? double.infinity));
  final dx = center
      ? painter.width / 2
      : alignRight
      ? painter.width
      : 0.0;
  painter.paint(canvas, at - Offset(dx, painter.height / 2));
  final w = painter.width;
  painter.dispose();
  return w;
}
