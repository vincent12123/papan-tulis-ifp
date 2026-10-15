import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../canvas/canvas_view.dart';
import '../canvas/ink_controller.dart';
import '../canvas/media_images.dart';
import '../canvas/stroke.dart';
import '../data/media_store.dart';
import '../data/board_repository.dart';

enum SaveStatus { saved, saving, storageFull, failed }

/// Runs writes one after another and reports the save indicator state
/// (SCR-01 "Menyimpan…" / "Tersimpan"). A failed write never touches the
/// board in memory (REQ-18); the next successful write clears the error.
class SaveQueue {
  final ValueNotifier<SaveStatus> status = ValueNotifier(SaveStatus.saved);
  Future<void> _tail = Future.value();
  int _pending = 0;
  bool _disposed = false;

  /// Writes still finish after the board is closed; only the indicator
  /// stops updating.
  void _set(SaveStatus value) {
    if (!_disposed) status.value = value;
  }

  Future<void> run(Future<void> Function() write) {
    _pending++;
    _set(SaveStatus.saving);
    final next = _tail.then((_) async {
      try {
        await write();
        if (--_pending == 0) _set(SaveStatus.saved);
      } on StorageFullException {
        _pending--;
        _set(SaveStatus.storageFull);
      } catch (_) {
        _pending--;
        _set(SaveStatus.failed);
      }
    });
    _tail = next;
    return next;
  }

  /// Completes when every queued write has finished.
  Future<void> flush() => _tail;

  void dispose() {
    _disposed = true;
    status.dispose();
  }
}

typedef ThumbnailRenderer = Future<Uint8List?> Function(
  List<PageItem> items,
  PageBackground? background,
  MediaImages media,
);

/// One page of the open board: its items, background, pan/zoom, and saving
/// of all three.
class PageState implements InkChangeListener {
  PageState._(
    this.id,
    this._doc,
    List<PageItem> items,
    PageBackground? background,
    this.view,
  ) {
    ink = InkController(initial: items, background: background, listener: this);
    view.revision.addListener(_viewChanged);
  }

  final String id;
  final BoardDocument _doc;
  late final InkController ink;
  final CanvasView view;
  Timer? _viewTimer;

  PageBackground? get background => ink.background.value;

  @override
  void itemsAdded(List<PageItem> items) {
    final copy = List.of(items);
    _doc._changed(() => _doc.repo.addItems(id, copy));
  }

  @override
  void itemsRemoved(List<PageItem> items) {
    final ids = [for (final i in items) i.id];
    _doc._changed(() => _doc.repo.removeObjects(ids));
  }

  @override
  void itemChanged(PageItem item) {
    _doc._changed(() => _doc.repo.addItems(id, [item]));
  }

  /// Pan/zoom is saved shortly after it stops, not on every frame.
  void _viewChanged() {
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(milliseconds: 800), saveView);
  }

  void saveView() {
    _viewTimer?.cancel();
    final o = view.offset, z = view.scale;
    _doc.queue.run(() => _doc.repo.saveView(id, o.dx, o.dy, z));
  }

  void dispose() {
    _viewTimer?.cancel();
    view.revision.removeListener(_viewChanged);
    ink.dispose();
    view.dispose();
  }
}

/// Copy of [item] under a new id (page duplicate).
PageItem _copyItem(PageItem item, String id) => switch (item) {
  Stroke() => Stroke(
    id: id,
    color: item.color,
    width: item.width,
    hasPressure: item.hasPressure,
    z: item.z,
    points: List.of(item.points),
    chalk: item.chalk,
  ),
  ShapeItem() => ShapeItem(
    id: id,
    type: item.type,
    points: List.of(item.points),
    color: item.color,
    width: item.width,
    z: item.z,
  ),
  ImageItem() => ImageItem(id: id, file: item.file, rect: item.rect, z: item.z),
  GraphItem() => item.copyAs(id),
  TextItem() => item.copyAs(id),
  SolidItem() => item.copyAs(id),
  PeragaItem() => item.copyAs(id),
  QuizItem() => item.copyAs(id),
  TableItem() => item.copyAs(id),
  ChartItem() => item.copyAs(id),
};

