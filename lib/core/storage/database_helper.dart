import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Notebooks table
    await db.execute('''
      CREATE TABLE notebooks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Notes table
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        notebook_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        canvas_data BLOB,
        snapshot_image_path TEXT,
        recognized_text TEXT,
        FOREIGN KEY (notebook_id) REFERENCES notebooks (id) ON DELETE CASCADE
      )
    ''');

    // Note entries table (for parsed OCR results)
    await db.execute('''
      CREATE TABLE note_entries (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        type TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        amount REAL,
        category TEXT,
        event_title TEXT,
        event_date INTEGER,
        is_completed INTEGER DEFAULT 0,
        memo_text TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
      )
    ''');

    // Create default notebook
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('notebooks', {
      'id': 'default-notebook',
      'title': '我的笔记',
      'created_at': now,
      'updated_at': now,
    });
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

  Future<List<Map<String, dynamic>>> searchNotes(String query) async {
    final db = await database;
    return await db.query(
      'notes',
      where: 'recognized_text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'updated_at DESC',
    );
  }

  // Note entry operations
  Future<int> insertNoteEntry(Map<String, dynamic> entry) async {
    final db = await database;
    return await db.insert('note_entries', entry);
  }

  Future<List<Map<String, dynamic>>> getNoteEntries(String noteId) async {
    final db = await database;
    return await db.query(
      'note_entries',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
  }

  Future<int> deleteNoteEntries(String noteId) async {
    final db = await database;
    return await db.delete(
      'note_entries',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
