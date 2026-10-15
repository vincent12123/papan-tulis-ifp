import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../ui/theme.dart';
import '../graph/graph_painter.dart';
import 'eraser.dart';
import 'media_images.dart';
import '../mandarin/mandarin_painter.dart';
import '../mandarin/mandarin_voice.dart';
import '../peraga/peraga_painter.dart';
import '../peraga/quiz_painter.dart';
import '../solid/solid_painter.dart';
import '../table/table_painter.dart';
import 'shapes.dart';
import 'stroke.dart';

/// One undoable change to the page.
sealed class InkAction {}

class AddItems extends InkAction {
  AddItems(this.items);
  final List<PageItem> items;
}

/// Items removed together, with the index each had when it was removed so
/// undo can put them back in the same stacking order.
class RemoveItems extends InkAction {
  RemoveItems(this.removed);
  final List<({int index, PageItem item})> removed;
}

/// Handwriting replaced by something else in one step ("Rapikan rumus",
/// REQ-22); undo brings the handwriting back.
class SwapItems extends InkAction {
  SwapItems(this.removed, this.added);
  final List<({int index, PageItem item})> removed;
  final List<PageItem> added;
}

/// An item moved or resized with Pilih.
class ReplaceItem extends InkAction {
  ReplaceItem(this.before, this.after);
  final PageItem before;
  final PageItem after;
}

/// Several items changed in place as one step (a table and its charts).
class ReplaceMany extends InkAction {
  ReplaceMany(this.changes);
  final List<(PageItem before, PageItem after)> changes;
}

/// Receives every change to the committed items so they can be saved
/// (REQ-06). In-progress strokes and shapes are not reported until they
/// finish.
abstract interface class InkChangeListener {
  void itemsAdded(List<PageItem> items);
  void itemsRemoved(List<PageItem> items);
  void itemChanged(PageItem item);
}

/// Owns the items of one page and turns raw pointer events into strokes,
/// shapes, erasing, and selection changes.
///
/// Every pointer writes its own stroke, so several fingers or students can
/// write at the same time (REQ-03). Two separate notifiers let the canvas
/// repaint only the in-progress ink on every move, while the large layer of
/// completed items repaints only when it actually changes (NFR-30).
class InkController {
  InkController({
    IdGenerator? ids,
    List<PageItem>? initial,
    PageBackground? background,
    this.listener,
  }) : _ids = ids ?? IdGenerator(),
       background = ValueNotifier(background) {
    if (initial != null) {
      _items.addAll(initial..sort((a, b) => a.z.compareTo(b.z)));
      for (final item in initial) {
        _maxZ = max(_maxZ, item.z);
      }
    }
  }

  final IdGenerator _ids;

  /// Persistence hook; null means nothing is saved (tests, diagnostics).
  InkChangeListener? listener;

  int _maxZ = 0;
  final List<PageItem> _items = [];
  final Map<int, Stroke> _active = {};
  final Set<int> _recognize = {};
  final Map<int, ShapeItem> _activeShapes = {};
  final List<InkAction> _undo = [];
  final List<InkAction> _redo = [];

  /// Eraser pointers currently down, with their latest position.
  final Map<int, Offset> _erasers = {};
  List<({int index, PageItem item})>? _eraseGroup;
  double _eraserRadius = 0;

  /// Item being moved/resized: taken out of [items] and drawn live.
  ({int index, PageItem original})? _transform;
  PageItem? _transformPreview;

  /// Bumped whenever [items] changes.
  final ValueNotifier<int> committedRevision = ValueNotifier(0);

  /// Bumped on every in-progress point, shape, eraser, or transform move.
  final ValueNotifier<int> activeRevision = ValueNotifier(0);

  /// Bumped when undo/redo availability or pen settings change.
  final ValueNotifier<int> stateRevision = ValueNotifier(0);

  /// PDF page or picture behind the ink (REQ-09); never erased.
  final ValueNotifier<PageBackground?> background;

  /// Id of the item selected with Pilih, if any.
  final ValueNotifier<String?> selected = ValueNotifier(null);

