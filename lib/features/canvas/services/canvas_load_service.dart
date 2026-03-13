import 'dart:typed_data';

import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';

class CanvasLoadResult {
  final Note? note;
  final Uint8List? canvasData;
  final String ocrResult;

  const CanvasLoadResult({
    required this.note,
    required this.canvasData,
    required this.ocrResult,
  });
}

class CanvasLoadService {
  final DatabaseHelper databaseHelper;

  CanvasLoadService({required this.databaseHelper});

  Future<CanvasLoadResult> load(String noteId) async {
    final noteData = await databaseHelper.getNote(noteId);
    if (noteData == null) {
      return const CanvasLoadResult(
        note: null,
        canvasData: null,
        ocrResult: '',
      );
    }

    final note = Note.fromMap(noteData);
    final canvasData = note.canvasData != null && note.canvasData!.isNotEmpty
        ? Uint8List.fromList(note.canvasData!)
        : null;

    return CanvasLoadResult(
      note: note,
      canvasData: canvasData,
      ocrResult: note.recognizedText ?? '',
    );
  }
}
