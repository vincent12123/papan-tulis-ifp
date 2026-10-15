import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/app_database.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

Stroke stroke(String id, {int z = 1, bool pressure = false}) => Stroke(
  id: id,
  color: PenColors.red,
  width: 6,
  hasPressure: pressure,
  z: z,
  points: const [InkPoint(1.234, 5.678, 0.3), InkPoint(10, 20, 0.8)],
);

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AppDatabase db;
  late BoardRepository repo;
  var now = DateTime.utc(2026, 10, 14, 4);

  Future<AppDatabase> open() => AppDatabase.open(
    factory: databaseFactoryFfi,
    mainPath: p.join(dir.path, 'papan.db'),
    snapshotPath: p.join(dir.path, 'salinan.db'),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papan_test');
    db = await open();
    repo = BoardRepository(db, clock: () => now);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('StrokeCodec', () {
    test('round-trips points, color, width, and pressure', () {
      final s = stroke('a', z: 7, pressure: true);
      final back = StrokeCodec.decode(
        id: 'a',
        z: 7,
        data: StrokeCodec.encode(s),
      );
      expect(back.color, PenColors.red);
      expect(back.width, 6);
      expect(back.hasPressure, isTrue);
      expect(back.z, 7);
      expect(back.points.first.x, closeTo(1.23, 0.001));
      expect(back.points.last.pressure, closeTo(0.8, 0.001));
    });

    for (final bad in [
      'not json',
      '{}',
      '{"v":1,"c":1,"w":2,"p":false,"pts":[1]}',
      '[]',
    ]) {
      test('rejects damaged data: $bad', () {
        expect(
          () => StrokeCodec.decode(id: 'x', z: 1, data: bad),
          throwsFormatException,
        );
      });
    }
  });

  test(
    'AC-30 board, pages, and strokes survive closing the database',
    () async {
      final board = await repo.createBoard('Mtk XI');
      final page1 = board.pages.single.id;
      await repo.addStrokes(page1, [stroke('s1', z: 1), stroke('s2', z: 2)]);
      final page2 = repo.newId();
      await repo.addPage(board.id, page2, [page1, page2]);
      await repo.addStrokes(page2, [stroke('s3')]);
      await repo.saveView(page2, 10, 20, 2);
      await repo.touchBoard(board.id, lastPage: 2);

      await db.close();
      db = await open();
      repo = BoardRepository(db, clock: () => now);

      expect(await repo.lastBoardId(), board.id);
      final loaded = await repo.loadBoard(board.id);
      expect(loaded.title, 'Mtk XI');
      expect(loaded.lastPage, 2);
      expect(loaded.pages.map((p) => p.id), [page1, page2]);
      expect(loaded.pages[0].strokes.map((s) => s.id), ['s1', 's2']);
      expect(loaded.pages[1].strokes.single.id, 's3');
      expect(loaded.pages[1].viewZoom, 2);
      expect(loaded.pages[1].viewX, 10);
    },
  );

  test('strokes load in stacking order (z)', () async {
    final board = await repo.createBoard('Z');
    final page = board.pages.single.id;
    await repo.addStrokes(page, [stroke('top', z: 9), stroke('bottom', z: 2)]);
    final loaded = await repo.loadBoard(board.id);
    expect(loaded.pages.single.strokes.map((s) => s.id), ['bottom', 'top']);
  });

  test('removed objects are gone after reload', () async {
    final board = await repo.createBoard('Hapus');
    final page = board.pages.single.id;
    await repo.addStrokes(page, [stroke('a'), stroke('b', z: 2)]);
    await repo.removeObjects(['a']);
    final loaded = await repo.loadBoard(board.id);
    expect(loaded.pages.single.strokes.map((s) => s.id), ['b']);
  });

  test(
    'AC-23 duplicate page copies objects under new ids right after source',
    () async {
      final board = await repo.createBoard('Dup');
      final page1 = board.pages.single.id;
      await repo.addStrokes(page1, [stroke('orig')]);
      final page2 = repo.newId();
      final copy = stroke('copy-id');
      await repo.duplicatePage(
        boardId: board.id,
        sourceId: page1,
        newPageId: page2,
        copies: [copy],
        orderedIds: [page1, page2],
      );
      final loaded = await repo.loadBoard(board.id);
      expect(loaded.pages.map((p) => p.id), [page1, page2]);
      expect(loaded.pages[1].strokes.single.id, 'copy-id');
      expect(loaded.pages[0].strokes.single.id, 'orig');
    },
  );

  test('AC-24 reorder and delete pages keep positions 1..n', () async {
    final board = await repo.createBoard('Urut');
    final a = board.pages.single.id;
    final b = repo.newId();
    final c = repo.newId();
    await repo.addPage(board.id, b, [a, b]);
    await repo.addPage(board.id, c, [a, b, c]);
    await repo.reorderPages([c, a, b]);
    var loaded = await repo.loadBoard(board.id);
    expect(loaded.pages.map((p) => p.id), [c, a, b]);
    expect(loaded.pages.map((p) => p.position), [1, 2, 3]);

    await repo.addStrokes(a, [stroke('on-a')]);
    await repo.deletePage(a, [c, b]);
    loaded = await repo.loadBoard(board.id);
    expect(loaded.pages.map((p) => p.id), [c, b]);
    expect(loaded.pages.map((p) => p.position), [1, 2]);
  });

  test('AC-32 rename rejects an empty title', () async {
    final board = await repo.createBoard('Lama');
    expect(() => repo.renameBoard(board.id, '   '), throwsArgumentError);
    await repo.renameBoard(board.id, '  Basis Data  ');
    expect((await repo.loadBoard(board.id)).title, 'Basis Data');
  });

  test('AC-33 deleting a board removes its pages, objects, and copy', () async {
    final board = await repo.createBoard('Buang');
    await repo.addStrokes(board.pages.single.id, [stroke('x')]);
    await repo.saveSnapshot(board.id);
    await repo.deleteBoard(board.id);
    expect(await repo.boardExists(board.id), isFalse);
    expect(await repo.snapshotTakenAt(board.id), isNull);
    final orphans = await db.main.query('objects');
    expect(orphans, isEmpty);
  });

  test('list shows newest first with page counts and thumbnails', () async {
    final old = await repo.createBoard('Lama');
    now = now.add(const Duration(hours: 1));
    final fresh = await repo.createBoard('Baru');
    await repo.addPage(fresh.id, repo.newId(), [fresh.pages.single.id]);
    await repo.saveThumbnail(old.id, Uint8List.fromList([1, 2, 3]));

    final list = await repo.listBoards();
    expect(list.map((b) => b.title), ['Baru', 'Lama']);
    expect(list.first.pageCount, 2);
    expect(list.last.thumbnail, [1, 2, 3]);
  });

  test('AC-34 damaged board is detected and restored from the copy', () async {
    final board = await repo.createBoard('Rusak');
    final page = board.pages.single.id;
    await repo.addStrokes(page, [stroke('good')]);
    now = DateTime.utc(2026, 10, 14, 5, 15);
    await repo.saveSnapshot(board.id);

    // Damage the stored stroke after the copy was taken.
    await db.main.update('objects', {'data': '{broken'});

    await expectLater(
      repo.loadBoard(board.id),
      throwsA(
        isA<BoardCorruptException>()
            .having((e) => e.title, 'title', 'Rusak')
            .having((e) => e.snapshotTakenAt, 'taken', now),
      ),
    );

    await repo.restoreSnapshot(board.id);
    final loaded = await repo.loadBoard(board.id);
    expect(loaded.pages.single.strokes.single.id, 'good');
  });

  test('damaged board without a copy reports no copy time', () async {
    final board = await repo.createBoard('Tanpa salinan');
    await repo.addStrokes(board.pages.single.id, [stroke('a')]);
    await db.main.update('objects', {'data': 'x'});
    await expectLater(
      repo.loadBoard(board.id),
      throwsA(
        isA<BoardCorruptException>().having(
          (e) => e.snapshotTakenAt,
          'taken',
          isNull,
        ),
      ),
    );
  });

  test('AC-35 schema carries a version for future migrations', () async {
    expect(await db.main.getVersion(), AppDatabase.mainVersion);
  });
}
