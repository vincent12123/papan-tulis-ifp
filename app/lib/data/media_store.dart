import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../canvas/stroke.dart';

/// Picture and background files copied into the app's own storage, so a
/// board stays intact when the original file on the panel is deleted
/// (SPEC 5.4). The database stores only the file name.
class MediaStore {
  MediaStore(this.dir, {IdGenerator? ids}) : _ids = ids ?? IdGenerator();

  final Directory dir;
  final IdGenerator _ids;

  File file(String name) => File(p.join(dir.path, p.basename(name)));

  /// Saves [bytes] under a new unique name with [extension] (e.g. `png`).
  Future<String> save(Uint8List bytes, String extension) async {
    await dir.create(recursive: true);
    final name = '${_ids.next()}.${extension.toLowerCase()}';
    await file(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<Uint8List?> read(String name) async {
    final f = file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Deletes files no board or automatic copy refers to. Returns how many.
  Future<int> collectGarbage(Set<String> keep) async {
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is File && !keep.contains(p.basename(entity.path))) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }
}
