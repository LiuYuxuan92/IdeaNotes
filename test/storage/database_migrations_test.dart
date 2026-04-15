import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

Future<void> _createLegacyV3Schema(DatabaseExecutor db) async {
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

Future<bool> _indexExists(Database db, String indexName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ? AND name = ?',
    whereArgs: ['index', indexName],
  );
  return rows.isNotEmpty;
}

void main() {
  group('database migrations', () {
    setUp(() {
      databaseFactory = _databaseFactory;
    });

    test('ffi factory opens an in-memory database on the current platform',
        () async {
      final db = await _databaseFactory.openDatabase(inMemoryDatabasePath);
      final rows = await db.rawQuery('SELECT 1 AS value');

      expect(rows.single['value'], 1);

      await db.close();
    });

    test('create schema version 6 includes structured-data tables and indexes',
        () async {
      final db = await _databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kDatabaseVersion,
          onCreate: createDatabaseSchema,
        ),
      );

      expect(await _tableExists(db, 'entries'), isTrue);
      expect(await _tableExists(db, 'entry_subjects'), isTrue);
      expect(await _tableExists(db, 'entry_tags'), isTrue);
      expect(await _tableExists(db, 'entry_links'), isTrue);
      expect(await _tableExists(db, 'ai_extractions'), isTrue);
      expect(await _tableExists(db, 'saved_filters'), isTrue);
      expect(await _indexExists(db, 'idx_entries_type_date'), isTrue);
      expect(await _indexExists(db, 'idx_entry_subjects_name'), isTrue);

      final notebookRows = await db.query(
        'notebooks',
        where: 'id = ?',
        whereArgs: ['default-notebook'],
      );
      expect(notebookRows.length, 1);

      await db.close();
    });

    test('migrates from v3 to v6 and backfills legacy note_entries', () async {
      final tempDir = await Directory.systemTemp.createTemp('ideanotes-mig-');
      final dbPath = path.join(tempDir.path, 'idea_notes_test.db');
      final createdAt = DateTime(2025, 8, 1, 9, 0).millisecondsSinceEpoch;

      final legacyDb = await _databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await _createLegacyV3Schema(db);
            await db.insert('notebooks', {
              'id': 'default-notebook',
              'title': '我的笔记',
              'created_at': createdAt,
              'updated_at': createdAt,
            });
            await db.insert('notes', {
              'id': 'note-1',
              'notebook_id': 'default-notebook',
              'created_at': createdAt,
              'updated_at': createdAt,
              'recognized_text': '疫苗费用 628元',
            });
            await db.insert('note_entries', {
              'id': 'legacy-entry-1',
              'note_id': 'note-1',
              'type': 'expense',
              'raw_text': '疫苗费用 628元',
              'amount': '628',
              'category': '医疗',
              'event_title': null,
              'event_date': null,
              'is_completed': 0,
              'memo_text': null,
              'created_at': createdAt,
            });
          },
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

      expect(await _tableExists(migratedDb, 'entries'), isTrue);
      expect(await _tableExists(migratedDb, 'saved_filters'), isTrue);

      final entries = await migratedDb.query(
        'entries',
        where: 'id = ?',
        whereArgs: ['legacy-entry-1'],
      );
      expect(entries.length, 1);
      expect(entries.first['entry_type'], 'expense');
      expect(entries.first['domain'], 'finance');
      expect(entries.first['category_l1'], '医疗');
      expect(entries.first['amount_value'], '628');
      expect(entries.first['occurred_date'], '2025-08-01');
      expect(entries.first['source_engine'], 'rule-legacy');

      await migratedDb.close();
      await tempDir.delete(recursive: true);
    });
  });
}
