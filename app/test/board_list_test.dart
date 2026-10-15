import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/boards/board_list_screen.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/memory_repository.dart';

import 'support/app_harness.dart';

void main() {
  group('SCR-02 Daftar Papan (REQ-06, TSK-07)', () {
    testWidgets('Beranda opens the list; Kembali ke papan returns', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      expect(find.text('Papan saya'), findsOneWidget);
      expect(find.textContaining('1 hlm'), findsOneWidget);
      await tester.tap(find.text('Kembali ke papan'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
    });

    testWidgets('Papan baru creates and opens a new board', (tester) async {
      final repo = await pumpApp(tester);
      await drag(tester, const Offset(900, 500), const Offset(100, 0));
      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Papan baru'));
      await tester.pumpAndSettle();
      expect(repo.boards, hasLength(2));
      expect(inkOf(tester).strokes, isEmpty);
    });

    testWidgets('open another board in 2 taps from the board (TSK-07)', (
      tester,
    ) async {
      final repo = MemoryBoardRepository();
      final other = await repo.createBoard('Basis Data');
      await repo.createBoard('Mtk XI');
      await pumpApp(tester, repo: repo);
      expect(find.text('Mtk XI'), findsOneWidget);
      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Basis Data'));
      await tester.pumpAndSettle();
      expect(find.text('Basis Data'), findsOneWidget);
      expect(await repo.lastBoardId(), other.id);
    });

    testWidgets('AC-32 rename validates and updates the open board title', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ganti nama Papan 14 Okt 2026 11.30'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Simpan'));
      await tester.pump();
      expect(find.text('Nama papan tidak boleh kosong.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Fisika X');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Nama papan diubah.'), findsOneWidget);
      await tester.tap(find.text('Kembali ke papan'));
      await tester.pumpAndSettle();
      expect(find.text('Fisika X'), findsOneWidget);
    });

    testWidgets('AC-33 delete asks with title and page count', (tester) async {
      final repo = MemoryBoardRepository();
      await repo.createBoard('Lama');
      await pumpApp(tester, repo: repo); // opens "Lama"
      await tester.tap(find.byTooltip('Halaman baru'));
      await tester.pump();
      await tester.tap(find.byTooltip('Beranda'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hapus Lama'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus papan Lama?'), findsOneWidget);
      expect(
        find.text(
          'Seluruh 2 halamannya ikut terhapus dan tidak bisa dikembalikan.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await tester.pumpAndSettle();
      expect(find.text('Papan Lama dihapus.'), findsOneWidget);
      expect(find.text(BoardListScreen.emptyText), findsOneWidget);
      // The open board is gone, so there is no way back to it.
      expect(find.text('Kembali ke papan'), findsNothing);
      await tester.tap(find.text('Papan baru'));
      await tester.pumpAndSettle();
      expect(repo.boards, hasLength(1));
      expect(find.byType(BoardScreen), findsOneWidget);
    });

    testWidgets('UX-02 empty list text', (tester) async {
      panelSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: BoardListScreen(repo: MemoryBoardRepository(), currentId: 'x'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(BoardListScreen.emptyText), findsOneWidget);
    });
  });
}