  /// Area circled with Pilih (canvas coordinates) for Asisten AI; null when
  /// nothing is circled. Selecting an item clears it and the other way round.
  final ValueNotifier<Rect?> area = ValueNotifier(null);
  List<Offset>? _lasso;

  /// The lasso while it is being drawn.
  List<Offset>? get lasso => _lasso;

  /// Smallest circled area that counts, in canvas units.
  static const minArea = 24.0;

  Color color = PenColors.black;
  double width = PenWidths.medium;

  /// New strokes in chalk style (REQ-29).
  bool chalk = false;

  void setChalk(bool value) {
    chalk = value;
    stateRevision.value++;
  }

  /// Highest number of simultaneous pointers seen (Checkpoint 1 report).
  int maxSimultaneousPointers = 0;

  /// Whether a stylus has ever been seen (Checkpoint 1 report).
  bool stylusSeen = false;

  List<PageItem> get items => List.unmodifiable(_items);
  List<Stroke> get strokes => _items.whereType<Stroke>().toList();
  Iterable<Stroke> get activeStrokes => _active.values;
  Iterable<ShapeItem> get activeShapes => _activeShapes.values;
  PageItem? get transformPreview => _transformPreview;

  /// Eraser circles in canvas coordinates, for drawing feedback.
  Iterable<Offset> get eraserPositions => _erasers.values;
  double get eraserRadius => _eraserRadius;

