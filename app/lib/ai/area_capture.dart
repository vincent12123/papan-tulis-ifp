import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../canvas/item_painter.dart';
import '../canvas/media_images.dart';
import '../canvas/stroke.dart';
import '../ui/theme.dart';

/// Largest side of the PNG sent to the AI: enough to read handwriting,
/// small enough to upload quickly over school Wi-Fi.
const maxCaptureSide = 1024.0;

/// PNG of everything inside [area] (canvas coordinates) on a white page,
/// as the AI will see it (P-03).
Future<Uint8List?> captureArea({
  required Rect area,
  required List<PageItem> items,
  PageBackground? background,
  MediaImages? media,
}) async {
  final box = area.inflate(16);
  final scale = math.min(1.5, maxCaptureSide / math.max(box.width, box.height));
  final size = Size(
    (box.width * scale).roundToDouble().clamp(1, maxCaptureSide),
    (box.height * scale).roundToDouble().clamp(1, maxCaptureSide),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.canvas);
  canvas
    ..scale(scale)
    ..translate(-box.left, -box.top);
  paintBackground(canvas, background, media);
  for (final item in items) {
    if (item.bounds.overlaps(box)) paintItem(canvas, item, media);
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    picture.dispose();
  }
}
