import 'package:idea_notes/core/models/note.dart';

class CanvasEditorState {
  final Note? existingNote;
  final String ocrResult;
  final bool isSaving;
  final bool isRecognizing;

  const CanvasEditorState({
    this.existingNote,
    this.ocrResult = '',
    this.isSaving = false,
    this.isRecognizing = false,
  });

  CanvasEditorState copyWith({
    Note? existingNote,
    String? ocrResult,
    bool? isSaving,
    bool? isRecognizing,
    bool clearExistingNote = false,
  }) {
    return CanvasEditorState(
      existingNote: clearExistingNote ? null : (existingNote ?? this.existingNote),
      ocrResult: ocrResult ?? this.ocrResult,
      isSaving: isSaving ?? this.isSaving,
      isRecognizing: isRecognizing ?? this.isRecognizing,
    );
  }
}
