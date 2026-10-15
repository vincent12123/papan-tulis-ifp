import 'dart:ui';

import '../canvas/stroke.dart';
import '../graph/expression.dart';
import '../ui/theme.dart';

/// Curve colors, in order: like the video (red, blue), then more pens.
const graphColors = [
  PenColors.red,
  PenColors.blue,
  PenColors.green,
  PenColors.purple,
];

double _num(Object? v, double fallback) =>
    v is num && v.isFinite ? v.toDouble() : fallback;

/// Turns the server's graph description into a [GraphItem] at [rect]
/// (REQ-20). Formulas the panel's own parser cannot read are dropped, so
/// nothing unexpected is ever drawn or run (AC-85). Returns null when no
/// formula is left.
GraphItem? buildGraph(Map<String, dynamic> data, Rect rect, String id) {
  final formulas = <String>[];
  final used = <String>{};
  for (final f in (data['fungsi'] as List? ?? const [])) {
    if (f is! String) continue;
    try {
      final e = Expression.parse(f);
      formulas.add(f.trim());
      used.addAll(e.parameters);
    } on FormatException {
      continue;
    }
    if (formulas.length == graphColors.length) break;
  }
  if (formulas.isEmpty) return null;

  final params = <GraphParam>[];
  for (final p in (data['parameter'] as List? ?? const [])) {
    if (p is! Map) continue;
    final name = p['nama'];
    if (name is! String || !used.contains(name)) continue;
    if (params.any((q) => q.name == name)) continue;
    var lo = _num(p['min'], -5), hi = _num(p['maks'], 5);
    if (lo >= hi) (lo, hi) = (-5, 5);
    params.add(
      GraphParam(
        name: name,
        min: lo,
        max: hi,
        value: _num(p['nilai'], 1),
      ).withValue(_num(p['nilai'], 1)),
    );
  }
  // Letters the AI forgot to describe still get a slider.
  for (final name in used.toList()..sort()) {
    if (!params.any((p) => p.name == name)) {
      params.add(GraphParam(name: name, min: -5, max: 5, value: 1));
    }
  }

  final axes = data['sumbu'] is Map ? data['sumbu'] as Map : const {};
  var xMin = _num(axes['x_min'], -10), xMax = _num(axes['x_maks'], 10);
  var yMin = _num(axes['y_min'], -10), yMax = _num(axes['y_maks'], 10);
  if (xMin >= xMax) (xMin, xMax) = (-10, 10);
  if (yMin >= yMax) (yMin, yMax) = (-10, 10);

  return GraphItem(
    id: id,
    rect: rect,
    functions: [
      for (var i = 0; i < formulas.length; i++)
        GraphFunction(formulas[i], graphColors[i]),
    ],
    params: params,
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
  );
}

/// Where a pasted result goes: right of the circled [area] if it fits in
/// the [visible] part of the page, otherwise in the middle of it.
Rect placeResult(Size size, Rect visible, Rect? area) {
  if (area != null) {
    final right = Rect.fromLTWH(
      area.right + 24,
      area.top,
      size.width,
      size.height,
    );
    if (visible.contains(right.topLeft) &&
        visible.contains(right.bottomRight)) {
      return right;
    }
    final left = Rect.fromLTWH(
      area.left - 24 - size.width,
      area.top,
      size.width,
      size.height,
    );
    if (visible.contains(left.topLeft) && visible.contains(left.bottomRight)) {
      return left;
    }
  }
  return Rect.fromCenter(
    center: visible.center,
    width: size.width,
    height: size.height,
  );
}
