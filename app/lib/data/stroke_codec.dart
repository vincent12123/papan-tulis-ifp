import 'dart:convert';
import 'dart:ui';

import '../canvas/stroke.dart';
import '../peraga/peraga_specs.dart';
import '../solid/solid_geometry.dart';

/// Object kinds stored in `objects.kind` (SPEC §4.3).
abstract final class ObjectKind {
  static const stroke = 'goresan';
  static const shape = 'bentuk';
  static const image = 'gambar';
  static const graph = 'grafik';
  static const text = 'teks';
  static const solid = 'bangun';
  static const peraga = 'peraga';
  static const quiz = 'kuis';

  static String of(PageItem item) => switch (item) {
    Stroke() => stroke,
    ShapeItem() => shape,
    ImageItem() => image,
    GraphItem() => graph,
    TextItem() => text,
    SolidItem() => solid,
    PeragaItem() => peraga,
    QuizItem() => quiz,
  };
}

/// Versioned JSON for `objects.data`, per kind. Coordinates are rounded to
/// 0.01 px: invisible, and it keeps rows small.
abstract final class ItemCodec {
  static String encode(PageItem item) => switch (item) {
    Stroke() => StrokeCodec.encode(item),
    ShapeItem() => jsonEncode({
      'v': 1,
      't': item.type.name,
      'c': item.color.toARGB32(),
      'w': _round(item.width),
      'pts': [
        for (final p in item.points) ...[_round(p.dx), _round(p.dy)],
      ],
    }),
    TextItem() => jsonEncode({
      'v': 1,
      'teks': item.text,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
      'ukuran': _round(item.fontSize),
      'c': item.color.toARGB32(),
    }),
    PeragaItem() => jsonEncode({
      'v': 1,
      'jenis': item.kind.name,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
      'nilai': item.values,
    }),
    QuizItem() => jsonEncode({
      'v': 1,
      'judul': item.title,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
      'pasangan': [
        for (final (a, b) in item.pairs) [a, b],
      ],
    }),
    SolidItem() => jsonEncode({
      'v': 1,
      'bentuk': item.kind.name,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
      'putar': [_round(item.yaw), _round(item.pitch)],
      'buka': _round(item.unfold),
      'potong': item.cut,
    }),
    GraphItem() => jsonEncode({
      'v': 1,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
      'sumbu': [item.xMin, item.xMax, item.yMin, item.yMax],
      'fungsi': [
        for (final f in item.functions)
          {'rumus': f.formula, 'c': f.color.toARGB32()},
      ],
      'parameter': [
        for (final p in item.params)
          {'nama': p.name, 'min': p.min, 'maks': p.max, 'nilai': p.value},
      ],
    }),
    ImageItem() => jsonEncode({
      'v': 1,
      'file': item.file,
      'x': _round(item.rect.left),
      'y': _round(item.rect.top),
      'w': _round(item.rect.width),
      'h': _round(item.rect.height),
    }),
  };