  bool get isWriting =>
      _active.isNotEmpty || _erasers.isNotEmpty || _activeShapes.isNotEmpty;
  bool get isEmpty =>
      _items.isEmpty &&
      _active.isEmpty &&
      _activeShapes.isEmpty &&
      _transform == null;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  PageItem? get selectedItem {
    final id = selected.value;
    if (id == null) return null;
    if (_transformPreview?.id == id) return _transformPreview;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String newId() => _ids.next();

  void setColor(Color value) {
    color = value;
    stateRevision.value++;
  }

  void setWidth(double value) {
    width = value;
    stateRevision.value++;
  }

  bool _busy(int pointer) =>
      _active.containsKey(pointer) ||
      _erasers.containsKey(pointer) ||
      _activeShapes.containsKey(pointer);

  // --- pen -----------------------------------------------------------------

  /// Starts a stroke. [widthScale] is the current zoom: the stroke is stored
  /// thinner when zoomed in so it looks the chosen width on screen.
  /// With [recognize] the finished stroke is turned into a shape when it
  /// clearly is one (Bentuk → Otomatis).
  void pointerDown(
    int pointer,
    Offset position, {
    double? pressure,
    bool isStylus = false,
    double widthScale = 1,
    bool recognize = false,
  }) {
    if (_busy(pointer)) return;
    if (isStylus) stylusSeen = true;
    final stroke = Stroke(
      id: _ids.next(),
      color: color,
      width: width / widthScale,
      hasPressure: pressure != null,
      z: ++_maxZ,
      chalk: chalk,
    )..points.add(InkPoint(position.dx, position.dy, pressure ?? 0.5));
    _active[pointer] = stroke;
    if (recognize) _recognize.add(pointer);
    _trackPointers();
    activeRevision.value++;
  }

  void pointerMove(int pointer, Offset position, {double? pressure}) {
    final stroke = _active[pointer];
    if (stroke == null) return;
    final last = stroke.points.last;
    // Skip sub-pixel jitter: it adds work without changing the ink.
    if ((last.x - position.dx).abs() < 0.5 &&
        (last.y - position.dy).abs() < 0.5) {
      return;
    }
    stroke.points.add(InkPoint(position.dx, position.dy, pressure ?? 0.5));
    activeRevision.value++;
  }

  /// Finishes the pointer's stroke and adds it on top of the page.
  void pointerUp(int pointer) {
    final stroke = _active.remove(pointer);
    if (stroke == null) return;
    PageItem item = stroke;
    if (_recognize.remove(pointer)) {
      final shape = recognizeShape(stroke.points);
      if (shape != null) {
        item = ShapeItem(
          id: stroke.id,
          type: shape.type,
          points: shape.points,
          color: stroke.color,
          width: stroke.width,
          z: stroke.z,
        );
      }
    }
    _addCommitted([item]);
    activeRevision.value++;
  }

  /// The system took the pointer away (e.g. palm rejection): drop its ink.
  void pointerCancel(int pointer) {
    _recognize.remove(pointer);
    if (_active.remove(pointer) != null) activeRevision.value++;
    if (_activeShapes.remove(pointer) != null) activeRevision.value++;
    if (_erasers.containsKey(pointer)) eraserUp(pointer);
  }

  // --- shapes from the menu ------------------------------------------------

  void shapeDown(
    int pointer,
    Offset position,
    ShapeType type, {
    double widthScale = 1,
  }) {
    if (_busy(pointer)) return;
    _activeShapes[pointer] = ShapeItem(
      id: _ids.next(),
      type: type,
      points: [position, position],
      color: color,
      width: width / widthScale,
      z: ++_maxZ,
    );
    _trackPointers();
    activeRevision.value++;
  }

  void shapeMove(int pointer, Offset position) {
    final shape = _activeShapes[pointer];
    if (shape == null) return;
    _activeShapes[pointer] = ShapeItem(
      id: shape.id,
      type: shape.type,
      points: [shape.points.first, position],
      color: shape.color,
      width: shape.width,
      z: shape.z,
    );
    activeRevision.value++;
  }

  /// Adds the dragged shape; a tap without dragging adds nothing.
  void shapeUp(int pointer) {
    final shape = _activeShapes.remove(pointer);
    if (shape == null) return;
    activeRevision.value++;
    if ((shape.points[1] - shape.points[0]).distance < 8) return;
    _addCommitted([shape]);
  }

  // --- eraser --------------------------------------------------------------

  /// Starts erasing. All eraser fingers down at the same time form one
  /// undo step.
  void eraserDown(int pointer, Offset position, {required double radius}) {
    if (_busy(pointer)) return;
    _eraseGroup ??= [];
    _eraserRadius = radius;
    _erasers[pointer] = position;
    _trackPointers();
    _eraseAt(position);
    activeRevision.value++;
  }

  void eraserMove(int pointer, Offset position) {
    final last = _erasers[pointer];
    if (last == null) return;
    _erasers[pointer] = position;
    // Sample along fast movements so thin strokes are not skipped.
    final steps = max(
      1,
      ((position - last).distance / max(1, _eraserRadius)).ceil(),
    );
    for (var i = 1; i <= steps; i++) {
      _eraseAt(Offset.lerp(last, position, i / steps)!);
    }
    activeRevision.value++;
  }

  void eraserUp(int pointer) {
    if (_erasers.remove(pointer) == null) return;
    activeRevision.value++;
    if (_erasers.isNotEmpty) return;
    final group = _eraseGroup;
    _eraseGroup = null;
    if (group != null && group.isNotEmpty) _record(RemoveItems(group));
  }

  void _eraseAt(Offset center) {
    final erased = <PageItem>[];
    for (var i = _items.length - 1; i >= 0; i--) {
      if (eraserTouchesItem(_items[i], center, _eraserRadius)) {
        final item = _items.removeAt(i);
        _eraseGroup!.add((index: i, item: item));
        erased.add(item);
        if (selected.value == item.id) selected.value = null;
      }
    }
    if (erased.isNotEmpty) {
      listener?.itemsRemoved(erased);
      committedRevision.value++;
    }
  }

  // --- pictures and selection (Pilih) --------------------------------------

  /// Adds a ready-made item (an inserted picture) on top of the page.
  void addItem(PageItem item) {
    item.z = ++_maxZ;
    _addCommitted([item]);
  }

  /// Removes [remove] and adds [add] on top as one undoable step.
  void replaceItems(List<PageItem> remove, List<PageItem> add) {
    final removed = <({int index, PageItem item})>[];
    for (var i = _items.length - 1; i >= 0; i--) {
      if (remove.contains(_items[i])) {
        removed.add((index: i, item: _items.removeAt(i)));
      }
    }
    for (final item in add) {
      item.z = ++_maxZ;
    }
    _items.addAll(add);
    _record(SwapItems(removed, add));
    if (removed.isNotEmpty) {
      listener?.itemsRemoved([for (final r in removed) r.item]);
    }
    listener?.itemsAdded(add);
    _clearStaleSelection();
    committedRevision.value++;
  }

  /// Topmost shape or picture at [at] (canvas coordinates).
  PageItem? hitSelectable(Offset at, {double tolerance = 12}) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (item is Stroke) continue;
      if (item.bounds.inflate(tolerance).contains(at)) return item;
    }
    return null;
  }

  void select(String? id) {
    if (id != null) area.value = null;
    if (selected.value == id) return;
    selected.value = id;
    activeRevision.value++;
  }

  void lassoStart(Offset at) {
    select(null);
    area.value = null;
    _lasso = [at];
    activeRevision.value++;
  }

  void lassoMove(Offset at) {
    _lasso?.add(at);
    activeRevision.value++;
  }

  /// Finishes the lasso; its bounds become the circled [area].
  void lassoEnd() {
    final points = _lasso;
    _lasso = null;
    activeRevision.value++;
    if (points == null || points.length < 2) return;
    var box = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    if (box.width >= minArea && box.height >= minArea) area.value = box;
  }

  void clearArea() {
    if (area.value == null && _lasso == null) return;
    area.value = null;
    _lasso = null;
    activeRevision.value++;
  }

  /// Lifts the selected item out of the page to move/resize it live.
  void beginTransform() {
    final id = selected.value;
    if (id != null) beginLift(id);
  }

  /// Lifts item [id] out of the page so it can change live (move, resize,
  /// or a graph slider); [endTransform] puts it back as one undo step.
  void beginLift(String id) {
    if (_transform != null) return;
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    _transform = (index: index, original: item);
    _transformPreview = item;
    committedRevision.value++;
    activeRevision.value++;
  }

  /// Moves/scales the lifted item so its frame becomes [to].
  void updateTransform(Rect to) {
    final t = _transform;
    if (t == null) return;
    final original = t.original;
    _transformPreview = switch (original) {
      ImageItem() => original.withRect(to),
      ShapeItem() => original.transformed(frameOf(original), to),
      GraphItem() => original.withRect(to),
      TextItem() => original.withRect(to),
      SolidItem() => original.withRect(to),
      PeragaItem() => original.withRect(to),
      QuizItem() => original.withRect(to),
      TableItem() => original.withRect(to),
      ChartItem() => original.withRect(to),
      MandarinItem() => original.withRect(to),
      Stroke() => original,
    };
    activeRevision.value++;
  }

  /// Topmost graph slider at [at] (canvas coordinates), if any (REQ-20).
  ({GraphItem graph, int slider})? hitGraphSlider(
    Offset at, {
    double tolerance = 24,
  }) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (item is! GraphItem || !item.rect.contains(at)) continue;
      final slider = GraphLayout(item).sliderAt(at, tolerance: tolerance);
      if (slider != null) return (graph: item, slider: slider);
      return null; // the topmost graph under the finger hides those below
    }
    return null;
  }

  // --- tables and their charts (REQ-21) ------------------------------------

  /// Topmost table under [at] and the cell there; null when something else
  /// is on top or nothing is there.
  ({TableItem table, int row, int col})? hitTableCell(Offset at) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (!item.bounds.contains(at)) continue;
      if (item is! TableItem) return null;
      final cell = TableLayout(item).cellAt(at);
      return cell == null ? null : (table: item, row: cell.row, col: cell.col);
    }
    return null;
  }

  /// Gives table [tableId] new [cells]; every chart drawn from it on this
  /// page follows in the same undo step (grafik terhubung, REQ-21).
  /// [rect] resizes the table too (a row or column added).
  void updateTable(String tableId, List<List<String>> cells, {Rect? rect}) {
    final changes = <(PageItem, PageItem)>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final PageItem? after = switch (item) {
        TableItem() when item.id == tableId =>
          item.withCells(cells).withRect(rect ?? item.rect),
        ChartItem() when item.tableId == tableId => item.withCells(cells),
        _ => null,
      };
      if (after == null) continue;
      _items[i] = after;
      changes.add((item, after));
      listener?.itemChanged(after);
    }
    if (changes.isEmpty) return;
    _record(ReplaceMany(changes));
    committedRevision.value++;
    activeRevision.value++;
  }

  /// Whether table [id] is still on this page (a chart is linked to it).
  bool hasTable(String id) => _items.any((i) => i is TableItem && i.id == id);

  /// Topmost solid under [at] and the button there, if any (REQ-23).
  ({SolidItem solid, SolidButton? button})? hitSolid(Offset at) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (!item.bounds.contains(at)) continue;
      if (item is! SolidItem) return null; // something else is on top
      return (solid: item, button: SolidLayout(item).buttonAt(at));
    }
    return null;
  }

  // --- alat peraga and quizzes (REQ-26–28), drawn on the live layer -------

  /// Peraga playing now; not saved (a board always opens paused).
  final Set<String> running = {};

  /// Seconds each peraga has played since Ulang.
  final Map<String, double> liveTime = {};

  /// Quiz progress while on screen; not saved.
  final Map<String, QuizState> quizzes = {};

  /// Repaints the live layer (every frame while something plays).
  final ValueNotifier<int> liveRevision = ValueNotifier(0);

  /// Items drawn on the live layer instead of the cached ink: quizzes, and
  /// peraga that play or are paused mid-way.
  /// Mandarin cards are live too: their speak buttons depend on whether the
  /// panel has a Mandarin voice, which is known only after start-up.
  bool isLive(PageItem item) =>
      item is QuizItem ||
      item is MandarinItem ||
      (item is PeragaItem &&
          (running.contains(item.id) || (liveTime[item.id] ?? 0) > 0));

  /// Completed items for the cached layer (live ones left out).
  List<PageItem> get committedItems => _items.any(isLive)
      ? [
          for (final i in _items)
            if (!isLive(i)) i,
        ]
      : _items;

  List<PageItem> get liveItems => [
    for (final i in _items)
      if (isLive(i)) i,
  ];

  QuizState quizState(QuizItem quiz) => quizzes.putIfAbsent(
    quiz.id,
    () => QuizState(quiz.pairs.length, quiz.id.hashCode),
  );

  /// Topmost peraga or quiz control under [at]; null when nothing there or
  /// something else is on top.
  ({PageItem item, Object control})? hitLiveControl(Offset at) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (!item.bounds.contains(at)) continue;
      final Object? control = switch (item) {
        PeragaItem() => PeragaLayout(item).controlAt(at),
        QuizItem() => QuizLayout(item).targetAt(at),
        MandarinItem() => MandarinLayout(
          item,
          voice: MandarinVoiceStatus.available.value,
        ).targetAt(at),
        _ => null,
      };
      if (item is! PeragaItem && item is! QuizItem && item is! MandarinItem) {
        return null;
      }
      return control == null ? null : (item: item, control: control);
    }
    return null;
  }

  /// Whether [at] is on the body of a peraga or quiz (not a control).
  bool onLiveBody(Offset at) {
    for (var i = _items.length - 1; i >= 0; i--) {
      final item = _items[i];
      if (!item.bounds.contains(at)) continue;
      return item is PeragaItem || item is QuizItem || item is MandarinItem;
    }
    return false;
  }

  void togglePeraga(String id) {
    if (!running.remove(id)) running.add(id);
    liveTime.putIfAbsent(id, () => 0);
    committedRevision.value++;
    liveRevision.value++;
  }

  void resetPeraga(String id) {
    running.remove(id);
    liveTime.remove(id);
    committedRevision.value++;
    liveRevision.value++;
  }

  /// Moves the clock of every playing peraga on by [seconds].
  void advance(double seconds) {
    if (running.isEmpty) return;
    for (final id in running) {
      liveTime[id] = (liveTime[id] ?? 0) + seconds;
    }
    liveRevision.value++;
  }

  /// A student taps a quiz card or Acak ulang.
  void quizTap(QuizItem quiz, QuizTarget target) {
    final s = quizState(quiz);
    switch (target) {
      case QuizShuffle():
        quizzes[quiz.id] = QuizState(
          quiz.pairs.length,
          DateTime.now().microsecondsSinceEpoch,
        );
      case QuizLeft(:final index):
        s.wrong = null;
        if (!s.matched.contains(index)) s.selectedLeft = index;
      case QuizRight(:final row):
        final pick = s.order[row];
        final left = s.selectedLeft;
        s.wrong = null;
        if (left == null || s.matched.contains(pick)) break;
        if (pick == left) {
          s.matched.add(left);
          s.selectedLeft = null;
        } else {
          s.wrong = (left, row);
        }
    }
    liveRevision.value++;
  }

  /// True while an item is lifted (moved, resized, turned, or animating).
  bool get lifting => _transform != null;

  /// Turns the lifted solid by a finger drag of [delta] screen pixels.
  void turnSolid(Offset delta) {
    final preview = _transformPreview;
    if (preview is! SolidItem) return;
    _transformPreview = preview.turnedBy(delta.dx * 0.01, -delta.dy * 0.01);
    activeRevision.value++;
  }

  /// Replaces the lifted item's live state (net animation, cut plane).
  void updateLifted(PageItem Function(PageItem current) change) {
    final preview = _transformPreview;
    if (preview == null) return;
    _transformPreview = change(preview);
    activeRevision.value++;
  }

  /// Moves slider [slider] of the lifted graph to canvas x [canvasX].
  void updateSlider(int slider, double canvasX) {
    final preview = _transformPreview;
    if (preview is! GraphItem) return;
    final layout = GraphLayout(preview);
    if (slider >= preview.params.length) return;
    final name = preview.params[slider].name;
    final value = layout.valueAt(slider, canvasX);
    if (value == preview.params[slider].value) return;
    _transformPreview = preview.withParam(name, value);
    activeRevision.value++;
  }

  /// Frame the Pilih tool moves/resizes: a shape's corner points (without
  /// stroke padding) or a picture's rectangle.
  Rect frameOf(PageItem item) {
    if (item is! ShapeItem) return item.bounds;
    var r = Rect.fromPoints(item.points.first, item.points.first);
    for (final p in item.points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  void endTransform() {
    final t = _transform;
    if (t == null) return;
    final after = _transformPreview ?? t.original;
    _transform = null;
    _transformPreview = null;
    _items.insert(t.index.clamp(0, _items.length), after);
    if (!identical(after, t.original)) {
      _record(ReplaceItem(t.original, after));
      listener?.itemChanged(after);
    }
    committedRevision.value++;
    activeRevision.value++;
  }

  void deleteSelected() {
    final id = selected.value;
    if (id == null) return;
    final index = _items.indexWhere((i) => i.id == id);
    selected.value = null;
    if (index < 0) return;
    final item = _items.removeAt(index);
    _record(RemoveItems([(index: index, item: item)]));
    listener?.itemsRemoved([item]);
    committedRevision.value++;
    activeRevision.value++;
  }

  // --- history -------------------------------------------------------------

  void undo() {
    if (!canUndo) return;
    final action = _undo.removeLast();
    switch (action) {
      case AddItems(:final items):
        for (final item in items) {
          _items.remove(item);
        }
        listener?.itemsRemoved(items);
      case RemoveItems(:final removed):
        for (final r in removed.reversed) {
          _items.insert(r.index.clamp(0, _items.length), r.item);
        }
        listener?.itemsAdded([for (final r in removed) r.item]);
      case ReplaceItem(:final before, :final after):
        _swap(after, before);
      case ReplaceMany(:final changes):
        for (final (before, after) in changes) {
          _swap(after, before);
        }
      case SwapItems(:final removed, :final added):
        for (final item in added) {
          _items.remove(item);
        }
        for (final r in removed.reversed) {
          _items.insert(r.index.clamp(0, _items.length), r.item);
        }
        listener?.itemsRemoved(added);
        listener?.itemsAdded([for (final r in removed) r.item]);
    }
    _clearStaleSelection();
    _redo.add(action);
    committedRevision.value++;
    stateRevision.value++;
  }

  void redo() {
    if (!canRedo) return;
    final action = _redo.removeLast();
    switch (action) {
      case AddItems(:final items):
        _items.addAll(items);
        listener?.itemsAdded(items);
      case RemoveItems(:final removed):
        for (final r in removed) {
          _items.remove(r.item);
        }
        listener?.itemsRemoved([for (final r in removed) r.item]);
      case ReplaceItem(:final before, :final after):
        _swap(before, after);
      case ReplaceMany(:final changes):
        for (final (before, after) in changes) {
          _swap(before, after);
        }
      case SwapItems(:final removed, :final added):
        for (final r in removed) {
          _items.remove(r.item);
        }
        _items.addAll(added);
        listener?.itemsRemoved([for (final r in removed) r.item]);
        listener?.itemsAdded(added);
    }
    _clearStaleSelection();
    _undo.add(action);
    committedRevision.value++;
    stateRevision.value++;
  }

  void _swap(PageItem from, PageItem to) {
    final index = _items.indexOf(from);
    if (index < 0) return;
    _items[index] = to;
    listener?.itemChanged(to);
  }

  void _clearStaleSelection() {
    final id = selected.value;
    if (id != null && !_items.any((i) => i.id == id)) selected.value = null;
    activeRevision.value++;
  }

  /// Removes every item as one undoable step (diagnostics only).
  void clear() {
    if (_items.isEmpty) return;
    final removed = [
      for (var i = _items.length - 1; i >= 0; i--) (index: i, item: _items[i]),
    ];
    _items.clear();
    selected.value = null;
    _record(RemoveItems(removed));
    listener?.itemsRemoved([for (final r in removed) r.item]);
    committedRevision.value++;
  }

  /// Fills the page with [count] random scribbles for the NFR-30 load test.
  void addLoadTestStrokes(int count, Size area, {int seed = 7}) {
    final random = Random(seed);
    final added = <Stroke>[];
    for (var i = 0; i < count; i++) {
      var x = random.nextDouble() * area.width;
      var y = random.nextDouble() * area.height;
      final stroke = Stroke(
        id: _ids.next(),
        color: PenColors.all[random.nextInt(PenColors.all.length)].color,
        width: PenWidths.all[random.nextInt(PenWidths.all.length)].width,
        hasPressure: false,
        z: ++_maxZ,
      );
      final pointCount = 20 + random.nextInt(40);
      for (var p = 0; p < pointCount; p++) {
        x = (x + random.nextDouble() * 16 - 8).clamp(0, area.width);
        y = (y + random.nextDouble() * 16 - 8).clamp(0, area.height);
        stroke.points.add(InkPoint(x, y));
      }
      added.add(stroke);
    }
    _addCommitted(added);
  }

  void _addCommitted(List<PageItem> added) {
    _items.addAll(added);
    _record(AddItems(added));
    listener?.itemsAdded(added);
    committedRevision.value++;
  }

  void _record(InkAction action) {
    _undo.add(action);
    _redo.clear();
    stateRevision.value++;
  }

  void _trackPointers() {
    maxSimultaneousPointers = max(
      maxSimultaneousPointers,
      _active.length + _erasers.length + _activeShapes.length,
    );
  }

  void dispose() {
    committedRevision.dispose();
    activeRevision.dispose();
    stateRevision.dispose();
    selected.dispose();
    area.dispose();
    background.dispose();
    liveRevision.dispose();
  }
}
