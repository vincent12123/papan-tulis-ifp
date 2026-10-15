import 'dart:math';
import 'dart:ui';

import '../peraga/peraga_specs.dart';
import '../solid/solid_geometry.dart';

import '../graph/expression.dart';

/// One sampled input point in canvas coordinates.
class InkPoint {
  const InkPoint(this.x, this.y, [this.pressure = 0.5]);

  final double x;
  final double y;

  /// Normalized 0..1. Only meaningful when the stroke [Stroke.hasPressure].
  final double pressure;
}

/// Anything placed on a page (SPEC §4.3 Objek). Ordered by [z]; newer is on
/// top.
sealed class PageItem {
  PageItem({required this.id, this.z = 0});

  final String id;

  /// Stacking order on the page (SPEC §4.3 urutan_tumpuk).
  int z;

  Rect get bounds;
}

/// A finished or in-progress freehand stroke (jenis = goresan).
class Stroke extends PageItem {
  Stroke({
    required super.id,
    required this.color,
    required this.width,
    required this.hasPressure,
    super.z,
    List<InkPoint>? points,
    this.chalk = false,
  }) : points = points ?? <InkPoint>[];

  final Color color;
  final double width;

  /// Drawn with a chalk grain (gaya kapur, REQ-29).
  final bool chalk;

  /// True when points carry real stylus pressure; otherwise thickness is
  /// simulated from drawing speed.
  final bool hasPressure;
  final List<InkPoint> points;

  /// Cached outline of a completed stroke; built once by the renderer.
  Path? cachedPath;

  bool get isDot => points.length == 1;

  @override
  Rect get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width);
  }
}

/// Basic shapes (REQ-08). Names match the Indonesian UI labels.
enum ShapeType { garis, persegi, lingkaran, segitiga, panah }

/// A neat shape (jenis = bentuk). [points] are two opposite corners (or the
/// two line ends) for every type except [ShapeType.segitiga], which keeps its
/// three corners.
class ShapeItem extends PageItem {
  ShapeItem({
    required super.id,
    required this.type,
    required this.points,
    required this.color,
    required this.width,
    super.z,
  });

  final ShapeType type;
  final List<Offset> points;
  final Color color;
  final double width;

  @override
  Rect get bounds {
    var r = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(width + (type == ShapeType.panah ? width * 3 : 0));
  }

  /// Same shape moved/scaled from [from] to [to] (Pilih tool).
  ShapeItem transformed(Rect from, Rect to) => ShapeItem(
    id: id,
    type: type,
    points: [for (final p in points) mapPoint(p, from, to)],
    color: color,
    width: width,
    z: z,
  );
}

/// An inserted picture (jenis = gambar). [file] is a name in the media
/// store; [rect] is where it sits on the canvas.
class ImageItem extends PageItem {
  ImageItem({
    required super.id,
    required this.file,
    required this.rect,
    super.z,
  });

  final String file;
  final Rect rect;

  @override
  Rect get bounds => rect;

  ImageItem withRect(Rect r) => ImageItem(id: id, file: file, rect: r, z: z);
}

/// Typed text on the page (jenis = teks), e.g. a pasted AI answer.
/// [fontSize] is in canvas units; text wraps at the box width.
class TextItem extends PageItem {
  TextItem({
    required super.id,
    required this.text,
    required this.rect,
    required this.fontSize,
    required this.color,
    super.z,
  });

  final String text;
  final Rect rect;
  final double fontSize;
  final Color color;

  @override
  Rect get bounds => rect;

  /// Resizing scales the text with the box.
  TextItem withRect(Rect r) => TextItem(
    id: id,
    text: text,
    rect: r,
    fontSize: rect.height > 0 ? fontSize * r.height / rect.height : fontSize,
    color: color,
    z: z,
  );

  TextItem copyAs(String newId) => TextItem(
    id: newId,
    text: text,
    rect: rect,
    fontSize: fontSize,
    color: color,
    z: z,
  );
}

/// A parameter of an interactive graph, moved with its slider (REQ-20).
class GraphParam {
  const GraphParam({
    required this.name,
    required this.min,
    required this.max,
    required this.value,
  });

  final String name;
  final double min;
  final double max;
  final double value;

  GraphParam withValue(double v) =>
      GraphParam(name: name, min: min, max: max, value: v.clamp(min, max));
}

/// One curve: its formula as written (e.g. `y = A sin x + B`) and color.
class GraphFunction {
  const GraphFunction(this.formula, this.color);
  final String formula;
  final Color color;
}

