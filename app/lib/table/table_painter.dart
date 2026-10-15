import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';

import '../canvas/stroke.dart';
import '../peraga/peraga_painter.dart' show iconSpan;
import '../ui/theme.dart';
import 'table_data.dart';

/// Where each cell of a table sits (canvas coordinates).
class TableLayout {
  TableLayout(this.item)
    : cellW = item.rect.width / item.cols,
      cellH = item.rect.height / item.rows;

  final TableItem item;
  final double cellW, cellH;

  /// Text size: big enough to read from the back of the class at the
  /// default size (≥ 20 sp on screen), smaller for a shrunk table.
  double get fontSize => (cellH * 0.42).clamp(8.0, 60.0);

  Rect cell(int row, int col) => Rect.fromLTWH(
    item.rect.left + col * cellW,
    item.rect.top + row * cellH,
    cellW,
    cellH,
  );

  /// The (row, column) under [at], or null outside the table.
  ({int row, int col})? cellAt(Offset at) {
    if (!item.rect.contains(at)) return null;
    final col = ((at.dx - item.rect.left) / cellW).floor();
    final row = ((at.dy - item.rect.top) / cellH).floor();
    return (row: row.clamp(0, item.rows - 1), col: col.clamp(0, item.cols - 1));
  }
}

void paintTable(Canvas canvas, TableItem item) {
  final l = TableLayout(item);
  final r = item.rect;
  canvas.drawRect(r, Paint()..color = AppColors.surface);
  canvas.drawRect(
    Rect.fromLTWH(r.left, r.top, r.width, l.cellH),
    Paint()..color = AppColors.background,
  );
  final grid = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = AppColors.textMuted;
  for (var c = 1; c < item.cols; c++) {
    final x = r.left + c * l.cellW;
    canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
  }
  for (var row = 1; row < item.rows; row++) {
    final y = r.top + row * l.cellH;
    canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
  }
  canvas.drawRect(r, grid..strokeWidth = 2);

  final size = l.fontSize;
  for (var row = 0; row < item.rows; row++) {
    for (var col = 0; col < item.cols; col++) {
      final box = l.cell(row, col);
      final text = item.cells[row][col];
      final bad = isBadCell(item.cells, row, col);
      if (row == 0 && text.trim().isEmpty) {
        _cellText(canvas, 'Judul', box, size, AppColors.textMuted);
        continue;
      }
      _cellText(
        canvas,
        text,
        box,
        size,
        bad ? AppColors.danger : AppColors.text,
        bold: row == 0,
        warn: bad,
      );
      if (bad) {
        // Marked by underline and icon too, never by color alone.
        final y = box.bottom - size * 0.35;
        canvas.drawLine(
          Offset(box.left + size * 0.3, y),
          Offset(box.right - size * 0.3, y),
          Paint()
            ..strokeWidth = 2
            ..color = AppColors.danger,
        );
      }
    }
  }
}

void _cellText(
  Canvas canvas,
  String text,
  Rect box,
  double size,
  Color color, {
  bool bold = false,
  bool warn = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      children: [
        if (warn) iconSpan(Icons.error_outline, size, color),
        if (warn) const TextSpan(text: ' '),
        TextSpan(text: text),
      ],
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: box.width - size * 0.6);
  painter.paint(
    canvas,
    Offset(
      box.center.dx - painter.width / 2,
      box.center.dy - painter.height / 2,
    ),
  );
  painter.dispose();
}
