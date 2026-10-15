import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/eraser.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/canvas/media_images.dart';
import 'package:whiteboard_ifp/canvas/shapes.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

/// Points along a polyline, with a little hand wobble.
List<InkPoint> trace(
  List<Offset> corners, {
  int perSide = 20,
  double wobble = 2,
}) {
  final random = Random(3);
  final pts = <InkPoint>[];
  for (var i = 0; i < corners.length - 1; i++) {
    for (var s = 0; s < perSide; s++) {
      final p = Offset.lerp(corners[i], corners[i + 1], s / perSide)!;
      pts.add(
        InkPoint(
          p.dx + (random.nextDouble() - 0.5) * wobble,
          p.dy + (random.nextDouble() - 0.5) * wobble,
        ),
      );
    }
  }
  pts.add(InkPoint(corners.last.dx, corners.last.dy));
  return pts;
}

List<InkPoint> circle(Offset c, double rx, double ry) => [
  for (var i = 0; i <= 60; i++)
    InkPoint(c.dx + rx * cos(i * pi / 30), c.dy + ry * sin(i * pi / 30)),
];

void main() {
  group('recognizeShape (P-07 Otomatis)', () {
    test('a nearly straight stroke becomes a line', () {
      final r = recognizeShape(
        trace([const Offset(10, 10), const Offset(300, 40)]),
      );
      expect(r?.type, ShapeType.garis);
      expect(r!.points.first.dx, closeTo(10, 3));
    });

    test('a closed four-corner stroke becomes an axis-aligned rectangle', () {
      final r = recognizeShape(
        trace(const [
          Offset(100, 100),
          Offset(400, 100),
          Offset(400, 300),
          Offset(100, 300),
          Offset(100, 100),
        ]),
      );
      expect(r?.type, ShapeType.persegi);
      final rect = Rect.fromPoints(r!.points[0], r.points[1]);
      expect(rect.left, closeTo(100, 4));
      expect(rect.bottom, closeTo(300, 4));
    });

    test('a round closed stroke becomes a circle/ellipse', () {
      final r = recognizeShape(circle(const Offset(200, 200), 120, 80));
      expect(r?.type, ShapeType.lingkaran);
      final rect = Rect.fromPoints(r!.points[0], r.points[1]);
      expect(rect.width, closeTo(240, 3));
      expect(rect.height, closeTo(160, 3));
    });

    test(
      'a closed three-corner stroke becomes a triangle with its corners',
      () {
        final r = recognizeShape(
          trace(const [
            Offset(100, 300),
            Offset(250, 80),
            Offset(400, 300),
            Offset(100, 300),
          ]),
        );
        expect(r?.type, ShapeType.segitiga);
        expect(r!.points, hasLength(3));
      },
    );

    test('an open squiggle stays as drawn', () {
      final r = recognizeShape(
        trace(const [
          Offset(0, 0),
          Offset(80, 120),
          Offset(160, 0),
          Offset(240, 120),
        ]),
      );
      expect(r, isNull);
    });

    test('tiny marks and single taps are not shapes', () {
      expect(recognizeShape(const [InkPoint(1, 1)]), isNull);
      expect(
        recognizeShape(trace([const Offset(0, 0), const Offset(10, 5)])),
        isNull,
      );
    });
  });

  group('shape geometry', () {
    ShapeItem shape(ShapeType t, List<Offset> pts) => ShapeItem(
      id: 's',
      type: t,
      points: pts,
      color: PenColors.black,
      width: 6,
    );

    test('triangle from a dragged box has apex top-center', () {
      final t = trianglePoints(
        shape(ShapeType.segitiga, const [Offset(0, 0), Offset(100, 80)]),
      );
      expect(t.first, const Offset(50, 0));
    });

    test('eraser hits a shape on its outline but not in its empty middle', () {
      final box = shape(ShapeType.persegi, const [
        Offset(0, 0),
        Offset(200, 200),
      ]);
      expect(eraserTouchesItem(box, const Offset(100, 2), 5), isTrue);
      expect(eraserTouchesItem(box, const Offset(100, 100), 5), isFalse);
      final ring = shape(ShapeType.lingkaran, const [
        Offset(0, 0),
        Offset(200, 200),
      ]);
      expect(eraserTouchesItem(ring, const Offset(200, 100), 5), isTrue);
    });

    test('pictures are never erased', () {
      final pic = ImageItem(
        id: 'p',
        file: 'a.png',
        rect: const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(eraserTouchesItem(pic, const Offset(50, 50), 20), isFalse);
    });

    test('transformed maps the shape into a new frame', () {
      final s = shape(ShapeType.persegi, const [Offset(0, 0), Offset(100, 50)]);
      final moved = s.transformed(
        const Rect.fromLTWH(0, 0, 100, 50),
        const Rect.fromLTWH(10, 20, 200, 100),
      );
      expect(moved.points, const [Offset(10, 20), Offset(210, 120)]);
      expect(moved.id, s.id);
    });

    test('codec round-trips shapes, triangles, and pictures', () {
      final items = <PageItem>[
        shape(ShapeType.panah, const [Offset(1, 2), Offset(30, 40)]),
        shape(ShapeType.segitiga, const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(5, 9),
        ]),
        ImageItem(
          id: 'i',
          file: 'x.png',
          rect: const Rect.fromLTWH(5, 6, 70, 80),
        ),
      ];
      for (final item in items) {
        final back = ItemCodec.decode(
          kind: ObjectKind.of(item),
          id: item.id,
          z: 3,
          data: ItemCodec.encode(item),
        );
        expect(back.runtimeType, item.runtimeType);
        expect(back!.bounds, item.bounds);
      }
    });

    test('codec rejects damaged shapes and skips unknown kinds', () {
      expect(
        () => ItemCodec.decode(
          kind: ObjectKind.shape,
          id: 'x',
          z: 1,
          data: '{"v":1,"t":"bintang","c":1,"w":2,"pts":[0,0,1,1]}',
        ),
        throwsFormatException,
      );
      expect(
        ItemCodec.decode(kind: 'teks-masa-depan', id: 'x', z: 1, data: '{}'),
        isNull,
      );
    });

    test('background JSON round-trips and rejects junk', () {
      const bg = PageBackground(
        file: 'b.png',
        rect: Rect.fromLTWH(0, 0, 800, 600),
      );
      final back = PageBackground.fromJson(bg.toJson())!;
      expect(back.file, 'b.png');
      expect(back.rect, bg.rect);
      expect(PageBackground.fromJson({'file': 3}), isNull);
    });

    test('fitInside keeps the aspect ratio and centers', () {
      final r = fitInside(
        const Size(200, 100),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(r, const Rect.fromLTWH(0, 25, 100, 50));
    });
  });

  group('InkController shapes and Pilih', () {
    late InkController ink;
    setUp(() => ink = InkController());
    tearDown(() => ink.dispose());

    test('AC-42 dragging with a menu shape adds that shape', () {
      ink.shapeDown(1, const Offset(10, 10), ShapeType.lingkaran);
      ink.shapeMove(1, const Offset(110, 60));
      expect(ink.activeShapes, hasLength(1));
      ink.shapeUp(1);
      final s = ink.items.single as ShapeItem;
      expect(s.type, ShapeType.lingkaran);
      expect(s.points.last, const Offset(110, 60));
      expect(ink.canUndo, isTrue);
    });

    test('a tap with a shape tool adds nothing', () {
      ink.shapeDown(1, const Offset(10, 10), ShapeType.persegi);
      ink.shapeUp(1);
      expect(ink.items, isEmpty);
    });

    test('Otomatis turns a circle drawing into a shape, a squiggle stays', () {
      final pts = circle(const Offset(200, 200), 80, 80);
      ink.pointerDown(1, Offset(pts.first.x, pts.first.y), recognize: true);
      for (final p in pts.skip(1)) {
        ink.pointerMove(1, Offset(p.x, p.y));
      }
      ink.pointerUp(1);
      expect(ink.items.single, isA<ShapeItem>());

      ink.pointerDown(2, Offset.zero, recognize: true);
      for (final p in trace(const [
        Offset(0, 0),
        Offset(80, 120),
        Offset(160, 0),
      ]).skip(1)) {
        ink.pointerMove(2, Offset(p.x, p.y));
      }
      ink.pointerUp(2);
      expect(ink.items.last, isA<Stroke>());
    });

    test('Pilih selects only shapes and pictures, topmost first', () {
      ink.pointerDown(1, const Offset(0, 50));
      ink.pointerMove(1, const Offset(300, 50));
      ink.pointerUp(1);
      expect(ink.hitSelectable(const Offset(150, 50)), isNull);

      ink.shapeDown(1, const Offset(100, 0), ShapeType.persegi);
      ink.shapeMove(1, const Offset(200, 100));
      ink.shapeUp(1);
      final pic = ImageItem(
        id: 'pic',
        file: 'a.png',
        rect: const Rect.fromLTWH(150, 40, 100, 100),
      );
      ink.addItem(pic);
      expect(ink.hitSelectable(const Offset(160, 50))?.id, 'pic');
      expect(ink.hitSelectable(const Offset(110, 10)), isA<ShapeItem>());
    });

    test('AC-40 move/resize is one undo step and is reported for saving', () {
      final changed = <PageItem>[];
      ink.listener = _Recorder(changed);
      final pic = ImageItem(
        id: 'pic',
        file: 'a.png',
        rect: const Rect.fromLTWH(0, 0, 100, 50),
      );
      ink.addItem(pic);
      ink.select('pic');
      ink.beginTransform();
      expect(ink.items, isEmpty, reason: 'lifted while moving');
      ink.updateTransform(const Rect.fromLTWH(40, 40, 200, 100));
      ink.endTransform();
      expect(ink.items.single.bounds, const Rect.fromLTWH(40, 40, 200, 100));
      expect(changed.single.bounds, const Rect.fromLTWH(40, 40, 200, 100));

      ink.undo();
      expect(ink.items.single.bounds, const Rect.fromLTWH(0, 0, 100, 50));
      ink.redo();
      expect(ink.items.single.bounds, const Rect.fromLTWH(40, 40, 200, 100));
    });

    test('a tap without moving changes nothing and adds no undo step', () {
      final pic = ImageItem(
        id: 'pic',
        file: 'a.png',
        rect: const Rect.fromLTWH(0, 0, 100, 50),
      );
      ink.addItem(pic);
      ink.select('pic');
      ink.beginTransform();
      ink.endTransform();
      ink.undo(); // undoes the insert itself
      expect(ink.items, isEmpty);
    });

    test('AC-40 delete selected removes it; undo brings it back', () {
      ink.addItem(
        ImageItem(
          id: 'pic',
          file: 'a.png',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
        ),
      );
      ink.select('pic');
      ink.deleteSelected();
      expect(ink.items, isEmpty);
      expect(ink.selected.value, isNull);
      ink.undo();
      expect(ink.items.single.id, 'pic');
    });

    test('AC-44 eraser removes shapes but not pictures', () {
      ink.addItem(
        ImageItem(
          id: 'pic',
          file: 'a.png',
          rect: const Rect.fromLTWH(0, 0, 200, 200),
        ),
      );
      ink.shapeDown(1, const Offset(0, 100), ShapeType.garis);
      ink.shapeMove(1, const Offset(200, 100));
      ink.shapeUp(1);
      ink.eraserDown(2, const Offset(100, 100), radius: 10);
      ink.eraserUp(2);
      expect(ink.items.single.id, 'pic');
    });
  });
}

class _Recorder implements InkChangeListener {
  _Recorder(this.changed);
  final List<PageItem> changed;
  @override
  void itemChanged(PageItem item) => changed.add(item);
  @override
  void itemsAdded(List<PageItem> items) {}
  @override
  void itemsRemoved(List<PageItem> items) {}
}
