import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';

/// Where the parts of a graph sit, in canvas coordinates. Shared by the
/// painter and by slider hit tests so they always agree.
class GraphLayout {
  GraphLayout(this.graph) {
    final r = graph.rect;
    unit = (r.shortestSide / 18).clamp(8.0, 40.0);
    plot = r.deflate(unit * 0.6);
    final trackWidth = math.min(plot.width * 0.32, unit * 9);
    final rowHeight = unit * 1.7;
    sliders = [
      for (var i = 0; i < graph.params.length; i++)
        Rect.fromLTWH(
          plot.right - trackWidth - unit * 0.6,
          plot.top + unit * 1.2 + i * rowHeight,
          trackWidth,
          0,
        ),
    ];
  }

  final GraphItem graph;
  late final double unit;
  late final Rect plot;

  /// Slider tracks (zero height: the line the knob runs on).
  late final List<Rect> sliders;

  double get knobRadius => unit * 0.45;

  Offset toCanvas(double x, double y) => Offset(
    plot.left + (x - graph.xMin) / (graph.xMax - graph.xMin) * plot.width,
    plot.bottom - (y - graph.yMin) / (graph.yMax - graph.yMin) * plot.height,
  );

  Offset knob(int i) {
    final p = graph.params[i];
    final t = p.max == p.min ? 0.5 : (p.value - p.min) / (p.max - p.min);
    final track = sliders[i];
    return Offset(track.left + t * track.width, track.top);
  }

  /// Index of the slider at [point], with a finger-sized [tolerance].
  int? sliderAt(Offset point, {double tolerance = 24}) {
    for (var i = 0; i < sliders.length; i++) {
      final track = sliders[i];
      final area = Rect.fromLTRB(
        track.left - tolerance,
        track.top - math.max(tolerance, unit * 0.8),
        track.right + tolerance,
        track.top + math.max(tolerance, unit * 0.8),
      );
      if (area.contains(point)) return i;
    }
    return null;
  }

  /// Parameter value for a finger at canvas x on slider [i].
  double valueAt(int i, double canvasX) {
    final track = sliders[i];
    final p = graph.params[i];
    final t = ((canvasX - track.left) / track.width).clamp(0.0, 1.0);
    final raw = p.min + t * (p.max - p.min);
    // Snap to a tidy step so labels read cleanly (A = 1,5 not 1,4837).
    final step = niceStep((p.max - p.min) / 40);
    return ((raw / step).round() * step).clamp(p.min, p.max);
  }
}

/// 1, 2, or 5 × 10^k closest above [raw].
double niceStep(double raw) {
  if (raw <= 0 || raw.isNaN || raw.isInfinite) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (m * exp >= raw) return m * exp;
  }
  return 10 * exp;
}

