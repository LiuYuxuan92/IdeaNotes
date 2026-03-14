import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart' as sqlite3_open;
import 'package:idea_notes/features/canvas/canvas_screen.dart';
import 'package:idea_notes/features/canvas/services/canvas_save_service.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
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

Future<void> _setLargeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  tester.view.devicePixelRatio = 1.0;
}

Future<void> _resetSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(null);
  tester.view.resetDevicePixelRatio();
}

Future<void> _insertNote({
  required String id,
  required String recognizedText,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await DatabaseHelper.instance.insertNote({
    'id': id,
    'notebook_id': 'default-notebook',
    'created_at': now,
    'updated_at': now,
    'canvas_data': null,
    'snapshot_image_path': null,
    'thumbnail_image_path': null,
    'recognized_text': recognizedText,
  });
}

void main() {
  setUpAll(() {
    databaseFactory = _testDatabaseFactory;
  });

  group('CanvasScreen widget', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    testWidgets('初始状态显示手写笔记页面与 OCR 提示', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      expect(find.text('新建手写笔记'), findsOneWidget);
      expect(find.text('识别结果'), findsOneWidget);
      expect(find.byIcon(Icons.text_snippet_outlined), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    });

    testWidgets('无识别结果时点击编辑按钮不会打开编辑弹窗', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('编辑识别文本'), findsNothing);
    });

    testWidgets('有识别结果时可以打开编辑弹窗', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await _insertNote(id: 'note-edit', recognizedText: '旧识别结果');

      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen(noteId: 'note-edit')),
      );
      await tester.pumpAndSettle();

      expect(find.text('旧识别结果'), findsWidgets);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('编辑识别文本'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('编辑后 OCR 结果区域内容更新', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await _insertNote(id: 'note-update', recognizedText: '旧识别结果');

      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen(noteId: 'note-update')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, '新的 OCR 文本');
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      expect(find.text('编辑识别文本'), findsNothing);
      expect(find.text('新的 OCR 文本'), findsWidgets);
    });

    testWidgets('点击清除按钮会弹出确认框', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_sweep_rounded));
      await tester.pumpAndSettle();

      expect(find.text('清空整张画布？'), findsOneWidget);
      expect(find.text('这会移除当前所有笔迹。如果只是写错一点，建议先用撤销或橡皮。'), findsOneWidget);
      expect(find.text('继续保留'), findsOneWidget);
      expect(find.text('确认清空'), findsOneWidget);
    });

    testWidgets('工具栏显示撤销/重做与清除入口', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      expect(find.byIcon(Icons.redo_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_rounded), findsOneWidget);
    });

    testWidgets('保存编辑后的 OCR 文本会更新数据库 note 内容', (tester) async {
      await _setLargeSurface(tester);
      addTearDown(() => _resetSurface(tester));
      await _insertNote(id: 'note-save-db', recognizedText: '旧识别结果');

      await tester.pumpWidget(
        MaterialApp(
          home: CanvasScreen(
            noteId: 'note-save-db',
            captureCanvasForSave: () async => Uint8List.fromList([1, 2, 3]),
            captureThumbnailForSave: () async => Uint8List.fromList([4, 5, 6]),
            saveServiceOverride: CanvasSaveService(
              databaseHelper: DatabaseHelper.instance,
              saveSnapshot: (_, noteId) async => '/tmp/$noteId-snapshot.png',
              saveThumbnail: (_, noteId) async => '/tmp/$noteId-thumb.png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '记得买牛奶');
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('保存当前笔记'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final note = await DatabaseHelper.instance.getNote('note-save-db');
      final entries = await DatabaseHelper.instance.getNoteEntries('note-save-db');

      expect(note, isNotNull);
      expect(note!['recognized_text'], '记得买牛奶');
      expect(entries.length, 1);
      expect(entries.first['raw_text'], '记得买牛奶');
      expect(entries.first['type'], 'event');
    });

  });
}
