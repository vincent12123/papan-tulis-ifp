import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Pan/zoom state of one page (REQ-04). Screen = canvas * scale + offset.
class CanvasView {
  CanvasView({this.scale = 1, this.offset = Offset.zero});

  /// Zoom limits (usulan; batas kanvas final menunggu SPEC P-08).
  static const minScale = 0.5;
  static const maxScale = 4.0;

  double scale;
  Offset offset;

  /// Bumped on every change so painters can repaint.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Offset toCanvas(Offset screen) => (screen - offset) / scale;
  Offset toScreen(Offset canvas) => canvas * scale + offset;

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    offset += delta;
    revision.value++;
  }

  /// Scales by [factor] keeping the canvas point under [focal] fixed. Stops
  /// at the limits without error (AC-21).
  void zoomAt(Offset focal, double factor) {
    final next = (scale * factor).clamp(minScale, maxScale);
    if (next == scale) return;
    final anchor = toCanvas(focal);
    scale = next;
    offset = focal - anchor * scale;
    revision.value++;
  }

  void dispose() => revision.dispose();
}
