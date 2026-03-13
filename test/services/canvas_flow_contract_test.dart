import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/features/canvas/services/canvas_load_service.dart';
import 'package:idea_notes/features/canvas/services/canvas_save_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _setUpInMemoryDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  try {
    await DatabaseHelper.instance.close();
  } catch (_) {}

  final db = await databaseFactoryFfi.openDatabase(
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
  group('Canvas flow contract', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('save 后再 load，note 与 entry 数据保持一致', () async {
      final saveService = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'flow-note-1',
        saveSnapshot: (_, noteId) async => '/tmp/$noteId-snapshot.png',
        saveThumbnail: (_, noteId) async => '/tmp/$noteId-thumb.png',
      );
      final loadService = CanvasLoadService(databaseHelper: DatabaseHelper.instance);

      final now = DateTime(2026, 3, 13, 17, 10);
      await saveService.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([1, 2, 3, 4]),
          snapshotBytes: Uint8List.fromList([7, 7]),
          thumbnailBytes: Uint8List.fromList([8, 8]),
          recognizedText: '买菜 35.5\n记得买牛奶',
          now: now,
        ),
      );

      final loaded = await loadService.load('flow-note-1');
      final entryMaps = await DatabaseHelper.instance.getNoteEntries('flow-note-1');

      expect(loaded.note, isNotNull);
      expect(loaded.note!.snapshotImagePath, '/tmp/flow-note-1-snapshot.png');
      expect(loaded.note!.thumbnailImagePath, '/tmp/flow-note-1-thumb.png');
      expect(loaded.ocrResult, '买菜 35.5\n记得买牛奶');
      expect(loaded.canvasData, Uint8List.fromList([1, 2, 3, 4]));

      expect(entryMaps.length, 2);
      expect(entryMaps[0]['type'], 'expense');
      expect(entryMaps[0]['raw_text'], '买菜 35.5');
      expect(entryMaps[1]['type'], 'event');
      expect(entryMaps[1]['raw_text'], '记得买牛奶');
    });
  });
}
