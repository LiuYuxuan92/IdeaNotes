import 'package:idea_notes/features/canvas/models/extraction_preview.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

abstract class PreviewStore {
  Future<int> upsertPreview(ExtractionPreview preview);
  Future<List<ExtractionPreview>> getPendingPreviews(String noteId);
  Future<ExtractionPreview?> getPreview(String id);
  Future<void> markConfirmed(String id, DateTime confirmedAt);
}

class ExtractionPreviewRepository implements PreviewStore {
  final DatabaseHelper databaseHelper;

  ExtractionPreviewRepository({required this.databaseHelper});

  @override
  Future<int> upsertPreview(ExtractionPreview preview) async {
    final db = await databaseHelper.database;
    return db.insert(
      'extraction_previews',
      preview.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ExtractionPreview>> getPendingPreviews(String noteId) async {
    final db = await databaseHelper.database;
    final rows = await db.query(
      'extraction_previews',
      columns: [
        'id',
        'note_id',
        'raw_text',
        'merged_extraction',
        'status',
        'created_at',
        'confirmed_at',
      ],
      where: 'note_id = ? AND status = ?',
      whereArgs: [noteId, ExtractionPreviewStatus.pending.name],
    );
    return rows.map(ExtractionPreview.fromMap).toList(growable: false);
  }

  @override
  Future<ExtractionPreview?> getPreview(String id) async {
    final db = await databaseHelper.database;
    final rows = await db.query(
      'extraction_previews',
      columns: [
        'id',
        'note_id',
        'raw_text',
        'merged_extraction',
        'status',
        'created_at',
        'confirmed_at',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExtractionPreview.fromMap(rows.first);
  }

  @override
  Future<void> markConfirmed(String id, DateTime confirmedAt) async {
    final db = await databaseHelper.database;
    await db.update(
      'extraction_previews',
      {
        'status': ExtractionPreviewStatus.confirmed.name,
        'confirmed_at': confirmedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
