import 'dart:typed_data';

import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/parser/entry_parser.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/image_storage.dart';
import 'package:uuid/uuid.dart';

class CanvasSaveInput {
  final Note? existingNote;
  final Uint8List canvasData;
  final Uint8List? snapshotBytes;
  final Uint8List? thumbnailBytes;
  final String? recognizedText;
  final DateTime now;

  const CanvasSaveInput({
    required this.existingNote,
    required this.canvasData,
    required this.snapshotBytes,
    required this.thumbnailBytes,
    required this.recognizedText,
    required this.now,
  });
}

class CanvasSaveService {
  final DatabaseHelper databaseHelper;
  final String Function() createId;
  final Future<String> Function(Uint8List bytes, String noteId) saveSnapshot;
  final Future<String?> Function(Uint8List bytes, String noteId) saveThumbnail;

  CanvasSaveService({
    required this.databaseHelper,
    String Function()? createId,
    Future<String> Function(Uint8List bytes, String noteId)? saveSnapshot,
    Future<String?> Function(Uint8List bytes, String noteId)? saveThumbnail,
  })  : createId = createId ?? const Uuid().v4,
        saveSnapshot = saveSnapshot ?? ImageStorage.saveSnapshot,
        saveThumbnail = saveThumbnail ?? ImageStorage.saveThumbnail;

  Future<Note> save(CanvasSaveInput input) async {
    final noteId = input.existingNote?.id ?? createId();
    final imagePaths = await _persistImages(
      noteId: noteId,
      snapshotBytes: input.snapshotBytes,
      thumbnailBytes: input.thumbnailBytes,
    );

    final recognizedText = _normalizedText(input.recognizedText);

    final note = await _upsertNote(
      existingNote: input.existingNote,
      noteId: noteId,
      canvasData: input.canvasData,
      snapshotPath: imagePaths.snapshotPath,
      thumbnailPath: imagePaths.thumbnailPath,
      recognizedText: recognizedText,
      now: input.now,
    );

    await _replaceEntries(noteId, recognizedText, input.now);
    return note;
  }

  Future<_SavedImagePaths> _persistImages({
    required String noteId,
    required Uint8List? snapshotBytes,
    required Uint8List? thumbnailBytes,
  }) async {
    String? snapshotPath;
    String? thumbnailPath;

    if (snapshotBytes != null) {
      snapshotPath = await saveSnapshot(snapshotBytes, noteId);
    }

    if (thumbnailBytes != null) {
      thumbnailPath = await saveThumbnail(thumbnailBytes, noteId);
    }

    return _SavedImagePaths(
      snapshotPath: snapshotPath,
      thumbnailPath: thumbnailPath,
    );
  }

  Future<Note> _upsertNote({
    required Note? existingNote,
    required String noteId,
    required Uint8List canvasData,
    required String? snapshotPath,
    required String? thumbnailPath,
    required String? recognizedText,
    required DateTime now,
  }) async {
    if (existingNote != null) {
      await databaseHelper.updateNote(existingNote.id, {
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': canvasData,
        'snapshot_image_path': snapshotPath ?? existingNote.snapshotImagePath,
        'thumbnail_image_path': thumbnailPath ?? existingNote.thumbnailImagePath,
        'recognized_text': recognizedText,
      });

      return existingNote.copyWith(
        updatedAt: now,
        canvasData: canvasData,
        snapshotImagePath: snapshotPath ?? existingNote.snapshotImagePath,
        thumbnailImagePath: thumbnailPath ?? existingNote.thumbnailImagePath,
        recognizedText: recognizedText,
      );
    }

    await databaseHelper.insertNote({
      'id': noteId,
      'notebook_id': 'default-notebook',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
      'canvas_data': canvasData,
      'snapshot_image_path': snapshotPath,
      'thumbnail_image_path': thumbnailPath,
      'recognized_text': recognizedText,
    });

    return Note(
      id: noteId,
      notebookId: 'default-notebook',
      createdAt: now,
      updatedAt: now,
      canvasData: canvasData,
      snapshotImagePath: snapshotPath,
      thumbnailImagePath: thumbnailPath,
      recognizedText: recognizedText,
    );
  }

  Future<void> _replaceEntries(String noteId, String? recognizedText, DateTime now) async {
    await databaseHelper.deleteNoteEntries(noteId);

    if (recognizedText == null || recognizedText.isEmpty) {
      return;
    }

    final entries = EntryParser.parseMultiLine(recognizedText);
    for (final entry in entries) {
      await databaseHelper.insertNoteEntry({
        'id': entry.id,
        'note_id': noteId,
        'type': entry.type.name,
        'raw_text': entry.rawText,
        'amount': entry.expense?.amount.toString(),
        'category': entry.expense?.category,
        'event_title': entry.event?.title,
        'event_date': entry.event?.date?.millisecondsSinceEpoch,
        'is_completed': (entry.event?.isCompleted ?? false) ? 1 : 0,
        'memo_text': entry.memoText,
        'created_at': now.millisecondsSinceEpoch,
      });
    }
  }

  String? _normalizedText(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _SavedImagePaths {
  final String? snapshotPath;
  final String? thumbnailPath;

  const _SavedImagePaths({
    required this.snapshotPath,
    required this.thumbnailPath,
  });
}