  /// Throws [FormatException] when the data cannot be read, so a damaged
  /// board is detected instead of drawing garbage (SPEC 5.3). Unknown kinds
  /// from a newer app version return null and are skipped.
  static PageItem? decode({
    required String kind,
    required String id,
    required int z,
    required String data,
  }) {
    switch (kind) {
      case ObjectKind.stroke:
        return StrokeCodec.decode(id: id, z: z, data: data);
      case ObjectKind.shape:
        final json = _map(id, data);
        final type = ShapeType.values.asNameMap()[json['t']];
        final raw = json['pts'];
        if (type == null ||
            json['c'] is! int ||
            json['w'] is! num ||
            raw is! List ||
            raw.any((v) => v is! num) ||
            raw.length % 2 != 0 ||
            raw.length < 4 ||
            raw.length > 6) {
          throw FormatException('Bentuk $id rusak');
        }
        final nums = raw.cast<num>();
        return ShapeItem(
          id: id,
          z: z,
          type: type,
          color: Color(json['c'] as int),
          width: (json['w'] as num).toDouble(),
          points: [
            for (var i = 0; i < nums.length; i += 2)
              Offset(nums[i].toDouble(), nums[i + 1].toDouble()),
          ],
        );
      case ObjectKind.image:
        final json = _map(id, data);
        final values = [json['x'], json['y'], json['w'], json['h']];
        if (json['file'] is! String || values.any((v) => v is! num)) {
          throw FormatException('Gambar $id rusak');
        }
        final v = values.cast<num>();
        return ImageItem(
          id: id,
          z: z,
          file: json['file'] as String,
          rect: Rect.fromLTWH(
            v[0].toDouble(),
            v[1].toDouble(),
            v[2].toDouble(),
            v[3].toDouble(),
          ),
        );
      case ObjectKind.text:
        final j = _map(id, data);
        final values = [j['x'], j['y'], j['w'], j['h'], j['ukuran']];
        if (j['teks'] is! String ||
            j['c'] is! int ||
            values.any((v) => v is! num)) {
          throw FormatException('Teks $id rusak');
        }
        final v = values.cast<num>();
        return TextItem(
          id: id,
          z: z,
          text: j['teks'] as String,
          rect: Rect.fromLTWH(
            v[0].toDouble(),
            v[1].toDouble(),
            v[2].toDouble(),
            v[3].toDouble(),
          ),
          fontSize: v[4].toDouble(),
          color: Color(j['c'] as int),
        );
      case ObjectKind.graph:
        return _decodeGraph(id, z, _map(id, data));
      case ObjectKind.peraga:
        final j = _map(id, data);
        final kind = PeragaKind.values.where((k) => k.name == j['jenis']);
        final values = [j['x'], j['y'], j['w'], j['h']];
        final raw = j['nilai'];
        if (kind.isEmpty || values.any((v) => v is! num) || raw is! Map) {
          throw FormatException('Alat peraga $id rusak');
        }
        final spec = kind.first.spec;
        final v = values.cast<num>();
        return PeragaItem(
          id: id,
          z: z,
          kind: kind.first,
          rect: Rect.fromLTWH(
            v[0].toDouble(),
            v[1].toDouble(),
            v[2].toDouble(),
            v[3].toDouble(),
          ),
          values: {
            for (final p in spec.params)
              if (raw[p.name] is num)
                p.name: p.snap((raw[p.name] as num).toDouble()),
          },
        );
      case ObjectKind.quiz:
        final j = _map(id, data);
        final values = [j['x'], j['y'], j['w'], j['h']];
        final pairs = j['pasangan'];
        if (j['judul'] is! String ||
            values.any((v) => v is! num) ||
            pairs is! List ||
            pairs.isEmpty ||
            pairs.length > QuizItem.maxPairs ||
            pairs.any(
              (p) => p is! List || p.length != 2 || p.any((s) => s is! String),
            )) {
          throw FormatException('Kuis $id rusak');
        }
        final v = values.cast<num>();
        return QuizItem(
          id: id,
          z: z,
          title: j['judul'] as String,
          rect: Rect.fromLTWH(
            v[0].toDouble(),
            v[1].toDouble(),
            v[2].toDouble(),
            v[3].toDouble(),
          ),
          pairs: [
            for (final p in pairs.cast<List<dynamic>>())
              (p[0] as String, p[1] as String),
          ],
        );
      case ObjectKind.solid:
        final j = _map(id, data);
        final kind = SolidKind.values.where((k) => k.name == j['bentuk']);
        final values = [j['x'], j['y'], j['w'], j['h'], j['buka']];
        final turn = j['putar'];
        if (kind.isEmpty ||
            values.any((v) => v is! num) ||
            turn is! List ||
            turn.length != 2 ||
            turn.any((v) => v is! num) ||
            j['potong'] is! bool) {
          throw FormatException('Bangun ruang $id rusak');
        }
        final v = values.cast<num>();
        return SolidItem(
          id: id,
          z: z,
          kind: kind.first,
          rect: Rect.fromLTWH(
            v[0].toDouble(),
            v[1].toDouble(),
            v[2].toDouble(),
            v[3].toDouble(),
          ),
          yaw: (turn[0] as num).toDouble(),
          pitch: (turn[1] as num).toDouble(),
          unfold: v[4].toDouble().clamp(0.0, 1.0),
          cut: j['potong'] as bool,
        );
      default:
        return null;
    }
  }

