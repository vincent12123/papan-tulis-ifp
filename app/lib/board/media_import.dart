import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../canvas/media_images.dart';
import '../canvas/stroke.dart';
import '../data/media_store.dart';
import 'board_document.dart';

/// A file the teacher picked from the panel's storage (P-06).
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;

  bool get isPdf => p.extension(name).toLowerCase() == '.pdf';
}

abstract interface class FileSource {
  /// A picture for Gambar; null when the teacher cancels.
  Future<PickedFile?> pickImage();

  /// A PDF or picture for Pasang latar; null when cancelled.
  Future<PickedFile?> pickBackground();
}

/// Android's own file picker, reading from the panel's storage.
class DeviceFileSource implements FileSource {
  const DeviceFileSource();

  static const imageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

  Future<PickedFile?> _pick(List<String> extensions) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return PickedFile(file.name, await file.xFile.readAsBytes());
  }

  @override
  Future<PickedFile?> pickImage() => _pick(imageExtensions);

  @override
  Future<PickedFile?> pickBackground() => _pick(['pdf', ...imageExtensions]);
}

/// The PDF is protected with a password.
class PdfLockedException implements Exception {
  const PdfLockedException();
}

/// The file is not a readable PDF or picture.
class UnreadableFileException implements Exception {
  const UnreadableFileException();
}

/// Rendered PDF pages as PNG, plus the total page count.
typedef PdfPages = ({int total, List<Uint8List> pages});

abstract interface class PdfRasterizer {
  Future<PdfPages> render(Uint8List pdf, {required int maxPages});
}

/// Renders with Android's built-in PdfRenderer (no Google services needed).
class DevicePdfRasterizer implements PdfRasterizer {
  DevicePdfRasterizer(this.tempDir);

  final Directory tempDir;

  /// Rendered width in pixels: sharp on a 4K panel without huge files.
  static const pageWidth = 2400.0;

  @override
  Future<PdfPages> render(Uint8List pdf, {required int maxPages}) async {
    await tempDir.create(recursive: true);
    final temp = File(
      p.join(
        tempDir.path,
        'impor-${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    await temp.writeAsBytes(pdf, flush: true);
    PdfDocument? doc;
    try {
      try {
        doc = await PdfDocument.openFile(temp.path);
      } catch (e) {
        // Android reports protected PDFs as a security/renderer error.
        final text = e.toString().toLowerCase();
        if (text.contains('password') || text.contains('security')) {
          throw const PdfLockedException();
        }
        throw const UnreadableFileException();
      }
      final count = doc.pagesCount < maxPages ? doc.pagesCount : maxPages;
      final pages = <Uint8List>[];
      for (var i = 1; i <= count; i++) {
        final page = await doc.getPage(i);
        try {
          final scale = pageWidth / page.width;
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (image == null) throw const UnreadableFileException();
          pages.add(image.bytes);
        } finally {
          await page.close();
        }
      }
      return (total: doc.pagesCount, pages: pages);
    } finally {
      await doc?.close();
      if (await temp.exists()) await temp.delete();
    }
  }
}

sealed class ImportResult {}

class ImportCancelled extends ImportResult {}

/// The file could not be used; [name] is shown in the message.
class ImportRejected extends ImportResult {
  ImportRejected(this.name, {this.locked = false});
  final String name;
  final bool locked;
}

class ImageInserted extends ImportResult {}

/// Background set on [pageCount] pages starting at page [firstPage]
/// (1-based). [truncatedFrom] is the PDF's page count when it had more than
/// the limit.
class BackgroundSet extends ImportResult {
  BackgroundSet({
    required this.firstPage,
    required this.pageCount,
    required this.name,
    this.truncatedFrom,
  });
  final int firstPage;
  final int pageCount;
  final String name;
  final int? truncatedFrom;
}

/// Puts pictures and backgrounds on the board (REQ-07, REQ-09).
class MediaImporter {
  MediaImporter({
    required this.doc,
    required this.store,
    required this.files,
    required this.pdf,
  });

  final BoardDocument doc;
  final MediaStore store;
  final FileSource files;
  final PdfRasterizer pdf;

  /// PDF background limit (P-13).
  static const maxPdfPages = 5;

  /// Largest share of the visible area a newly inserted picture takes.
  static const insertShare = 0.6;

  /// Picks a picture and places it in the middle of [visible] (canvas
  /// coordinates), then selects it so it can be moved right away.
  Future<ImportResult> insertImage(Rect visible) async {
    final file = await files.pickImage();
    if (file == null) return ImportCancelled();
    final Image image;
    try {
      image = await decodeImage(file.bytes);
    } catch (_) {
      return ImportRejected(file.name);
    }
    final name = await store.save(file.bytes, _extension(file.name));
    doc.images.put(name, image);
    final area = Rect.fromCenter(
      center: visible.center,
      width: visible.width * insertShare,
      height: visible.height * insertShare,
    );
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rect = size.width <= area.width && size.height <= area.height
        ? Rect.fromCenter(
            center: visible.center,
            width: size.width,
            height: size.height,
          )
        : fitInside(size, area);
    final ink = doc.page.ink;
    final item = ImageItem(id: ink.newId(), file: name, rect: rect);
    ink.addItem(item);
    ink.select(item.id);
    return ImageInserted();
  }

  /// Picks a PDF or picture as background for the open page. A PDF's
  /// further pages (up to [maxPdfPages]) become new pages after it.
  /// [visible] is the open page's visible area; [screen] the canvas size for
  /// new pages.
  Future<ImportResult> setBackground(Rect visible, Size screen) async {
    final file = await files.pickBackground();
    if (file == null) return ImportCancelled();
    final firstPage = doc.current.value + 1;
    if (!file.isPdf) {
      final Image image;
      try {
        image = await decodeImage(file.bytes);
      } catch (_) {
        return ImportRejected(file.name);
      }
      final name = await store.save(file.bytes, _extension(file.name));
      doc.images.put(name, image);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      doc.setBackground(
        doc.current.value,
        PageBackground(file: name, rect: fitInside(size, visible)),
      );
      return BackgroundSet(firstPage: firstPage, pageCount: 1, name: file.name);
    }

    final PdfPages rendered;
    try {
      rendered = await pdf.render(file.bytes, maxPages: maxPdfPages);
    } on PdfLockedException {
      return ImportRejected(file.name, locked: true);
    } catch (_) {
      return ImportRejected(file.name);
    }
    if (rendered.pages.isEmpty) return ImportRejected(file.name);
    final backgrounds = <PageBackground>[];
    for (var i = 0; i < rendered.pages.length; i++) {
      final bytes = rendered.pages[i];
      final image = await decodeImage(bytes);
      final name = await store.save(bytes, 'png');
      doc.images.put(name, image);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final area = i == 0 ? visible : Offset.zero & screen;
      backgrounds.add(PageBackground(file: name, rect: fitInside(size, area)));
    }
    final count = doc.addBackgroundPages(backgrounds);
    return BackgroundSet(
      firstPage: firstPage,
      pageCount: count,
      name: file.name,
      truncatedFrom: rendered.total > maxPdfPages ? rendered.total : null,
    );
  }

  static String _extension(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? 'png' : ext;
  }
}
