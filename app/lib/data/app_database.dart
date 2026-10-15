import 'package:sqflite/sqflite.dart';

/// Opens the two SQLite files used on the panel:
/// - the main database with boards, pages, and objects (SPEC §4.1–4.3);
/// - a separate snapshot database holding the last automatic copy of each
///   board, so a damaged main file does not take the copy with it
///   (SPEC 5.3, NFR-05).
class AppDatabase {
  AppDatabase._(this.main, this.snapshots);

  final Database main;
  final Database snapshots;

  /// Board storage format version. Bump with a migration in [_upgradeMain]
  /// so a newer APK still opens boards saved by an older one (SPEC §8A.2).
  static const mainVersion = 1;
  static const snapshotVersion = 1;

  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String mainPath,
    required String snapshotPath,
  }) async {
    final main = await factory.openDatabase(
      mainPath,
      options: OpenDatabaseOptions(
        version: mainVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createMain(db),
        onUpgrade: _upgradeMain,
      ),
    );
    final snapshots = await factory.openDatabase(
      snapshotPath,
      options: OpenDatabaseOptions(
        version: snapshotVersion,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE snapshots (
            board_id TEXT PRIMARY KEY,
            taken_at TEXT NOT NULL,
            data TEXT NOT NULL
          )'''),
      ),
    );
    return AppDatabase._(main, snapshots);
  }

  static Future<void> _createMain(Database db) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE boards (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_page INTEGER NOT NULL DEFAULT 1,
          thumbnail BLOB
        )''')
      ..execute('''
        CREATE TABLE pages (
          id TEXT PRIMARY KEY,
          board_id TEXT NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          background TEXT,
          view_x REAL NOT NULL DEFAULT 0,
          view_y REAL NOT NULL DEFAULT 0,
          view_zoom REAL NOT NULL DEFAULT 1
        )''')
      ..execute('CREATE INDEX pages_board ON pages(board_id, position)')
      ..execute('''
        CREATE TABLE objects (
          id TEXT PRIMARY KEY,
          page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          data TEXT NOT NULL,
          z INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX objects_page ON objects(page_id, z)')
      ..execute('''
        CREATE TABLE app_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )''');
    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeMain(Database db, int from, int to) async {
    // No migrations yet: version 1 is the first format.
  }

  Future<void> close() async {
    await main.close();
    await snapshots.close();
  }
}
