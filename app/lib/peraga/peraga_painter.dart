import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';
import 'peraga_specs.dart';

/// What a touch on an alat peraga hits.
sealed class PeragaControl {}

class PeragaSlider extends PeragaControl {
  PeragaSlider(this.index);
  final int index;
}

class PeragaChoice extends PeragaControl {
  PeragaChoice(this.index);
  final int index;
}

class PeragaPlay extends PeragaControl {}

class PeragaReset extends PeragaControl {}

/// Where the parts of an alat peraga sit, in canvas coordinates. Shared by
/// the painter and the hit tests.
class PeragaLayout {
  PeragaLayout(this.item) {
    final r = item.rect;
    unit = (r.shortestSide / 18).clamp(8.0, 40.0);
    final pad = unit * 0.6;
    final params = item.kind.spec.params;
    final rowH = unit * 1.8;
    final buttonsH = unit * 2.2;
    header = Rect.fromLTWH(r.left, r.top, r.width, unit * 2);
    buttons = Rect.fromLTRB(
      r.left + pad,
      r.bottom - pad - buttonsH,
      r.right - pad,
      r.bottom - pad,
    );
    final controlsTop = buttons.top - pad - rowH * params.length;
    rows = [
      for (var i = 0; i < params.length; i++)
        Rect.fromLTWH(
          r.left + pad,
          controlsTop + i * rowH,
          r.width - 2 * pad,
          rowH,
        ),
    ];
    readout = Rect.fromLTRB(
      r.left + pad,
      controlsTop - unit * 1.6,
      r.right - pad,
      controlsTop - unit * 0.2,
    );
    scene = Rect.fromLTRB(
      r.left + pad,
      header.bottom,
      r.right - pad,
      readout.top - unit * 0.2,
    );
    final half = (buttons.width - unit * 0.6) / 2;
    play = Rect.fromLTWH(buttons.left, buttons.top, half, buttons.height);
    reset = Rect.fromLTWH(
      buttons.left + half + unit * 0.6,
      buttons.top,
      half,
      buttons.height,
    );
  }

  final PeragaItem item;
  late final double unit;
  late final Rect header, scene, readout, buttons, play, reset;
  late final List<Rect> rows;

  /// Slider track (a line) of row [i], right of its label.
  Rect track(int i) {
    final row = rows[i];
    return Rect.fromLTWH(
      row.left + row.width * 0.45,
      row.center.dy,
      row.width * 0.53,
      0,
    );
  }

  Offset knob(int i) {
    final p = item.kind.spec.params[i];
    final v = item.values[p.name]!;
    final t = (v - p.min) / (p.max - p.min);
    final tr = track(i);
    return Offset(tr.left + t * tr.width, tr.top);
  }

  double valueAt(int i, double x) {
    final p = item.kind.spec.params[i];
    final tr = track(i);
    final t = ((x - tr.left) / tr.width).clamp(0.0, 1.0);
    return p.snap(p.min + t * (p.max - p.min));
  }

  PeragaControl? controlAt(Offset at) {
    if (play.inflate(unit * 0.2).contains(at)) return PeragaPlay();
    if (reset.inflate(unit * 0.2).contains(at)) return PeragaReset();
    final params = item.kind.spec.params;
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].contains(at)) continue;
      if (params[i].choices != null) return PeragaChoice(i);
      final tr = track(i);
      if (at.dx >= tr.left - unit && at.dx <= tr.right + unit) {
        return PeragaSlider(i);
      }
    }
    return null;
  }
}

