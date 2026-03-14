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

      expect(find.text('还没有识别内容，打开笔记后可继续书写或识别。'), findsOneWidget);
      expect(find.text('未命名笔记'), findsOneWidget);
    });
  });
}
