import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/ocr/ocr_engine.dart';
import 'package:idea_notes/features/canvas/canvas_screen.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';

class _FakeOcrEngine implements OcrEngine {
  @override
  String get engineName => 'fake';

  @override
  void dispose() {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async => const [];

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async =>
      const [];
}

ExtractionPreview _preview({
  String id = 'preview-1',
  String text = '午饭 32 元',
}) {
  return ExtractionPreview(
    id: id,
    noteId: 'note-1',
    rawText: text,
    mergedExtractionJson: text,
    status: ExtractionPreviewStatus.pending,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CanvasScreen realtime preview', () {
    testWidgets('shows pending preview text on screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CanvasScreen(
            ocrEngineOverride: _FakeOcrEngine(),
            initialPendingPreviews: [_preview()],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('午饭 32 元'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);
    });

    testWidgets('confirm removes pending preview from screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CanvasScreen(
            ocrEngineOverride: _FakeOcrEngine(),
            initialPendingPreviews: [_preview()],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('确认'));
      await tester.pump();

      expect(find.text('午饭 32 元'), findsNothing);
      expect(find.text('确认'), findsNothing);
    });
  });
}
