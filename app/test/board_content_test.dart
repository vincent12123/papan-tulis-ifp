import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_document.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/media_import.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/ui/notices.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/media_fakes.dart';
import 'support/memory_repository.dart';

class _Setup {
  _Setup(this.doc, this.files, this.pdf);
  final BoardDocument doc;
  final FakeFileSource files;
  final FakePdfRasterizer pdf;
}

/// SCR-01 with a real document on in-memory storage and fake file access.
Future<_Setup> _pumpBoard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryBoardRepository();
  final store = MemoryMediaStore();
  final doc = await BoardDocument.create(
    repo,
    'Konten',
    media: store,
    snapshotInterval: Duration.zero,
  );
  final files = FakeFileSource();
  final pdf = FakePdfRasterizer();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: BoardScreen(
        doc: doc,
        onHome: () {},
        importer: MediaImporter(doc: doc, store: store, files: files, pdf: pdf),
      ),
    ),
  );
  addTearDown(() async {
    Notices.hide();
    await tester.pumpWidget(const SizedBox());
    doc.dispose();
  });
  return _Setup(doc, files, pdf);
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from);
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 6)!);
  }
  await g.up();
  await tester.pump();
}

/// Runs a tap whose handler does real async work (decoding pictures) and
/// waits until [done] holds (or ~3 s pass).
Future<void> _tapAndWait(
  WidgetTester tester,
  Finder finder, {
  bool Function()? done,
}) async {
  await tester.tap(finder);
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (done == null ? i >= 3 : done()) break;
  }
  await tester.pump();
}

Offset _canvasTopLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(InkCanvas));

