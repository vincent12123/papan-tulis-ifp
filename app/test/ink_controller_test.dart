import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/canvas/ink_painters.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

void main() {
  late InkController ink;

  setUp(() => ink = InkController());
  tearDown(() => ink.dispose());

  void drawLine(int pointer, Offset from, Offset to, {int steps = 10}) {
    ink.pointerDown(pointer, from);
    for (var i = 1; i <= steps; i++) {
      ink.pointerMove(pointer, Offset.lerp(from, to, i / steps)!);
    }
    ink.pointerUp(pointer);
  }

  test('AC-01 one finger stroke keeps all points, color and width', () {
    ink.setColor(PenColors.blue);
    ink.setWidth(PenWidths.thick);
    drawLine(1, const Offset(0, 0), const Offset(100, 0));

    expect(ink.strokes, hasLength(1));
    final stroke = ink.strokes.single;
    expect(stroke.points, hasLength(11));
    expect(stroke.points.last.x, 100);
    expect(stroke.color, PenColors.blue);
    expect(stroke.width, PenWidths.thick);
    expect(stroke.hasPressure, isFalse);
  });

  test('AC-04 changing pen affects only new strokes', () {
    drawLine(1, const Offset(0, 0), const Offset(50, 50));
    ink.setColor(PenColors.red);
    ink.setWidth(PenWidths.thin);
    drawLine(1, const Offset(0, 100), const Offset(50, 150));

    expect(ink.strokes[0].color, PenColors.black);
    expect(ink.strokes[0].width, PenWidths.medium);
    expect(ink.strokes[1].color, PenColors.red);
    expect(ink.strokes[1].width, PenWidths.thin);
  });

  test('AC-06 undo twice then redo once leaves two strokes in order', () {
    drawLine(1, const Offset(0, 0), const Offset(10, 0));
    drawLine(1, const Offset(0, 10), const Offset(10, 10));
    drawLine(1, const Offset(0, 20), const Offset(10, 20));
    final ids = ink.strokes.map((s) => s.id).toList();

    ink.undo();
    ink.undo();
    ink.redo();

    expect(ink.strokes.map((s) => s.id), [ids[0], ids[1]]);
    expect(ink.canRedo, isTrue);
  });

  test('AC-07 a new page cannot undo or redo', () {
    expect(ink.canUndo, isFalse);
    expect(ink.canRedo, isFalse);
    ink.undo();
    ink.redo();
    expect(ink.strokes, isEmpty);
  });

  test('AC-08 a new stroke after undo clears redo history', () {
    drawLine(1, const Offset(0, 0), const Offset(10, 0));
    ink.undo();
    expect(ink.canRedo, isTrue);
    drawLine(1, const Offset(0, 10), const Offset(10, 10));
    expect(ink.canRedo, isFalse);
  });

  test('AC-09 three simultaneous fingers make three separate strokes', () {
    ink.pointerDown(1, const Offset(0, 0));
    ink.pointerDown(2, const Offset(0, 100));
    ink.pointerDown(3, const Offset(0, 200));
    for (var i = 1; i <= 5; i++) {
      ink.pointerMove(1, Offset(i * 10, 0));
      ink.pointerMove(2, Offset(i * 10, 100));
      ink.pointerMove(3, Offset(i * 10, 200));
    }
    expect(ink.activeStrokes, hasLength(3));
    ink.pointerUp(2);
    ink.pointerUp(1);
    ink.pointerUp(3);

    expect(ink.strokes, hasLength(3));
    for (final stroke in ink.strokes) {
      expect(stroke.points, hasLength(6));
      // Each stroke stays on its own row: fingers never join.
      expect(stroke.points.map((p) => p.y).toSet(), hasLength(1));
    }
    expect(ink.maxSimultaneousPointers, 3);
  });

  test('AC-11 a tap is stored as a dot', () {
    ink.pointerDown(1, const Offset(5, 5));
    ink.pointerUp(1);
    expect(ink.strokes.single.isDot, isTrue);
  });

  test('cancelled pointer (palm rejection) leaves no ink', () {
    ink.pointerDown(1, const Offset(0, 0));
    ink.pointerMove(1, const Offset(20, 20));
    ink.pointerCancel(1);
    expect(ink.strokes, isEmpty);
    expect(ink.isWriting, isFalse);
  });

  test('events for unknown pointers are ignored', () {
    ink.pointerMove(9, const Offset(1, 1));
    ink.pointerUp(9);
    expect(ink.strokes, isEmpty);
  });

  test('sub-pixel jitter is not stored', () {
    ink.pointerDown(1, const Offset(10, 10));
    ink.pointerMove(1, const Offset(10.2, 10.1));
    ink.pointerUp(1);
    expect(ink.strokes.single.points, hasLength(1));
  });

  test('stylus pressure is kept and marks the stroke', () {
    ink.pointerDown(1, const Offset(0, 0), pressure: 0.2, isStylus: true);
    ink.pointerMove(1, const Offset(10, 0), pressure: 0.9);
    ink.pointerUp(1);
    final stroke = ink.strokes.single;
    expect(stroke.hasPressure, isTrue);
    expect(stroke.points.map((p) => p.pressure), [0.2, 0.9]);
    expect(ink.stylusSeen, isTrue);
  });

  test(
    'load test fills exactly the requested number of strokes inside the area',
    () {
      ink.addLoadTestStrokes(3000, const Size(1920, 1080));
      expect(ink.strokes, hasLength(3000));
      for (final s in ink.strokes) {
        for (final p in s.points) {
          expect(p.x, inInclusiveRange(0, 1920));
          expect(p.y, inInclusiveRange(0, 1080));
        }
      }
    },
  );

  test(
    'the picture cache redraws items the controller adds or swaps in place',
    () {
      final cache = InkPictureCache(chunkSize: 2);
      expect(cache.chunksFor(ink.committedItems), isEmpty);
      drawLine(1, const Offset(0, 0), const Offset(50, 0));
      expect(cache.chunksFor(ink.committedItems), hasLength(1));
      drawLine(2, const Offset(0, 10), const Offset(50, 10));
      drawLine(3, const Offset(0, 20), const Offset(50, 20));
      expect(cache.chunksFor(ink.committedItems), hasLength(2));
      final first = cache.chunksFor(ink.committedItems).first;
      ink.addItem(
        TableItem(
          id: 't',
          rect: const Rect.fromLTWH(0, 40, 100, 40),
          cells: TableItem.blank(2, 2),
        ),
      );
      final last = cache.chunksFor(ink.committedItems).last;
      ink.updateTable('t', [
        ['x', 'y'],
        ['1', '2'],
      ]);
      final chunks = cache.chunksFor(ink.committedItems);
      expect(chunks.first, same(first), reason: 'unchanged chunk kept');
      expect(chunks.last, isNot(same(last)), reason: 'edited table redrawn');
    },
  );
}
