import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/features/notedetail/note_detail_screen.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
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
      version: kDatabaseVersion,
      onCreate: createDatabaseSchema,
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

    testWidgets('优先展示结构化条目与 AI 审计信息', (tester) async {
      final now = DateTime(2026, 3, 21, 9, 30);
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
        'id': 'legacy-entry-1',
        'note_id': note.id,
        'type': 'memo',
        'raw_text': '旧版解析结果',
        'amount': null,
        'category': null,
        'event_title': null,
        'event_date': null,
        'is_completed': 0,
        'memo_text': '旧版解析结果',
        'created_at': now.millisecondsSinceEpoch,
      });

      final db = await DatabaseHelper.instance.database;
      await db.insert('entries', {
        'id': 'entry-1',
        'note_id': note.id,
        'entry_type': 'task',
        'domain': 'life',
        'occurred_at': now.millisecondsSinceEpoch,
        'occurred_date': '2026-03-21',
        'end_at': null,
        'title': '买牛奶',
        'summary': '提醒去超市买牛奶',
        'raw_text': '记得买牛奶',
        'normalized_json': '{}',
        'amount_value': null,
        'amount_currency': null,
        'category_l1': '生活',
        'category_l2': '采购',
        'status': 'pending',
        'confidence': 0.96,
        'is_user_confirmed': 0,
        'source_engine': 'rule+ai',
        'source_version': '1.0',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      await db.insert('ai_extractions', {
        'id': 'ai-1',
        'note_id': note.id,
        'engine_name': 'deepseek',
        'engine_model': 'deepseek-chat',
        'prompt_version': '1.0',
        'input_text': '记得买牛奶',
        'raw_response_json': '{}',
        'normalized_entries_json': '{"entries":[]}',
        'status': 'success',
        'created_at': now.millisecondsSinceEpoch,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: NoteDetailScreen(note: note),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('解析结果'), findsWidgets);
      expect(find.text('买牛奶'), findsOneWidget);
      expect(find.text('规则 + AI'), findsOneWidget);
      expect(find.text('deepseek-chat'), findsWidgets);
      expect(find.text('识别文本'), findsOneWidget);
      expect(find.text('旧版解析结果'), findsNothing);
    });

    testWidgets('结构化健康记录会展示记录与健康标签', (tester) async {
      final now = DateTime(2026, 3, 21, 9, 30);
      final note = Note(
        id: 'note-health-tags',
        notebookId: 'default-notebook',
        createdAt: now,
        updatedAt: now,
        recognizedText: '今天吃了牛肉',
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

      final db = await DatabaseHelper.instance.database;
      await db.insert('entries', {
        'id': 'entry-health-1',
        'note_id': note.id,
        'entry_type': 'health_record',
        'domain': 'health',
        'occurred_at': now.millisecondsSinceEpoch,
        'occurred_date': '2026-03-21',
        'end_at': null,
        'title': '今天吃了牛肉',
        'summary': '饮食记录',
        'raw_text': '今天吃了牛肉',
        'normalized_json': '{}',
        'amount_value': null,
        'amount_currency': null,
        'category_l1': '健康',
        'category_l2': '饮食',
        'status': 'recorded',
        'confidence': 0.9,
        'is_user_confirmed': 0,
        'source_engine': 'rule-parser',
        'source_version': '1.0',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      await db.insert('entry_tags', {
        'id': 'tag-1',
        'entry_id': 'entry-health-1',
        'tag': '记录',
        'created_at': now.millisecondsSinceEpoch,
      });
      await db.insert('entry_tags', {
        'id': 'tag-2',
        'entry_id': 'entry-health-1',
        'tag': '健康',
        'created_at': now.millisecondsSinceEpoch,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: NoteDetailScreen(note: note),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('今天吃了牛肉'), findsWidgets);
      expect(find.text('记录'), findsWidgets);
      expect(find.text('健康'), findsWidgets);
      expect(find.textContaining('1 条健康'), findsWidgets);
      expect(find.textContaining('1 条记录'), findsWidgets);
    });
  });
}