/// An interactive function graph made by "Jadikan grafik" (jenis = grafik).
class GraphItem extends PageItem {
  GraphItem({
    required super.id,
    required this.rect,
    required this.functions,
    required this.params,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    super.z,
  });

  final Rect rect;
  final List<GraphFunction> functions;
  final List<GraphParam> params;
  final double xMin, xMax, yMin, yMax;

  /// Parsed formulas, in the order of [functions]; null if unparsable.
  late final List<Expression?> expressions = [
    for (final f in functions) _tryParse(f.formula),
  ];

  Map<String, double> get values => {for (final p in params) p.name: p.value};

  @override
  Rect get bounds => rect;

  GraphItem _copy({Rect? rect, List<GraphParam>? params}) => GraphItem(
    id: id,
    rect: rect ?? this.rect,
    functions: functions,
    params: params ?? this.params,
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
    z: z,
  );

  GraphItem withRect(Rect r) => _copy(rect: r);

  GraphItem withParam(String name, double value) => _copy(
    params: [for (final p in params) p.name == name ? p.withValue(value) : p],
  );

  /// Same graph under another id (page duplicate, paste).
  GraphItem copyAs(String newId) => GraphItem(
    id: newId,
    rect: rect,
    functions: functions,
    params: params,
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
    z: z,
  );

  static Expression? _tryParse(String formula) {
    try {
      return Expression.parse(formula);
    } on FormatException {
      return null;
    }
  }
}

/// Maps [p] from rectangle [from] to rectangle [to].
Offset mapPoint(Offset p, Rect from, Rect to) {
  final sx = from.width == 0 ? 1.0 : to.width / from.width;
  final sy = from.height == 0 ? 1.0 : to.height / from.height;
  return Offset(
    to.left + (p.dx - from.left) * sx,
    to.top + (p.dy - from.top) * sy,
  );
}

/// Random version-4 UUIDs (SPEC §4: id uuid) without extra dependencies.
class IdGenerator {
  IdGenerator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  String next() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// A 3D solid on the board (jenis = bangun, REQ-23): which solid, how it is
/// turned, how far its net is open, and whether its cut plane shows.
class SolidItem extends PageItem {
  SolidItem({
    required super.id,
    required this.kind,
    required this.rect,
    this.yaw = defaultYaw,
    this.pitch = defaultPitch,
    this.unfold = 0,
    this.cut = false,
    super.z,
  });

  static const defaultYaw = -0.6;
  static const defaultPitch = 0.45;

  /// Tilt limit so the solid never flips upside down while turning.
  static const maxPitch = 1.45;

  final SolidKind kind;
  final Rect rect;
  final double yaw, pitch;

  /// 0 = closed solid, 1 = net fully open.
  final double unfold;
  final bool cut;

  @override
  Rect get bounds => rect;

  SolidItem _copy({
    String? id,
    Rect? rect,
    double? yaw,
    double? pitch,
    double? unfold,
    bool? cut,
  }) => SolidItem(
    id: id ?? this.id,
    kind: kind,
    rect: rect ?? this.rect,
    yaw: yaw ?? this.yaw,
    pitch: (pitch ?? this.pitch).clamp(-maxPitch, maxPitch),
    unfold: (unfold ?? this.unfold).clamp(0.0, 1.0),
    cut: cut ?? this.cut,
    z: z,
  );

  SolidItem withRect(Rect r) => _copy(rect: r);
  SolidItem turnedBy(double dYaw, double dPitch) =>
      _copy(yaw: yaw + dYaw, pitch: pitch + dPitch);
  SolidItem withUnfold(double value) => _copy(unfold: value);
  SolidItem withCut(bool value) => _copy(cut: value);
  SolidItem copyAs(String newId) => _copy(id: newId);
}

/// An alat peraga on the board (jenis = peraga): a physics simulation
/// (REQ-26) or a virtual chemistry lab (REQ-28) with its slider values.
/// Whether it is playing is not saved: a board always opens paused.
class PeragaItem extends PageItem {
  PeragaItem({
    required super.id,
    required this.kind,
    required this.rect,
    Map<String, double>? values,
    super.z,
  }) : values = {...kind.spec.defaults, ...?values};

  final PeragaKind kind;
  final Rect rect;
  final Map<String, double> values;

  @override
  Rect get bounds => rect;

  PeragaItem withRect(Rect r) =>
      PeragaItem(id: id, kind: kind, rect: r, values: values, z: z);

  PeragaItem withValue(String name, double value) => PeragaItem(
    id: id,
    kind: kind,
    rect: rect,
    values: {...values, name: value},
    z: z,
  );