void main() {
  testWidgets('TSK-01 a shape takes 2 taps: Bentuk, Persegi, then drag', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    await tester.tap(find.text('Persegi'));
    await tester.pump();
    expect(find.text('Persegi'), findsNothing, reason: 'menu closed');
    await _drag(tester, const Offset(700, 300), const Offset(900, 450));
    final shape = s.doc.page.ink.items.single as ShapeItem;
    expect(shape.type, ShapeType.persegi);
  });

  testWidgets('a menu item still works when the finger stays down a while', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    // A real finger: down, a frame passes, then up.
    final g = await tester.startGesture(
      tester.getCenter(find.text('Lingkaran')),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await g.up();
    await tester.pump();
    await _drag(tester, const Offset(700, 300), const Offset(850, 420));
    expect(
      (s.doc.page.ink.items.single as ShapeItem).type,
      ShapeType.lingkaran,
    );

    await tester.tap(find.byTooltip('Warna'));
    await tester.pump();
    final c = await tester.startGesture(tester.getCenter(find.text('Merah')));
    await tester.pump(const Duration(milliseconds: 80));
    await c.up();
    await tester.pump();
    expect(s.doc.page.ink.color, PenColors.red);
  });

  testWidgets('P-07 Otomatis tidies a drawn circle into a shape', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    await tester.tap(find.text('Otomatis'));
    await tester.pump();
    final g = await tester.startGesture(const Offset(1000, 400));
    for (var i = 1; i <= 60; i++) {
      await g.moveTo(
        Offset(900 + 100 * cos(i * pi / 30), 400 + 100 * sin(i * pi / 30)),
      );
    }
    await g.up();
    await tester.pump();
    final shape = s.doc.page.ink.items.single as ShapeItem;
    expect(shape.type, ShapeType.lingkaran);
  });

  testWidgets('AC-40 Pilih: tap selects, drag moves, Hapus deletes', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    final ink = s.doc.page.ink;
    final origin = _canvasTopLeft(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    await tester.tap(find.text('Garis'));
    await tester.pump();
    await _drag(
      tester,
      origin + const Offset(400, 300),
      origin + const Offset(600, 300),
    );

    await tester.tap(find.text('Pilih'));
    await tester.pump();
    expect(find.text('Hapus'), findsNothing);
    await _drag(
      tester,
      origin + const Offset(500, 300),
      origin + const Offset(500, 400),
    );
    final moved = ink.items.single as ShapeItem;
    expect(moved.points.first.dy, closeTo(400, 0.01));
    expect(find.text('Hapus'), findsOneWidget);

    await tester.tap(find.text('Hapus'));
    await tester.pump();
    expect(ink.items, isEmpty);
    // Undo brings it back where it was moved to.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect((ink.items.single as ShapeItem).points.first.dy, closeTo(400, 0.01));
  });

  testWidgets('Pilih: a corner handle resizes', (tester) async {
    final s = await _pumpBoard(tester);
    final ink = s.doc.page.ink;
    final origin = _canvasTopLeft(tester);
    ink.addItem(
      ImageItem(
        id: 'pic',
        file: 'tidak-ada.png',
        rect: const Rect.fromLTWH(400, 300, 200, 100),
      ),
    );
    await tester.tap(find.text('Pilih'));
    await tester.pump();
    await tester.tapAt(origin + const Offset(500, 350));
    await tester.pump();
    // Drag the bottom-right handle; the picture keeps its 2:1 shape.
    await _drag(
      tester,
      origin + const Offset(600, 400),
      origin + const Offset(800, 420),
    );
    expect(ink.items.single.bounds, const Rect.fromLTWH(400, 300, 400, 200));
  });

  testWidgets('REQ-07 Gambar inserts a picture and switches to Pilih', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    s.files.nextImage = PickedFile('foto.png', wideRedPng);
    await _tapAndWait(tester, find.text('Gambar'));
    expect(s.doc.page.ink.items.single, isA<ImageItem>());
    final pilih = tester.getSemantics(find.bySemanticsLabel('Pilih'));
    expect(pilih.flagsCollection.isSelected, Tristate.isTrue);
    expect(find.text('Hapus'), findsOneWidget);
    expect(find.text(BoardScreen.emptyHint), findsNothing);
  });

  testWidgets('AC-41 a broken picture shows its name in the message', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    s.files.nextImage = PickedFile('rusak.jpg', Uint8List.fromList([0, 1, 2]));
    await _tapAndWait(tester, find.text('Gambar'));
    expect(find.text(BoardScreen.imageRejected('rusak.jpg')), findsOneWidget);
    expect(s.doc.page.ink.items, isEmpty);
  });

  testWidgets('TSK-04 Pasang latar from the page panel, then Lepas latar', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    s.files.nextBackground = PickedFile('peta.png', tallBluePng);
    await tester.tap(find.text('Hlm 1/1')); // 1
    await tester.pump();
    await _tapAndWait(tester, find.text('Pasang latar')); // 2 (+ pick file)
    expect(find.text('Latar terpasang di halaman 1.'), findsOneWidget);
    expect(s.doc.page.background, isNotNull);
    expect(find.text(BoardScreen.emptyHint), findsNothing);

    await tester.tap(find.text('Lepas latar'));
    await tester.pump();
    expect(find.text('Latar halaman 1 dilepas.'), findsOneWidget);
    expect(s.doc.page.background, isNull);
    expect(find.text('Pasang latar'), findsOneWidget);
  });

  testWidgets('P-13 a long PDF tells the teacher only 5 pages were used', (
    tester,
  ) async {
    final s = await _pumpBoard(tester);
    s.pdf.total = 8;
    s.files.nextBackground = PickedFile('modul.pdf', Uint8List(4));
    await tester.tap(find.text('Hlm 1/1'));
    await tester.pump();
    await _tapAndWait(
      tester,
      find.text('Pasang latar'),
      done: () => s.doc.pages.length == 5,
    );
    expect(
      find.text(
        'Latar terpasang di halaman 1 sampai 5. '
        '${BoardScreen.pdfTruncated('modul.pdf', 8)}',
      ),
      findsOneWidget,
    );
    expect(find.text('Hlm 1/5'), findsOneWidget);
  });

  testWidgets('AC-45 a locked PDF is refused with its name', (tester) async {
    final s = await _pumpBoard(tester);
    s.pdf.locked = true;
    s.files.nextBackground = PickedFile('ujian.pdf', Uint8List(4));
    await tester.tap(find.text('Hlm 1/1'));
    await tester.pump();
    await _tapAndWait(tester, find.text('Pasang latar'));
    expect(find.text(BoardScreen.pdfLocked('ujian.pdf')), findsOneWidget);
  });

  testWidgets('NF-06 new tools are at least 64 dp and labelled', (
    tester,
  ) async {
    await _pumpBoard(tester);
    for (final label in ['Pilih', 'Bentuk', 'Gambar']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(AppSizes.primaryTarget));
    }
  });
}
