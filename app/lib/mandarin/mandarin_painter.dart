import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../peraga/peraga_painter.dart' show iconSpan;
import '../ui/theme.dart';

/// Something on a Mandarin card that speaks when tapped (REQ-30).
class MandarinSpeak {
  const MandarinSpeak(this.text, {this.slow = false});
  final String text;
  final bool slow;
}

/// Where everything sits on a Mandarin card. The card scales with its
/// frame; [voice] says whether the panel can speak Mandarin (the buttons
/// show only then, otherwise a hint how to install the voice).
class MandarinLayout {
  MandarinLayout(this.item, {required this.voice}) {
    final r = item.rect;
    final rows = (item.words.length / perRow).ceil();
    final units =
        1.0 + // top padding
        1.6 + // pinyin
        3.2 + // hanzi
        (item.translation == null ? 1.6 : 2.6) + // translation or AI note
        rows * cellUnits +
        0.6 +
        2.8 + // buttons / voice hint
        0.8;
    unit = math.min(r.width / 28, r.height / units);
    final u = unit;
    final left = r.left + u, width = r.width - 2 * u;
    var y = r.top + u;
    pinyin = Rect.fromLTWH(left, y, width, 1.6 * u);
    y += 1.6 * u;
    hanzi = Rect.fromLTWH(left, y, width, 3.2 * u);
    y += 3.2 * u;
    final tr = item.translation == null ? 1.6 : 2.6;
    translation = Rect.fromLTWH(left, y, width, tr * u);
    y += tr * u;
    final cellW = width / perRow;
    words = [
      for (var i = 0; i < item.words.length; i++)
        Rect.fromLTWH(
          left + (i % perRow) * cellW,
          y + (i ~/ perRow) * cellUnits * u,
          cellW,
          cellUnits * u,
        ).deflate(0.2 * u),
    ];
    y += rows * cellUnits * u + 0.6 * u;
    final buttonW = math.min(9.0 * u, width / 2 - 0.5 * u);
    listen = Rect.fromLTWH(left, y, buttonW, 2.8 * u);
    slow = Rect.fromLTWH(left + buttonW + u, y, buttonW, 2.8 * u);
    hint = Rect.fromLTWH(left, y, width, 2.8 * u);
  }

  static const perRow = 4;

  /// Height of a word cell: Hanzi, pinyin, and two lines of meaning.
  static const cellUnits = 4.9;

  final MandarinItem item;
  final bool voice;
  late final double unit;
  late final Rect pinyin, hanzi, translation, listen, slow, hint;
  late final List<Rect> words;

  /// Height a card of [width] needs to show everything.
  static double heightFor(MandarinItem item, double width) {
    final rows = (item.words.length / perRow).ceil();
    final units =
        1.0 +
        1.6 +
        3.2 +
        (item.translation == null ? 1.6 : 2.6) +
        rows * cellUnits +
        0.6 +
        2.8 +
        0.8;
    return width / 28 * units;
  }

  /// What speaks at [at]: a word, or the whole sentence (normal or slow).
  MandarinSpeak? targetAt(Offset at) {
    if (!voice) return null;
    if (listen.contains(at)) return MandarinSpeak(item.hanzi);
    if (slow.contains(at)) return MandarinSpeak(item.hanzi, slow: true);
    for (var i = 0; i < words.length; i++) {
      if (words[i].contains(at)) return MandarinSpeak(item.words[i].hanzi);
    }
    return null;
  }
}

/// Texts on the card (ux-flow, REQ-30).
abstract final class MandarinTexts {
  static const aiNote = 'Terjemahan AI — periksa sebelum dipakai';
  static const noTranslation =
      'Terjemahan kalimat belum tersedia (AI tidak menjawab). '
      'Arti per kata dari kamus.';
  static const english = 'Inggris';
  static const listen = 'Dengarkan';
  static const slow = 'Pelan';
  static const noVoice =
      'Suara Mandarin belum terpasang di panel. Pasang paket suara Mandarin '
      'di Pengaturan Android.';
}

