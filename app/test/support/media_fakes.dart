import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:whiteboard_ifp/board/media_import.dart';
import 'package:whiteboard_ifp/data/media_store.dart';

/// 40×20 red PNG.
final Uint8List wideRedPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nGO4o6Y2IIhh1OJRi0ctHrV41OJRi0ctHrV45FgMAFSNnS6UOhs6AAAAAElFTkSuQmCC',
);

/// 30×40 blue PNG.
final Uint8List tallBluePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAB4AAAAoCAIAAABmcd1FAAAALElEQVR4nO3MQQkAAAgEsCtiJfMbxxQ+hMHeS/UciVqtVqvVarVarVar/9cLIg3qXKDo0aQAAAAASUVORK5CYII=',
);

/// Media store kept in memory.
class MemoryMediaStore extends MediaStore {
  MemoryMediaStore() : super(Directory('tidak-dipakai'));

  final Map<String, Uint8List> files = {};
  int _n = 0;

  @override
  Future<String> save(Uint8List bytes, String extension) async {
    final name = 'media-${_n++}.$extension';
    files[name] = bytes;
    return name;
  }

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<int> collectGarbage(Set<String> keep) async {
    final before = files.length;
    files.removeWhere((k, _) => !keep.contains(k));
    return before - files.length;
  }
}

/// Returns whatever the test queues next; null = cancelled.
class FakeFileSource implements FileSource {
  PickedFile? nextImage;
  PickedFile? nextBackground;

  @override
  Future<PickedFile?> pickImage() async => nextImage;

  @override
  Future<PickedFile?> pickBackground() async => nextBackground;
}

/// Pretends to render a PDF with [total] pages.
class FakePdfRasterizer implements PdfRasterizer {
  int total = 1;
  bool locked = false;
  bool broken = false;
  int? lastMaxPages;

  @override
  Future<PdfPages> render(Uint8List pdf, {required int maxPages}) async {
    lastMaxPages = maxPages;
    if (locked) throw const PdfLockedException();
    if (broken) throw const UnreadableFileException();
    final count = total < maxPages ? total : maxPages;
    return (total: total, pages: [for (var i = 0; i < count; i++) wideRedPng]);
  }
}
