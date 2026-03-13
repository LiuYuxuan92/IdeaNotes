import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
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
  group('CanvasSaveService', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('创建新 note 时会写入 note 与 entries', () async {
      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'note-new-1',
        saveSnapshot: (_, noteId) async => '/tmp/$noteId-snapshot.png',
        saveThumbnail: (_, noteId) async => '/tmp/$noteId-thumb.png',
      );

      final saved = await service.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([1, 2, 3]),
          snapshotBytes: Uint8List.fromList([1]),
          thumbnailBytes: Uint8List.fromList([2]),
          recognizedText: '记得买牛奶',
          now: DateTime(2026, 3, 13, 12, 0),
        ),
      );

      expect(saved.id, 'note-new-1');
      expect(saved.snapshotImagePath, '/tmp/note-new-1-snapshot.png');
      expect(saved.thumbnailImagePath, '/tmp/note-new-1-thumb.png');
      expect(saved.recognizedText, '记得买牛奶');

      final noteMap = await DatabaseHelper.instance.getNote('note-new-1');
      expect(noteMap, isNotNull);
      expect(noteMap!['thumbnail_image_path'], '/tmp/note-new-1-thumb.png');

      final entries = await DatabaseHelper.instance.getNoteEntries('note-new-1');
      expect(entries, isNotEmpty);
      expect(entries.first['type'], 'event');
    });

    test('更新已有 note 时会替换旧 entries 并保留旧图路径回退', () async {
      final now = DateTime(2026, 3, 13, 12, 0);
      await DatabaseHelper.instance.insertNote({
        'id': 'note-existing',
        'notebook_id': 'default-notebook',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': Uint8List.fromList([9]),
        'snapshot_image_path': '/tmp/old-snapshot.png',
        'thumbnail_image_path': '/tmp/old-thumb.png',
        'recognized_text': '旧文本',
      });
      await DatabaseHelper.instance.insertNoteEntry({
        'id': 'old-entry',
        'note_id': 'note-existing',
        'type': 'memo',
        'raw_text': '旧文本',
        'amount': null,
        'category': null,
        'event_title': null,
        'event_date': null,
        'is_completed': 0,
        'memo_text': '旧文本',
        'created_at': now.millisecondsSinceEpoch,
      });

      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        saveSnapshot: (_, noteId) async => '/tmp/$noteId-new-snapshot.png',
        saveThumbnail: (_, noteId) async => null,
      );

      final existing = Note(
        id: 'note-existing',
        notebookId: 'default-notebook',
        createdAt: now,
        updatedAt: now,
        snapshotImagePath: '/tmp/old-snapshot.png',
        thumbnailImagePath: '/tmp/old-thumb.png',
        recognizedText: '旧文本',
      );

      final saved = await service.save(
        CanvasSaveInput(
          existingNote: existing,
          canvasData: Uint8List.fromList([4, 5, 6]),
          snapshotBytes: Uint8List.fromList([7]),
          thumbnailBytes: Uint8List.fromList([8]),
          recognizedText: '买菜 35.5',
          now: DateTime(2026, 3, 13, 13, 0),
        ),
      );

      expect(saved.id, 'note-existing');
      expect(saved.snapshotImagePath, '/tmp/note-existing-new-snapshot.png');
      expect(saved.thumbnailImagePath, '/tmp/old-thumb.png');

      final entries = await DatabaseHelper.instance.getNoteEntries('note-existing');
      expect(entries.length, 1);
      expect(entries.first['raw_text'], '买菜 35.5');
      expect(entries.first['type'], 'expense');
    });

    test('识别文本为空时会清空旧 entries 且不新增', () async {
      final now = DateTime(2026, 3, 13, 12, 0);
      await DatabaseHelper.instance.insertNote({
        'id': 'note-empty-text',
        'notebook_id': 'default-notebook',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': Uint8List.fromList([1]),
        'snapshot_image_path': null,
        'thumbnail_image_path': null,
        'recognized_text': '旧文本',
      });
      await DatabaseHelper.instance.insertNoteEntry({
        'id': 'old-entry-2',
        'note_id': 'note-empty-text',
        'type': 'memo',
        'raw_text': '旧文本',
        'amount': null,
        'category': null,
        'event_title': null,
        'event_date': null,
        'is_completed': 0,
        'memo_text': '旧文本',
        'created_at': now.millisecondsSinceEpoch,
      });

      final service = CanvasSaveService(databaseHelper: DatabaseHelper.instance);
      final existing = Note(
        id: 'note-empty-text',
        notebookId: 'default-notebook',
        createdAt: now,
        updatedAt: now,
        recognizedText: '旧文本',
      );

      await service.save(
        CanvasSaveInput(
          existingNote: existing,
          canvasData: Uint8List.fromList([2, 3]),
          snapshotBytes: null,
          thumbnailBytes: null,
          recognizedText: '   ',
          now: DateTime(2026, 3, 13, 14, 0),
        ),
      );

      final entries = await DatabaseHelper.instance.getNoteEntries('note-empty-text');
      expect(entries, isEmpty);
    });
  });
}
