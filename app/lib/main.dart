import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_shell.dart';
import 'board/media_import.dart';
import 'board/page_thumbnail.dart';
import 'data/app_database.dart';
import 'data/board_repository.dart';
import 'data/media_store.dart';
import 'server/settings_store.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(WhiteboardApp(repository: _openRepository()));
}

Future<Directory> _supportDir() => getApplicationSupportDirectory();

Future<BoardRepository> _openRepository() async {
  final dir = await getDatabasesPath();
  final db = await AppDatabase.open(
    factory: databaseFactory,
    mainPath: p.join(dir, 'papan.db'),
    snapshotPath: p.join(dir, 'salinan.db'),
  );
  return BoardRepository(db);
}

class WhiteboardApp extends StatelessWidget {
  const WhiteboardApp({super.key, required this.repository});

  final Future<BoardRepository> repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papan Tulis',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppShell(
        repository: repository,
        renderThumbnail: renderThumbnailPng,
        media: _supportDir().then(
          (dir) => MediaStore(Directory(p.join(dir.path, 'media'))),
        ),
        pdf: DevicePdfRasterizer(Directory.systemTemp),
        settingsFor: DeviceSettingsStore.new,
      ),
    );
  }
}
