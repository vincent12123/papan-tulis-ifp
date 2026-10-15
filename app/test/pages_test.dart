import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';

import 'support/app_harness.dart';

void main() {
  group('Halaman (REQ-05, TSK-06)', () {
    testWidgets('AC-22 ＋ adds an empty page in 1 tap and opens it', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.tap(find.byTooltip('Halaman baru'));
      await tester.pump();
      expect(find.text('Hlm 2/2'), findsOneWidget);
      expect(find.text('Halaman 2 ditambahkan.'), findsOneWidget);
      expect(inkOf(tester).strokes, isEmpty);
      expect(repo.boards.values.single.pages, hasLength(2));

      await tester.tap(find.byTooltip('Halaman sebelumnya'));
      await tester.pump();
      expect(find.text('Hlm 1/2'), findsOneWidget);
      expect(inkOf(tester).strokes, hasLength(1));
    });

    testWidgets('writing right after ＋ (same frame) lands on the new page', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      await tester.tap(find.byTooltip('Halaman baru'));
      // No pump: the touch arrives before the screen rebuilds.
      final g = await tester.startGesture(const Offset(900, 500));
      await g.moveBy(const Offset(60, 0));
      await g.up();
      await tester.pump();
      final pages = repo.boards.values.single.pages;
      expect(pages[0].strokes, isEmpty);
      expect(pages[1].strokes, hasLength(1));
    });

    testWidgets('AC-27 each page remembers its pan/zoom', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Geser'));
      await tester.pump();
      await drag(tester, const Offset(900, 500), const Offset(-150, 0));
      CanvasViewSnapshot view() {
        final v = tester.widget<InkCanvas>(find.byType(InkCanvas)).viewport!;
        return (v.offset.dx, v.scale);
      }

      final page1 = view();
      await tester.tap(find.byTooltip('Halaman baru'));
      await tester.pump();
      expect(view(), (0.0, 1.0));
      await tester.tap(find.byTooltip('Halaman sebelumnya'));
      await tester.pump();
      expect(view(), page1);
    });

    testWidgets('SCR-03 duplicate, then delete with confirmation', (
      tester,
    ) async {
      final repo = await pumpApp(tester);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.tap(find.text('Hlm 1/1'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman'), findsOneWidget);

      await tester.tap(find.text('Duplikat'));
      await tester.pump();
      expect(find.text('Halaman 1 diduplikat.'), findsOneWidget);
      expect(find.text('Hlm 2/2'), findsOneWidget);
      expect(inkOf(tester).strokes, hasLength(1), reason: 'copy has the ink');
      final pages = repo.boards.values.single.pages;
      expect(pages[1].strokes.keys, isNot(pages[0].strokes.keys));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Hapus'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus halaman 2?'), findsOneWidget);
      expect(
        find.text('Tulisan dan gambar di halaman ini ikut terhapus.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await tester.pumpAndSettle();
      expect(find.text('Hlm 1/1'), findsOneWidget);
      expect(repo.boards.values.single.pages, hasLength(1));
    });

    testWidgets('AC-25 the only page cannot be deleted', (tester) async {
      final repo = await pumpApp(tester);
      await tester.tap(find.text('Hlm 1/1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hapus'));
      await tester.pumpAndSettle();
      expect(
        find.text('Papan harus punya minimal satu halaman.'),
        findsOneWidget,
      );
      expect(find.text('Hapus halaman 1?'), findsNothing);
      expect(repo.boards.values.single.pages, hasLength(1));
    });

    testWidgets('tapping a thumbnail opens that page', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Halaman baru'));
      await tester.pump();
      await tester.tap(find.text('Hlm 2/2'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Halaman 1'));
      await tester.pump();
      expect(find.text('Hlm 1/2'), findsOneWidget);
    });
  });
}
