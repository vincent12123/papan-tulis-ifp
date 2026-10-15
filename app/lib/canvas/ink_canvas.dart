import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart';

import '../peraga/peraga_painter.dart';
import '../peraga/quiz_painter.dart';
import '../solid/solid_painter.dart';
import '../ui/theme.dart';
import 'canvas_view.dart';
import 'ink_controller.dart';
import 'ink_painters.dart';
import 'media_images.dart';
import 'stroke.dart';

/// Board tools that act on the canvas (SCR-01). Teks arrives with
/// Checkpoint 6; Gambar is an action, not a mode.
enum CanvasTool { pen, eraser, select, shape, pan }

typedef InkTarget = ({InkController ink, CanvasView view});

/// The writing surface. Uses a raw [Listener] instead of gesture detectors so
/// every finger is tracked independently and no gesture arena delays the
/// first point of a stroke (REQ-01, REQ-03).
///
/// Gesture rule (SPEC P-02): with Pena/Penghapus/Bentuk every finger draws;
/// panning and pinch-zoom happen only with the Geser tool.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.controller,
    this.viewport,
    this.tool,
    this.shape,
    this.target,
    this.media,
    this.color = AppColors.canvas,
  });

  final InkController controller;
  final CanvasView? viewport;

  /// Current tool, read at each pointer-down so a tool change applies to the
  /// very next touch even before the next frame. Defaults to the pen.
  final ValueListenable<CanvasTool>? tool;

  /// Shape drawn by the Bentuk tool; null means Otomatis (draw freehand and
  /// tidy it into a shape).
  final ValueListenable<ShapeType?>? shape;

  /// Where a new touch should go, read at pointer-down. Lets a touch right
  /// after switching pages land on the new page even before the next frame.
  /// Defaults to [controller] and [viewport].
  final InkTarget Function()? target;

  /// Decoded pictures for images and backgrounds.
  final MediaImages? media;

  /// Board color (tema papan, REQ-29).
  final Color color;

  /// Eraser radius on screen, in logical pixels.
  static const eraserScreenRadius = 24.0;

  /// Smallest size a picture or shape can be resized to, in canvas units.
  static const minItemSize = 24.0;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

/// What a Pilih drag does.
sealed class _SelectDrag {}

class _MoveDrag extends _SelectDrag {
  _MoveDrag(this.startFrame, this.startAt);
  final Rect startFrame;
  final Offset startAt;
}

class _ResizeDrag extends _SelectDrag {
  _ResizeDrag(this.fixed, this.startFrame, this.keepAspect);
  final Offset fixed;
  final Rect startFrame;
  final bool keepAspect;
}

class _InkCanvasState extends State<InkCanvas> with TickerProviderStateMixin {
  InkPictureCache _cache = InkPictureCache();
  final CanvasView _ownViewport = CanvasView();

  /// The page each pointer started on; its moves and lift go there too.
  final Map<int, InkTarget> _targets = {};

  /// Pointers that started in pan mode, with their latest screen position.
  final Map<int, Offset> _panPointers = {};

  /// Which tool each pointer started with, so switching tools mid-gesture
  /// cannot leave a stroke or eraser hanging.
  final Map<int, CanvasTool> _pointerTool = {};

  /// Graph sliders being dragged, per pointer (REQ-20).
  final Map<int, int> _sliderDrags = {};

  /// Solids being turned (button null) or a solid button pressed, per
  /// pointer, with the last screen position (REQ-23).
  final Map<int, ({String id, SolidButton? button, Offset last})>
  _solidTouches = {};

  /// Peraga sliders being dragged and peraga/quiz controls pressed, per
  /// pointer (REQ-26–28).
  final Map<int, ({String id, Object control})> _liveTouches = {};

  /// Drives playing peraga; runs only while one plays.
  late final Ticker _clock = createTicker(_tick);
  Duration _lastTick = Duration.zero;

