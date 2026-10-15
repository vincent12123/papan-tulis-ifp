import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../canvas/media_images.dart';
import '../canvas/stroke.dart';
import 'app_database.dart';
import 'stroke_codec.dart';

class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.pageCount,
    this.thumbnail,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final int pageCount;
  final Uint8List? thumbnail;
}

class PageRecord {
  PageRecord({
    required this.id,
    required this.position,
    required this.items,
    this.background,
    this.viewX = 0,
    this.viewY = 0,
    this.viewZoom = 1,
  });

  final String id;
  int position;
  final PageBackground? background;
  final double viewX;
  final double viewY;
  final double viewZoom;
  final List<PageItem> items;

  List<Stroke> get strokes => items.whereType<Stroke>().toList();
}

class BoardRecord {
  BoardRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.lastPage,
    required this.pages,
  });

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  int lastPage;
  final List<PageRecord> pages;
}

/// The board's data could not be read (SPEC 5.3: berkas papan rusak).
class BoardCorruptException implements Exception {
  BoardCorruptException(this.boardId, this.title, this.snapshotTakenAt);

  final String boardId;
  final String title;

  /// When the last automatic copy was taken; null if there is none.
  final DateTime? snapshotTakenAt;

  @override
  String toString() => 'BoardCorruptException($boardId)';
}

/// The panel's storage is full (SPEC 5.3).
class StorageFullException implements Exception {
  const StorageFullException();
}

/// All reads and writes of boards on the panel (REQ-06).
class BoardRepository {
  BoardRepository(this.db, {DateTime Function()? clock, IdGenerator? ids})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      _ids = ids ?? IdGenerator();

  final AppDatabase db;
  final DateTime Function() _clock;
  final IdGenerator _ids;

  Database get _main => db.main;

  String newId() => _ids.next();
  String _now() => _clock().toUtc().toIso8601String();

