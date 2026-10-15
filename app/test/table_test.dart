import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/table/table_data.dart';
import 'package:whiteboard_ifp/table/table_editor.dart';
import 'package:whiteboard_ifp/table/table_painter.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/memory_repository.dart';

/// Tabel → grafik (REQ-21, AC-180–AC-186).
Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

Future<TableItem> _insertTable(WidgetTester tester, {int fewerRows = 0}) async {
  await tester.tap(find.text('Tabel'));
  await tester.pumpAndSettle();
  for (var i = 0; i < fewerRows; i++) {
    await tester.tap(find.byTooltip('Kurangi Baris'));
    await tester.pump();
  }
  await tester.tap(find.text(TableSizeDialog.insert));
  await tester.pumpAndSettle();
  return inkOf(tester).items.whereType<TableItem>().single;
}

Future<void> _tapCell(
  WidgetTester tester,
  TableItem t,
  int row,
  int col,
) async {
  await tester.tapAt(_screen(tester, TableLayout(t).cell(row, col).center));
  await tester.pumpAndSettle();
}

/// Fills a table through the editor dialog, opened from cell (1, 1).
Future<void> _fill(
  WidgetTester tester,
  TableItem t,
  List<List<String>> cells,
) async {
  await _tapCell(tester, t, 1, 1);
  for (var r = 0; r < cells.length; r++) {
    for (var c = 0; c < cells[r].length; c++) {
      await tester.enterText(find.byKey(ValueKey('sel-$r-$c')), cells[r][c]);
    }
  }
  await tester.tap(find.text(TableEditor.save));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, PageItem item) async {
  await tester.tap(find.text('Pilih'));
  await tester.pump();
  await tester.tapAt(_screen(tester, item.bounds.center));
  await tester.pumpAndSettle();
}

