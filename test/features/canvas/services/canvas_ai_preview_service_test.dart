import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/ocr_text_correction_engine.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/features/canvas/services/canvas_ai_preview_service.dart';

class _FakeTextUnderstandingEngine implements TextUnderstandingEngine {
  @override
  String get engineName => 'fake-preview';

  final TextUnderstandingResult result;

  const _FakeTextUnderstandingEngine({
    required this.result,
  });

  @override
  Future<TextUnderstandingResult> extractStructuredData(
    ExtractionRequest request,
  ) async {
    return result;
  }

  @override
  Future<bool> isAvailable() async => true;
}

class _FakeOcrTextCorrectionEngine implements OcrTextCorrectionEngine {
  final OcrTextCorrectionResult result;

  const _FakeOcrTextCorrectionEngine({
    required this.result,
  });

  @override
  String get engineName => 'fake-correction';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<OcrTextCorrectionResult> correctText(
    OcrTextCorrectionRequest request,
  ) async {
    return result;
  }
}

void main() {
  group('CanvasAiPreviewService', () {
    test('OCR 文本为空时直接返回失败', () async {
      final service = CanvasAiPreviewService(
        engine: const _FakeTextUnderstandingEngine(
          result: TextUnderstandingResult.success(
            rawResponse: '{}',
            latency: Duration.zero,
          ),
        ),
      );

      final result = await service.preview(
        existingNote: null,
        recognizedText: '   ',
        now: DateTime(2026, 3, 21, 10, 0),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('没有可供 AI 整理'));
    });

    test('预览前会先应用 OCR 校对结果', () async {
      final service = CanvasAiPreviewService(
        engine: _FakeTextUnderstandingEngine(
          result: TextUnderstandingResult.success(
            rawResponse: jsonEncode({
              'entries': [
                {
                  'entry_id': 'entry-1',
                  'entry_type': 'health_record',
                  'domain': 'health',
                  'title': '今天吃了牛肉',
                  'raw_text': '今天吃了牛肉',
                  'occurred_date': '2026-03-21',
                },
              ],
            }),
            latency: const Duration(milliseconds: 120),
            modelName: 'deepseek-chat',
          ),
        ),
        correctionEngine: const _FakeOcrTextCorrectionEngine(
          result: OcrTextCorrectionResult.success(
            correctedText: '今天吃了牛肉',
            rawResponse: '{"corrected_text":"今天吃了牛肉"}',
            latency: Duration(milliseconds: 40),
            modelName: 'deepseek-chat',
          ),
        ),
      );

      final result = await service.preview(
        existingNote: null,
        recognizedText: '今天吃了3牛肉',
        now: DateTime(2026, 3, 21, 10, 0),
      );

      expect(result.success, isTrue);
      expect(result.correctionApplied, isTrue);
      expect(result.originalText, '今天吃了3牛肉');
      expect(result.correctedText, '今天吃了牛肉');
      expect(result.document?.ocrSummary.fullText, '今天吃了牛肉');
    });

    test('成功时返回解析后的结构化文档', () async {
      final service = CanvasAiPreviewService(
        engine: _FakeTextUnderstandingEngine(
          result: TextUnderstandingResult.success(
            rawResponse: jsonEncode({
              'entries': [
                {
                  'entry_id': 'entry-1',
                  'entry_type': 'expense',
                  'domain': 'finance',
                  'title': '今天花了 7200',
                  'raw_text': '今天花了7200',
                  'occurred_date': '2026-03-21',
                  'amount': {
                    'value': '7200',
                    'currency': 'CNY',
                  },
                },
              ],
            }),
            latency: const Duration(milliseconds: 120),
            modelName: 'deepseek-chat',
          ),
        ),
      );

      final result = await service.preview(
        existingNote: Note(
          id: 'note-1',
          notebookId: 'default-notebook',
          createdAt: DateTime(2026, 3, 21, 9, 0),
          updatedAt: DateTime(2026, 3, 21, 9, 0),
          recognizedText: '今天花了7200',
        ),
        recognizedText: '今天花了7200',
        now: DateTime(2026, 3, 21, 10, 0),
      );

      expect(result.success, isTrue);
      expect(result.engineName, 'fake-preview');
      expect(result.modelName, 'deepseek-chat');
      expect(result.correctionApplied, isFalse);
      expect(result.document, isNotNull);
      expect(result.document!.entries.length, 1);
      expect(result.document!.entries.first.title, '今天花了 7200');
      expect(result.document!.entries.first.amount?.value, '7200');
    });
  });
}
