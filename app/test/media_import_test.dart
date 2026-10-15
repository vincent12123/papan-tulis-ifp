import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whiteboard_ifp/board/board_document.dart';
import 'package:whiteboard_ifp/board/media_import.dart';
import 'package:whiteboard_ifp/canvas/media_images.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/app_database.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';
import 'package:whiteboard_ifp/data/media_store.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/media_fakes.dart';
import 'support/memory_repository.dart';

const visible = Rect.fromLTWH(0, 0, 1000, 600);
const screen = Size(1000, 600);

void main() {
  group('MediaImporter', () {
    late MemoryBoardRepository repo;
    late BoardDocument doc;
    late MemoryMediaStore store;
    late FakeFileSource files;
    late FakePdfRasterizer pdf;
    late MediaImporter importer;

    Future<void> setUpDoc() async {
      repo = MemoryBoardRepository();
      store = MemoryMediaStore();
      doc = await BoardDocument.create(
        repo,
        'Uji',
        media: store,
        snapshotInterval: Duration.zero,
      );
      files = FakeFileSource();
      pdf = FakePdfRasterizer();
      importer = MediaImporter(doc: doc, store: store, files: files, pdf: pdf);
    }

    tearDown(() => doc.dispose());

    testWidgets('AC-40 a picture is placed in the middle at natural size and '
        'selected', (tester) async {
      await setUpDoc();
      files.nextImage = PickedFile('foto.png', wideRedPng);
      final result = await tester.runAsync(() => importer.insertImage(visible));
      expect(result, isA<ImageInserted>());
      final item = doc.page.ink.items.single as ImageItem;
      expect(
        item.rect,
        Rect.fromCenter(center: visible.center, width: 40, height: 20),
      );
      expect(doc.page.ink.selected.value, item.id);
      expect(store.files, hasLength(1));
      await tester.runAsync(doc.queue.flush);
      // Saved to the board.
      final page = repo.boards.values.single.pages.single;
      expect(page.strokes.values.single, isA<ImageItem>());
    });

    testWidgets('a picture larger than the screen is scaled down to fit', (
      tester,
    ) async {
      await setUpDoc();
      files.nextImage = PickedFile('besar.png', wideRedPng);
      await tester.runAsync(
        () => importer.insertImage(const Rect.fromLTWH(0, 0, 50, 50)),
      );
      final item = doc.page.ink.items.single as ImageItem;
      expect(item.rect.width, closeTo(30, 0.01)); // 60% of 50
      expect(item.rect.height, closeTo(15, 0.01));
    });

    testWidgets('AC-41 a file that is not a picture is rejected by name', (
      tester,
    ) async {
      await setUpDoc();
      files.nextImage = PickedFile(
        'tugas.png',
        Uint8List.fromList([1, 2, 3, 4]),
      );
      final result = await tester.runAsync(() => importer.insertImage(visible));
      expect(result, isA<ImportRejected>());
      expect((result! as ImportRejected).name, 'tugas.png');
      expect(doc.page.ink.items, isEmpty);
      expect(store.files, isEmpty);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      await setUpDoc();
      final result = await tester.runAsync(() => importer.insertImage(visible));
      expect(result, isA<ImportCancelled>());
      expect(doc.page.ink.items, isEmpty);
    });

    testWidgets('REQ-09 a picture as background fits the visible area', (
      tester,
    ) async {
      await setUpDoc();
      files.nextBackground = PickedFile('peta.png', tallBluePng);
      final result = await tester.runAsync(
        () => importer.setBackground(visible, screen),
      );
      expect(result, isA<BackgroundSet>());
      final bg = doc.page.background!;
      expect(bg.rect.height, closeTo(600, 0.01));
      expect(bg.rect.width, closeTo(450, 0.01));
      await tester.runAsync(doc.queue.flush);
      expect(repo.boards.values.single.pages.single.background, isNotNull);
    });

    testWidgets('AC-43 a 3-page PDF gives 3 pages with backgrounds in order', (
      tester,
    ) async {
      await setUpDoc();
      pdf.total = 3;
      files.nextBackground = PickedFile('soal.pdf', Uint8List(10));
      final result = await tester.runAsync(
        () => importer.setBackground(visible, screen),
      );
      final set = result! as BackgroundSet;
      expect(set.pageCount, 3);
      expect(set.firstPage, 1);
      expect(set.truncatedFrom, isNull);
      expect(doc.pages, hasLength(3));
      expect(doc.pages.every((p) => p.background != null), isTrue);
      await tester.runAsync(doc.queue.flush);
      expect(repo.boards.values.single.pages, hasLength(3));
      expect(doc.current.value, 0, reason: 'stays on the first PDF page');
    });

    testWidgets('P-13 a 9-page PDF installs only the first 5 pages', (
      tester,
    ) async {
      await setUpDoc();
      pdf.total = 9;
      files.nextBackground = PickedFile('modul.pdf', Uint8List(10));
      final set =
          (await tester.runAsync(
                () => importer.setBackground(visible, screen),
              ))!
              as BackgroundSet;
      expect(pdf.lastMaxPages, 5);
      expect(set.pageCount, 5);
      expect(set.truncatedFrom, 9);
      expect(doc.pages, hasLength(5));
    });

    testWidgets('PDF pages go after the open page, not at the end', (
      tester,
    ) async {
      await setUpDoc();
      doc.addPage(); // page 2, open
      doc.addPage(); // page 3, open
      doc.goTo(1); // back to page 2
      pdf.total = 2;
      files.nextBackground = PickedFile('lks.pdf', Uint8List(10));
      final set =
          (await tester.runAsync(
                () => importer.setBackground(visible, screen),
              ))!
              as BackgroundSet;
      expect(set.firstPage, 2);
      expect(doc.pages[1].background, isNotNull);
      expect(doc.pages[2].background, isNotNull);
      expect(doc.pages[3].background, isNull, reason: 'old page 3 moved down');
    });

    testWidgets('AC-45 a locked PDF is rejected with the locked message', (
      tester,
    ) async {
      await setUpDoc();
      pdf.locked = true;
      files.nextBackground = PickedFile('rahasia.pdf', Uint8List(10));
      final result =
          (await tester.runAsync(
                () => importer.setBackground(visible, screen),
              ))!
              as ImportRejected;
      expect(result.locked, isTrue);
      expect(result.name, 'rahasia.pdf');
      expect(doc.page.background, isNull);
    });

    testWidgets('AC-41 a broken PDF is rejected by name', (tester) async {
      await setUpDoc();
      pdf.broken = true;
      files.nextBackground = PickedFile('rusak.pdf', Uint8List(10));
      final result =
          (await tester.runAsync(
                () => importer.setBackground(visible, screen),
              ))!
              as ImportRejected;
      expect(result.locked, isFalse);
      expect(doc.pages, hasLength(1));
    });
  });

  group('storage of shapes, pictures, and backgrounds', () {
    sqfliteFfiInit();
    late Directory dir;
    late AppDatabase db;
    late BoardRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('papan_media');
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        mainPath: p.join(dir.path, 'papan.db'),
        snapshotPath: p.join(dir.path, 'salinan.db'),
      );
      repo = BoardRepository(db);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test(
      'items and background survive reload; moved items replace rows',
      () async {
        final board = await repo.createBoard('Media');
        final page = board.pages.single.id;
        final shape = ShapeItem(
          id: 'sh',
          type: ShapeType.panah,
          points: const [Offset(0, 0), Offset(50, 50)],
          color: PenColors.red,
          width: 6,
          z: 1,
        );
        final pic = ImageItem(
          id: 'pic',
          file: 'a.png',
          rect: const Rect.fromLTWH(1, 2, 30, 40),
          z: 2,
        );
        await repo.addItems(page, [shape, pic]);
        await repo.addItems(page, [
          pic.withRect(const Rect.fromLTWH(9, 9, 30, 40)),
        ]);
        await repo.setBackground(
          page,
          const PageBackground(
            file: 'bg.png',
            rect: Rect.fromLTWH(0, 0, 800, 600),
          ),
        );
        final loaded = (await repo.loadBoard(board.id)).pages.single;
        expect(loaded.items.map((i) => i.id), ['sh', 'pic']);
        expect((loaded.items[0] as ShapeItem).type, ShapeType.panah);
        expect(loaded.items[1].bounds.left, 9);
        expect(loaded.background!.file, 'bg.png');

        await repo.setBackground(page, null);
        expect(
          (await repo.loadBoard(board.id)).pages.single.background,
          isNull,
        );
      },
    );

    test('a damaged background marks the board as damaged', () async {
      final board = await repo.createBoard('Rusak');
      await db.main.update('pages', {'background': '{"file":1}'});
      await expectLater(
        repo.loadBoard(board.id),
        throwsA(isA<BoardCorruptException>()),
      );
    });

    test(
      'unused media files are deleted, used ones (incl. copies) kept',
      () async {
        final board = await repo.createBoard('GC');
        final page = board.pages.single.id;
        await repo.addItems(page, [
          ImageItem(id: 'p', file: 'dipakai.png', rect: Rect.zero, z: 1),
        ]);
        await repo.setBackground(
          page,
          const PageBackground(file: 'latar.png', rect: Rect.zero),
        );
        await repo.saveSnapshot(board.id);
        await repo.removeObjects(['p']); // only the copy still refers to it

        final store = MediaStore(Directory(p.join(dir.path, 'media')));
        for (final name in ['dipakai.png', 'latar.png', 'sampah.png']) {
          await store.dir.create(recursive: true);
          await store.file(name).writeAsBytes([1]);
        }
        final removed = await store.collectGarbage(
          await repo.referencedMedia(),
        );
        expect(removed, 1);
        expect(await store.file('sampah.png').exists(), isFalse);
        expect(await store.file('dipakai.png').exists(), isTrue);
        expect(await store.file('latar.png').exists(), isTrue);
      },
    );
  });
}
