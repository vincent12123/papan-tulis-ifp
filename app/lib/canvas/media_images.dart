import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'stroke.dart';

/// Decoded pictures for drawing, loaded on first use. [revision] is bumped
/// when a picture finishes loading so painters can redraw.
class MediaImages {
  MediaImages(this._load);

  final Future<Uint8List?> Function(String name) _load;
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  final ValueNotifier<int> revision = ValueNotifier(0);
  bool _disposed = false;

  /// The decoded picture, or null while it loads or if it cannot be read.
  ui.Image? get(String name) {
    final image = _images[name];
    if (image == null && !_loading.contains(name) && !_failed.contains(name)) {
      _fetch(name);
    }
    return image;
  }

  /// Size of a decoded picture already in memory.
  ui.Image? peek(String name) => _images[name];

  /// Registers a picture that was just decoded (e.g. right after insert).
  void put(String name, ui.Image image) {
    _images[name]?.dispose();
    _images[name] = image;
    revision.value++;
  }

  Future<void> _fetch(String name) async {
    _loading.add(name);
    try {
      final bytes = await _load(name);
      if (bytes == null) throw StateError('tidak ada');
      final image = await decodeImage(bytes);
      if (_disposed) {
        image.dispose();
        return;
      }
      _images[name] = image;
      revision.value++;
    } catch (_) {
      _failed.add(name);
    } finally {
      _loading.remove(name);
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    revision.dispose();
  }
}

/// Decodes PNG/JPG/WebP bytes; throws when the bytes are not a picture.
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// A PDF page or picture behind a page's ink (SPEC §4.2 latar, REQ-09).
/// Never touched by the eraser.
class PageBackground {
  const PageBackground({required this.file, required this.rect});

  final String file;

  /// Where the background sits on the canvas.
  final ui.Rect rect;

  Map<String, Object?> toJson() => {
    'file': file,
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
  };

  /// Returns null when [json] is not a valid background.
  static PageBackground? fromJson(Object? json) {
    if (json is! Map) return null;
    final file = json['file'];
    final values = [json['x'], json['y'], json['w'], json['h']];
    if (file is! String || values.any((v) => v is! num)) return null;
    final v = values.cast<num>();
    return PageBackground(
      file: file,
      rect: ui.Rect.fromLTWH(
        v[0].toDouble(),
        v[1].toDouble(),
        v[2].toDouble(),
        v[3].toDouble(),
      ),
    );
  }
}

/// Fits a picture of [size] inside [area], centered.
ui.Rect fitInside(ui.Size size, ui.Rect area) {
  final scale = (area.width / size.width) < (area.height / size.height)
      ? area.width / size.width
      : area.height / size.height;
  final w = size.width * scale, h = size.height * scale;
  return ui.Rect.fromLTWH(
    area.left + (area.width - w) / 2,
    area.top + (area.height - h) / 2,
    w,
    h,
  );
}

/// Media files an item refers to.
Iterable<String> mediaOf(PageItem item) =>
    item is ImageItem ? [item.file] : const [];