/// The board that is open on the panel, kept in memory and saved as it
/// changes (REQ-05, REQ-06, NFR-32).
class BoardDocument {
  BoardDocument._(
    this.repo,
    this.record, {
    this.renderThumbnail,
    this.media,
    this.snapshotInterval = defaultSnapshotInterval,
  }) : images = MediaImages(media?.read ?? (_) async => null) {
    for (final p in record.pages) {
      pages.add(
        PageState._(
          p.id,
          this,
          p.items,
          p.background,
          CanvasView(scale: p.viewZoom, offset: Offset(p.viewX, p.viewY)),
        ),
      );
    }
    current.value = record.lastPage - 1;
  }

  final BoardRepository repo;
  final BoardRecord record;
  final ThumbnailRenderer? renderThumbnail;

  /// Where pictures and backgrounds are stored; null in tests.
  final MediaStore? media;

  /// Decoded pictures shared by all pages of this board.
  final MediaImages images;
  final SaveQueue queue = SaveQueue();
  final List<PageState> pages = [];

  /// Index of the open page.
  final ValueNotifier<int> current = ValueNotifier(0);

  /// Bumped when pages are added, removed, reordered, or get a background.
  final ValueNotifier<int> pagesRevision = ValueNotifier(0);

  /// Automatic copy at most this often while editing (SPEC 5.3).
  static const defaultSnapshotInterval = Duration(seconds: 60);

  /// [Duration.zero] turns the timed copy off (tests).
  final Duration snapshotInterval;
  Timer? _snapshotTimer;
  bool _dirtySinceSnapshot = false;

  String get id => record.id;

  /// Board title; updated when renamed from the board list.
  late final ValueNotifier<String> title = ValueNotifier(record.title);
  PageState get page => pages[current.value];

  static Future<BoardDocument> open(
    BoardRepository repo,
    String id, {
    ThumbnailRenderer? renderThumbnail,
    MediaStore? media,
    Duration snapshotInterval = defaultSnapshotInterval,
  }) async {
    final record = await repo.loadBoard(id);
    await repo.setLastBoardId(id);
    final doc = BoardDocument._(
      repo,
      record,
      renderThumbnail: renderThumbnail,
      media: media,
      snapshotInterval: snapshotInterval,
    );
    // The board just loaded fine, so it is a good automatic copy.
    unawaited(doc.queue.run(() => repo.saveSnapshot(id)));
    return doc;
  }

  static Future<BoardDocument> create(
    BoardRepository repo,
    String title, {
    ThumbnailRenderer? renderThumbnail,
    MediaStore? media,
    Duration snapshotInterval = defaultSnapshotInterval,
  }) async {
    final record = await repo.createBoard(title);
    return BoardDocument._(
      repo,
      record,
      renderThumbnail: renderThumbnail,
      media: media,
      snapshotInterval: snapshotInterval,
    );
  }

  void _changed(Future<void> Function() write) {
    queue.run(write);
    queue.run(() => repo.touchBoard(id));
    _dirtySinceSnapshot = true;
    if (snapshotInterval == Duration.zero) return;
    _snapshotTimer ??= Timer(snapshotInterval, () {
      _snapshotTimer = null;
      snapshot();
    });
  }

  List<String> get _order => [for (final p in pages) p.id];

  void goTo(int index) {
    if (index < 0 || index >= pages.length || index == current.value) return;
    pages[current.value].ink.select(null);
    current.value = index;
    queue.run(() => repo.touchBoard(id, lastPage: index + 1));
  }

  /// Adds an empty page right after the open one and opens it. Returns its
  /// 1-based number.
  int addPage() {
    final at = current.value + 1;
    final pageId = repo.newId();
    pages.insert(at, PageState._(pageId, this, [], null, CanvasView()));
    final order = _order;
    _changed(() => repo.addPage(id, pageId, order));
    pagesRevision.value++;
    goTo(at);
    return at + 1;
  }