  void _tick(Duration elapsed) {
    final ink = widget.controller;
    if (ink.running.isEmpty) {
      _clock.stop();
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    ink.advance(dt.clamp(0, 0.1));
  }

  void _startClock() {
    if (_clock.isActive || widget.controller.running.isEmpty) return;
    _lastTick = Duration.zero;
    _clock.start();
  }

  /// Opens or closes a solid's net smoothly.
  late final AnimationController _netAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _lassoing = false;

  /// Pilih works with one finger at a time.
  int? _selectPointer;
  _SelectDrag? _selectDrag;

  CanvasView get _viewport => widget.viewport ?? _ownViewport;

  @override
  void didUpdateWidget(InkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // Another page: its items need their own picture cache.
      _cache.dispose();
      _cache = InkPictureCache();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _netAnimation.dispose();
    _cache.dispose();
    _ownViewport.dispose();
    super.dispose();
  }

  /// Real pressure is used only for a stylus that reports a pressure range;
  /// fingers get thickness simulated from speed.
  double? _pressure(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus) return null;
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) return null;
    return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e) {
    final target =
        widget.target?.call() ?? (ink: widget.controller, view: _viewport);
    final ink = target.ink;
    final view = target.view;
    final tool = e.kind == PointerDeviceKind.invertedStylus
        ? CanvasTool.eraser
        : (widget.tool?.value ?? CanvasTool.pen);
    final at = view.toCanvas(e.localPosition);
    // A finger on a graph slider moves the slider with any tool but Geser.
    if (tool != CanvasTool.pan && _sliderDrags.isEmpty) {
      final hit = ink.hitGraphSlider(at, tolerance: 24 / view.scale);
      if (hit != null) {
        _targets[e.pointer] = target;
        _sliderDrags[e.pointer] = hit.slider;
        ink.beginLift(hit.graph.id);
        ink.updateSlider(hit.slider, at.dx);
        return;
      }
    }
    // Peraga and quiz controls work with any tool but Geser; their bodies
    // take no ink (it would hide under them on the live layer).
    if (tool != CanvasTool.pan && _liveTouches.isEmpty) {
      final hit = ink.hitLiveControl(at);
      if (hit != null) {
        final control = hit.control;
        if (control is PeragaSlider) {
          if (ink.lifting) return;
          ink.beginLift(hit.item.id);
          final value = PeragaLayout(hit.item as PeragaItem)
              .valueAt(control.index, at.dx);
          _setPeragaValue(ink, control.index, value);
        }
        _targets[e.pointer] = target;
        _liveTouches[e.pointer] = (id: hit.item.id, control: control);
        return;
      }
      if (tool != CanvasTool.select && ink.onLiveBody(at)) return;
    }
    // A solid turns under a finger, and its buttons work, with any tool but
    // Geser; Pilih still moves and resizes it (its buttons work there too).
    if (tool != CanvasTool.pan && _solidTouches.isEmpty) {
      final hit = ink.hitSolid(at);
      if (hit != null && (hit.button != null || tool != CanvasTool.select)) {
        if (hit.button == null) {
          if (ink.lifting) return;
          ink.beginLift(hit.solid.id);
        }
        _targets[e.pointer] = target;
        _solidTouches[e.pointer] = (
          id: hit.solid.id,
          button: hit.button,
          last: e.localPosition,
        );
        return;
      }
    }
    if (tool == CanvasTool.select && _selectPointer != null) return;
    _targets[e.pointer] = target;
    _pointerTool[e.pointer] = tool;
    switch (tool) {
      case CanvasTool.pen:
        ink.pointerDown(
          e.pointer,
          at,
          pressure: _pressure(e),
          isStylus: e.kind == PointerDeviceKind.stylus,
          widthScale: view.scale,
        );
      case CanvasTool.shape:
        final type = widget.shape?.value;
        if (type == null) {
          ink.pointerDown(
            e.pointer,
            at,
            pressure: _pressure(e),
            widthScale: view.scale,
            recognize: true,
          );
        } else {
          ink.shapeDown(e.pointer, at, type, widthScale: view.scale);
        }
      case CanvasTool.eraser:
        ink.eraserDown(
          e.pointer,
          at,
          radius: InkCanvas.eraserScreenRadius / view.scale,
        );
      case CanvasTool.select:
        _selectPointer = e.pointer;
        _selectDown(ink, view, e.localPosition);
      case CanvasTool.pan:
        _panPointers[e.pointer] = e.localPosition;
    }
  }

  /// Pilih: a corner handle resizes, inside the frame moves, another item
  /// gets selected, empty canvas clears the selection.
  void _selectDown(InkController ink, CanvasView view, Offset screen) {
    final at = view.toCanvas(screen);
    final current = ink.selectedItem;
    if (current != null) {
      final frame = selectionFrame(ink, view, current);
      final canvasFrame = ink.frameOf(current);
      final corners = {
        frame.topLeft: canvasFrame.bottomRight,
        frame.topRight: canvasFrame.bottomLeft,
        frame.bottomLeft: canvasFrame.topRight,
        frame.bottomRight: canvasFrame.topLeft,
      };
      for (final entry in corners.entries) {
        if ((entry.key - screen).distance <= ActiveInkPainter.handleSize) {
          _selectDrag = _ResizeDrag(
            entry.value,
            canvasFrame,
            current is ImageItem,
          );
          ink.beginTransform();
          return;
        }
      }
      if (frame.inflate(8).contains(screen)) {
        _selectDrag = _MoveDrag(canvasFrame, at);
        ink.beginTransform();
        return;
      }
    }
    final hit = ink.hitSelectable(at, tolerance: 12 / view.scale);
    ink.select(hit?.id);
    if (hit != null) {
      _selectDrag = _MoveDrag(ink.frameOf(hit), at);
      ink.beginTransform();
    } else {
      // Empty canvas: circle an area for Asisten AI.
      ink.lassoStart(at);
      _lassoing = true;
    }
  }

  void _selectMove(InkController ink, CanvasView view, Offset screen) {
    final drag = _selectDrag;
    final at = view.toCanvas(screen);
    if (_lassoing) {
      ink.lassoMove(at);
      return;
    }
    switch (drag) {
      case _MoveDrag(:final startFrame, :final startAt):
        ink.updateTransform(startFrame.shift(at - startAt));
      case _ResizeDrag(:final fixed, :final startFrame, :final keepAspect):
        var corner = at;
        if (keepAspect && startFrame.height > 0) {
          // Pictures keep their proportions.
          final ratio = startFrame.width / startFrame.height;
          final w = (at.dx - fixed.dx).abs();
          final h = w / ratio;
          corner = Offset(at.dx, fixed.dy + (at.dy >= fixed.dy ? h : -h));
        }
        var rect = Rect.fromPoints(fixed, corner);
        if (rect.width < InkCanvas.minItemSize ||
            rect.height < InkCanvas.minItemSize) {
          rect = Rect.fromLTWH(
            rect.left,
            rect.top,
            rect.width.clamp(InkCanvas.minItemSize, double.infinity),
            rect.height.clamp(InkCanvas.minItemSize, double.infinity),
          );
        }
        ink.updateTransform(rect);
      case null:
        break;
    }
  }

  void _move(PointerMoveEvent e) {
    final target = _targets[e.pointer];
    if (target == null) return;
    final ink = target.ink;
    final view = target.view;
    final slider = _sliderDrags[e.pointer];
    if (slider != null) {
      ink.updateSlider(slider, view.toCanvas(e.localPosition).dx);
      return;
    }
    final live = _liveTouches[e.pointer];
    if (live != null) {
      final control = live.control;
      final preview = ink.transformPreview;
      if (control is PeragaSlider && preview is PeragaItem) {
        final x = view.toCanvas(e.localPosition).dx;
        _setPeragaValue(
          ink,
          control.index,
          PeragaLayout(preview).valueAt(control.index, x),
        );
      }
      return;
    }
    final solid = _solidTouches[e.pointer];
    if (solid != null) {
      if (solid.button == null) {
        ink.turnSolid(e.localPosition - solid.last);
        _solidTouches[e.pointer] = (
          id: solid.id,
          button: null,
          last: e.localPosition,
        );
      }
      return;
    }
    switch (_pointerTool[e.pointer]) {
      case CanvasTool.pen:
        ink.pointerMove(
          e.pointer,
          view.toCanvas(e.localPosition),
          pressure: _pressure(e),
        );
      case CanvasTool.shape:
        final at = view.toCanvas(e.localPosition);
        ink.pointerMove(e.pointer, at, pressure: _pressure(e));
        ink.shapeMove(e.pointer, at);
      case CanvasTool.eraser:
        ink.eraserMove(e.pointer, view.toCanvas(e.localPosition));
      case CanvasTool.select:
        _selectMove(ink, view, e.localPosition);
      case CanvasTool.pan:
        _panMove(view, e.pointer, e.localPosition);
      case null:
        break;
    }
  }

  void _setPeragaValue(InkController ink, int index, double value) {
    ink.updateLifted((item) {
      final p = item as PeragaItem;
      return p.withValue(p.kind.spec.params[index].name, value);
    });
  }

  /// A tap on a peraga button or choice, or on a quiz card.
  void _pressLive(InkController ink, PageItem item, Object control) {
    switch ((item, control)) {
      case (PeragaItem p, PeragaPlay()):
        ink.togglePeraga(p.id);
        _startClock();
      case (PeragaItem p, PeragaReset()):
        ink.resetPeraga(p.id);
      case (PeragaItem p, PeragaChoice(:final index)):
        if (ink.lifting) return;
        final param = p.kind.spec.params[index];
        final next =
            (p.values[param.name]!.round() + 1) % param.choices!.length;
        ink.beginLift(p.id);
        _setPeragaValue(ink, index, next.toDouble());
        ink.endTransform();
      case (QuizItem q, QuizTarget target):
        ink.quizTap(q, target);
    }
  }

  /// Jaring-jaring opens/closes the net with an animation; Bidang potong
  /// toggles at once. Each is one undo step.
  void _press(InkController ink, SolidItem solid, SolidButton button) {
    if (ink.lifting) return;
    ink.beginLift(solid.id);
    switch (button) {
      case SolidButton.cut:
        ink.updateLifted((s) => (s as SolidItem).withCut(!s.cut));
        ink.endTransform();
      case SolidButton.net:
        final from = solid.unfold;
        final to = from > 0.5 ? 0.0 : 1.0;
        void tick() {
          final t = Curves.easeInOut.transform(_netAnimation.value);
          ink.updateLifted(
            (s) => (s as SolidItem).withUnfold(from + (to - from) * t),
          );
        }

        _netAnimation
          ..stop()
          ..value = 0
          ..addListener(tick);
        _netAnimation.forward().whenCompleteOrCancel(() {
          _netAnimation.removeListener(tick);
          ink.updateLifted((s) => (s as SolidItem).withUnfold(to));
          ink.endTransform();
        });
    }
  }

  /// One finger pans; two fingers pan by their midpoint and zoom by their
  /// spread.
  void _panMove(CanvasView view, int pointer, Offset position) {
    final previous = Map<int, Offset>.of(_panPointers);
    _panPointers[pointer] = position;
    if (_panPointers.length == 1) {
      view.panBy(position - previous[pointer]!);
      return;
    }
    final ids = _panPointers.keys.take(2).toList();
    if (!ids.contains(pointer)) return;
    final a0 = previous[ids[0]]!, b0 = previous[ids[1]]!;
    final a1 = _panPointers[ids[0]]!, b1 = _panPointers[ids[1]]!;
    final mid0 = (a0 + b0) / 2, mid1 = (a1 + b1) / 2;
    view.panBy(mid1 - mid0);
    final spread0 = (a0 - b0).distance;
    if (spread0 > 0) view.zoomAt(mid1, (a1 - b1).distance / spread0);
  }

  void _end(PointerEvent e, {required bool cancelled}) {
    final target = _targets.remove(e.pointer);
    if (target == null) return;
    final ink = target.ink;
    if (_sliderDrags.remove(e.pointer) != null) {
      ink.endTransform();
      return;
    }
    final live = _liveTouches.remove(e.pointer);
    if (live != null) {
      if (live.control is PeragaSlider) {
        ink.endTransform();
      } else if (!cancelled) {
        final hit = ink.hitLiveControl(target.view.toCanvas(e.localPosition));
        if (hit != null &&
            hit.item.id == live.id &&
            hit.control.runtimeType == live.control.runtimeType) {
          _pressLive(ink, hit.item, hit.control);
        }
      }
      return;
    }
    final solid = _solidTouches.remove(e.pointer);
    if (solid != null) {
      final button = solid.button;
      if (button == null) {
        ink.endTransform();
      } else if (!cancelled) {
        final at = target.view.toCanvas(e.localPosition);
        final hit = ink.hitSolid(at);
        if (hit?.solid.id == solid.id && hit?.button == button) {
          _press(ink, hit!.solid, button);
        }
      }
      return;
    }
    switch (_pointerTool.remove(e.pointer)) {
      case CanvasTool.pen:
        cancelled ? ink.pointerCancel(e.pointer) : ink.pointerUp(e.pointer);
      case CanvasTool.shape:
        if (cancelled) {
          ink.pointerCancel(e.pointer);
        } else {
          ink.pointerUp(e.pointer);
          ink.shapeUp(e.pointer);
        }
      case CanvasTool.eraser:
        ink.eraserUp(e.pointer);
      case CanvasTool.select:
        if (_selectPointer == e.pointer) {
          _selectPointer = null;
          _selectDrag = null;
          if (_lassoing) {
            _lassoing = false;
            cancelled ? ink.clearArea() : ink.lassoEnd();
          } else {
            ink.endTransform();
          }
        }
      case CanvasTool.pan:
        _panPointers.remove(e.pointer);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (e) => _end(e, cancelled: false),
      onPointerCancel: (e) => _end(e, cancelled: true),
      child: ColoredBox(
        color: widget.color,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Completed ink is isolated in its own layer so the engine can
            // cache it while only the active layer repaints.
            RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                painter: CommittedInkPainter(
                  controller,
                  _cache,
                  _viewport,
                  widget.media,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: LiveItemsPainter(controller, _viewport, widget.media),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: ActiveInkPainter(controller, _viewport, widget.media),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