void _text(
  Canvas canvas,
  String text,
  Offset at,
  double size,
  Color color, {
  bool center = false,
  double? maxWidth,
  FontWeight weight = FontWeight.w500,
  IconData? icon,
  IconData? trailing,
}) {
  final style = TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFamily: 'Roboto',
    // Arrows and subscripts (→, ₂) come from the system fallback font.
    fontFamilyFallback: const ['Noto Sans CJK SC'],
  );
  final painter = TextPainter(
    text: TextSpan(
      style: style,
      children: [
        if (icon != null) iconSpan(icon, size * 1.15, color),
        if (icon != null) const TextSpan(text: '  '),
        TextSpan(text: text),
        if (trailing != null) const TextSpan(text: ' '),
        if (trailing != null) iconSpan(trailing, size * 1.15, color),
      ],
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  painter.paint(
    canvas,
    at - Offset(center ? painter.width / 2 : 0, painter.height / 2),
  );
  painter.dispose();
}

/// A Material icon inside painted text.
TextSpan iconSpan(IconData icon, double size, Color color) => TextSpan(
  text: String.fromCharCode(icon.codePoint),
  style: TextStyle(
    fontFamily: icon.fontFamily,
    package: icon.fontPackage,
    fontSize: size,
    color: color,
  ),
);

void _arrow(Canvas canvas, Offset from, Offset to, Color color, double w) {
  final d = to - from;
  if (d.distance < w * 2) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(from, to, paint);
  final dir = d / d.distance;
  final side = Offset(-dir.dy, dir.dx);
  final head = w * 3.5;
  canvas.drawPath(
    Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        (to - dir * head + side * head * 0.6).dx,
        (to - dir * head + side * head * 0.6).dy,
      )
      ..lineTo(
        (to - dir * head - side * head * 0.6).dx,
        (to - dir * head - side * head * 0.6).dy,
      )
      ..close(),
    Paint()..color = color,
  );
}

void _dash(Canvas canvas, Offset a, Offset b, Paint paint, double dash) {
  final d = b - a;
  final length = d.distance;
  if (length == 0) return;
  final step = d / length;
  for (var t = 0.0; t < length; t += dash * 2) {
    canvas.drawLine(a + step * t, a + step * math.min(t + dash, length), paint);
  }
}

