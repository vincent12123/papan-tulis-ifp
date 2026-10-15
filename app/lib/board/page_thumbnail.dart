import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../canvas/ink_controller.dart';
import '../canvas/item_painter.dart';
import '../canvas/media_images.dart';
import '../canvas/stroke.dart';
import '../ui/theme.dart';

/// Area a thumbnail shows: the items and background, at least one screen.
Rect thumbnailArea(
  List<PageItem> items,
  PageBackground? background,
  Size screen,
) {
  var area = Offset.zero & screen;
  if (background != null) area = area.expandToInclude(background.rect);
  for (final item in items) {
    area = area.expandToInclude(item.bounds);
  }
  return area;
}

void paintPageFitted(
  Canvas canvas,
  Size size,
  List<PageItem> items,
  PageBackground? background,
  MediaImages? media,
  Rect area,
) {
  final scale = (size.width / area.width) < (size.height / area.height)
      ? size.width / area.width
      : size.height / area.height;
  canvas
    ..save()
    ..translate(
      (size.width - area.width * scale) / 2,
      (size.height - area.height * scale) / 2,
    )
    ..scale(scale)
    ..translate(-area.left, -area.top);
  paintBackground(canvas, background, media);
  for (final item in items) {
    paintItem(canvas, item, media);
  }
  canvas.restore();
}

/// Live miniature of a page for the page panel (SCR-03).
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({
    super.key,
    required this.ink,
    required this.screen,
    this.media,
  });

  final InkController ink;
  final Size screen;
  final MediaImages? media;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: CustomPaint(
        painter: _ThumbnailPainter(ink, screen, media),
        size: Size.infinite,
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.ink, this.screen, this.media)
    : super(
        repaint: Listenable.merge([
          ink.committedRevision,
          ink.background,
          ?media?.revision,
        ]),
      );

  final InkController ink;
  final Size screen;
  final MediaImages? media;

  @override
  void paint(Canvas canvas, Size size) {
    final items = ink.items;
    final bg = ink.background.value;
    paintPageFitted(
      canvas,
      size,
      items,
      bg,
      media,
      thumbnailArea(items, bg, screen),
    );
  }

  @override
  bool shouldRepaint(_ThumbnailPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.media != media;
}

/// PNG of the first page for the board list (SCR-02).
Future<Uint8List?> renderThumbnailPng(
  List<PageItem> items,
  PageBackground? background,
  MediaImages? media, {
  Size screen = const Size(1920, 1080),
  Size size = const Size(320, 180),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.canvas);
  paintPageFitted(
    canvas,
    size,
    items,
    background,
    media,
    thumbnailArea(items, background, screen),
  );
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