  /// Runs a write and turns "disk full" into [StorageFullException].
  Future<T> _write<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DatabaseException catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('full') || text.contains('sqlite_full')) {
        throw const StorageFullException();
      }
      rethrow;
    }
  }

  // --- app state -----------------------------------------------------------

  Future<String?> lastBoardId() async {
    final rows = await _main.query(
      'app_state',
      where: 'key = ?',
      whereArgs: ['last_board'],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setLastBoardId(String id) => _write(
    () => _main.insert('app_state', {
      'key': 'last_board',
      'value': id,
    }, conflictAlgorithm: ConflictAlgorithm.replace),
  );

  /// A small app setting (server address, AI choice). Never secrets.
  Future<String?> appState(String key) async {
    final rows = await _main.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Stores [value]; null removes the setting.
  Future<void> setAppState(String key, String? value) => _write(() async {
    if (value == null) {
      await _main.delete('app_state', where: 'key = ?', whereArgs: [key]);
    } else {
      await _main.insert('app_state', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  // --- boards --------------------------------------------------------------

  /// Creates a board with one empty page and makes it the last board.
  Future<BoardRecord> createBoard(String title) => _write(() async {
    final now = _clock().toUtc();
    final board = BoardRecord(
      id: newId(),
      title: title,
      createdAt: now,
      updatedAt: now,
      lastPage: 1,
      pages: [PageRecord(id: newId(), position: 1, items: [])],
    );
    await _main.transaction((txn) async {
      await txn.insert('boards', {
        'id': board.id,
        'title': title,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'last_page': 1,
      });
      await txn.insert('pages', {
        'id': board.pages.single.id,
        'board_id': board.id,
        'position': 1,
      });
      await txn.insert('app_state', {
        'key': 'last_board',
        'value': board.id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return board;
  });

  /// Newest first.
  Future<List<BoardSummary>> listBoards() async {
    final rows = await _main.rawQuery('''
      SELECT b.id, b.title, b.updated_at, b.thumbnail,
             (SELECT COUNT(*) FROM pages p WHERE p.board_id = b.id) AS page_count
      FROM boards b
      ORDER BY b.updated_at DESC''');
    return [
      for (final r in rows)
        BoardSummary(
          id: r['id'] as String,
          title: r['title'] as String,
          updatedAt: DateTime.parse(r['updated_at'] as String),
          pageCount: r['page_count'] as int,
          thumbnail: r['thumbnail'] as Uint8List?,
        ),
    ];
  }

  Future<bool> boardExists(String id) async {
    final rows = await _main.query(
      'boards',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty;
  }

  /// Loads a full board. Throws [BoardCorruptException] when any of its data
  /// cannot be read.
  Future<BoardRecord> loadBoard(String id) async {
    final List<Map<String, Object?>> boardRows;
    try {
      boardRows = await _main.query('boards', where: 'id = ?', whereArgs: [id]);
    } on DatabaseException {
      throw BoardCorruptException(id, '', await snapshotTakenAt(id));
    }
    if (boardRows.isEmpty) throw StateError('Papan $id tidak ada');
    final b = boardRows.first;
    final title = b['title'] as String;
    try {
      final pageRows = await _main.query(
        'pages',
        where: 'board_id = ?',
        whereArgs: [id],
        orderBy: 'position',
      );
      if (pageRows.isEmpty) throw const FormatException('tanpa halaman');
      final pages = <PageRecord>[];
      for (final p in pageRows) {
        final pageId = p['id'] as String;
        final objectRows = await _main.query(
          'objects',
          where: 'page_id = ?',
          whereArgs: [pageId],
          orderBy: 'z',
        );
        final rawBackground = p['background'] as String?;
        PageBackground? background;
        if (rawBackground != null) {
          background = PageBackground.fromJson(jsonDecode(rawBackground));
          if (background == null) {
            throw FormatException('Latar halaman $pageId rusak');
          }
        }
        pages.add(
          PageRecord(
            id: pageId,
            position: p['position'] as int,
            background: background,
            viewX: (p['view_x'] as num).toDouble(),
            viewY: (p['view_y'] as num).toDouble(),
            viewZoom: (p['view_zoom'] as num).toDouble(),
            items: [
              for (final o in objectRows)
                ?ItemCodec.decode(
                  kind: o['kind'] as String,
                  id: o['id'] as String,
                  z: o['z'] as int,
                  data: o['data'] as String,
                ),
            ],
          ),
        );
      }
      return BoardRecord(
        id: id,
        title: title,
        createdAt: DateTime.parse(b['created_at'] as String),
        updatedAt: DateTime.parse(b['updated_at'] as String),
        lastPage: (b['last_page'] as int).clamp(1, pages.length),
        pages: pages,
      );
    } on FormatException {
      throw BoardCorruptException(id, title, await snapshotTakenAt(id));
    } on DatabaseException {
      throw BoardCorruptException(id, title, await snapshotTakenAt(id));
    } on TypeError {
      throw BoardCorruptException(id, title, await snapshotTakenAt(id));
    }
  }

  Future<void> renameBoard(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Nama papan tidak boleh kosong.',
      );
    }
    return _write(
      () => _main.update(
        'boards',
        {'title': trimmed, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      ),
    );
  }

  Future<void> deleteBoard(String id) => _write(() async {
    await _main.delete('boards', where: 'id = ?', whereArgs: [id]);
    await db.snapshots.delete(
      'snapshots',
      where: 'board_id = ?',
      whereArgs: [id],
    );
  });

  Future<void> touchBoard(String id, {int? lastPage}) => _write(
    () => _main.update(
      'boards',
      {'updated_at': _now(), 'last_page': ?lastPage},
      where: 'id = ?',
      whereArgs: [id],
    ),
  );

  Future<void> saveThumbnail(String id, Uint8List png) => _write(
    () => _main.update(
      'boards',
      {'thumbnail': png},
      where: 'id = ?',
      whereArgs: [id],
    ),
  );

  // --- pages ---------------------------------------------------------------

  /// Inserts a page (empty, or with a [background] for PDF pages);
  /// [orderedIds] is the full new page order.
  Future<void> addPage(
    String boardId,
    String pageId,
    List<String> orderedIds, {
    PageBackground? background,
  }) => _write(
    () => _main.transaction((txn) async {
      await txn.insert('pages', {
        'id': pageId,
        'board_id': boardId,
        'position': orderedIds.indexOf(pageId) + 1,
        'background': background == null
            ? null
            : jsonEncode(background.toJson()),
      });
      await _setPositions(txn, orderedIds);
    }),
  );

  /// Copies a page and its objects under new ids.
  Future<void> duplicatePage({
    required String boardId,
    required String sourceId,
    required String newPageId,
    required List<PageItem> copies,
    required List<String> orderedIds,
  }) => _write(
    () => _main.transaction((txn) async {
      final src = await txn.query(
        'pages',
        where: 'id = ?',
        whereArgs: [sourceId],
      );
      final s = src.first;
      await txn.insert('pages', {
        'id': newPageId,
        'board_id': boardId,
        'position': orderedIds.indexOf(newPageId) + 1,
        'background': s['background'],
        'view_x': s['view_x'],
        'view_y': s['view_y'],
        'view_zoom': s['view_zoom'],
      });
      final batch = txn.batch();
      for (final item in copies) {
        batch.insert('objects', _itemRow(newPageId, item));
      }
      await batch.commit(noResult: true);
      await _setPositions(txn, orderedIds);
    }),
  );

  Future<void> deletePage(String pageId, List<String> orderedIds) => _write(
    () => _main.transaction((txn) async {
      await txn.delete('pages', where: 'id = ?', whereArgs: [pageId]);
      await _setPositions(txn, orderedIds);
    }),
  );

  Future<void> reorderPages(List<String> orderedIds) =>
      _write(() => _main.transaction((txn) => _setPositions(txn, orderedIds)));

  Future<void> _setPositions(Transaction txn, List<String> orderedIds) async {
    final batch = txn.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(
        'pages',
        {'position': i + 1},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> setBackground(String pageId, PageBackground? background) =>
      _write(
        () => _main.update(
          'pages',
          {
            'background': background == null
                ? null
                : jsonEncode(background.toJson()),
          },
          where: 'id = ?',
          whereArgs: [pageId],
        ),
      );

  Future<void> saveView(String pageId, double x, double y, double zoom) =>
      _write(
        () => _main.update(
          'pages',
          {'view_x': x, 'view_y': y, 'view_zoom': zoom},
          where: 'id = ?',
          whereArgs: [pageId],
        ),
      );

  // --- objects -------------------------------------------------------------

  /// Inserts items, or replaces them when they already exist (an item
  /// moved or resized keeps its id).
  Future<void> addItems(String pageId, List<PageItem> items) =>
      _write(() async {
        final batch = _main.batch();
        for (final item in items) {
          batch.insert(
            'objects',
            _itemRow(pageId, item),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

  Future<void> addStrokes(String pageId, List<Stroke> strokes) =>
      addItems(pageId, strokes);

  Future<void> removeObjects(List<String> ids) => _write(() async {
    final batch = _main.batch();
    for (final id in ids) {
      batch.delete('objects', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  });

  Map<String, Object?> _itemRow(String pageId, PageItem item) => {
    'id': item.id,
    'page_id': pageId,
    'kind': ObjectKind.of(item),
    'data': ItemCodec.encode(item),
    'z': item.z,
  };

  /// Media files still used by any board or automatic copy, so unused
  /// pictures can be deleted from storage.
  Future<Set<String>> referencedMedia() async {
    final names = <String>{};
    void addObject(Object? kind, Object? data) {
      if (kind != ObjectKind.image || data is! String) return;
      try {
        final file = (jsonDecode(data) as Map)['file'];
        if (file is String) names.add(file);
      } catch (_) {}
    }

    void addBackground(Object? raw) {
      if (raw is! String) return;
      try {
        final bg = PageBackground.fromJson(jsonDecode(raw));
        if (bg != null) names.add(bg.file);
      } catch (_) {}
    }

    for (final o in await _main.query('objects', columns: ['kind', 'data'])) {
      addObject(o['kind'], o['data']);
    }
    for (final p in await _main.query('pages', columns: ['background'])) {
      addBackground(p['background']);
    }
    for (final row in await db.snapshots.query('snapshots')) {
      try {
        final data = jsonDecode(row['data'] as String) as Map;
        for (final o in data['objects'] as List) {
          addObject((o as Map)['kind'], o['data']);
        }
        for (final p in data['pages'] as List) {
          addBackground((p as Map)['background']);
        }
      } catch (_) {}
    }
    return names;
  }

  // --- automatic copy (snapshot) -------------------------------------------

  Future<DateTime?> snapshotTakenAt(String boardId) async {
    try {
      final rows = await db.snapshots.query(
        'snapshots',
        columns: ['taken_at'],
        where: 'board_id = ?',
        whereArgs: [boardId],
      );
      return rows.isEmpty
          ? null
          : DateTime.parse(rows.first['taken_at'] as String);
    } on DatabaseException {
      return null;
    }
  }

  /// Copies the board's rows, as stored, into the snapshot database. Only
  /// called after the board loaded successfully, so the copy is readable.
  Future<void> saveSnapshot(String boardId) => _write(() async {
    final board = await _main.query(
      'boards',
      columns: ['id', 'title', 'created_at', 'updated_at', 'last_page'],
      where: 'id = ?',
      whereArgs: [boardId],
    );
    if (board.isEmpty) return;
    final pages = await _main.query(
      'pages',
      where: 'board_id = ?',
      whereArgs: [boardId],
    );
    final objects = await _main.rawQuery(
      'SELECT o.* FROM objects o JOIN pages p ON p.id = o.page_id '
      'WHERE p.board_id = ?',
      [boardId],
    );
    await db.snapshots.insert('snapshots', {
      'board_id': boardId,
      'taken_at': _now(),
      'data': jsonEncode({
        'board': board.first,
        'pages': pages,
        'objects': objects,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  /// Replaces the board's rows with the last automatic copy.
  Future<void> restoreSnapshot(String boardId) => _write(() async {
    final rows = await db.snapshots.query(
      'snapshots',
      where: 'board_id = ?',
      whereArgs: [boardId],
    );
    if (rows.isEmpty) throw StateError('Tidak ada salinan untuk $boardId');
    final data =
        jsonDecode(rows.first['data'] as String) as Map<String, Object?>;
    await _main.transaction((txn) async {
      await txn.delete('boards', where: 'id = ?', whereArgs: [boardId]);
      await txn.insert(
        'boards',
        Map<String, Object?>.from(data['board'] as Map),
      );
      for (final p in data['pages'] as List) {
        await txn.insert('pages', Map<String, Object?>.from(p as Map));
      }
      final batch = txn.batch();
      for (final o in data['objects'] as List) {
        batch.insert('objects', Map<String, Object?>.from(o as Map));
      }
      await batch.commit(noResult: true);
    });
  });
}
