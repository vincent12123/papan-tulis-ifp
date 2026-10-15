import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';
import 'peraga_painter.dart' show iconSpan;

/// Progress on one quiz while it is on screen (REQ-27); not saved.
class QuizState {
  QuizState(int pairs, [int seed = 1])
    : order = List<int>.generate(pairs, (i) => i)..shuffle(math.Random(seed));

  /// Right column: which pair sits in each row.
  final List<int> order;
  int? selectedLeft;
  final Set<int> matched = {};

  /// The last wrong try (left pair, right row), shown red until the next tap.
  (int, int)? wrong;
}

sealed class QuizTarget {}

class QuizLeft extends QuizTarget {
  QuizLeft(this.index);
  final int index;
}

class QuizRight extends QuizTarget {
  QuizRight(this.row);
  final int row;
}

class QuizShuffle extends QuizTarget {}

class QuizLayout {
  QuizLayout(this.item) {
    final r = item.rect;
    unit = (r.shortestSide / 18).clamp(8.0, 40.0);
    final pad = unit * 0.7;
    header = Rect.fromLTWH(r.left, r.top, r.width, unit * 2.2);
    shuffle = Rect.fromLTRB(
      r.center.dx - unit * 5,
      r.bottom - pad - unit * 2,
      r.center.dx + unit * 5,
      r.bottom - pad,
    );
    final top = header.bottom + unit * 0.3;
    final bottom = shuffle.top - unit * 0.6;
    final n = item.pairs.length;
    final rowH = (bottom - top) / n;
    final colW = (r.width - pad * 3) / 2;
    left = [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(r.left + pad, top + i * rowH, colW, rowH * 0.86),
    ];
    right = [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(
          r.left + pad * 2 + colW,
          top + i * rowH,
          colW,
          rowH * 0.86,
        ),
    ];
  }

  final QuizItem item;
  late final double unit;
  late final Rect header, shuffle;
  late final List<Rect> left, right;

  QuizTarget? targetAt(Offset at) {
    if (shuffle.contains(at)) return QuizShuffle();
    for (var i = 0; i < left.length; i++) {
      if (left[i].contains(at)) return QuizLeft(i);
      if (right[i].contains(at)) return QuizRight(i);
    }
    return null;
  }
}

void _text(
  Canvas canvas,
  String text,
  Rect box,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w500,
  bool left = false,
  IconData? icon,
}) {
  final painter = TextPainter(
    text: TextSpan(
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Noto Sans CJK SC'],
      ),
      children: [
        if (icon != null) iconSpan(icon, size * 1.15, color),
        if (icon != null) const TextSpan(text: ' '),
        TextSpan(text: text),
      ],
    ),
    textAlign: left ? TextAlign.left : TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: box.width - size);
  final dx = left ? box.left + size / 2 : box.center.dx - painter.width / 2;
  painter.paint(canvas, Offset(dx, box.center.dy - painter.height / 2));
  painter.dispose();
}

/// Draws [item] with its progress [state] (null = fresh, as stored).
void paintQuiz(Canvas canvas, QuizItem item, QuizState? state) {
  final l = QuizLayout(item);
  final u = l.unit;
  final s = state ?? QuizState(item.pairs.length);
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
    item.title,
    l.header.deflate(u * 0.3),
    u * 0.9,
    AppColors.text,
    weight: FontWeight.w700,
    left: true,
  );
  _text(
    canvas,
    'Skor ${s.matched.length} / ${item.pairs.length}',
    Rect.fromLTWH(
      l.header.right - u * 8,
      l.header.top,
      u * 7.5,
      l.header.height,
    ),
    u * 0.85,
    AppColors.primary,
    weight: FontWeight.w700,
  );

  void cardAt(
    Rect r,
    String text, {
    required bool matched,
    required bool selected,
    required bool wrong,
  }) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(u * 0.35));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = matched
            ? PeragaColors.matched
            : wrong
            ? PeragaColors.wrong
            : selected
            ? AppColors.primaryContainer
            : AppColors.surface,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1.5
        ..color = matched
            ? AppColors.success
            : wrong
            ? AppColors.danger
            : selected
            ? AppColors.primary
            : AppColors.border,
    );
    // Matched shows a check, not only green (never color alone).
    _text(
      canvas,
      text,
      r,
      u * 0.75,
      AppColors.text,
      icon: matched ? Icons.check_circle : null,
    );
  }

  for (var i = 0; i < item.pairs.length; i++) {
    cardAt(
      l.left[i],
      item.pairs[i].$1,
      matched: s.matched.contains(i),
      selected: s.selectedLeft == i,
      wrong: s.wrong?.$1 == i,
    );
    final pair = s.order[i];
    cardAt(
      l.right[i],
      item.pairs[pair].$2,
      matched: s.matched.contains(pair),
      selected: false,
      wrong: s.wrong?.$2 == i,
    );
  }
  final pill = RRect.fromRectAndRadius(
    l.shuffle,
    Radius.circular(l.shuffle.height / 2),
  );
  canvas.drawRRect(pill, Paint()..color = AppColors.primaryContainer);
  _text(
    canvas,
    'Acak ulang',
    l.shuffle,
    u * 0.8,
    AppColors.primary,
    weight: FontWeight.w700,
    icon: Icons.shuffle,
  );
}
