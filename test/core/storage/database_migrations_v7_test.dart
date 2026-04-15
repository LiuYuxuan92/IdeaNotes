import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

Future<void> _createLegacyV6Schema(DatabaseExecutor db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE notebooks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE notes (
      id TEXT PRIMARY KEY,
      notebook_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      canvas_data BLOB,
      snapshot_image_path TEXT,
      thumbnail_image_path TEXT,
      recognized_text TEXT,
      FOREIGN KEY (notebook_id) REFERENCES notebooks (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE note_entries (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      type TEXT NOT NULL,
      raw_text TEXT NOT NULL,
      amount TEXT,
      category TEXT,
      event_title TEXT,
      event_date INTEGER,
      is_completed INTEGER DEFAULT 0,
      memo_text TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE entries (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      domain TEXT NOT NULL,
      occurred_at INTEGER,
      occurred_date TEXT NOT NULL,
      end_at INTEGER,
      title TEXT NOT NULL,
      summary TEXT,
      raw_text TEXT NOT NULL,
      normalized_json TEXT,
      amount_value TEXT,
      amount_currency TEXT,
      category_l1 TEXT,
      category_l2 TEXT,
      status TEXT,
      confidence REAL,
      is_user_confirmed INTEGER DEFAULT 0,
      source_engine TEXT NOT NULL,
      source_version TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE ai_extractions (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      engine_name TEXT NOT NULL,
      engine_model TEXT NOT NULL,
      prompt_version TEXT NOT NULL,
      input_text TEXT NOT NULL,
      raw_response_json TEXT NOT NULL,
      normalized_entries_json TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE saved_filters (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      filter_json TEXT NOT NULL,
      sort_json TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ? AND name = ?',
    whereArgs: ['table', tableName],
  );
  return rows.isNotEmpty;
}

Future<List<String>> _columnNames(Database db, String tableName) async {
  final rows = await db.rawQuery('PRAGMA table_info($tableName)');
  return rows.map((row) => row['name']! as String).toList();
}

void main() {
  group('database migrations v7', () {
    setUp(() {
      sqfliteFfiInit();
      databaseFactory = _databaseFactory;
    });

    test('database version is bumped to 7', () {
      expect(kDatabaseVersion, 7);
    });

    test(
        'new installs include extraction preview schema and new ai_extractions columns',
        () async {
      final db = await _databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kDatabaseVersion,
          onCreate: createDatabaseSchema,
        ),
      );

      expect(await _tableExists(db, 'extraction_previews'), isTrue);
      final extractionPreviewColumns =
          await _columnNames(db, 'extraction_previews');
      expect(
        extractionPreviewColumns,
        containsAll([
          'id',
          'note_id',
          'raw_text',
          'rule_extraction',
          'ai_extraction',
          'merged_extraction',
          'status',
          'user_correction',
          'created_at',
          'confirmed_at',
        ]),
      );

      final aiExtractionColumns = await _columnNames(db, 'ai_extractions');
      expect(
        aiExtractionColumns,
        containsAll([
          'user_correction',
          'original_extraction',
          'correction_feedback',
        ]),
      );

      await db.close();
    });

    test(
        'migrates from v6 to v7 by adding extraction preview schema and columns',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ideanotes-mig-v7-');
      final dbPath = path.join(tempDir.path, 'idea_notes_test.db');

      final legacyDb = await _databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, _) => _createLegacyV6Schema(db),
        ),
      );
      await legacyDb.close();

      final migratedDb = await _databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: kDatabaseVersion,
          onCreate: createDatabaseSchema,
          onUpgrade: migrateDatabaseSchema,
        ),
      );

      expect(await _tableExists(migratedDb, 'extraction_previews'), isTrue);
      final extractionPreviewColumns = await _columnNames(
        migratedDb,
        'extraction_previews',
      );
      expect(
        extractionPreviewColumns,
        containsAll([
          'id',
          'note_id',
          'raw_text',
          'rule_extraction',
          'ai_extraction',
          'merged_extraction',
          'status',
          'user_correction',
          'created_at',
          'confirmed_at',
        ]),
      );
      final aiExtractionColumns =
          await _columnNames(migratedDb, 'ai_extractions');
      expect(
        aiExtractionColumns,
        containsAll([
          'user_correction',
          'original_extraction',
          'correction_feedback',
        ]),
      );

      await migratedDb.close();
      await tempDir.delete(recursive: true);
    });
  });
}
