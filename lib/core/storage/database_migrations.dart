import 'package:sqflite/sqflite.dart';

const int kDatabaseVersion = 7;

Future<void> createDatabaseSchema(Database db, int version) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await _createBaseTables(db);
  await _ensureDefaultNotebook(db);

  // New installs should include the latest structured-data/query schema.
  if (version >= 4) {
    await _createEntriesSchema(db);
  }
  if (version >= 5) {
    await _createEntryRelationSchema(db);
  }
  if (version >= 6) {
    await _createAiAndFilterSchema(db);
  }
  if (version >= 7) {
    await _createExtractionPreviewSchema(db);
  }
}

Future<void> migrateDatabaseSchema(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  await db.execute('PRAGMA foreign_keys = ON');
  if (oldVersion < 2) {
    await _migrateNoteEntriesAmountToText(db);
  }

  if (oldVersion < 3) {
    await db.execute('ALTER TABLE notes ADD COLUMN thumbnail_image_path TEXT');
  }

  if (oldVersion < 4) {
    await _createEntriesSchema(db);
    await _backfillEntriesFromLegacyNoteEntries(db);
  }

  if (oldVersion < 5) {
    await _createEntryRelationSchema(db);
  }

  if (oldVersion < 6) {
    await _createAiAndFilterSchema(db);
  }

  if (oldVersion < 7) {
    await _createExtractionPreviewSchema(db);
    await _addAiExtractionCorrectionColumns(db);
  }

  // Defensive: keep the default notebook present for future writes.
  await _ensureDefaultNotebook(db);
  if (newVersion > kDatabaseVersion) {
    // Reserve hook for future migrations.
  }
}

Future<void> _createBaseTables(Database db) async {
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
}

Future<void> _migrateNoteEntriesAmountToText(Database db) async {
  await db.execute('''
    CREATE TABLE note_entries_new (
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

  await db.execute('''
    INSERT INTO note_entries_new
      SELECT id, note_id, type, raw_text, CAST(amount AS TEXT),
             category, event_title, event_date, is_completed, memo_text, created_at
      FROM note_entries
  ''');

  await db.execute('DROP TABLE note_entries');
  await db.execute('ALTER TABLE note_entries_new RENAME TO note_entries');
}

Future<void> _createEntriesSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS entries (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      domain TEXT NOT NULL,
      occurred_at INTEGER,
      occurred_date TEXT NOT NULL,
      end_at INTEGER,
      title TEXT NOT NULL,
      summary TEXT,
      raw_text TEXT NOT NULL,
      normalized_json TEXT,
      amount_value TEXT,
      amount_currency TEXT,
      category_l1 TEXT,
      category_l2 TEXT,
      status TEXT,
      confidence REAL,
      is_user_confirmed INTEGER DEFAULT 0,
      source_engine TEXT NOT NULL,
      source_version TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_occurred_date
    ON entries (occurred_date)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_type_date
    ON entries (entry_type, occurred_date)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_domain_date
    ON entries (domain, occurred_date)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_category_l1_date
    ON entries (category_l1, occurred_date)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_note_id
    ON entries (note_id)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entries_status
    ON entries (status)
  ''');
}