/// Draws [item] at time [t] seconds: card, title, scene, readout, sliders,
/// and Putar/Jeda + Ulang.
void paintPeraga(
  Canvas canvas,
  PeragaItem item, {
  double t = 0,
  bool running = false,
}) {
  final l = PeragaLayout(item);
  final u = l.unit;
  final card = RRect.fromRectAndRadius(item.rect, Radius.circular(u * 0.4));
  canvas.drawRRect(card, Paint()..color = AppColors.surface);
  canvas.drawRRect(
    card,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.border,
  );
  _text(
    canvas,
    '${item.kind.fisika ? 'Simulasi' : 'Lab virtual'}: ${item.kind.label}',
    Offset(l.header.left + u * 0.6, l.header.center.dy),
    u * 0.85,
    AppColors.text,
    weight: FontWeight.w700,
  );

  canvas.save();
  canvas.clipRect(l.scene);
  _scene(canvas, item, l.scene, u, t, running);
  canvas.restore();

  final spec = item.kind.spec;
  _text(
    canvas,
    spec.readout(item.values),
    Offset(l.readout.left, l.readout.center.dy),
    u * 0.72,
    AppColors.primary,
    maxWidth: l.readout.width,
    weight: FontWeight.w600,
  );

  final params = spec.params;
  for (var i = 0; i < params.length; i++) {
    final p = params[i];
    final row = l.rows[i];
    final value = item.values[p.name]!;
    if (p.choices != null) {
      final pill = RRect.fromRectAndRadius(
        row.deflate(u * 0.2),
        Radius.circular(row.height / 2),
      );
      canvas.drawRRect(pill, Paint()..color = AppColors.primaryContainer);
      _text(
        canvas,
        '${p.label}: ${p.show(value)}',
        row.center,
        u * 0.72,
        AppColors.primary,
        center: true,
        weight: FontWeight.w600,
        trailing: Icons.chevron_right,
      );
      continue;
    }
    _text(
      canvas,
      '${p.label}: ${p.show(value)}',
      Offset(row.left, row.center.dy),
      u * 0.7,
      AppColors.text,
      maxWidth: row.width * 0.44,
    );
    final tr = l.track(i);
    canvas.drawLine(
      tr.centerLeft,
      tr.centerRight,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = u * 0.22
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(l.knob(i), u * 0.5, Paint()..color = AppColors.primary);
  }

  for (final (rect, label, icon, on) in [
    (
      l.play,
      running ? 'Jeda' : 'Putar',
      running ? Icons.pause : Icons.play_arrow,
      running,
    ),
    (l.reset, 'Ulang', Icons.replay, false),
  ]) {
    final pill = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    canvas.drawRRect(
      pill,
      Paint()..color = on ? AppColors.primaryContainer : AppColors.primary,
    );
    _text(
      canvas,
      label,
      rect.center,
      u * 0.8,
      on ? AppColors.primary : AppColors.onPrimary,
      center: true,
      weight: FontWeight.w700,
      icon: icon,
    );
  }
}

void _scene(
  Canvas canvas,
  PeragaItem item,
  Rect s,
  double u,
  double t,
  bool running,
) {
  final v = item.values;
  final line = Paint()
    ..color = PeragaColors.ink
    ..strokeWidth = math.max(2, u * 0.12)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final w = math.max(2.0, u * 0.14);
  switch (item.kind) {
    case PeragaKind.bandul:
      final pivot = Offset(s.center.dx, s.top + u * 0.8);
      final scale = (s.height - u * 2.4) / 2.5;
      final len = v['L']! * scale;
      final theta0 = v['sudut']! * math.pi / 180;
      final omega = math.sqrt(v['g']! / v['L']!);
      final theta = theta0 * math.cos(omega * t);
      final dTheta = -theta0 * omega * math.sin(omega * t);
      canvas.drawLine(
        pivot - Offset(u * 3, 0),
        pivot + Offset(u * 3, 0),
        line..strokeWidth = u * 0.25,
      );
      line.strokeWidth = math.max(2, u * 0.12);
      _dash(
        canvas,
        pivot,
        pivot + Offset(0, len),
        Paint()
          ..color = PeragaColors.muted
          ..strokeWidth = 1.5,
        u * 0.3,
      );
      canvas.drawArc(
        Rect.fromCircle(center: pivot, radius: len),
        math.pi / 2 - theta0,
        2 * theta0,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = PeragaColors.muted.withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
      final bob = pivot + Offset(len * math.sin(theta), len * math.cos(theta));
      canvas.drawLine(pivot, bob, line);
      final tangent = Offset(math.cos(theta), -math.sin(theta));
      _arrow(
        canvas,
        bob,
        bob + tangent * (dTheta * len * 0.35),
        PeragaColors.velocity,
        w,
      );
      _arrow(
        canvas,
        bob,
        bob - tangent * (math.sin(theta) * u * 6),
        PeragaColors.force,
        w,
      );
      canvas.drawCircle(
        bob,
        (len * 0.18).clamp(u * 0.5, u * 0.9),
        Paint()..color = PeragaColors.bob,
      );
      _legend(canvas, s, u, const [
        ('v kecepatan', PeragaColors.velocity),
        ('F pemulih', PeragaColors.force),
      ]);
    case PeragaKind.parabola:
      final a = v['sudut']! * math.pi / 180;
      final v0 = v['v0']!, g = v['g']!;
      final flight = 2 * v0 * math.sin(a) / g;
      final range = v0 * v0 * math.sin(2 * a) / g;
      final top = v0 * v0 * math.pow(math.sin(a), 2) / (2 * g);
      final origin = Offset(s.left + u * 1.5, s.bottom - u * 1.2);
      final scale = math.min(
        (s.width - u * 3) / math.max(range, 1),
        (s.height - u * 3) / math.max(top, 1),
      );
      Offset at(double tt) => origin.translate(
        v0 * math.cos(a) * tt * scale,
        -(v0 * math.sin(a) * tt - g * tt * tt / 2) * scale,
      );
      canvas.drawLine(
        Offset(s.left, origin.dy),
        Offset(s.right, origin.dy),
        line,
      );
      final path = Path()..moveTo(origin.dx, origin.dy);
      for (var i = 1; i <= 60; i++) {
        final p = at(flight * i / 60);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = PeragaColors.muted,
      );
      final cycle = flight + 0.8;
      final tt = math.min(t % cycle, flight);
      final ball = at(tt);
      _arrow(
        canvas,
        ball,
        ball.translate(
          v0 * math.cos(a) * scale * 0.18,
          -(v0 * math.sin(a) - g * tt) * scale * 0.18,
        ),
        PeragaColors.velocity,
        w,
      );
      canvas.drawCircle(ball, u * 0.6, Paint()..color = PeragaColors.bob);
      _legend(canvas, s, u, const [('v kecepatan', PeragaColors.velocity)]);
    case PeragaKind.pegas:
      final omega = math.sqrt(v['k']! / v['m']!);
      final x = v['A']! * math.cos(omega * t);
      final floor = s.bottom - u * 1.5;
      final wall = s.left + u * 1.5;
      final rest = s.left + s.width * 0.55;
      final px = (s.width * 0.3) / 0.3;
      final blockW = u * (2 + v['m']!);
      final blockLeft = rest + x * px - blockW / 2;
      canvas.drawLine(Offset(wall, s.top + u), Offset(wall, floor), line);
      canvas.drawLine(Offset(wall, floor), Offset(s.right, floor), line);
      final y = floor - blockW / 2;
      final coils = 10;
      final spring = Path()..moveTo(wall, y);
      for (var i = 1; i <= coils * 2; i++) {
        final px2 = wall + (blockLeft - wall) * i / (coils * 2 + 1);
        spring.lineTo(px2, y + (i.isOdd ? -u * 0.7 : u * 0.7));
      }
      spring.lineTo(blockLeft, y);
      canvas.drawPath(spring, line);
      canvas.drawRect(
        Rect.fromLTWH(blockLeft, floor - blockW, blockW, blockW),
        Paint()..color = PeragaColors.block,
      );
      _dash(
        canvas,
        Offset(rest, s.top + u),
        Offset(rest, floor),
        Paint()
          ..color = PeragaColors.muted
          ..strokeWidth = 1.5,
        u * 0.3,
      );
      final center = Offset(blockLeft + blockW / 2, floor - blockW - u * 0.6);
      _arrow(
        canvas,
        center,
        center.translate(-x * px * 0.9, 0),
        PeragaColors.force,
        w,
      );
      _legend(canvas, s, u, const [('F = −kx', PeragaColors.force)]);
    case PeragaKind.bidangMiring:
      final angle = v['sudut']! * math.pi / 180;
      final base = Offset(s.left + u, s.bottom - u);
      final width = s.width - u * 2;
      var height = width * math.tan(angle);
      var run = width;
      if (height > s.height - u * 3) {
        height = s.height - u * 3;
        run = height / math.tan(angle);
      }
      final topPt = base.translate(0, -height);
      final foot = base.translate(run, 0);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..lineTo(topPt.dx, topPt.dy)
          ..lineTo(foot.dx, foot.dy)
          ..close(),
        Paint()..color = PeragaColors.milky,
      );
      canvas.drawLine(topPt, foot, line);
      canvas.drawLine(base, foot, line);
      _text(
        canvas,
        'θ',
        foot.translate(-u * 2.2, -u * 0.6),
        u * 0.8,
        PeragaColors.ink,
      );
      final slope = math.sqrt(run * run + height * height);
      final acc = inclineAcceleration(v);
      final meters = 3.0; // the slope is 3 m long in the model
      final cycle = acc > 0 ? math.sqrt(2 * meters / acc) + 0.6 : 1;
      final tt = acc > 0 ? math.min(t % cycle, math.sqrt(2 * meters / acc)) : 0;
      final s1 =
          (0.5 * acc * tt * tt / meters).clamp(0.0, 1.0) * (slope - u * 3);
      final down = (foot - topPt) / slope;
      final normal = Offset(down.dy, -down.dx) * -1;
      final size = u * 2.2;
      final c = topPt + down * (u * 1.5 + s1) + normal * (-size / 2);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.atan2(down.dy, down.dx));
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        Paint()..color = PeragaColors.block,
      );
      canvas.restore();
      _arrow(canvas, c, c.translate(0, u * 3), PeragaColors.weight, w);
      _arrow(
        canvas,
        c,
        c - normal * (u * 3 * math.cos(angle)),
        PeragaColors.velocity,
        w,
      );
      if (v['mu']! > 0) {
        _arrow(
          canvas,
          c,
          c - down * (u * 2.5 * v['mu']!),
          PeragaColors.force,
          w,
        );
      }
      _legend(canvas, s, u, const [
        ('w berat', PeragaColors.weight),
        ('N normal', PeragaColors.velocity),
        ('f gesek', PeragaColors.force),
      ]);
    case PeragaKind.indikator:
      final ph = v['pH']!;
      final color = indicatorColor(v['indikator']!.round(), ph);
      final beaker = Rect.fromCenter(
        center: Offset(s.center.dx, s.bottom - s.height * 0.38),
        width: s.width * 0.34,
        height: s.height * 0.5,
      );
      _beaker(canvas, beaker, color, u);
      // Dropper and falling drops while playing.
      final tip = Offset(beaker.center.dx, s.top + u * 3);
      canvas.drawRect(
        Rect.fromCenter(
          center: tip.translate(0, -u * 1.4),
          width: u,
          height: u * 2.6,
        ),
        Paint()..color = PeragaColors.glass,
      );
      if (running) {
        final fall = (t * 1.3) % 1;
        final drop = Offset.lerp(
          tip,
          Offset(tip.dx, beaker.top + beaker.height * 0.35),
          fall,
        )!;
        canvas.drawCircle(drop, u * 0.35, Paint()..color = color);
      }
      // pH scale under the beaker.
      final bar = Rect.fromLTWH(
        s.left + u,
        s.bottom - u * 1.1,
        s.width - u * 2,
        u * 0.7,
      );
      for (var i = 0; i < 28; i++) {
        final p = 1 + 13 * i / 27;
        canvas.drawRect(
          Rect.fromLTWH(
            bar.left + bar.width * i / 28,
            bar.top,
            bar.width / 28 + 0.5,
            bar.height,
          ),
          Paint()..color = indicatorColor(0, p),
        );
      }
      final mark = bar.left + bar.width * (ph - 1) / 13;
      _arrow(
        canvas,
        Offset(mark, bar.top - u * 1.2),
        Offset(mark, bar.top),
        PeragaColors.ink,
        w * 0.8,
      );
    case PeragaKind.logamAsam:
      final metal = v['logam']!.round();
      final rate = metalRate[metal] * v['M']! / 2;
      final tube = Rect.fromCenter(
        center: s.center.translate(0, u * 0.5),
        width: s.width * 0.18,
        height: s.height * 0.8,
      );
      _tube(canvas, tube, PeragaColors.water, 0.65, u);
      final metalRect = Rect.fromCenter(
        center: Offset(tube.center.dx, tube.bottom - u * 1.6),
        width: tube.width * 0.5,
        height: u * 1.2,
      );
      canvas.drawRect(metalRect, Paint()..color = PeragaColors.metals[metal]);
      if (running && rate > 0) {
        final n = (24 * rate).ceil();
        final surface = tube.bottom - tube.height * 0.65;
        for (var i = 0; i < n; i++) {
          final phase = (t * (0.6 + rate) + i / n) % 1;
          final y = metalRect.top - (metalRect.top - surface) * phase;
          final x =
              tube.center.dx + math.sin(i * 7.3 + t * 3) * tube.width * 0.3;
          canvas.drawCircle(
            Offset(x, y),
            u * (0.18 + 0.1 * (i % 3)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = PeragaColors.ink.withValues(alpha: 0.5),
          );
        }
      }
      _text(
        canvas,
        metalNames[metal],
        metalRect.center.translate(tube.width, 0),
        u * 0.8,
        PeragaColors.ink,
      );
    case PeragaKind.pemanasan:
      final temp = v['suhu']!;
      final clearNow = temp >= 66;
      final tube = Rect.fromCenter(
        center: Offset(s.center.dx, s.top + s.height * 0.4),
        width: s.width * 0.16,
        height: s.height * 0.6,
      );
      _tube(
        canvas,
        tube,
        clearNow ? PeragaColors.water : PeragaColors.milky,
        0.55,
        u,
      );
      if (!clearNow) {
        // Two layers with droplets: phenol and water do not mix.
        final level = tube.bottom - tube.height * 0.3;
        canvas.drawLine(
          Offset(tube.left + 2, level),
          Offset(tube.right - 2, level),
          Paint()
            ..color = PeragaColors.muted
            ..strokeWidth = 1.5,
        );
        for (var i = 0; i < 14; i++) {
          final x = tube.left + tube.width * (0.2 + 0.6 * ((i * 37) % 10) / 10);
          final y =
              tube.bottom - tube.height * (0.08 + 0.4 * ((i * 53) % 10) / 10);
          canvas.drawCircle(
            Offset(x, y),
            u * 0.15,
            Paint()..color = PeragaColors.glass,
          );
        }
      }
      _flame(
        canvas,
        Offset(tube.center.dx, s.bottom - u * 0.8),
        u * (0.8 + 2.2 * (temp - 20) / 70),
        t,
        blue: true,
      );
      _text(
        canvas,
        '${temp.round()} °C',
        Offset(tube.right + u, tube.center.dy),
        u * 0.9,
        PeragaColors.ink,
        weight: FontWeight.w700,
      );
    case PeragaKind.pembakaran:
      final o2 = v['O2']!;
      final complete = o2 >= 70;
      final base = Offset(s.center.dx, s.bottom - u * 3.2);
      canvas.drawRect(
        Rect.fromCenter(
          center: base.translate(0, u * 1.6),
          width: u * 1.6,
          height: u * 3.2,
        ),
        Paint()..color = PeragaColors.glass,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(base.dx, s.bottom - u * 0.4),
          width: u * 5,
          height: u * 0.8,
        ),
        Paint()..color = PeragaColors.muted,
      );
      _flame(
        canvas,
        base,
        u * (complete ? 3.4 : 5.5),
        running ? t : 0,
        blue: complete,
      );
      if (!complete && running) {
        for (var i = 0; i < 10; i++) {
          final phase = (t * 0.5 + i / 10) % 1;
          canvas.drawCircle(
            base.translate(
              math.sin(i * 2.1 + t) * u * 1.5,
              -u * 6 - phase * s.height * 0.4,
            ),
            u * (0.5 + phase),
            Paint()
              ..color = PeragaColors.smoke.withValues(
                alpha: 0.35 * (1 - phase),
              ),
          );
        }
      }
  }
}

