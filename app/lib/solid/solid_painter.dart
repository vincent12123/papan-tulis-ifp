import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';
import 'solid_geometry.dart';

/// The two buttons drawn inside a solid (REQ-23), used with any tool but
/// Geser, like graph sliders.
enum SolidButton { net, cut }

/// Where the parts of a solid sit, in canvas coordinates. Shared by the
/// painter and the hit tests so they always agree.
class SolidLayout {
  SolidLayout(this.item) {
    final r = item.rect;
    unit = (r.shortestSide / 16).clamp(8.0, 40.0);
    final bar = unit * 2.4;
    view = Rect.fromLTRB(
      r.left,
      r.top,
      r.right,
      r.bottom - bar,
    ).deflate(unit * 0.6);
    final y = r.bottom - bar + unit * 0.4;
    final h = bar - unit * 0.8;
    final w = math.min(r.width * 0.42, unit * 9);
    final gap = unit * 0.6;
    final kinds = [if (item.kind.hasNet) SolidButton.net, SolidButton.cut];
    final total = kinds.length * w + (kinds.length - 1) * gap;
    var x = r.center.dx - total / 2;
    buttons = {};
    for (final k in kinds) {
      buttons[k] = Rect.fromLTWH(x, y, w, h);
      x += w + gap;
    }
  }

  final SolidItem item;
  late final double unit;

  /// Where the solid itself is drawn.
  late final Rect view;
  late final Map<SolidButton, Rect> buttons;

  static String labelOf(SolidButton b, SolidItem item) => switch (b) {
    SolidButton.net => item.unfold > 0.5 ? 'Tutup jaring' : 'Jaring-jaring',
    SolidButton.cut => item.cut ? 'Sembunyikan potongan' : 'Bidang potong',
  };

  SolidButton? buttonAt(Offset at) {
    for (final e in buttons.entries) {
      if (e.value.inflate(unit * 0.3).contains(at)) return e.key;
    }
    return null;
  }
}

/// Built solids are cached per kind: building a sphere is not free.
final Map<SolidKind, Solid> _solids = {};
Solid solidOf(SolidKind kind) =>
    _solids.putIfAbsent(kind, () => Solid.of(kind));

class _Projected {
  _Projected(this.points, this.depth, this.front, this.light);
  final List<Offset> points;
  final double depth;
  final bool front;
  final double light;
}

/// Turns, then projects with a little perspective, fitted into [box].
class _Camera {
  _Camera(this.yaw, this.pitch, List<List<Vec3>> faces, Rect box) {
    var radius = 0.0;
    for (final f in faces) {
      for (final p in f) {
        radius = math.max(radius, p.length);
      }
    }
    scale = math.min(box.width, box.height) * 0.47 / math.max(radius, 1e-6);
    center = box.center;
    _distance = radius * 5;
  }

  final double yaw, pitch;
  late final double scale;
  late final Offset center;
  late final double _distance;

  Vec3 turn(Vec3 p) {
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = p.x * cy + p.z * sy;
    final z1 = -p.x * sy + p.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = p.y * cp - z1 * sp;
    final z2 = p.y * sp + z1 * cp;
    return Vec3(x1, y2, z2);
  }

  Offset project(Vec3 turned) {
    final k = _distance / (_distance - turned.z);
    return center + Offset(turned.x * k * scale, -turned.y * k * scale);
  }
}

String _key(Vec3 p) =>
    '${(p.x * 1e4).round()},${(p.y * 1e4).round()},${(p.z * 1e4).round()}';

