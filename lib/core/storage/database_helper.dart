import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'database_migrations.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Injects an existing [Database] instance, intended for use in tests only.
  /// Call [close] before injecting to reset the singleton state.
  static void injectDatabase(Database db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('idea_notes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: kDatabaseVersion,
      onCreate: createDatabaseSchema,
      onUpgrade: migrateDatabaseSchema,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // Notebook operations
  Future<int> insertNotebook(Map<String, dynamic> notebook) async {
    final db = await database;
    return await db.insert('notebooks', notebook);
  }

  Future<List<Map<String, dynamic>>> getNotebooks() async {
    final db = await database;
    return await db.query('notebooks', orderBy: 'updated_at DESC');
  }

  Future<int> updateNotebook(String id, Map<String, dynamic> notebook) async {
    final db = await database;
    return await db.update(
      'notebooks',
      notebook,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteNotebook(String id) async {
    final db = await database;
    return await db.delete(
      'notebooks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Note operations
  Future<int> insertNote(Map<String, dynamic> note) async {
    final db = await database;
    return await db.insert('notes', note);
  }

  Future<List<Map<String, dynamic>>> getNotes({String? notebookId}) async {
    final db = await database;
    if (notebookId != null) {
      return await db.query(
        'notes',
        where: 'notebook_id = ?',
        whereArgs: [notebookId],
        orderBy: 'updated_at DESC',
      );
    }
    return await db.query('notes', orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getNote(String id) async {
    final db = await database;
    final results = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateNote(String id, Map<String, dynamic> note) async {
    final db = await database;
    return await db.update(
      'notes',
      note,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteNote(String id) async {
    final db = await database;
    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> searchNotes(
    String query, {
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await database;
    final escaped = escapeSqlLike(query);
    return await db.query(
      'notes',
      where: "recognized_text LIKE ? ESCAPE '\\'",
      whereArgs: ['%$escaped%'],
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 转义 LIKE 通配符 `%`、`_` 与转义符自身，使其按字面量匹配。
  /// 配合查询里的 `ESCAPE '\\'` 子句使用。
  static String escapeSqlLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
