import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:idea_notes/features/canvas/canvas_screen.dart';
import 'package:idea_notes/features/canvas/bloc/canvas_bloc.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
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
  group('CanvasScreen widget', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    testWidgets('初始状态显示手写笔记页面与 OCR 提示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      expect(find.text('手写笔记'), findsOneWidget);
      expect(find.text('OCR 识别结果'), findsOneWidget);
      expect(find.text('点击 OCR 按钮识别手写内容'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera), findsOneWidget);
      expect(find.byIcon(Icons.save), findsOneWidget);
    });

    testWidgets('点击编辑按钮在无识别结果时不会打开编辑弹窗', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      expect(find.text('编辑识别结果'), findsNothing);
    });

    testWidgets('工具栏显示撤销/重做与清除入口', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CanvasScreen()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.redo), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });
}
