import 'dart:math' as math;

import '../canvas/stroke.dart';

/// Reads a typed number: "12,5" and "12.5" are both 12.5 (koma desimal
/// diterima, REQ-21). Anything else, including empty text, is null.
double? parseCell(String text) {
  final t = text.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (!RegExp(r'^[+-]?(\d+([.,]\d*)?|[.,]\d+)$').hasMatch(t)) return null;
  final v = double.tryParse(t.replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

/// Whether a series cell (not the title row, not column 0) holds text that
/// is not a number; such cells are skipped and marked (empty ones are just
/// skipped).
bool isBadCell(List<List<String>> cells, int row, int col) =>
    row > 0 &&
    col > 0 &&
    cells[row][col].trim().isNotEmpty &&
    parseCell(cells[row][col]) == null;

/// One number series of a table: column [col] with its title.
class Series {
  Series(this.col, this.title, this.values);

  final int col;
  final String title;

  /// One value per data row; null where the cell is empty or not a number.
  final List<double?> values;
}

/// What a chart needs from table cells (REQ-21).
class TableData {
  TableData(this.cells)
    : labels = [for (final row in cells.skip(1)) row[0].trim()],
      series = [
        for (var c = 1; c < cells.first.length; c++)
          Series(c, _title(cells[0][c], c), [
            for (final row in cells.skip(1)) parseCell(row[c]),
          ]),
      ] {
    x = [for (final l in labels) parseCell(l)];
    numericX =
        labels.any((l) => l.isNotEmpty) &&
        labels.every((l) => l.isEmpty || parseCell(l) != null);
  }

  final List<List<String>> cells;

  /// Column 0 of each data row, as typed.
  final List<String> labels;

  /// Column 0 as numbers (null where empty or not a number).
  late final List<double?> x;
  final List<Series> series;

  /// Column 0 holds only numbers (empty cells allowed), so Garis and Titik
  /// can be drawn; otherwise only Batang.
  late final bool numericX;

  /// At least one number in a series column.
  bool get hasNumbers => series.any((s) => s.values.any((v) => v != null));

  /// Kinds that can be drawn from this data.
  List<ChartKind> get allowedKinds =>
      numericX ? ChartKind.values : const [ChartKind.batang];

  static String _title(String typed, int col) =>
      typed.trim().isEmpty ? 'Kolom $col' : typed.trim();
}

/// A tidy axis from [min] to [max] with about [count] round steps.
({double min, double max, double step}) niceAxis(
  double min,
  double max, {
  int count = 5,
}) {
  if (min == max) {
    final pad = min == 0 ? 1.0 : min.abs() * 0.5;
    min -= pad;
    max += pad;
  }
  final raw = (max - min) / count;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final step = [
    1.0,
    2.0,
    2.5,
    5.0,
    10.0,
  ].map((f) => f * magnitude).firstWhere((s) => s >= raw);
  return (
    min: (min / step).floor() * step,
    max: (max / step).ceil() * step,
    step: step,
  );
}

/// Short label for an axis number: 1 000 → "1000", 2.5 → "2,5".
String axisLabel(double v, double step) {
  final decimals = step >= 1 ? 0 : (-math.log(step) / math.ln10).ceil();
  final text = v.toStringAsFixed(decimals.clamp(0, 4));
  return (text == '-0' ? '0' : text).replaceAll('.', ',');
}
