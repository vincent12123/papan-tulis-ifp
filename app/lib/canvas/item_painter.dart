import 'dart:math';
import 'dart:ui' show PictureRecorder;

import 'package:flutter/rendering.dart';

import '../peraga/peraga_painter.dart';
import '../peraga/quiz_painter.dart';
import '../mandarin/mandarin_painter.dart';
import '../solid/solid_painter.dart';
import '../table/chart_painter.dart';
import '../table/table_painter.dart';
import '../ui/theme.dart';
import 'media_images.dart';
import '../graph/graph_painter.dart';
import 'shapes.dart';
import 'stroke.dart';
import 'stroke_geometry.dart';

/// Draws any page item. Pictures not loaded yet show as a light frame.
void paintItem(
  Canvas canvas,
  PageItem item,
  MediaImages? media, {
  bool live = false,
}) {
  switch (item) {
    case Stroke():
      final paint = Paint()
        ..isAntiAlias = true
        ..color = item.color;
      if (item.chalk) {
        // Grain: a tiled noise mask tinted with the stroke color.
        paint
          ..shader = chalkGrain()
          ..colorFilter = ColorFilter.mode(item.color, BlendMode.srcIn);
      }
      canvas.drawPath(
        live
            ? buildStrokePath(item, complete: false)
            : completedStrokePath(item),
        paint,
      );
    case ShapeItem():
      final paint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = item.width
        ..color = item.color;
      canvas.drawPath(shapePath(item), paint);
    case ImageItem():
      _paintPicture(canvas, item.file, item.rect, media);
    case GraphItem():
      paintGraph(canvas, item);
    case SolidItem():
      paintSolid(canvas, item);
    case PeragaItem():
      paintPeraga(canvas, item);
    case QuizItem():
      paintQuiz(canvas, item, null);
    case TableItem():
      paintTable(canvas, item);
    case ChartItem():
      paintChart(canvas, item);
    case MandarinItem():
      paintMandarin(canvas, item, voice: false);
    case TextItem():
      final painter = TextPainter(
        text: TextSpan(
          text: item.text,
          style: TextStyle(
            fontSize: item.fontSize,
            color: item.color,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: item.rect.width);
      canvas.save();
      canvas.clipRect(item.rect.inflate(item.fontSize));
      painter.paint(canvas, item.rect.topLeft);
      canvas.restore();
      painter.dispose();
  }
}

/// Draws a page background (REQ-09) under everything else.
ImageShader? _grain;

/// A 96 px tile of chalk grain: mostly opaque with small gaps, drawn once.
ImageShader chalkGrain() {
  final cached = _grain;
  if (cached != null) return cached;
  const size = 96;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  final random = Random(29);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 96),
    Paint()..color = const Color(0xE6FFFFFF),
  );
  final hole = Paint()..blendMode = BlendMode.clear;
  for (var i = 0; i < 420; i++) {
    canvas.drawCircle(
      Offset(random.nextDouble() * size, random.nextDouble() * size),
      0.4 + random.nextDouble() * 1.1,
      hole,
    );
  }
  final image = recorder.endRecording().toImageSync(size, size);
  return _grain = ImageShader(
    image,
    TileMode.repeated,
    TileMode.repeated,
    Matrix4.identity().storage,
  );
}

void paintBackground(Canvas canvas, PageBackground? bg, MediaImages? media) {
  if (bg == null) return;
  _paintPicture(canvas, bg.file, bg.rect, media);
}

void _paintPicture(Canvas canvas, String file, Rect rect, MediaImages? media) {
  final image = media?.get(file);
  if (image == null) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.border,
    );
    return;
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium,
  );
}
