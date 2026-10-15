import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_document.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/memory_repository.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('AC-09 three fingers on the canvas write three strokes', (
    tester,
  ) async {
    final ink = InkController();
    await tester.pumpWidget(MaterialApp(home: InkCanvas(controller: ink)));
    final fingers = <TestGesture>[];
    for (var i = 0; i < 3; i++) {
      fingers.add(
        await tester.startGesture(Offset(100, 100 + i * 100.0), pointer: i + 1),
      );
    }
    for (var step = 1; step <= 5; step++) {
      for (final f in fingers) {
        await f.moveBy(const Offset(20, 0));
      }
      await tester.pump();
    }
    for (final f in fingers) {
      await f.up();
    }
    await tester.pump();
    expect(ink.strokes, hasLength(3));
    // Unmount before disposing so painters stop listening first.
    await tester.pumpWidget(const SizedBox());
    ink.dispose();
  });

  group('SCR-01 Papan', () {
    testWidgets('UX-01 first start creates a board with Pena active', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      expect(repo.boards, hasLength(1));
      expect(find.text('Papan 14 Okt 2026 11.30'), findsOneWidget);
      expect(find.text('Hlm 1/1'), findsOneWidget);
      final pena = tester.getSemantics(find.bySemanticsLabel('Pena'));
      expect(pena.flagsCollection.isSelected, Tristate.isTrue);

      expect(find.text(BoardScreen.emptyHint), findsOneWidget);
      await drag(tester, const Offset(900, 500), const Offset(100, 40));
      expect(inkOf(tester).strokes, hasLength(1));
      expect(find.text(BoardScreen.emptyHint), findsNothing);
    });

    testWidgets('AC-31 a finished stroke is saved and shows Tersimpan', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.pump();
      expect(strokesStored(repo), 1);
      expect(find.byTooltip('Tersimpan'), findsOneWidget);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(strokesStored(repo), 0, reason: 'undo is saved too');
    });

    testWidgets('AC-30 / P-10 reopening opens the last board as it was', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.tap(find.byTooltip('Halaman baru'));
      await tester.pump();
      await drag(tester, const Offset(700, 400), const Offset(50, 50));
      await tester.pump();

      // Restart the app on the same storage.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, repo: repo);

      expect(repo.boards, hasLength(1));
      expect(find.text('Hlm 2/2'), findsOneWidget);
      expect(inkOf(tester).strokes, hasLength(1));
      await tester.tap(find.byTooltip('Halaman sebelumnya'));
      await tester.pump();
      expect(inkOf(tester).strokes, hasLength(1));
    });

    testWidgets('AC-07 undo/redo buttons follow history', (tester) async {
      await pumpApp(tester);
      IconButton button(IconData icon) =>
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));
      expect(button(Icons.undo).onPressed, isNull);
      expect(button(Icons.redo).onPressed, isNull);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      expect(button(Icons.undo).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(inkOf(tester).strokes, isEmpty);
      expect(button(Icons.redo).onPressed, isNotNull);
    });

    testWidgets('TSK-01 change color in 2 taps; menu closes, pen active', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Penghapus'));
      await tester.pump();
      await tester.tap(find.byTooltip('Warna'));
      await tester.pump();
      await tester.tap(find.text('Merah'));
      await tester.pump();
      expect(find.text('Merah'), findsNothing);
      await drag(tester, const Offset(900, 400), const Offset(100, 0));
      expect(inkOf(tester).strokes.single.color, PenColors.red);
    });

    testWidgets('TSK-01 change width in 2 taps', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Ketebalan'));
      await tester.pump();
      await tester.tap(find.text('Tebal'));
      await tester.pump();
      await drag(tester, const Offset(900, 400), const Offset(100, 0));
      expect(inkOf(tester).strokes.single.width, PenWidths.thick);
    });

    testWidgets('AC-05 Penghapus removes the touched stroke', (tester) async {
      await pumpApp(tester);
      await drag(tester, const Offset(700, 300), const Offset(300, 0));
      await drag(tester, const Offset(700, 500), const Offset(300, 0));
      final ink = inkOf(tester);
      final keep = ink.strokes[1];
      await tester.tap(find.text('Penghapus'));
      await tester.pump();
      await drag(tester, const Offset(850, 280), const Offset(0, 40));
      expect(ink.strokes, [keep]);
    });

    testWidgets('P-02 Geser pans without writing; pen writes in place', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Geser'));
      await tester.pump();
      await drag(tester, const Offset(900, 500), const Offset(-200, -100));
      expect(inkOf(tester).strokes, isEmpty);
      await tester.tap(find.text('Pena'));
      await tester.pump();
      await drag(tester, const Offset(900, 500), const Offset(10, 0));
      final topLeft = tester.getTopLeft(find.byType(InkCanvas));
      final first = inkOf(tester).strokes.single.points.first;
      expect(first.x, closeTo(900 - topLeft.dx + 200, 0.01));
      expect(first.y, closeTo(500 - topLeft.dy + 100, 0.01));
    });

    testWidgets('P-02 two fingers in Pena mode write, not zoom', (
      tester,
    ) async {
      await pumpApp(tester);
      final a = await tester.startGesture(const Offset(800, 400), pointer: 1);
      final b = await tester.startGesture(const Offset(1000, 400), pointer: 2);
      for (var i = 0; i < 5; i++) {
        await a.moveBy(const Offset(-20, 0));
        await b.moveBy(const Offset(20, 0));
      }
      await a.up();
      await b.up();
      await tester.pump();
      expect(inkOf(tester).strokes, hasLength(2));
    });

    testWidgets('Geser with two fingers zooms', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Geser'));
      await tester.pump();
      final a = await tester.startGesture(const Offset(800, 400), pointer: 1);
      final b = await tester.startGesture(const Offset(1000, 400), pointer: 2);
      for (var i = 0; i < 5; i++) {
        await a.moveBy(const Offset(-20, 0));
        await b.moveBy(const Offset(20, 0));
      }
      await a.up();
      await b.up();
      await tester.pump();
      final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
      expect(canvas.viewport!.scale, closeTo(2, 0.01));
    });

    testWidgets('A11Y-05 toolbar moves to the right, left, and back', (
      tester,
    ) async {
      await pumpApp(tester);
      double x() => tester.getCenter(find.text('Pena')).dx;
      final center = x();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      final right = x();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      final left = x();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      expect(right, greaterThan(center));
      expect(left, lessThan(center));
      expect(x(), closeTo(center, 0.5));
    });

    testWidgets('NF-06 tools are at least 64 dp with labels', (tester) async {
      await pumpApp(tester);
      for (final label in [
        'Pena',
        'Penghapus',
        'Geser',
        'Warna',
        'Ketebalan',
      ]) {
        final size = tester.getSize(
          find.descendant(
            of: find.byTooltip(label),
            matching: find.byType(InkWell),
          ),
        );
        expect(size.width, greaterThanOrEqualTo(AppSizes.primaryTarget));
        expect(size.height, greaterThanOrEqualTo(AppSizes.primaryTarget));
      }
      for (final tip in ['Undo', 'Redo', 'Halaman baru']) {
        expect(
          tester.getSize(find.byTooltip(tip)).height,
          greaterThanOrEqualTo(AppSizes.target),
        );
      }
    });

    testWidgets('REQ-18 storage full keeps the ink and tells the teacher', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      repo.failWrites = const StorageFullException();
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.pump();
      expect(inkOf(tester).strokes, hasLength(1));
      expect(find.text('Belum tersimpan'), findsOneWidget);
      expect(find.text(BoardScreen.storageFullText), findsOneWidget);
    });
  });

  testWidgets('AC-34 damaged board offers the automatic copy', (tester) async {
    final repo = MemoryBoardRepository();
    final board = await repo.createBoard('Rusak');
    repo.damaged.add(board.id);
    await pumpApp(tester, repo: repo);
    expect(
      find.text(
        'Papan Rusak tidak bisa dibuka karena berkasnya rusak. '
        'Salinan otomatis terakhir pukul 10.45 masih ada.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Pulihkan salinan'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardScreen), findsOneWidget);
    expect(find.text('Rusak'), findsOneWidget);
  });

  testWidgets('damaged board: Buat papan baru opens a fresh board', (
    tester,
  ) async {
    final repo = MemoryBoardRepository();
    final board = await repo.createBoard('Rusak');
    repo.damaged.add(board.id);
    await pumpApp(tester, repo: repo);
    await tester.tap(find.text('Buat papan baru'));
    await tester.pumpAndSettle();
    expect(repo.boards, hasLength(2));
    expect(find.byType(BoardScreen), findsOneWidget);
  });

  testWidgets('diagnostics are hidden in normal builds', (tester) async {
    await pumpApp(tester);
    expect(find.text('Info panel'), findsNothing);
  });

  testWidgets('diagnostics build shows the device report', (tester) async {
    panelSize(tester);
    final repo = MemoryBoardRepository();
    final doc = await BoardDocument.create(repo, 'Uji');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BoardScreen(
          doc: doc,
          onHome: () {},
          diagnostics: true,
          collectReport: fakeReport,
        ),
      ),
    );
    await tester.tap(find.text('Info panel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hisense Uji'), findsOneWidget);
    expect(
      find.textContaining('Google Play Services: tidak ada'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    doc.dispose();
  });
}
