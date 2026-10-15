import 'dart:typed_data';

import 'package:whiteboard_ifp/canvas/media_images.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/app_database.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';

class MemPage {
  MemPage(this.id);
  final String id;
  final Map<String, PageItem> strokes = {};
  PageBackground? background;
  double x = 0, y = 0, zoom = 1;
}

class MemBoard {
  MemBoard(this.id, this.title, this.created);
  final String id;
  String title;
  final DateTime created;
  late DateTime updated = created;
  int lastPage = 1;
  final List<MemPage> pages = [];
  Uint8List? thumbnail;
}

/// In-memory stand-in for [BoardRepository] so widget tests run without
/// SQLite. Mirrors the real repository's behavior that screens rely on.
class MemoryBoardRepository implements BoardRepository {
  MemoryBoardRepository({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.utc(2026, 10, 14, 4));

  final DateTime Function() _clock;
  final Map<String, MemBoard> boards = {};
  final Set<String> damaged = {};
  String? _last;
  int _id = 0;

  /// When set, every write throws this.
  Object? failWrites;
  int writes = 0;

  Future<void> _w() async {
    writes++;
    final f = failWrites;
    if (f != null) throw f;
  }

  @override
  AppDatabase get db => throw UnsupportedError('memory');

  @override
  String newId() => 'id-${_id++}';

  @override
  Future<String?> lastBoardId() async => _last;

  @override
  Future<void> setLastBoardId(String id) async => _last = id;

  final Map<String, String> state = {};

  @override
  Future<String?> appState(String key) async => state[key];

  @override
  Future<void> setAppState(String key, String? value) async {
    if (value == null) {
      state.remove(key);
    } else {
      state[key] = value;
    }
  }

  @override
  Future<BoardRecord> createBoard(String title) async {
    await _w();
    final b = MemBoard(newId(), title, _clock())..pages.add(MemPage(newId()));
    boards[b.id] = b;
    _last = b.id;
    return _record(b);
  }

  BoardRecord _record(MemBoard b) => BoardRecord(
    id: b.id,
    title: b.title,
    createdAt: b.created,
    updatedAt: b.updated,
    lastPage: b.lastPage.clamp(1, b.pages.length),
    pages: [
      for (var i = 0; i < b.pages.length; i++)
        PageRecord(
          id: b.pages[i].id,
          position: i + 1,
          viewX: b.pages[i].x,
          viewY: b.pages[i].y,
          viewZoom: b.pages[i].zoom,
          background: b.pages[i].background,
          items: b.pages[i].strokes.values.toList()
            ..sort((a, c) => a.z.compareTo(c.z)),
        ),
    ],
  );

  @override
  Future<List<BoardSummary>> listBoards() async {
    final list = boards.values.toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return [
      for (final b in list)
        BoardSummary(
          id: b.id,
          title: b.title,
          updatedAt: b.updated,
          pageCount: b.pages.length,
          thumbnail: b.thumbnail,
        ),
    ];
  }

  @override
  Future<bool> boardExists(String id) async => boards.containsKey(id);

  @override
  Future<BoardRecord> loadBoard(String id) async {
    final b = boards[id]!;
    if (damaged.contains(id)) {
      throw BoardCorruptException(
        id,
        b.title,
        DateTime.utc(2026, 10, 14, 3, 45),
      );
    }
    return _record(b);
  }

  @override
  Future<void> renameBoard(String id, String title) async {
    if (title.trim().isEmpty) throw ArgumentError('kosong');
    await _w();
    boards[id]!.title = title.trim();
  }

  @override
  Future<void> deleteBoard(String id) async {
    await _w();
    boards.remove(id);
  }

  @override
  Future<void> touchBoard(String id, {int? lastPage}) async {
    await _w();
    final b = boards[id];
    if (b == null) return;
    b.updated = _clock();
    if (lastPage != null) b.lastPage = lastPage;
  }

  @override
  Future<void> saveThumbnail(String id, Uint8List png) async {
    await _w();
    boards[id]?.thumbnail = png;
  }

  MemPage _page(String id) =>
      boards.values.expand((b) => b.pages).firstWhere((p) => p.id == id);

  MemBoard _boardOfPage(String id) =>
      boards.values.firstWhere((b) => b.pages.any((p) => p.id == id));

  void _order(MemBoard b, List<String> ids) {
    final byId = {for (final p in b.pages) p.id: p};
    b.pages
      ..clear()
      ..addAll([for (final id in ids) byId[id]!]);
  }

  @override
  Future<void> addPage(
    String boardId,
    String pageId,
    List<String> orderedIds, {
    PageBackground? background,
  }) async {
    await _w();
    final b = boards[boardId]!
      ..pages.add(MemPage(pageId)..background = background);
    _order(b, orderedIds);
  }

  @override
  Future<void> duplicatePage({
    required String boardId,
    required String sourceId,
    required String newPageId,
    required List<PageItem> copies,
    required List<String> orderedIds,
  }) async {
    await _w();
    final page = MemPage(newPageId);
    for (final s in copies) {
      page.strokes[s.id] = s;
    }
    final b = boards[boardId]!..pages.add(page);
    _order(b, orderedIds);
  }

  @override
  Future<void> deletePage(String pageId, List<String> orderedIds) async {
    await _w();
    final b = _boardOfPage(pageId);
    b.pages.removeWhere((p) => p.id == pageId);
    _order(b, orderedIds);
  }

  @override
  Future<void> reorderPages(List<String> orderedIds) async {
    await _w();
    _order(_boardOfPage(orderedIds.first), orderedIds);
  }

  @override
  Future<void> saveView(String pageId, double x, double y, double zoom) async {
    await _w();
    final p = _page(pageId)
      ..x = x
      ..y = y
      ..zoom = zoom;
    p.toString();
  }

  @override
  Future<void> setBackground(String pageId, PageBackground? background) async {
    await _w();
    _page(pageId).background = background;
  }

  @override
  Future<void> addItems(String pageId, List<PageItem> items) async {
    await _w();
    final p = _page(pageId);
    for (final i in items) {
      p.strokes[i.id] = i;
    }
  }

  @override
  Future<Set<String>> referencedMedia() async => {
    for (final p in boards.values.expand((b) => b.pages)) ...[
      ?p.background?.file,
      for (final i in p.strokes.values) ...mediaOf(i),
    ],
  };

  @override
  Future<void> addStrokes(String pageId, List<Stroke> strokes) async {
    await _w();
    final p = _page(pageId);
    for (final s in strokes) {
      p.strokes[s.id] = s;
    }
  }

  @override
  Future<void> removeObjects(List<String> ids) async {
    await _w();
    for (final p in boards.values.expand((b) => b.pages)) {
      ids.forEach(p.strokes.remove);
    }
  }

  @override
  Future<DateTime?> snapshotTakenAt(String boardId) async => null;

  int snapshots = 0;

  @override
  Future<void> saveSnapshot(String boardId) async {
    await _w();
    snapshots++;
  }

  @override
  Future<void> restoreSnapshot(String boardId) async => damaged.remove(boardId);
}