void _legend(Canvas canvas, Rect s, double u, List<(String, Color)> items) {
  var y = s.top + u * 0.7;
  for (final (label, color) in items) {
    canvas.drawLine(
      Offset(s.right - u * 6.5, y),
      Offset(s.right - u * 5.3, y),
      Paint()
        ..color = color
        ..strokeWidth = u * 0.2,
    );
    _text(canvas, label, Offset(s.right - u * 5, y), u * 0.6, PeragaColors.ink);
    y += u * 0.9;
  }
}

void _beaker(Canvas canvas, Rect r, Color liquid, double u) {
  canvas.drawRect(
    Rect.fromLTRB(r.left, r.top + r.height * 0.35, r.right, r.bottom),
    Paint()..color = liquid,
  );
  canvas.drawPath(
    Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right, r.top),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.15
      ..color = PeragaColors.glass,
  );
}

void _tube(Canvas canvas, Rect r, Color liquid, double fill, double u) {
  final radius = Radius.circular(r.width / 2);
  final inside = RRect.fromRectAndCorners(
    Rect.fromLTRB(r.left, r.bottom - r.height * fill, r.right, r.bottom),
    bottomLeft: radius,
    bottomRight: radius,
  );
  canvas.drawRRect(inside, Paint()..color = liquid);
  canvas.drawRRect(
    RRect.fromRectAndCorners(r, bottomLeft: radius, bottomRight: radius),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.15
      ..color = PeragaColors.glass,
  );
}