Future<void> _createEntryRelationSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS entry_subjects (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL,
      subject_name TEXT NOT NULL,
      subject_type TEXT NOT NULL,
      role TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_subjects_name
    ON entry_subjects (subject_name)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_subjects_entry_id
    ON entry_subjects (entry_id)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS entry_tags (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL,
      tag TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_tags_tag
    ON entry_tags (tag)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_tags_entry_id
    ON entry_tags (entry_id)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS entry_links (
      id TEXT PRIMARY KEY,
      from_entry_id TEXT NOT NULL,
      to_entry_id TEXT NOT NULL,
      link_type TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (from_entry_id) REFERENCES entries (id) ON DELETE CASCADE,
      FOREIGN KEY (to_entry_id) REFERENCES entries (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_links_from
    ON entry_links (from_entry_id)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_entry_links_to
    ON entry_links (to_entry_id)
  ''');
}

Future<void> _createAiAndFilterSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ai_extractions (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      engine_name TEXT NOT NULL,
      engine_model TEXT NOT NULL,
      prompt_version TEXT NOT NULL,
      input_text TEXT NOT NULL,
      raw_response_json TEXT NOT NULL,
      normalized_entries_json TEXT NOT NULL,
      status TEXT NOT NULL,
      user_correction TEXT,
      original_extraction TEXT,
      correction_feedback TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_ai_extractions_note_id
    ON ai_extractions (note_id)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_ai_extractions_created_at
    ON ai_extractions (created_at)
  ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_ai_extractions_status
    ON ai_extractions (status)
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS saved_filters (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      filter_json TEXT NOT NULL,
      sort_json TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}

Future<void> _createExtractionPreviewSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS extraction_previews (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      raw_text TEXT NOT NULL,
      rule_extraction TEXT,
      ai_extraction TEXT,
      merged_extraction TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      user_correction TEXT,
      created_at INTEGER NOT NULL,
      confirmed_at INTEGER,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
}

Future<void> _addAiExtractionCorrectionColumns(Database db) async {
  await _addColumnIfMissing(db, 'ai_extractions', 'user_correction', 'TEXT');
  await _addColumnIfMissing(
      db, 'ai_extractions', 'original_extraction', 'TEXT');
  await _addColumnIfMissing(
      db, 'ai_extractions', 'correction_feedback', 'TEXT');
}

Future<void> _addColumnIfMissing(
  Database db,
  String tableName,
  String columnName,
  String columnDefinition,
) async {
  final columns = await db.rawQuery('PRAGMA table_info($tableName)');
  final hasColumn = columns.any((row) => row['name'] == columnName);
  if (hasColumn) {
    return;
  }

  await db.execute(
    'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
  );
}

Future<void> _backfillEntriesFromLegacyNoteEntries(Database db) async {
  await db.execute('''
    INSERT OR IGNORE INTO entries (
      id,
      note_id,
      entry_type,
      domain,
      occurred_at,
      occurred_date,
      end_at,
      title,
      summary,
      raw_text,
      normalized_json,
      amount_value,
      amount_currency,
      category_l1,
      category_l2,
      status,
      confidence,
      is_user_confirmed,
      source_engine,
      source_version,
      created_at,
      updated_at
    )
    SELECT
      ne.id,
      ne.note_id,
      CASE
        WHEN ne.type = 'expense' THEN 'expense'
        WHEN ne.type = 'event' THEN 'task'
        ELSE 'memo'
      END AS entry_type,
      CASE
        WHEN ne.type = 'expense' THEN 'finance'
        ELSE 'life'
      END AS domain,
      ne.event_date AS occurred_at,
      COALESCE(
        CASE
          WHEN ne.event_date IS NOT NULL
            THEN strftime('%Y-%m-%d', ne.event_date / 1000, 'unixepoch')
        END,
        strftime('%Y-%m-%d', n.created_at / 1000, 'unixepoch'),
        strftime('%Y-%m-%d', 'now')
      ) AS occurred_date,
      NULL AS end_at,
      COALESCE(ne.event_title, ne.memo_text, ne.raw_text) AS title,
      NULL AS summary,
      ne.raw_text,
      NULL AS normalized_json,
      ne.amount AS amount_value,
      CASE
        WHEN ne.amount IS NOT NULL THEN 'CNY'
        ELSE NULL
      END AS amount_currency,
      ne.category AS category_l1,
      NULL AS category_l2,
      CASE
        WHEN ne.type = 'event' AND ne.is_completed = 1 THEN 'done'
        ELSE 'recorded'
      END AS status,
      NULL AS confidence,
      1 AS is_user_confirmed,
      'rule-legacy' AS source_engine,
      'v1' AS source_version,
      ne.created_at,
      ne.created_at
    FROM note_entries ne
    LEFT JOIN notes n ON n.id = ne.note_id
  ''');
}

Future<void> _ensureDefaultNotebook(Database db) async {
  final rows = await db.query(
    'notebooks',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: ['default-notebook'],
    limit: 1,
  );

  if (rows.isNotEmpty) {
    return;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('notebooks', {
    'id': 'default-notebook',
    'title': '我的笔记',
    'created_at': now,
    'updated_at': now,
  });
}