  PeragaItem copyAs(String newId) =>
      PeragaItem(id: newId, kind: kind, rect: rect, values: values, z: z);
}

/// A matching quiz students solve at the board (jenis = kuis, REQ-27).
/// Progress (which pairs are matched) is not saved.
class QuizItem extends PageItem {
  QuizItem({
    required super.id,
    required this.rect,
    required this.title,
    required this.pairs,
    super.z,
  });

  static const maxPairs = 6;

  final Rect rect;
  final String title;
  final List<(String, String)> pairs;

  @override
  Rect get bounds => rect;

  QuizItem withRect(Rect r) =>
      QuizItem(id: id, rect: r, title: title, pairs: pairs, z: z);

  QuizItem copyAs(String newId) =>
      QuizItem(id: newId, rect: rect, title: title, pairs: pairs, z: z);
}

/// A table the teacher types into (jenis = tabel, REQ-21). Row 0 holds the
/// column titles; column 0 holds x values or category names; the other
/// columns are number series. Cells keep exactly what was typed.
class TableItem extends PageItem {
  TableItem({
    required super.id,
    required this.rect,
    required this.cells,
    super.z,
  });

  /// Rows count the title row too.
  static const minRows = 2, maxRows = 20, minCols = 2, maxCols = 6;

  /// Longest text a cell keeps.
  static const maxCellLength = 24;

  final Rect rect;

  /// [row][column]; every row has the same length.
  final List<List<String>> cells;

  int get rows => cells.length;
  int get cols => cells.first.length;

  /// Empty table with [rows] × [cols] cells.
  static List<List<String>> blank(int rows, int cols) => [
    for (var r = 0; r < rows; r++) List.filled(cols, ''),
  ];

  @override
  Rect get bounds => rect;

  TableItem withRect(Rect r) => TableItem(id: id, rect: r, cells: cells, z: z);

  TableItem withCells(List<List<String>> c) =>
      TableItem(id: id, rect: rect, cells: c, z: z);

  TableItem copyAs(String newId) =>
      TableItem(id: newId, rect: rect, cells: cells, z: z);
}

/// Kinds of chart made from a table (REQ-21).
enum ChartKind {
  garis('Garis'),
  batang('Batang'),
  titik('Titik');

  const ChartKind(this.label);
  final String label;
}

/// A chart drawn from a table (stored as jenis = grafik, REQ-21). It keeps
/// its own copy of the table cells, so it still shows the last data after
/// the table is deleted; while table [tableId] is on the page, editing the
/// table updates this copy in the same step.
class ChartItem extends PageItem {
  ChartItem({
    required super.id,
    required this.rect,
    required this.kind,
    required this.tableId,
    required this.cells,
    super.z,
  });

  final Rect rect;
  final ChartKind kind;
  final String tableId;
  final List<List<String>> cells;

  @override
  Rect get bounds => rect;

  ChartItem withRect(Rect r) => ChartItem(
    id: id,
    rect: r,
    kind: kind,
    tableId: tableId,
    cells: cells,
    z: z,
  );

  ChartItem withCells(List<List<String>> c) => ChartItem(
    id: id,
    rect: rect,
    kind: kind,
    tableId: tableId,
    cells: c,
    z: z,
  );

  ChartItem copyAs(String newId, {String? tableId}) => ChartItem(
    id: newId,
    rect: rect,
    kind: kind,
    tableId: tableId ?? this.tableId,
    cells: cells,
    z: z,
  );
}

/// One word on a Mandarin card (REQ-30). [source] is `kamus` (Indonesian),
/// `inggris` (English meaning, no Indonesian yet), or `tidak_ada`.
typedef MandarinEntry = ({
  String hanzi,
  String pinyin,
  String meaning,
  String source,
});

/// Pinyin & arti card beside handwritten Hanzi (jenis = mandarin, REQ-30).
class MandarinItem extends PageItem {
  MandarinItem({
    required super.id,
    required this.rect,
    required this.hanzi,
    required this.pinyin,
    required this.words,
    this.translation,
    super.z,
  });

  static const maxWords = 24;

  final Rect rect;
  final String hanzi;
  final String pinyin;
  final List<MandarinEntry> words;

  /// Sentence translation by the AI; null when it was not available.
  final String? translation;

  @override
  Rect get bounds => rect;

  MandarinItem withRect(Rect r) => copyAs(id, rect: r);

  MandarinItem copyAs(String newId, {Rect? rect}) => MandarinItem(
    id: newId,
    rect: rect ?? this.rect,
    hanzi: hanzi,
    pinyin: pinyin,
    words: words,
    translation: translation,
    z: z,
  );
}
