import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/ai_extraction_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/extraction_orchestrator.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';

class _FakeEngine implements TextUnderstandingEngine {
  @override
  String get engineName => 'fake-ai';

  bool available = true;
  TextUnderstandingResult result = const TextUnderstandingResult.success(
    rawResponse: '{}',
    latency: Duration.zero,
  );

  @override
  Future<TextUnderstandingResult> extractStructuredData(
    ExtractionRequest request,
  ) async {
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  group('ExtractionOrchestrator', () {
    final request = ExtractionRequest(
      noteContext: ExtractionNoteContext(
        noteId: 'note-orchestrator',
        noteCreatedAt: DateTime(2026, 3, 20, 10, 0),
      ),
      ocrText: '明天复查，花费 88 元',
    );

    test('规则与 AI 同时开启时会合并结果并写审计记录', () async {
      final engine = _FakeEngine()
        ..result = TextUnderstandingResult.success(
          rawResponse: jsonEncode({
            'entries': [
              {
                'entry_id': 'ai-entry-1',
                'entry_type': 'expense',
                'domain': 'finance',
                'title': '复查费用',
                'raw_text': '花费 88 元',
                'occurred_date': '2026-03-20',
              },
            ],
          }),
          latency: const Duration(milliseconds: 100),
          modelName: 'gemini-test',
        );

      final auditRecords = <ExtractionAuditRecord>[];
      final orchestrator = ExtractionOrchestrator(
        aiExtractionService: AiExtractionService(engine: engine),
        ruleExtractor: (request) async => [
          ExtractedEntry(
            entryId: 'rule-entry-1',
            entryType: ExtractionEntryType.expense,
            domain: 'finance',
            title: '花费',
            rawText: '花费 88 元',
            occurredDate: DateTime(2026, 3, 20),
            amount: const ExtractionAmount(value: '88.00'),
          ),
          ExtractedEntry(
            entryId: 'rule-entry-2',
            entryType: ExtractionEntryType.task,
            domain: 'health',
            title: '复查',
            rawText: '明天复查',
            occurredDate: DateTime(2026, 3, 21),
          ),
        ],
        auditSink: (record) async {
          auditRecords.add(record);
        },
      );

      final result = await orchestrator.run(
        ExtractionOrchestratorInput(request: request),
      );

      expect(result.usedAi, isTrue);
      expect(result.usedRule, isTrue);
      expect(result.ruleEntriesCount, 2);
      expect(result.aiEntriesCount, 1);
      expect(result.mergedEntriesCount, 2);
      expect(result.aiError, isNull);
      expect(result.document.entries.length, 2);
      expect(
        result.document.entries
            .where((entry) => entry.entryType == ExtractionEntryType.expense)
            .single
            .amount
            ?.value,
        '88.00',
      );
      expect(auditRecords.length, 1);
      expect(auditRecords.first.engineName, 'fake-ai');
      expect(auditRecords.first.engineModel, 'gemini-test');
    });

    test('AI 失败时会降级为规则结果并返回 warning', () async {
      final engine = _FakeEngine()
        ..result = const TextUnderstandingResult.failure(
          message: 'rate limit',
          latency: Duration(milliseconds: 30),
        );

      final orchestrator = ExtractionOrchestrator(
        aiExtractionService: AiExtractionService(engine: engine),
        ruleExtractor: (request) async => [
          ExtractedEntry(
            entryId: 'rule-only',
            entryType: ExtractionEntryType.memo,
            domain: 'life',
            title: '规则记录',
            rawText: '规则记录',
            occurredDate: DateTime(2026, 3, 20),
          ),
        ],
      );

      final result = await orchestrator.run(
        ExtractionOrchestratorInput(request: request),
      );

      expect(result.aiError, isNotNull);
      expect(result.document.entries.length, 1);
      expect(result.document.entries.first.entryId, 'rule-only');
      expect(
        result.document.warnings
            .any((warning) => warning.code == 'ai_extraction_failed'),
        isTrue,
      );
    });
  });
}
