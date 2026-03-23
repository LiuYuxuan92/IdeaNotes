import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/features/canvas/services/canvas_save_service.dart';
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
      version: kDatabaseVersion,
      onCreate: createDatabaseSchema,
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

      final entries =
          await DatabaseHelper.instance.getNoteEntries('note-new-1');
      expect(entries, isNotEmpty);
      expect(entries.first['type'], 'event');

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-new-1'],
      );
      expect(structuredEntries, isNotEmpty);
      expect(structuredEntries.first['entry_type'], 'task');
      expect(structuredEntries.first['source_engine'], 'rule-parser');
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

      final entries =
          await DatabaseHelper.instance.getNoteEntries('note-existing');
      expect(entries.length, 1);
      expect(entries.first['raw_text'], '买菜 35.5');
      expect(entries.first['type'], 'expense');

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-existing'],
        orderBy: 'created_at ASC',
      );
      expect(structuredEntries.length, 1);
      expect(structuredEntries.first['entry_type'], 'expense');
      expect(structuredEntries.first['domain'], 'finance');
      expect(structuredEntries.first['amount_value'], '35.5');
    });

    test('健康类 memo 会写成可查询的结构化疫苗记录', () async {
      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'note-vaccine-1',
      );

      await service.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([5, 6, 7]),
          snapshotBytes: null,
          thumbnailBytes: null,
          recognizedText: '宝宝今天打了疫苗',
          now: DateTime(2026, 3, 20, 9, 30),
        ),
      );

      final db = await DatabaseHelper.instance.database;
      final legacyEntries =
          await DatabaseHelper.instance.getNoteEntries('note-vaccine-1');
      expect(legacyEntries.length, 1);
      expect(legacyEntries.first['type'], 'health');

      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-vaccine-1'],
      );
      expect(structuredEntries.length, 1);
      expect(structuredEntries.first['entry_type'], 'vaccination');
      expect(structuredEntries.first['domain'], 'health');
      expect(structuredEntries.first['category_l1'], '医疗');
      expect(structuredEntries.first['category_l2'], '疫苗');

      final entryId = structuredEntries.first['id'] as String;
      final subjects = await db.query(
        'entry_subjects',
        where: 'entry_id = ?',
        whereArgs: [entryId],
      );
      final tags = await db.query(
        'entry_tags',
        where: 'entry_id = ?',
        whereArgs: [entryId],
      );

      expect(subjects.length, 1);
      expect(subjects.first['subject_name'], '宝宝');
      expect(
        tags.map((row) => row['tag']).toSet(),
        {'记录', '健康', '宝宝', '疫苗'},
      );
    });

    test('健康花费会同时保留 expense 与派生的健康记录', () async {
      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'note-vaccine-expense-1',
      );

      await service.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([8, 9, 10]),
          snapshotBytes: null,
          thumbnailBytes: null,
          recognizedText: '宝宝打疫苗 128元',
          now: DateTime(2026, 3, 20, 10, 0),
        ),
      );

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-vaccine-expense-1'],
      );

      expect(structuredEntries.length, 2);
      expect(
        structuredEntries.map((row) => row['entry_type']).toSet(),
        {'expense', 'vaccination'},
      );

      final vaccinationEntry = structuredEntries.singleWhere(
        (row) => row['entry_type'] == 'vaccination',
      );
      expect(vaccinationEntry['domain'], 'health');
      expect(vaccinationEntry['amount_value'], isNull);
    });

    test('排便类文本会保留为 health 并写入健康结构化记录', () async {
      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'note-health-1',
      );

      await service.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([11, 12, 13]),
          snapshotBytes: null,
          thumbnailBytes: null,
          recognizedText: '今天拉屎了',
          now: DateTime(2026, 3, 20, 11, 0),
        ),
      );

      final legacyEntries =
          await DatabaseHelper.instance.getNoteEntries('note-health-1');
      expect(legacyEntries.length, 1);
      expect(legacyEntries.first['type'], 'health');

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-health-1'],
      );

      expect(structuredEntries.length, 1);
      expect(structuredEntries.first['entry_type'], 'health_record');
      expect(structuredEntries.first['domain'], 'health');
      expect(structuredEntries.first['category_l1'], '健康');
      expect(structuredEntries.first['category_l2'], '排便');

      final tags = await db.query(
        'entry_tags',
        where: 'entry_id = ?',
        whereArgs: [structuredEntries.first['id']],
      );
      expect(
        tags.map((row) => row['tag']).toSet(),
        {'记录', '健康', '排便'},
      );
    });

    test('饮食记录会同时保留健康与记录标签', () async {
      final service = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'note-diet-1',
      );

      await service.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([21, 22, 23]),
          snapshotBytes: null,
          thumbnailBytes: null,
          recognizedText: '今天吃了牛肉',
          now: DateTime(2026, 3, 20, 12, 0),
        ),
      );

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-diet-1'],
      );

      expect(structuredEntries.length, 1);
      expect(structuredEntries.first['entry_type'], 'health_record');
      expect(structuredEntries.first['domain'], 'health');

      final tags = await db.query(
        'entry_tags',
        where: 'entry_id = ?',
        whereArgs: [structuredEntries.first['id']],
      );
      expect(
        tags.map((row) => row['tag']).toSet(),
        {'记录', '健康', '饮食'},
      );
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

      final service =
          CanvasSaveService(databaseHelper: DatabaseHelper.instance);
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

      final entries =
          await DatabaseHelper.instance.getNoteEntries('note-empty-text');
      expect(entries, isEmpty);

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['note-empty-text'],
      );
      expect(structuredEntries, isEmpty);
    });
  });
}
