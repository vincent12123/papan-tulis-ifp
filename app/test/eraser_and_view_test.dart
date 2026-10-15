import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_title.dart';
import 'package:whiteboard_ifp/canvas/canvas_view.dart';
import 'package:whiteboard_ifp/canvas/eraser.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

void main() {
  late InkController ink;
  setUp(() => ink = InkController());
  tearDown(() => ink.dispose());

  void line(int pointer, Offset from, Offset to) {
    ink.pointerDown(pointer, from);
    for (var i = 1; i <= 10; i++) {
      ink.pointerMove(pointer, Offset.lerp(from, to, i / 10)!);
    }
    ink.pointerUp(pointer);
  }

  group('eraserTouches', () {
    final stroke = Stroke(
      id: 's',
      color: PenColors.black,
      width: 6,
      hasPressure: false,
      points: const [InkPoint(0, 0), InkPoint(100, 0)],
    );

    test('hits on and near the line, misses far away', () {
      expect(eraserTouches(stroke, const Offset(50, 0), 5), isTrue);
      expect(eraserTouches(stroke, const Offset(50, 7), 5), isTrue);
      expect(eraserTouches(stroke, const Offset(50, 30), 5), isFalse);
      expect(eraserTouches(stroke, const Offset(130, 0), 5), isFalse);
    });

    test('dot strokes are hit by distance', () {
      final dot = Stroke(
        id: 'd',
        color: PenColors.black,
        width: 6,
        hasPressure: false,
        points: const [InkPoint(10, 10)],
      );
      expect(eraserTouches(dot, const Offset(14, 10), 2), isTrue);
      expect(eraserTouches(dot, const Offset(30, 10), 2), isFalse);
    });
  });

  group('eraser (AC-05)', () {
    test('removes only the touched stroke, whole', () {
      line(1, const Offset(0, 0), const Offset(100, 0));
      line(1, const Offset(0, 100), const Offset(100, 100));
      final keep = ink.strokes[1];

      ink.eraserDown(5, const Offset(50, 2), radius: 10);
      ink.eraserUp(5);

      expect(ink.strokes, [keep]);
    });

    test('fast eraser movement does not skip a thin stroke in between', () {
      line(1, const Offset(50, 0), const Offset(50, 200)); // vertical
      ink.eraserDown(5, const Offset(0, 100), radius: 8);
      ink.eraserMove(5, const Offset(200, 100)); // jumps across it
      ink.eraserUp(5);
      expect(ink.strokes, isEmpty);
    });

    test('one erase gesture is one undo step and restores order', () {
      line(1, const Offset(0, 0), const Offset(100, 0));
      line(1, const Offset(0, 50), const Offset(100, 50));
      line(1, const Offset(0, 100), const Offset(100, 100));
      final before = ink.strokes.map((s) => s.id).toList();

      ink.eraserDown(5, const Offset(10, -20), radius: 6);
      ink.eraserMove(5, const Offset(10, 120)); // crosses all three
      ink.eraserUp(5);
      expect(ink.strokes, isEmpty);

      ink.undo();
      expect(ink.strokes.map((s) => s.id), before);
      ink.redo();
      expect(ink.strokes, isEmpty);
    });

    test('erasing nothing adds no undo step', () {
      line(1, const Offset(0, 0), const Offset(100, 0));
      ink.undo();
      ink.redo();
      ink.eraserDown(5, const Offset(500, 500), radius: 6);
      ink.eraserUp(5);
      ink.undo();
      expect(ink.strokes, isEmpty, reason: 'undo removed the stroke itself');
    });

    test('two eraser fingers at once form a single undo step', () {
      line(1, const Offset(0, 0), const Offset(100, 0));
      line(1, const Offset(0, 100), const Offset(100, 100));
      ink.eraserDown(5, const Offset(50, 0), radius: 6);
      ink.eraserDown(6, const Offset(50, 100), radius: 6);
      ink.eraserUp(5);
      ink.eraserUp(6);
      expect(ink.strokes, isEmpty);
      ink.undo();
      expect(ink.strokes, hasLength(2));
    });

    test('cancelled eraser still closes its undo step', () {
      line(1, const Offset(0, 0), const Offset(100, 0));
      ink.eraserDown(5, const Offset(50, 0), radius: 6);
      ink.pointerCancel(5);
      expect(ink.isWriting, isFalse);
      ink.undo();
      expect(ink.strokes, hasLength(1));
    });
  });

  group('CanvasView (REQ-04)', () {
    test(
      'AC-20 screen and canvas coordinates round-trip after pan and zoom',
      () {
        final view = CanvasView();
        view.panBy(const Offset(100, 50));
        view.zoomAt(const Offset(400, 300), 2);
        const p = Offset(123, 456);
        final back = view.toCanvas(view.toScreen(p));
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
        view.dispose();
      },
    );

    test('zoom keeps the point under the fingers fixed', () {
      final view = CanvasView();
      const focal = Offset(300, 200);
      final before = view.toCanvas(focal);
      view.zoomAt(focal, 1.7);
      final after = view.toCanvas(focal);
      expect((after - before).distance, lessThan(1e-9));
      view.dispose();
    });

    test('AC-21 zoom stops at the limits without error', () {
      final view = CanvasView();
      for (var i = 0; i < 50; i++) {
        view.zoomAt(Offset.zero, 2);
      }
      expect(view.scale, CanvasView.maxScale);
      for (var i = 0; i < 50; i++) {
        view.zoomAt(Offset.zero, 0.5);
      }
      expect(view.scale, CanvasView.minScale);
      view.dispose();
    });

    test('pen width looks the same on screen when zoomed in', () {
      ink.setWidth(PenWidths.thick);
      ink.pointerDown(1, Offset.zero, widthScale: 2);
      ink.pointerUp(1);
      expect(ink.strokes.single.width, PenWidths.thick / 2);
    });
  });

  test('NF-04 default title uses WIB', () {
    // 2026-10-14 20:05 UTC is 15 Oct 03.05 WIB.
    expect(
      defaultBoardTitle(DateTime.utc(2026, 10, 14, 20, 5)),
      'Papan 15 Okt 2026 03.05',
    );
  });
}