Future<void> _chart(WidgetTester tester, String kind) async {
  await tester.tap(find.text('Jadikan grafik'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(kind));
  await tester.pumpAndSettle();
}

const _scores = [
  ['Minggu', 'Kelas A', 'Kelas B'],
  ['1', '72', '68'],
  ['2', '78,5', '74'],
  ['3', '85', '82'],
];

void main() {
  tearDown(Notices.hide);

  group('reading cells', () {
    test('comma and dot decimals are numbers; text and empty are not', () {
      expect(parseCell('12,5'), 12.5);
      expect(parseCell(' 12.5 '), 12.5);
      expect(parseCell('-3'), -3);
      expect(parseCell(''), isNull);
      expect(parseCell('abc'), isNull);
      expect(parseCell('1,2,3'), isNull);
      expect(parseCell('Infinity'), isNull);
      expect(parseCell('NaN'), isNull);
    });

    test('column 0 text allows only Batang; numbers allow all kinds', () {
      expect(TableData(_scores).allowedKinds, ChartKind.values);
      final named = TableData([
        ['Kelas', 'Nilai'],
        ['X-A', '80'],
        ['X-B', '75'],
      ]);
      expect(named.numericX, isFalse);
      expect(named.allowedKinds, [ChartKind.batang]);
      expect(TableData(TableItem.blank(3, 2)).hasNumbers, isFalse);
    });

    test('only typed text that is not a number is marked', () {
      final cells = [
        ['x', 'y'],
        ['1', 'tujuh'],
        ['2', ''],
      ];
      expect(isBadCell(cells, 1, 1), isTrue);
      expect(isBadCell(cells, 2, 1), isFalse, reason: 'empty is skipped');
      expect(isBadCell(cells, 0, 1), isFalse, reason: 'title row');
    });

    test('axes get round steps', () {
      final a = niceAxis(68, 85);
      expect(a.min <= 68 && a.max >= 85, isTrue);
      expect([1, 2, 2.5, 5, 10].contains(a.step / 1), isTrue);
      expect(axisLabel(2.5, 0.5), '2,5');
    });
  });

  group('AC-186 saved data', () {
    test('tables and charts are saved and read back; damage is refused', () {
      final table = TableItem(
        id: 't',
        rect: const Rect.fromLTWH(10, 20, 600, 256),
        cells: _scores,
      );
      final back =
          ItemCodec.decode(
                kind: ObjectKind.of(table),
                id: 't',
                z: 3,
                data: ItemCodec.encode(table),
              )!
              as TableItem;
      expect(back.cells, _scores);
      expect(back.rect, table.rect);
      final chart = ChartItem(
        id: 'g',
        rect: const Rect.fromLTWH(700, 20, 600, 400),
        kind: ChartKind.titik,
        tableId: 't',
        cells: _scores,
      );
      expect(ObjectKind.of(chart), ObjectKind.graph);
      final c =
          ItemCodec.decode(
                kind: ObjectKind.graph,
                id: 'g',
                z: 4,
                data: ItemCodec.encode(chart),
              )!
              as ChartItem;
      expect((c.kind, c.tableId), (ChartKind.titik, 't'));
      expect(c.cells, _scores);
      for (final bad in [
        '{"v":1,"x":0,"y":0,"w":1,"h":1,"sel":[["a","b"]]}', // one row
        '{"v":1,"x":0,"y":0,"w":1,"h":1,"sel":[["a","b"],["c"]]}', // ragged
        '{"v":1,"x":0,"y":0,"w":1,"h":1,"sel":[["a",1],["c","d"]]}',
        '{"v":1,"sel":[["a","b"],["c","d"]]}',
      ]) {
        expect(
          () => ItemCodec.decode(
            kind: ObjectKind.table,
            id: 'x',
            z: 0,
            data: bad,
          ),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(
        () => ItemCodec.decode(
          kind: ObjectKind.graph,
          id: 'x',
          z: 0,
          data:
              '{"v":1,"jenis":"pai","tabel":"t","x":0,"y":0,"w":1,"h":1,'
              '"sel":[["a","b"],["c","d"]]}',
        ),
        throwsFormatException,
      );
    });

    test('editing a table updates its charts in one undo step', () {
      final ink = InkController();
      addTearDown(ink.dispose);
      final table = TableItem(
        id: 't',
        rect: const Rect.fromLTWH(0, 0, 400, 200),
        cells: _scores,
      );
      ink.addItem(table);
      ink.addItem(
        ChartItem(
          id: 'g',
          rect: const Rect.fromLTWH(500, 0, 400, 300),
          kind: ChartKind.garis,
          tableId: 't',
          cells: _scores,
        ),
      );
      final edited = [
        for (final r in _scores) [...r],
      ]..[1][1] = '90';
      ink.updateTable('t', edited);
      ChartItem chart() => ink.items.whereType<ChartItem>().single;
      expect(chart().cells[1][1], '90');
      ink.undo();
      expect(chart().cells[1][1], '72');
      expect(ink.items.whereType<TableItem>().single.cells[1][1], '72');
    });
  });

  testWidgets('AC-180 Tabel inserts an empty table; Undo removes it', (
    tester,
  ) async {
    final repo = await pumpApp(tester);
    final t = await _insertTable(tester, fewerRows: 1);
    expect((t.rows, t.cols), (4, 3));
    expect(t.cells.expand((r) => r).every((c) => c.isEmpty), isTrue);
    expect(find.text(BoardScreen.tablePlaced), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
      repo.boards.values.single.pages.single.strokes.values
          .whereType<TableItem>(),
      hasLength(1),
      reason: 'saved with the board',
    );
    inkOf(tester).undo();
    await tester.pump();
    expect(inkOf(tester).items.whereType<TableItem>(), isEmpty);
  });

  testWidgets('AC-181 a tap on a cell types into it, without ink', (
    tester,
  ) async {
    await pumpApp(tester);
    final t = await _insertTable(tester);
    await _tapCell(tester, t, 2, 1);
    expect(find.text(TableEditor.title), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sel-2-1')), '12,5');
    await tester.tap(find.text(TableEditor.save));
    await tester.pumpAndSettle();
    final ink = inkOf(tester);
    final after = ink.items.whereType<TableItem>().single;
    expect(after.cells[2][1], '12,5');
    expect(parseCell(after.cells[2][1]), 12.5);
    expect(ink.items.whereType<Stroke>(), isEmpty, reason: 'no ink on it');
    ink.undo();
    await tester.pump();
    expect(ink.items.whereType<TableItem>().single.cells[2][1], '');

    // Batal keeps the table as it was.
    await _tapCell(tester, t, 1, 0);
    await tester.enterText(find.byKey(const ValueKey('sel-1-0')), 'x');
    await tester.tap(find.text(TableEditor.cancel));
    await tester.pumpAndSettle();
    expect(ink.items.whereType<TableItem>().single.cells[1][0], '');

    // Geser pans; it does not open the editor.
    await tester.tap(find.text('Geser'));
    await tester.pump();
    await _tapCell(tester, t, 1, 1);
    expect(find.text(TableEditor.title), findsNothing);
  });

  testWidgets('AC-182 rows and columns stop at 20 × 6', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Tabel'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Kurangi Baris'));
      await tester.pump();
    }
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.remove).first,
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'cannot go below 2 rows',
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Tambah Kolom'));
      await tester.pump();
    }
    await tester.tap(find.text(TableSizeDialog.insert));
    await tester.pumpAndSettle();
    final ink = inkOf(tester);
    var t = ink.items.whereType<TableItem>().single;
    expect((t.rows, t.cols), (2, 6));

    await _select(tester, t);
    await tester.tap(find.text('Tambah kolom'));
    await tester.pumpAndSettle();
    expect(find.text(BoardScreen.tableLimit), findsOneWidget);
    expect(ink.items.whereType<TableItem>().single.cols, 6);

    Notices.hide();
    await tester.tap(find.text('Tambah baris'));
    await tester.pumpAndSettle();
    t = ink.items.whereType<TableItem>().single;
    expect(t.rows, 3);
    expect(t.rect.height, closeTo(3 * 64, 0.01), reason: 'grows by a row');
  });

  testWidgets(
    'AC-183/AC-185 Jadikan grafik: kinds, legend data, no server call',
    (tester) async {
      final server = FakeServer();
      await pumpApp(
        tester,
        settingsFor: (_) => MemorySettingsStore(
          const ServerSettings(
            serverUrl: 'https://papan.contoh',
            pin: '482915',
          ),
        ),
        clientFor: server.clientFor,
      );
      final t = await _insertTable(tester, fewerRows: 1);
      await _fill(tester, t, _scores);
      final ink = inkOf(tester);
      await _select(tester, ink.items.whereType<TableItem>().single);
      server.requests.clear();
      await _chart(tester, 'Garis');
      final chart = ink.items.whereType<ChartItem>().single;
      expect(chart.kind, ChartKind.garis);
      expect(chart.tableId, t.id);
      expect(TableData(chart.cells).series.map((s) => s.title), [
        'Kelas A',
        'Kelas B',
      ]);
      expect(chart.rect.overlaps(t.rect), isFalse, reason: 'beside it');
      expect(find.text(BoardScreen.chartPlaced), findsOneWidget);
      expect(server.requests, isEmpty, reason: 'made on the panel');
    },
  );

  testWidgets('AC-183 text in column 0 allows only Batang', (tester) async {
    await pumpApp(tester);
    final t = await _insertTable(tester, fewerRows: 2);
    await _fill(tester, t, [
      ['Kelas', 'Nilai', ''],
      ['X-A', '80', ''],
      ['X-B', '75', ''],
    ]);
    await _select(tester, inkOf(tester).items.whereType<TableItem>().single);
    await tester.tap(find.text('Jadikan grafik'));
    await tester.pumpAndSettle();
    expect(find.text(BoardScreen.chartNeedsNumbers), findsOneWidget);
    expect(
      tester
          .widget<MenuItemButton>(
            find.ancestor(
              of: find.text('Garis'),
              matching: find.byType(MenuItemButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Batang'));
    await tester.pumpAndSettle();
    expect(
      inkOf(tester).items.whereType<ChartItem>().single.kind,
      ChartKind.batang,
    );
  });

  testWidgets('AC-184 the chart follows the table; empty table refused', (
    tester,
  ) async {
    await pumpApp(tester);
    var t = await _insertTable(tester, fewerRows: 1);
    final ink = inkOf(tester);
    await _select(tester, t);
    await tester.tap(find.text('Jadikan grafik'));
    await tester.pumpAndSettle();
    expect(find.text(BoardScreen.tableNoNumbers), findsOneWidget);
    expect(find.text('Titik'), findsNothing, reason: 'no menu without numbers');
    expect(ink.items.whereType<ChartItem>(), isEmpty);
    Notices.hide();

    await tester.tap(find.text('Pena'));
    await tester.pump();
    await _fill(tester, t, _scores);
    t = ink.items.whereType<TableItem>().single;
    await _select(tester, t);
    await _chart(tester, 'Titik');
    await tester.tap(find.text('Pena'));
    await tester.pump();
    await _tapCell(tester, t, 3, 2);
    await tester.enterText(find.byKey(const ValueKey('sel-3-2')), 'banyak');
    await tester.tap(find.text(TableEditor.save));
    await tester.pumpAndSettle();
    final chart = ink.items.whereType<ChartItem>().single;
    expect(chart.cells[3][2], 'banyak', reason: 'linked: follows the table');
    expect(TableData(chart.cells).series[1].values[2], isNull);
    expect(isBadCell(chart.cells, 3, 2), isTrue, reason: 'marked in the cell');
  });

  testWidgets(
    'AC-186 reopened intact and linked; deleted table → chart stays',
    (tester) async {
      final repo = MemoryBoardRepository();
      await pumpApp(tester, repo: repo);
      final t = await _insertTable(tester, fewerRows: 1);
      await _fill(tester, t, _scores);
      await _select(tester, inkOf(tester).items.whereType<TableItem>().single);
      await _chart(tester, 'Batang');
      await tester.pump(const Duration(seconds: 2));

      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, repo: repo);
      final ink = inkOf(tester);
      final table = ink.items.whereType<TableItem>().single;
      expect(table.cells, _scores);
      expect(ink.items.whereType<ChartItem>().single.tableId, table.id);
      expect(ink.hasTable(table.id), isTrue);

      // Penghapus does not erase the table.
      await tester.tap(find.text('Penghapus'));
      await tester.pump();
      await drag(
        tester,
        _screen(tester, table.rect.center),
        const Offset(80, 0),
      );
      expect(ink.items.whereType<TableItem>(), hasLength(1));

      await _select(tester, table);
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(ink.items.whereType<TableItem>(), isEmpty);
      final chart = ink.items.whereType<ChartItem>().single;
      expect(chart.cells, _scores, reason: 'keeps the last data');
      expect(ink.hasTable(chart.tableId), isFalse, reason: 'no longer linked');
    },
  );
}
