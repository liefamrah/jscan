import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'jscan.db');
    _db = await openDatabase(
      dbPath,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE documents(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            page_count INTEGER NOT NULL,
            tag TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE pages(
            id TEXT PRIMARY KEY,
            doc_id TEXT NOT NULL,
            idx INTEGER NOT NULL,
            orig_path TEXT NOT NULL,
            out_path TEXT NOT NULL,
            thumb_path TEXT NOT NULL,
            corners_json TEXT NOT NULL,
            filter TEXT NOT NULL,
            rotation INTEGER NOT NULL,
            brightness REAL NOT NULL DEFAULT 0.0,
            contrast REAL NOT NULL DEFAULT 0.0,
            FOREIGN KEY(doc_id) REFERENCES documents(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_pages_doc_idx ON pages(doc_id, idx)');
        await db.execute('''
          CREATE TABLE settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE categories(
            name TEXT PRIMARY KEY COLLATE NOCASE,
            created_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE documents ADD COLUMN tag TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE pages ADD COLUMN brightness REAL NOT NULL DEFAULT 0.0',
          );
          await db.execute(
            'ALTER TABLE pages ADD COLUMN contrast REAL NOT NULL DEFAULT 0.0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories(
              name TEXT PRIMARY KEY COLLATE NOCASE,
              created_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }
}
