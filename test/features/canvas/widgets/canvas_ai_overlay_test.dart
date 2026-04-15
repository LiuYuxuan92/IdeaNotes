import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';
import 'package:idea_notes/features/canvas/widgets/canvas_ai_overlay.dart';

ExtractionPreview _makePreview({
  String id = 'p1',
  String noteId = 'note-1',
  String rawText = '午饭 32 元',
}) {
  return ExtractionPreview(
    id: id,
    noteId: noteId,
    rawText: rawText,
    mergedExtractionJson: rawText,
    status: ExtractionPreviewStatus.pending,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CanvasAiOverlay', () {
    testWidgets('displays preview rawText for each preview', (tester) async {
      final previews = [
        _makePreview(id: 'p1', rawText: '午饭 32 元'),
        _makePreview(id: 'p2', rawText: '打车 15'),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasAiOverlay(
            previews: previews,
            onConfirm: (_) {},
          ),
        ),
      ));

      expect(find.text('午饭 32 元'), findsOneWidget);
      expect(find.text('打车 15'), findsOneWidget);
    });

    testWidgets('shows confirm button for each preview', (tester) async {
      final previews = [_makePreview()];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasAiOverlay(
            previews: previews,
            onConfirm: (_) {},
          ),
        ),
      ));

      expect(find.text('确认'), findsOneWidget);
    });

    testWidgets('confirm button calls onConfirm with correct preview',
        (tester) async {
      final previews = [_makePreview(id: 'p1', rawText: '咖啡 28')];
      ExtractionPreview? confirmed;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasAiOverlay(
            previews: previews,
            onConfirm: (p) => confirmed = p,
          ),
        ),
      ));

      await tester.tap(find.text('确认'));
      expect(confirmed, isNotNull);
      expect(confirmed!.id, 'p1');
      expect(confirmed!.rawText, '咖啡 28');
    });

    testWidgets('renders nothing when previews is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasAiOverlay(
            previews: const [],
            onConfirm: (_) {},
          ),
        ),
      ));

      // The Column should exist but have zero children
      final column = tester.widget<Column>(find.byType(Column));
      expect(column.children, isEmpty);
    });
  });
}
