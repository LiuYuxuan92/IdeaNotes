import 'package:sqflite/sqflite.dart';

import '../storage/database_helper.dart';

/// Persists user-provided API keys in the local SQLite database.
/// Keys are stored in a simple key-value table.
class ApiKeyStorage {
  static const _table = 'app_config';
  static const _keyDeepSeek = 'deepseek_api_key';

  ApiKeyStorage._();
  static final instance = ApiKeyStorage._();

  String? _cached;

  /// Ensures the config table exists.
  Future<void> _ensureTable() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Returns the stored DeepSeek API key, or `null` if not set.
  Future<String?> getDeepSeekApiKey() async {
    if (_cached != null) return _cached;
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      _table,
      where: 'key = ?',
      whereArgs: [_keyDeepSeek],
    );
    if (rows.isNotEmpty) {
      final value = rows.first['value'] as String?;
      if (value != null && value.trim().isNotEmpty) {
        _cached = value.trim();
        return _cached;
      }
    }
    return null;
  }

  /// Saves the DeepSeek API key.
  Future<void> setDeepSeekApiKey(String apiKey) async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      _table,
      {'key': _keyDeepSeek, 'value': apiKey.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cached = apiKey.trim();
  }

  /// Removes the stored DeepSeek API key.
  Future<void> clearDeepSeekApiKey() async {
    await _ensureTable();
    final db = await DatabaseHelper.instance.database;
    await db.delete(_table, where: 'key = ?', whereArgs: [_keyDeepSeek]);
    _cached = null;
  }

  /// Whether a key has been configured.
  Future<bool> hasDeepSeekApiKey() async {
    final key = await getDeepSeekApiKey();
    return key != null && key.isNotEmpty;
  }
}
