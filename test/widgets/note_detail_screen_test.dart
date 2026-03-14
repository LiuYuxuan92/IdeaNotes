import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/features/notedetail/note_detail_screen.dart';


DynamicLibrary _openSqlite() {
  const candidates = [
    '/usr/lib64/libsqlite3.so.0',
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/lib/x86_64-linux-gnu/libsqlite3.so.0',
    'libsqlite3.so',
  ];

  for (final path in candidates) {
    if (path.startsWith('/') && !File(path).existsSync()) {
      continue;
    }

    try {
      return DynamicLibrary.open(path);
    } catch (_) {}
  }

  throw StateError('Unable to load sqlite3 dynamic library');
}

void _ffiInit() {
  sqlite3_open.open.overrideForAll(_openSqlite);
}

final _testDatabaseFactory = createDatabaseFactoryFfi(
  ffiInit: _ffiInit,
  noIsolate: true,
);

Future<void> _setUpInMemoryDatabase() async {
  databaseFactory = _testDatabaseFactory;

  try {
    await DatabaseHelper.instance.close();
  } catch (_) {}

  final db = await _testDatabaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, version) async {
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
      },
    ),
  );

  DatabaseHelper.injectDatabase(db);
}

void main() {
  setUpAll(() {
    databaseFactory = _testDatabaseFactory;
  });

  group('NoteDetailScreen', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    testWidgets('优先展示数据库中已持久化的结构化条目', (tester) async {
      final now = DateTime.now();
      final note = Note(
        id: 'note-1',
        notebookId: 'default-notebook',
        createdAt: now,
        updatedAt: now,
        recognizedText: '记得买牛奶',
      );

      await DatabaseHelper.instance.insertNote({
        'id': note.id,
        'notebook_id': note.notebookId,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': null,
        'snapshot_image_path': null,
        'thumbnail_image_path': null,
        'recognized_text': note.recognizedText,
      });

      await DatabaseHelper.instance.insertNoteEntry({
        'id': 'entry-1',
        'note_id': note.id,
        'type': 'event',
        'raw_text': '记得买牛奶',
        'amount': null,
        'category': null,
        'event_title': '买牛奶',
        'event_date': null,
        'is_completed': 1,
        'memo_text': null,
        'created_at': now.millisecondsSinceEpoch,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: NoteDetailScreen(note: note),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('解析结果'), findsOneWidget);
      expect(find.text('记得买牛奶'), findsWidgets);
      expect(find.text('识别文本'), findsOneWidget);
    });
  });
}
