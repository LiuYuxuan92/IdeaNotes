import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/features/notelist/note_list_item.dart';

void main() {
  group('NoteListItem', () {
    testWidgets('无识别文本时显示默认摘要占位文案', (tester) async {
      final note = Note(
        id: 'note-empty',
        createdAt: DateTime(2026, 3, 13, 10, 0),
        updatedAt: DateTime(2026, 3, 13, 10, 0),
        recognizedText: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteListItem(note: note),
          ),
        ),
      );

      expect(find.text('暂无识别内容'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });
  });
}