/// A formula as people write it: `y = A*sin(x) + B` → `y = A sin(x) + B`,
/// `x^2 - 3` → `x² − 3`.
String prettyFormula(String formula) {
  var s = formula
      .replaceAll('^2', '²')
      .replaceAll('^3', '³')
      .replaceAllMapped(
        RegExp(r'\*\s*(?=(sin|cos|tan|sqrt|log|ln|abs|exp|[a-zA-Z(]))'),
        (_) => ' ',
      )
      .replaceAll('*', '·')
      .replaceAll('sqrt', '√')
      .replaceAllMapped(RegExp(r'(?<=[\w)²³])\s*-\s*'), (_) => ' − ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// "1,5", "-2", "0,25": Indonesian decimal comma, no trailing zeros.
String formatNumber(double v) {
  if (v.abs() < 1e-9) return '0';
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

void _text(
  Canvas canvas,
  String text,
  Offset at,
  double size,
  Color color, {
  bool alignRight = false,
  bool center = false,
  FontWeight weight = FontWeight.w400,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = at.dx;
  if (alignRight) dx -= painter.width;
  if (center) dx -= painter.width / 2;
  painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  painter.dispose();
}

/// Draws [graph]: grid, numbered axes, curves, legend, and sliders.
void paintGraph(Canvas canvas, GraphItem graph) {
  final l = GraphLayout(graph);
  final plot = l.plot;
  canvas.drawRRect(
    RRect.fromRectAndRadius(graph.rect, Radius.circular(l.unit * 0.4)),
    Paint()..color = AppColors.surface,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(graph.rect, Radius.circular(l.unit * 0.4)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.border,
  );

  canvas.save();
  canvas.clipRect(plot);
  final grid = Paint()
    ..color = AppColors.border
    ..strokeWidth = 1;
  final xStep = niceStep((graph.xMax - graph.xMin) / 10);
  final yStep = niceStep((graph.yMax - graph.yMin) / 8);
  for (
    var x = (graph.xMin / xStep).ceil() * xStep;
    x <= graph.xMax;
    x += xStep
  ) {
    canvas.drawLine(l.toCanvas(x, graph.yMin), l.toCanvas(x, graph.yMax), grid);
  }
  for (
    var y = (graph.yMin / yStep).ceil() * yStep;
    y <= graph.yMax;
    y += yStep
  ) {
    canvas.drawLine(l.toCanvas(graph.xMin, y), l.toCanvas(graph.xMax, y), grid);
  }
  final axis = Paint()
    ..color = AppColors.textMuted
    ..strokeWidth = 2;
  final y0 = 0.0.clamp(graph.yMin, graph.yMax);
  final x0 = 0.0.clamp(graph.xMin, graph.xMax);
  canvas.drawLine(l.toCanvas(graph.xMin, y0), l.toCanvas(graph.xMax, y0), axis);
  canvas.drawLine(l.toCanvas(x0, graph.yMin), l.toCanvas(x0, graph.yMax), axis);

  // Axis numbers.
  final small = l.unit * 0.55;
  for (
    var x = (graph.xMin / xStep).ceil() * xStep;
    x <= graph.xMax;
    x += xStep
  ) {
    if (x.abs() < xStep / 2) continue;
    _text(
      canvas,
      formatNumber(x),
      l.toCanvas(x, y0) + Offset(0, small),
      small,
      AppColors.textMuted,
      center: true,
    );
  }
  for (
    var y = (graph.yMin / yStep).ceil() * yStep;
    y <= graph.yMax;
    y += yStep
  ) {
    if (y.abs() < yStep / 2) continue;
    _text(
      canvas,
      formatNumber(y),
      l.toCanvas(x0, y) + Offset(-small * 0.4, 0),
      small,
      AppColors.textMuted,
      alignRight: true,
    );
  }

  // Curves: sampled per pixel column, broken where undefined or jumping.
  final values = graph.values;
  final yRange = graph.yMax - graph.yMin;
  for (var f = 0; f < graph.functions.length; f++) {
    final expr = graph.expressions[f];
    if (expr == null) continue;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, l.unit * 0.18)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = graph.functions[f].color;
    final path = Path();
    var drawing = false;
    double? lastY;
    final samples = math.max(60, plot.width.round());
    for (var i = 0; i <= samples; i++) {
      final x = graph.xMin + (graph.xMax - graph.xMin) * i / samples;
      final y = expr.evaluate(x, values);
      final ok =
          y.isFinite && (lastY == null || (y - lastY).abs() < yRange * 2);
      if (!ok) {
        drawing = false;
        lastY = y.isFinite ? y : null;
        continue;
      }
      final clampedY = y.clamp(graph.yMin - yRange, graph.yMax + yRange);
      final p = l.toCanvas(x, clampedY);
      if (drawing) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        drawing = true;
      }
      lastY = y;
    }
    canvas.drawPath(path, paint);
  }
  canvas.restore();

  // Legend: each formula in its curve color.
  final legend = l.unit * 0.8;
  for (var f = 0; f < graph.functions.length; f++) {
    final unreadable = graph.expressions[f] == null;
    _text(
      canvas,
      unreadable
          ? '${graph.functions[f].formula} (tidak terbaca)'
          : prettyFormula(graph.functions[f].formula),
      Offset(
        plot.left + l.unit * 0.6,
        plot.top + l.unit * 1.0 + f * legend * 1.5,
      ),
      legend,
      graph.functions[f].color,
      weight: FontWeight.w600,
    );
  }

  // Sliders: "A = 1,5" with a track and a knob.
  final track = Paint()
    ..color = AppColors.textMuted
    ..strokeWidth = math.max(3, l.unit * 0.15)
    ..strokeCap = StrokeCap.round;
  final knobFill = Paint()..color = AppColors.primary;
  final knobRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = AppColors.surface;
  for (var i = 0; i < graph.params.length; i++) {
    final t = l.sliders[i];
    final p = graph.params[i];
    canvas.drawLine(t.centerLeft, t.centerRight, track);
    final k = l.knob(i);
    canvas.drawCircle(k, l.knobRadius, knobFill);
    canvas.drawCircle(k, l.knobRadius, knobRing);
    _text(
      canvas,
      '${p.name} = ${formatNumber(p.value)}',
      t.centerLeft + Offset(-l.unit * 0.5, 0),
      l.unit * 0.7,
      AppColors.text,
      alignRight: true,
      weight: FontWeight.w600,
    );
  }
}
