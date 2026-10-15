import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../ui/theme.dart';
import 'canvas_view.dart';
import 'ink_controller.dart';
import 'item_painter.dart';
import 'media_images.dart';
import 'stroke.dart';
import '../peraga/peraga_painter.dart';
import '../peraga/quiz_painter.dart';

void _applyViewport(Canvas canvas, CanvasView viewport) {
  canvas
    ..translate(viewport.offset.dx, viewport.offset.dy)
    ..scale(viewport.scale);
}

/// Paints the page background and all completed items from cached picture
/// chunks, so committing a stroke on a page with thousands of strokes only
/// re-records one chunk.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter(this.controller, this.cache, this.viewport, this.media)
    : super(
        repaint: Listenable.merge([
          controller.committedRevision,
          controller.background,
          viewport.revision,
          ?media?.revision,
        ]),
      );

  final InkController controller;
  final InkPictureCache cache;
  final CanvasView viewport;
  final MediaImages? media;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    _applyViewport(canvas, viewport);
    paintBackground(canvas, controller.background.value, media);
    for (final chunk in cache.chunksFor(
      controller.committedItems,
      media,
      media?.revision.value ?? 0,
    )) {
      canvas.drawPicture(chunk);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommittedInkPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.viewport != viewport ||
      oldDelegate.cache != cache;
}

/// Paints what is still being drawn or moved, eraser feedback, and the Pilih
/// selection frame. Repaints on every move.
class ActiveInkPainter extends CustomPainter {
  ActiveInkPainter(this.controller, this.viewport, this.media)
    : super(
        repaint: Listenable.merge([
          controller.activeRevision,
          controller.area,
          viewport.revision,
          ?media?.revision,
        ]),
      );

  final InkController controller;
  final CanvasView viewport;
  final MediaImages? media;

  /// Corner handle size on screen (Pilih), large enough for a finger.
  static const handleSize = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    _applyViewport(canvas, viewport);
    final preview = controller.transformPreview;
    if (preview != null) _paintLive(canvas, controller, preview, media);
    for (final stroke in controller.activeStrokes) {
      paintItem(canvas, stroke, media, live: true);
    }
    for (final shape in controller.activeShapes) {
      paintItem(canvas, shape, media);
    }
    canvas.restore();

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.textMuted;
    final radius = controller.eraserRadius * viewport.scale;
    for (final at in controller.eraserPositions) {
      canvas.drawCircle(viewport.toScreen(at), radius, ring);
    }

    final lasso = controller.lasso;
    if (lasso != null && lasso.length > 1) {
      final path = Path()
        ..moveTo(
          viewport.toScreen(lasso.first).dx,
          viewport.toScreen(lasso.first).dy,
        );
      for (final p in lasso.skip(1)) {
        final s = viewport.toScreen(p);
        path.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.primary,
      );
    }
    final area = controller.area.value;
    if (area != null) {
      _dashedRect(
        canvas,
        Rect.fromPoints(
          viewport.toScreen(area.topLeft),
          viewport.toScreen(area.bottomRight),
        ),
      );
    }