  static GraphItem _decodeGraph(String id, int z, Map<dynamic, dynamic> j) {
    try {
      final axes = (j['sumbu'] as List).cast<num>();
      final rect = Rect.fromLTWH(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
      );
      if (axes.length != 4 || axes[0] >= axes[1] || axes[2] >= axes[3]) {
        throw const FormatException('sumbu');
      }
      return GraphItem(
        id: id,
        z: z,
        rect: rect,
        xMin: axes[0].toDouble(),
        xMax: axes[1].toDouble(),
        yMin: axes[2].toDouble(),
        yMax: axes[3].toDouble(),
        functions: [
          for (final f in j['fungsi'] as List)
            GraphFunction(f['rumus'] as String, Color(f['c'] as int)),
        ],
        params: [
          for (final p in j['parameter'] as List)
            GraphParam(
              name: p['nama'] as String,
              min: (p['min'] as num).toDouble(),
              max: (p['maks'] as num).toDouble(),
              value: (p['nilai'] as num).toDouble(),
            ),
        ],
      );
    } on TypeError {
      throw FormatException('Grafik $id rusak');
    } on FormatException {
      throw FormatException('Grafik $id rusak');
    }
  }

  static Map<dynamic, dynamic> _map(String id, String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map && json['v'] == 1) return json;
    } on FormatException {
      // Reported below.
    }
    throw FormatException('Objek $id rusak');
  }
}

/// Versioned JSON for a stroke's `objects.data`.
abstract final class StrokeCodec {
  static const version = 1;

  static String encode(Stroke stroke) {
    final pts = <num>[];
    for (final p in stroke.points) {
      pts
        ..add(_round(p.x))
        ..add(_round(p.y));
      if (stroke.hasPressure) pts.add(_round(p.pressure));
    }
    return jsonEncode({
      'v': version,
      'c': stroke.color.toARGB32(),
      'w': _round(stroke.width),
      'p': stroke.hasPressure,
      if (stroke.chalk) 'k': true,
      'pts': pts,
    });
  }

  static Stroke decode({
    required String id,
    required int z,
    required String data,
  }) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      throw FormatException('Goresan $id rusak');
    }
    if (json is! Map ||
        json['v'] != version ||
        json['c'] is! int ||
        json['w'] is! num ||
        json['p'] is! bool ||
        json['pts'] is! List) {
      throw FormatException('Goresan $id rusak');
    }
    final hasPressure = json['p'] as bool;
    final raw = json['pts'] as List;
    final stride = hasPressure ? 3 : 2;
    if (raw.isEmpty || raw.length % stride != 0 || raw.any((v) => v is! num)) {
      throw FormatException('Goresan $id rusak');
    }
    final points = <InkPoint>[
      for (var i = 0; i < raw.length; i += stride)
        InkPoint(
          (raw[i] as num).toDouble(),
          (raw[i + 1] as num).toDouble(),
          hasPressure ? (raw[i + 2] as num).toDouble() : 0.5,
        ),
    ];
    return Stroke(
      id: id,
      color: Color(json['c'] as int),
      width: (json['w'] as num).toDouble(),
      hasPressure: hasPressure,
      z: z,
      points: points,
      // Optional: strokes saved before chalk existed have no 'k'.
      chalk: json['k'] == true,
    );
  }
}

num _round(double v) => (v * 100).roundToDouble() / 100;
