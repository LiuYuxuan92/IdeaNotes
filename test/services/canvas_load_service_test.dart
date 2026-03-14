import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/features/canvas/services/canvas_load_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


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
  open.overrideForAll(_openSqlite);
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
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('notebooks', {
          'id': 'default-notebook',
          'title': '我的笔记',
          'created_at': now,
          'updated_at': now,
        });
      },
    ),
  );

  DatabaseHelper.injectDatabase(db);
}

void main() {
  group('CanvasLoadService', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('note 不存在时返回空结果', () async {
      final service = CanvasLoadService(databaseHelper: DatabaseHelper.instance);
      final result = await service.load('missing-note');

      expect(result.note, isNull);
      expect(result.canvasData, isNull);
      expect(result.ocrResult, '');
    });

    test('note 存在时返回 note、ocrResult 和 canvasData', () async {
      final now = DateTime(2026, 3, 13, 16, 0).millisecondsSinceEpoch;
      await DatabaseHelper.instance.insertNote({
        'id': 'note-1',
        'notebook_id': 'default-notebook',
        'created_at': now,
        'updated_at': now,
        'canvas_data': Uint8List.fromList([1, 2, 3]),
        'snapshot_image_path': '/tmp/snapshot.png',
        'thumbnail_image_path': '/tmp/thumb.png',
        'recognized_text': '识别结果',
      });

      final service = CanvasLoadService(databaseHelper: DatabaseHelper.instance);
      final result = await service.load('note-1');

      expect(result.note, isNotNull);
      expect(result.note!.id, 'note-1');
      expect(result.note!.thumbnailImagePath, '/tmp/thumb.png');
      expect(result.ocrResult, '识别结果');
      expect(result.canvasData, isNotNull);
      expect(result.canvasData, Uint8List.fromList([1, 2, 3]));
    });
  });
}