  /// Copies page [index] right after itself (AC-23) and opens the copy.
  int duplicatePage(int index) {
    final source = pages[index];
    final ids = {for (final item in source.ink.items) item.id: repo.newId()};
    final copies = [
      for (final item in source.ink.items)
        // A copied chart follows the copied table, not the original.
        item is ChartItem
            ? item.copyAs(ids[item.id]!, tableId: ids[item.tableId])
            : _copyItem(item, ids[item.id]!),
    ];
    final pageId = repo.newId();
    final view = CanvasView(
      scale: source.view.scale,
      offset: source.view.offset,
    );
    pages.insert(
      index + 1,
      PageState._(pageId, this, copies, source.background, view),
    );
    final order = _order;
    _changed(
      () => repo.duplicatePage(
        boardId: id,
        sourceId: source.id,
        newPageId: pageId,
        copies: copies,
        orderedIds: order,
      ),
    );
    pagesRevision.value++;
    goTo(index + 1);
    return index + 2;
  }

  /// Sets (or with null removes) the background of page [index].
  void setBackground(int index, PageBackground? background) {
    final page = pages[index];
    page.ink.background.value = background;
    _changed(() => repo.setBackground(page.id, background));
    pagesRevision.value++;
  }

  /// PDF pages as backgrounds (REQ-09, P-13): the first goes on the open
  /// page, the rest become new pages right after it. Returns how many pages
  /// got a background.
  int addBackgroundPages(List<PageBackground> backgrounds) {
    if (backgrounds.isEmpty) return 0;
    final start = current.value;
    setBackground(start, backgrounds.first);
    for (var i = 1; i < backgrounds.length; i++) {
      final pageId = repo.newId();
      final bg = backgrounds[i];
      pages.insert(start + i, PageState._(pageId, this, [], bg, CanvasView()));
      final order = _order;
      _changed(() => repo.addPage(id, pageId, order, background: bg));
    }
    pagesRevision.value++;
    return backgrounds.length;
  }

  /// Deletes page [index]. The last page cannot be deleted (AC-25).
  bool deletePage(int index) {
    if (pages.length <= 1) return false;
    final removed = pages.removeAt(index);
    final order = _order;
    _changed(() => repo.deletePage(removed.id, order));
    final open = current.value;
    final next = open > index || open >= pages.length ? open - 1 : open;
    current.value = next.clamp(0, pages.length - 1);
    queue.run(() => repo.touchBoard(id, lastPage: current.value + 1));
    pagesRevision.value++;
    removed.dispose();
    return true;
  }

  /// Moves page [from] to position [to] (indices after removal, like
  /// [List.insert]); the open page stays open.
  void movePage(int from, int to) {
    if (from == to) return;
    final open = pages[current.value];
    final moved = pages.removeAt(from);
    pages.insert(to.clamp(0, pages.length), moved);
    final order = _order;
    _changed(() => repo.reorderPages(order));
    current.value = pages.indexOf(open);
    queue.run(() => repo.touchBoard(id, lastPage: current.value + 1));
    pagesRevision.value++;
  }

  /// Saves the automatic copy and the list thumbnail.
  Future<void> snapshot() async {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    for (final p in pages) {
      p.saveView();
    }
    if (_dirtySinceSnapshot) {
      _dirtySinceSnapshot = false;
      await queue.run(() => repo.saveSnapshot(id));
    }
    final render = renderThumbnail;
    if (render != null) {
      final first = pages.first;
      final png = await render(first.ink.items, first.background, images);
      if (png != null) await queue.run(() => repo.saveThumbnail(id, png));
    }
    await queue.flush();
  }

  Future<void> close() async {
    await snapshot();
    dispose();
  }

  void dispose() {
    _snapshotTimer?.cancel();
    for (final p in pages) {
      p.dispose();
    }
    images.dispose();
    queue.dispose();
    current.dispose();
    pagesRevision.dispose();
    title.dispose();
  }
}
