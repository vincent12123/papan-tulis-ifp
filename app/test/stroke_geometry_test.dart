import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/ink_painters.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/canvas/stroke_geometry.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

Stroke _line({
  required int pointCount,
  double length = 300,
  bool pressure = false,
  double p = 0.5,
}) {
  final stroke = Stroke(
    id: 's',
    color: PenColors.black,
    width: PenWidths.medium,
    hasPressure: pressure,
  );
  for (var i = 0; i < pointCount; i++) {
    stroke.points.add(InkPoint(length * i / (pointCount - 1), 0, p));
  }
  return stroke;
}

/// Average thickness of an outline around a horizontal line, measured on the
/// middle half so the tapered ends do not dominate.
double _middleThickness(Stroke stroke) {
  final outline = strokeOutline(stroke, complete: true);
  final xs = outline.map((o) => o.dx);
  final minX = xs.reduce((a, b) => a < b ? a : b);
  final maxX = xs.reduce((a, b) => a > b ? a : b);
  final from = minX + (maxX - minX) * 0.25;
  final to = minX + (maxX - minX) * 0.75;
  final middle = outline.where((o) => o.dx >= from && o.dx <= to);
  final above = middle.where((o) => o.dy < 0).map((o) => -o.dy);
  final below = middle.where((o) => o.dy > 0).map((o) => o.dy);
  double avg(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
  return avg(above) + avg(below);
}

void main() {
  test('AC-02 thickness follows writing speed for fingers', () {
    // Same line drawn slowly (many close points) and fast (few far points).
    final slow = _middleThickness(_line(pointCount: 120));
    final fast = _middleThickness(_line(pointCount: 6));
    expect((slow - fast).abs(), greaterThan(0.5));
  });

  test('AC-02 thickness follows stylus pressure', () {
    final light = _middleThickness(
      _line(pointCount: 60, pressure: true, p: 0.1),
    );
    final heavy = _middleThickness(
      _line(pointCount: 60, pressure: true, p: 0.9),
    );
    expect(heavy, greaterThan(light));
  });

  test('AC-11 a single point becomes a round dot of the pen width', () {
    final dot = Stroke(
      id: 'd',
      color: PenColors.black,
      width: 12,
      hasPressure: false,
    )..points.add(const InkPoint(50, 50));
    final bounds = buildStrokePath(dot, complete: true).getBounds();
    expect(bounds.width, closeTo(12, 0.01));
    expect(bounds.center, const Offset(50, 50));
  });

  test('empty stroke yields an empty path', () {
    final empty = Stroke(
      id: 'e',
      color: PenColors.black,
      width: 6,
      hasPressure: false,
    );
    expect(buildStrokePath(empty, complete: true).getBounds(), Rect.zero);
  });

  test('completed path is computed once and reused', () {
    final stroke = _line(pointCount: 20);
    expect(
      identical(completedStrokePath(stroke), completedStrokePath(stroke)),
      isTrue,
    );
  });

  group('InkPictureCache', () {
    List<Stroke> strokes(int n) =>
        List.generate(n, (_) => _line(pointCount: 4, length: 20));

    test('appending re-records only the last chunk', () {
      final cache = InkPictureCache(chunkSize: 10);
      final list = strokes(25);
      final first = [...cache.chunksFor(list)];
      expect(first, hasLength(3));

      final second = cache.chunksFor([
        ...list,
        _line(pointCount: 4, length: 20),
      ]);
      expect(second, hasLength(3));
      expect(identical(second[0], first[0]), isTrue);
      expect(identical(second[1], first[1]), isTrue);
      expect(identical(second[2], first[2]), isFalse);
      cache.dispose();
    });

    test('undo of the newest stroke keeps earlier chunks', () {
      final cache = InkPictureCache(chunkSize: 10);
      final list = strokes(21);
      final first = [...cache.chunksFor(list)];
      final after = cache.chunksFor(list.sublist(0, 20));
      expect(after, hasLength(2));
      expect(identical(after[0], first[0]), isTrue);
      cache.dispose();
    });

    test('no strokes means no chunks', () {
      final cache = InkPictureCache();
      expect(cache.chunksFor(const []), isEmpty);
    });
  });
}