/// Draws [item]: a card, the solid (faces, edges, hidden edges dashed,
/// corner labels, cut plane), and its two buttons. [controls] false draws
/// the solid alone (toolbar icons).
void paintSolid(Canvas canvas, SolidItem item, {bool controls = true}) {
  final layout = SolidLayout(item);
  if (controls) {
    final card = RRect.fromRectAndRadius(
      item.rect,
      Radius.circular(layout.unit * 0.4),
    );
    canvas.drawRRect(card, Paint()..color = AppColors.surface);
    canvas.drawRRect(
      card,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.border,
    );
  }
  final box = controls ? layout.view : item.rect;
  final solid = solidOf(item.kind);
  final faces = solid.unfolded(item.unfold);
  // As the net opens the view tilts to look from above, so the finished
  // net lies flat facing the class.
  final pitch = item.pitch + (1.5 - item.pitch) * item.unfold;
  final cam = _Camera(item.yaw, pitch, faces, box);
  final open = item.unfold > 0;
  const lightDir = Vec3(-0.35, 0.6, 0.72);
  final light = lightDir.unit;

  final projected = <_Projected>[];
  for (final f in faces) {
    final turned = [for (final p in f) cam.turn(p)];
    final n = (turned[1] - turned[0]).cross(turned[2] - turned[0]).unit;
    final depth = turned.fold(0.0, (s, p) => s + p.z) / turned.length;
    projected.add(
      _Projected(
        [for (final p in turned) cam.project(p)],
        depth,
        n.z > 0,
        (0.55 + 0.45 * n.dot(light).abs()).clamp(0.0, 1.0),
      ),
    );
  }

  // Faces, far to near; see-through when closed so hidden edges show.
  final order = List<int>.generate(faces.length, (i) => i)
    ..sort((a, b) => projected[a].depth.compareTo(projected[b].depth));
  for (final i in order) {
    final p = projected[i];
    final shade = Color.lerp(
      AppColors.surface,
      SolidColors.face,
      open ? 0.75 * p.light : 0.55 * p.light,
    )!;
    final fill = Paint()
      ..color = shade.withValues(alpha: open ? 0.95 : (p.front ? 0.55 : 0.35));
    canvas.drawPath(Path()..addPolygon(p.points, true), fill);
  }

  // Edges: real edges solid when seen, dashed when hidden; curved surfaces
  // only show their outline. With the net open every face edge on the
  // outside of the net is drawn.
  final edges = <String, List<(int face, int edge)>>{};
  for (var i = 0; i < faces.length; i++) {
    final f = faces[i];
    for (var e = 0; e < f.length; e++) {
      final a = f[e], b = f[(e + 1) % f.length];
      final k = [_key(a), _key(b)]..sort();
      (edges[k.join('|')] ??= []).add((i, e));
    }
  }
  final width = math.max(2.0, layout.unit * 0.12);
  final visible = Paint()
    ..color = SolidColors.edge
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  final hidden = Paint()
    ..color = SolidColors.edge.withValues(alpha: 0.55)
    ..strokeWidth = width * 0.8;
  for (final users in edges.values) {
    final (fi, ei) = users.first;
    final smooth = solid.faces[fi].smoothEdges.contains(ei);
    final pts = projected[fi].points;
    final a = pts[ei], b = pts[(ei + 1) % pts.length];
    if (open) {
      if (!smooth || users.length == 1) canvas.drawLine(a, b, visible);
      continue;
    }
    final fronts = users.where((u) => projected[u.$1].front).length;
    if (smooth) {
      // Outline of a curved surface: one side seen, the other not.
      if (users.length == 2 && fronts == 1) canvas.drawLine(a, b, visible);
      continue;
    }
    if (fronts > 0) {
      canvas.drawLine(a, b, visible);
    } else {
      _dashed(canvas, a, b, hidden, layout.unit * 0.35);
    }
  }

  if (!open && item.cut) {
    final cut = [for (final p in solid.cut) cam.project(cam.turn(p))];
    canvas.drawPath(
      Path()..addPolygon(cut, true),
      Paint()..color = SolidColors.cut.withValues(alpha: 0.3),
    );
    canvas.drawPath(
      Path()..addPolygon(cut, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = SolidColors.cut,
    );
  }

  if (!open && controls && solid.labels.isNotEmpty) {
    final mid = cam.project(cam.turn(const Vec3(0, 0, 0)));
    for (final e in solid.labels.entries) {
      final at = cam.project(cam.turn(e.value));
      final away = at - mid;
      final offset = away.distance < 1e-6
          ? Offset.zero
          : away / away.distance * layout.unit * 0.9;
      _text(canvas, e.key, at + offset, layout.unit * 0.8, SolidColors.label);
    }
  }

  if (!controls) return;
  for (final e in layout.buttons.entries) {
    final on = e.key == SolidButton.net ? item.unfold > 0.5 : item.cut;
    final pill = RRect.fromRectAndRadius(
      e.value,
      Radius.circular(e.value.height / 2),
    );
    canvas.drawRRect(
      pill,
      Paint()..color = on ? AppColors.primary : AppColors.primaryContainer,
    );
    _text(
      canvas,
      SolidLayout.labelOf(e.key, item),
      e.value.center,
      layout.unit * 0.65,
      on ? AppColors.onPrimary : AppColors.primary,
    );
  }
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash) {
  final d = b - a;
  final length = d.distance;
  if (length < 1e-6) return;
  final step = d / length;
  for (var t = 0.0; t < length; t += dash * 2) {
    canvas.drawLine(a + step * t, a + step * math.min(t + dash, length), paint);
  }
}

void _text(Canvas canvas, String text, Offset center, double size, Color c) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: c,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}

/// A small drawing of a solid for the Bentuk menu.
class SolidIcon extends StatelessWidget {
  const SolidIcon(this.kind, {super.key, this.size = AppSizes.toolIcon});

  final SolidKind kind;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SolidIconPainter(kind));
}

class _SolidIconPainter extends CustomPainter {
  _SolidIconPainter(this.kind);
  final SolidKind kind;

  @override
  void paint(Canvas canvas, Size size) => paintSolid(
    canvas,
    SolidItem(id: 'ikon', kind: kind, rect: Offset.zero & size),
    controls: false,
  );

  @override
  bool shouldRepaint(_SolidIconPainter old) => old.kind != kind;
}