void _flame(
  Canvas canvas,
  Offset base,
  double height,
  double t, {
  required bool blue,
}) {
  final flicker = 1 + 0.06 * math.sin(t * 17) + 0.04 * math.sin(t * 29);
  final h = height * flicker;
  final w = height * 0.45;
  Path shape(double scale) => Path()
    ..moveTo(base.dx - w * scale / 2, base.dy)
    ..quadraticBezierTo(
      base.dx - w * scale / 2,
      base.dy - h * scale * 0.6,
      base.dx,
      base.dy - h * scale,
    )
    ..quadraticBezierTo(
      base.dx + w * scale / 2,
      base.dy - h * scale * 0.6,
      base.dx + w * scale / 2,
      base.dy,
    )
    ..close();
  canvas.drawPath(
    shape(1),
    Paint()..color = blue ? PeragaColors.flameBlue : PeragaColors.flameOrange,
  );
  canvas.drawPath(
    shape(0.55),
    Paint()..color = blue ? PeragaColors.flameCore : PeragaColors.flameYellow,
  );
}

/// Color of a solution at [ph] with indicator [kind] (0 universal, 1 lakmus,
/// 2 fenolftalein), as in school practicum charts.
Color indicatorColor(int kind, double ph) {
  switch (kind) {
    case 1:
      if (ph < 4.5) return PeragaColors.acidRed;
      if (ph > 8.3) return PeragaColors.baseBlue;
      return PeragaColors.litmusPurple;
    case 2:
      if (ph < 8.2) return PeragaColors.clear;
      final k = ((ph - 8.2) / 1.8).clamp(0.0, 1.0);
      return Color.lerp(PeragaColors.clear, PeragaColors.phenolPink, k)!;
    default:
      final hue = (ph - 1) / 13 * 275;
      return HSVColor.fromAHSV(1, hue, 0.75, 0.92).toColor();
  }
}
