import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/ai_extraction_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';

class _FakeTextUnderstandingEngine implements TextUnderstandingEngine {
  @override
  String get engineName => 'fake-engine';

  bool available;
  TextUnderstandingResult result;
  ExtractionRequest? lastRequest;

  _FakeTextUnderstandingEngine({
    this.available = true,
    required this.result,
  });

  @override
  Future<TextUnderstandingResult> extractStructuredData(
    ExtractionRequest request,
  ) async {
    lastRequest = request;
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  final request = ExtractionRequest(
    noteContext: ExtractionNoteContext(
      noteId: 'note-123',
      noteCreatedAt: DateTime(2026, 3, 20, 10, 0),
    ),
    ocrText: '明天提交评审',
  );

  group('AiExtractionService', () {
    test('engine 为空时返回失败', () async {
      const service = AiExtractionService(engine: null);
      final result = await service.extract(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not configured'));
    });

    test('engine 不可用时返回失败', () async {
      final engine = _FakeTextUnderstandingEngine(
        available: false,
        result: const TextUnderstandingResult.success(
          rawResponse: '{}',
          latency: Duration(milliseconds: 10),
        ),
      );
      final service = AiExtractionService(engine: engine);
      final result = await service.extract(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('unavailable'));
    });

    test('成功路径会解析文档并返回 entries', () async {
      final engine = _FakeTextUnderstandingEngine(
        result: TextUnderstandingResult.success(
          rawResponse: jsonEncode({
            'entries': [
              {
                'entry_id': 'entry-ok',
                'entry_type': 'task',
                'domain': 'work',
                'title': '提交评审',
                'raw_text': '明天提交评审',
                'occurred_date': '2026-03-21',
              },
            ],
          }),
          latency: const Duration(milliseconds: 120),
          modelName: 'gemini-3.1-pro-preview',
        ),
      );
      final service = AiExtractionService(engine: engine);

      final result = await service.extract(request);

      expect(result.success, isTrue);
      expect(result.document, isNotNull);
      expect(result.document!.entries.length, 1);
      expect(result.document!.entries.first.title, '提交评审');
      expect(result.modelName, 'gemini-3.1-pro-preview');
      expect(result.latency, const Duration(milliseconds: 120));
      expect(engine.lastRequest?.noteContext.noteId, 'note-123');
    });

    test('schema 非法时返回失败并带错误信息', () async {
      final engine = _FakeTextUnderstandingEngine(
        result: const TextUnderstandingResult.success(
          rawResponse: '{"entries": "invalid"}',
          latency: Duration(milliseconds: 20),
          modelName: 'bad-model',
        ),
      );
      final service = AiExtractionService(engine: engine);

      final result = await service.extract(request);

      expect(result.success, isTrue);
      expect(result.document, isNotNull);
      expect(result.document!.entries, isEmpty);
      expect(
        result.document!.warnings
            .any((warning) => warning.code == 'entries_missing'),
        isTrue,
      );
    });

    test('engine 失败时透传失败消息', () async {
      final engine = _FakeTextUnderstandingEngine(
        result: const TextUnderstandingResult.failure(
          message: 'request timeout',
          latency: Duration(milliseconds: 300),
          modelName: 'gemini',
        ),
      );
      final service = AiExtractionService(engine: engine);

      final result = await service.extract(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('request timeout'));
      expect(result.modelName, 'gemini');
      expect(result.latency, const Duration(milliseconds: 300));
    });
  });
}
