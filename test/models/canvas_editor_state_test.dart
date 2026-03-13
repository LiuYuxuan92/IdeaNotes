import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/features/canvas/models/canvas_editor_state.dart';

void main() {
  group('CanvasEditorState', () {
    test('copyWith 能更新 editor 状态字段', () {
      final initial = CanvasEditorState(
        ocrResult: '旧结果',
        isSaving: false,
        isRecognizing: false,
      );

      final next = initial.copyWith(
        ocrResult: '新结果',
        isSaving: true,
        isRecognizing: true,
      );

      expect(next.ocrResult, '新结果');
      expect(next.isSaving, isTrue);
      expect(next.isRecognizing, isTrue);
    });

    test('copyWith 能保留或替换 existingNote', () {
      final oldNote = Note(
        id: 'note-old',
        createdAt: DateTime(2026, 3, 13),
        updatedAt: DateTime(2026, 3, 13),
      );
      final newNote = Note(
        id: 'note-new',
        createdAt: DateTime(2026, 3, 14),
        updatedAt: DateTime(2026, 3, 14),
      );

      final initial = CanvasEditorState(existingNote: oldNote);
      final replaced = initial.copyWith(existingNote: newNote);
      final cleared = replaced.copyWith(clearExistingNote: true);

      expect(replaced.existingNote?.id, 'note-new');
      expect(cleared.existingNote, isNull);
    });
  });
}
