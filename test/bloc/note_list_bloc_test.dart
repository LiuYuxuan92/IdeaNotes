import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:idea_notes/features/notelist/bloc/note_list_bloc.dart';
import 'package:idea_notes/core/storage/database_helper.dart';

/// 初始化内存数据库并注入到 DatabaseHelper 单例，用于测试。
Future<void> setUpInMemoryDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 关闭可能残留的旧连接
  try {
    await DatabaseHelper.instance.close();
  } catch (_) {}

  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
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
  group('NoteListBloc', () {
    late DatabaseHelper dbHelper;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await setUpInMemoryDatabase();
      dbHelper = DatabaseHelper.instance;
    });

    tearDown(() async {
      await dbHelper.close();
    });

    // ===================== 初始状态 =====================

    test('初始状态：status 为 initial，笔记列表为空', () {
      final bloc = NoteListBloc(databaseHelper: dbHelper);
      expect(bloc.state.status, equals(NoteListStatus.initial));
      expect(bloc.state.notes, isEmpty);
      expect(bloc.state.filteredNotes, isEmpty);
      expect(bloc.state.searchQuery, equals(''));
      bloc.close();
    });

    // ===================== LoadNotes =====================

    test('LoadNotes：数据库为空时，状态变为 loaded 且笔记列表为空', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.status, equals(NoteListStatus.loaded));
      expect(bloc.state.notes, isEmpty);
      expect(bloc.state.filteredNotes, isEmpty);

      await bloc.close();
    });

    test('LoadNotes：经历 loading -> loaded 状态转换', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);
      final states = <NoteListState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));

      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.first.status, equals(NoteListStatus.loading));
      expect(states.last.status, equals(NoteListStatus.loaded));

      await sub.cancel();
      await bloc.close();
    });

    test('LoadNotes：数据库有笔记时，正确加载到状态', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await dbHelper.insertNote({
        'id': 'existing-note',
        'notebook_id': null,
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': null,
        'thumbnail_image_path': '/tmp/existing-thumb.png',
        'recognized_text': '已有笔记内容',
      });

      final bloc = NoteListBloc(databaseHelper: dbHelper);
      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.status, equals(NoteListStatus.loaded));
      expect(bloc.state.notes.length, equals(1));
      expect(bloc.state.notes.first.id, equals('existing-note'));
      expect(bloc.state.notes.first.thumbnailImagePath, equals('/tmp/existing-thumb.png'));

      await bloc.close();
    });

    // ===================== CreateNote =====================

    test('CreateNote：创建笔记后，列表中出现一条新笔记', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(bloc.state.notes, isEmpty);

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.notes.length, equals(1));
      expect(bloc.state.filteredNotes.length, equals(1));
      // 新笔记有合法的 id
      expect(bloc.state.notes.first.id, isNotEmpty);

      await bloc.close();
    });

    test('CreateNote：多次创建，列表笔记数量正确递增', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));
      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));
      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.notes.length, equals(3));

      await bloc.close();
    });

    test('CreateNote：新笔记排在列表最前面', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));
      final firstId = bloc.state.notes.first.id;

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));

      // 最新创建的笔记（第二条）应排在最前面
      expect(bloc.state.notes.first.id, isNot(equals(firstId)));

      await bloc.close();
    });

    // ===================== DeleteNote =====================

    test('DeleteNote：删除笔记后，列表中不再包含该笔记', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.notes.length, equals(1));
      final noteId = bloc.state.notes.first.id;

      bloc.add(DeleteNote(noteId));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.notes, isEmpty);
      expect(bloc.state.filteredNotes, isEmpty);

      await bloc.close();
    });

    test('DeleteNote：删除指定笔记，不影响其他笔记', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 50));
      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.notes.length, equals(2));
      final targetId = bloc.state.notes.last.id;
      final remainingId = bloc.state.notes.first.id;

      bloc.add(DeleteNote(targetId));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.notes.length, equals(1));
      expect(bloc.state.notes.any((n) => n.id == targetId), isFalse);
      expect(bloc.state.notes.first.id, equals(remainingId));

      await bloc.close();
    });

    // ===================== SearchNotes =====================

    test('SearchNotes：空查询时，filteredNotes 等于完整笔记列表', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));
      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(const SearchNotes(''));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        bloc.state.filteredNotes.length,
        equals(bloc.state.notes.length),
      );
      expect(bloc.state.searchQuery, equals(''));

      await bloc.close();
    });

    test('SearchNotes：搜索不存在的关键词，filteredNotes 为空', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));
      bloc.add(CreateNote());
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.add(const SearchNotes('不存在的关键词xyz'));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.filteredNotes, isEmpty);
      expect(bloc.state.searchQuery, equals('不存在的关键词xyz'));

      await bloc.close();
    });

    test('SearchNotes：通过 recognizedText 搜索，只返回匹配的笔记', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);
      final now = DateTime.now().millisecondsSinceEpoch;

      await dbHelper.insertNote({
        'id': 'note-apple',
        'notebook_id': null,
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': '苹果 买了很多苹果',
      });
      await dbHelper.insertNote({
        'id': 'note-banana',
        'notebook_id': null,
        'created_at': now + 1,
        'updated_at': now + 1,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': '香蕉 黄色的香蕉',
      });

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));
      expect(bloc.state.notes.length, equals(2));

      bloc.add(const SearchNotes('苹果'));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.filteredNotes.length, equals(1));
      expect(bloc.state.filteredNotes.first.id, equals('note-apple'));

      await bloc.close();
    });

    test('SearchNotes：搜索关键词大小写不敏感', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);
      final now = DateTime.now().millisecondsSinceEpoch;

      await dbHelper.insertNote({
        'id': 'note-english',
        'notebook_id': null,
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': 'Hello World',
      });

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));

      bloc.add(const SearchNotes('hello'));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.filteredNotes.length, equals(1));

      await bloc.close();
    });

    test('SearchNotes：搜索后再次清空查询，恢复完整列表', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);
      final now = DateTime.now().millisecondsSinceEpoch;

      await dbHelper.insertNote({
        'id': 'note-1',
        'notebook_id': null,
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': '苹果',
      });
      await dbHelper.insertNote({
        'id': 'note-2',
        'notebook_id': null,
        'created_at': now + 1,
        'updated_at': now + 1,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': '香蕉',
      });

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 200));

      bloc.add(const SearchNotes('苹果'));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.filteredNotes.length, equals(1));

      bloc.add(const SearchNotes(''));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.filteredNotes.length, equals(2));

      await bloc.close();
    });

    // ===================== RefreshNotes =====================

    test('RefreshNotes：触发后重新从数据库加载最新笔记', () async {
      final bloc = NoteListBloc(databaseHelper: dbHelper);

      bloc.add(LoadNotes());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(bloc.state.notes, isEmpty);

      // 直接向数据库插入一条笔记（绕过 bloc）
      final now = DateTime.now().millisecondsSinceEpoch;
      await dbHelper.insertNote({
        'id': 'external-note',
        'notebook_id': null,
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': null,
        'recognized_text': null,
      });

      bloc.add(RefreshNotes());
      await Future.delayed(const Duration(milliseconds: 300));

      expect(bloc.state.notes.length, equals(1));
      expect(bloc.state.notes.first.id, equals('external-note'));

      await bloc.close();
    });
  });
}