    final selected = controller.selectedItem;
    if (selected != null) {
      final frame = selectionFrame(controller, viewport, selected);
      canvas.drawRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.primary,
      );
      final handle = Paint()..color = AppColors.primary;
      for (final corner in [
        frame.topLeft,
        frame.topRight,
        frame.bottomLeft,
        frame.bottomRight,
      ]) {
        canvas.drawRect(
          Rect.fromCenter(
            center: corner,
            width: handleSize,
            height: handleSize,
          ),
          handle,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ActiveInkPainter oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.viewport != viewport;
}

/// Quizzes and playing peraga, above the cached ink (REQ-26–28). Repaints
/// every frame only while something plays.
class LiveItemsPainter extends CustomPainter {
  LiveItemsPainter(this.controller, this.viewport, this.media)
    : super(
        repaint: Listenable.merge([
          controller.liveRevision,
          controller.committedRevision,
          viewport.revision,
        ]),
      );

  final InkController controller;
  final CanvasView viewport;
  final MediaImages? media;

  @override
  void paint(Canvas canvas, Size size) {
    final live = controller.liveItems;
    if (live.isEmpty) return;
    canvas.save();
    _applyViewport(canvas, viewport);
    for (final item in live) {
      _paintLive(canvas, controller, item, media);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveItemsPainter oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.viewport != viewport;
}

/// Peraga at their own time, quizzes with their progress, others as usual.
void _paintLive(
  Canvas canvas,
  InkController controller,
  PageItem item,
  MediaImages? media,
) {
  switch (item) {
    case PeragaItem():
      paintPeraga(
        canvas,
        item,
        t: controller.liveTime[item.id] ?? 0,
        running: controller.running.contains(item.id),
      );
    case QuizItem():
      paintQuiz(canvas, item, controller.quizState(item));
    default:
      paintItem(canvas, item, media);
  }
}

/// Dashed outline of a circled area (ux-flow §6 Pilih area).
void _dashedRect(Canvas canvas, Rect r) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = AppColors.primary;
  const dash = 10.0, gap = 7.0;
  for (final side in [
    (r.topLeft, r.topRight),
    (r.topRight, r.bottomRight),
    (r.bottomRight, r.bottomLeft),
    (r.bottomLeft, r.topLeft),
  ]) {
    final (a, b) = side;
    final length = (b - a).distance;
    if (length == 0) continue;
    final dir = (b - a) / length;
    for (var t = 0.0; t < length; t += dash + gap) {
      canvas.drawLine(
        a + dir * t,
        a + dir * (t + dash).clamp(0, length),
        paint,
      );
    }
  }
}

/// Screen rectangle of the selection frame for [item].
Rect selectionFrame(InkController ink, CanvasView view, PageItem item) {
  final f = ink.frameOf(item);
  return Rect.fromPoints(
    view.toScreen(f.topLeft),
    view.toScreen(f.bottomRight),
  );
}

/// Splits completed items into fixed-size chunks, each recorded once as a
/// picture. Appending or undoing the newest item re-records only the last
/// chunk; any other change re-records from the first changed chunk. When a
/// picture finishes loading, everything is re-recorded so it appears.
class InkPictureCache {
  InkPictureCache({this.chunkSize = 128});

  final int chunkSize;
  final List<ui.Picture> _chunks = [];
  List<PageItem> _included = const [];
  int _mediaRevision = -1;

  int get chunkCount => _chunks.length;

  List<ui.Picture> chunksFor(
    List<PageItem> items, [
    MediaImages? media,
    int mediaRevision = 0,
  ]) {
    if (mediaRevision != _mediaRevision) {
      _clear();
      _mediaRevision = mediaRevision;
    }
    _sync(items, media);
    return _chunks;
  }

  void _sync(List<PageItem> items, MediaImages? media) {
    final shared = _sharedPrefixLength(items);
    if (shared == _included.length && shared == items.length) return;
    // Keep chunks that are entirely inside the unchanged prefix.
    final keep = shared ~/ chunkSize;
    while (_chunks.length > keep) {
      _chunks.removeLast().dispose();
    }
    for (
      var start = keep * chunkSize;
      start < items.length;
      start += chunkSize
    ) {
      final end = (start + chunkSize).clamp(0, items.length);
      _chunks.add(_record(items.sublist(start, end), media));
    }
    _included = items;
  }

  int _sharedPrefixLength(List<PageItem> items) {
    final limit = items.length < _included.length
        ? items.length
        : _included.length;
    var i = 0;
    while (i < limit && identical(items[i], _included[i])) {
      i++;
    }
    return i;
  }

  ui.Picture _record(List<PageItem> items, MediaImages? media) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final item in items) {
      paintItem(canvas, item, media);
    }
    return recorder.endRecording();
  }

  void _clear() {
    for (final chunk in _chunks) {
      chunk.dispose();
    }
    _chunks.clear();
    _included = const [];
  }

  void dispose() => _clear();
}