void paintMandarin(Canvas canvas, MandarinItem item, {required bool voice}) {
  final l = MandarinLayout(item, voice: voice);
  final u = l.unit;
  final card = RRect.fromRectAndRadius(item.rect, Radius.circular(u * 0.5));
  canvas.drawRRect(card, Paint()..color = AppColors.surface);
  canvas.drawRRect(
    card,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.border,
  );
  _text(canvas, item.pinyin, l.pinyin, u * 1.1, AppColors.primary);
  _text(
    canvas,
    item.hanzi,
    l.hanzi,
    u * 2.4,
    AppColors.text,
    weight: FontWeight.w700,
  );
  if (item.translation case final t?) {
    _text(
      canvas,
      t,
      Rect.fromLTWH(
        l.translation.left,
        l.translation.top,
        l.translation.width,
        1.6 * u,
      ),
      u * 1.0,
      AppColors.text,
    );
    _text(
      canvas,
      MandarinTexts.aiNote,
      Rect.fromLTWH(
        l.translation.left,
        l.translation.top + 1.6 * u,
        l.translation.width,
        u,
      ),
      u * 0.8,
      AppColors.textMuted,
      icon: Icons.info_outline,
    );
  } else {
    _text(
      canvas,
      MandarinTexts.noTranslation,
      l.translation,
      u * 0.8,
      AppColors.textMuted,
      icon: Icons.info_outline,
    );
  }
  for (var i = 0; i < l.words.length; i++) {
    final box = l.words[i];
    final w = item.words[i];
    final rr = RRect.fromRectAndRadius(box, Radius.circular(u * 0.35));
    canvas.drawRRect(rr, Paint()..color = AppColors.background);
    _text(
      canvas,
      w.hanzi,
      Rect.fromLTWH(box.left, box.top + 0.2 * u, box.width, 1.6 * u),
      u * 1.3,
      AppColors.text,
      weight: FontWeight.w700,
      center: true,
      trailing: voice ? Icons.volume_up : null,
    );
    _text(
      canvas,
      w.pinyin,
      Rect.fromLTWH(box.left, box.top + 1.8 * u, box.width, 0.9 * u),
      u * 0.8,
      AppColors.primary,
      center: true,
    );
    final meaning = switch (w.source) {
      'inggris' => '${w.meaning} (${MandarinTexts.english})',
      _ => w.meaning.isEmpty ? '–' : w.meaning,
    };
    _text(
      canvas,
      meaning,
      Rect.fromLTWH(box.left, box.top + 2.75 * u, box.width, 1.9 * u),
      u * 0.75,
      w.source == 'kamus' ? AppColors.text : AppColors.textMuted,
      center: true,
    );
  }
  if (voice) {
    for (final (box, label, icon) in [
      (l.listen, MandarinTexts.listen, Icons.volume_up),
      (l.slow, MandarinTexts.slow, Icons.slow_motion_video),
    ]) {
      final pill = RRect.fromRectAndRadius(
        box,
        Radius.circular(box.height / 2),
      );
      canvas.drawRRect(pill, Paint()..color = AppColors.primaryContainer);
      _text(
        canvas,
        label,
        box,
        u * 0.95,
        AppColors.primary,
        weight: FontWeight.w700,
        icon: icon,
        center: true,
      );
    }
  } else {
    _text(
      canvas,
      MandarinTexts.noVoice,
      l.hint,
      u * 0.8,
      AppColors.textMuted,
      icon: Icons.volume_off,
    );
  }
}

void _text(
  Canvas canvas,
  String text,
  Rect box,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  IconData? icon,
  IconData? trailing,
  bool center = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: 'Roboto',
        // Hanzi and pinyin tone letters come from the system's CJK font.
        fontFamilyFallback: const ['Noto Sans CJK SC'],
      ),
      children: [
        if (icon != null) iconSpan(icon, size * 1.1, color),
        if (icon != null) const TextSpan(text: ' '),
        TextSpan(text: text),
        if (trailing != null) const TextSpan(text: ' '),
        if (trailing != null) iconSpan(trailing, size * 0.7, color),
      ],
    ),
    textDirection: TextDirection.ltr,
    textAlign: center ? TextAlign.center : TextAlign.left,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: math.max(size, box.width));
  final dx = center ? box.center.dx - painter.width / 2 : box.left;
  painter.paint(canvas, Offset(dx, box.center.dy - painter.height / 2));
  painter.dispose();
}
