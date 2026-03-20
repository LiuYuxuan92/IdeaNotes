import 'ai_extraction_service.dart';
import 'entry_merge_service.dart';
import 'extraction_models.dart';

typedef RuleEntriesExtractor = Future<List<ExtractedEntry>> Function(
  ExtractionRequest request,
);

typedef ExtractionAuditSink = Future<void> Function(
    ExtractionAuditRecord record);

class ExtractionOrchestratorInput {
  final ExtractionRequest request;
  final bool enableRule;
  final bool enableAi;

  const ExtractionOrchestratorInput({
    required this.request,
    this.enableRule = true,
    this.enableAi = true,
  });
}

class OrchestratedExtractionResult {
  final NormalizedExtractionDocument document;
  final bool usedRule;
  final bool usedAi;
  final String? ruleError;
  final String? aiError;
  final String? aiRawResponse;
  final int ruleEntriesCount;
  final int aiEntriesCount;
  final int mergedEntriesCount;

  const OrchestratedExtractionResult({
    required this.document,
    required this.usedRule,
    required this.usedAi,
    required this.ruleEntriesCount,
    required this.aiEntriesCount,
    required this.mergedEntriesCount,
    this.ruleError,
    this.aiError,
    this.aiRawResponse,
  });
}

class ExtractionOrchestrator {
  final RuleEntriesExtractor? ruleExtractor;
  final AiExtractionService aiExtractionService;
  final EntryMergeService entryMergeService;
  final ExtractionAuditSink? auditSink;

  const ExtractionOrchestrator({
    required this.aiExtractionService,
    this.entryMergeService = const EntryMergeService(),
    this.ruleExtractor,
    this.auditSink,
  });

  Future<OrchestratedExtractionResult> run(
    ExtractionOrchestratorInput input,
  ) async {
    List<ExtractedEntry> ruleEntries = const [];
    String? ruleError;
    if (input.enableRule && ruleExtractor != null) {
      try {
        ruleEntries = await ruleExtractor!.call(input.request);
      } catch (error) {
        ruleError = 'Rule extraction failed: $error';
      }
    }

    List<ExtractedEntry> aiEntries = const [];
    String? aiError;
    String? aiRawResponse;
    AiExtractionResult? aiResult;
    if (input.enableAi) {
      aiResult = await aiExtractionService.extract(input.request);
      aiRawResponse =
          aiResult.rawResponse.isEmpty ? null : aiResult.rawResponse;
      if (aiResult.success && aiResult.document != null) {
        aiEntries = aiResult.document!.entries;
      } else {
        aiError = aiResult.errorMessage;
      }
    }

    final mergedEntries = entryMergeService.merge(
      ruleEntries: ruleEntries,
      aiEntries: aiEntries,
    );

    final warnings = <ExtractionWarning>[
      if (ruleError != null)
        const ExtractionWarning(
          code: 'rule_extraction_failed',
          message: 'Rule extraction failed',
        ),
      if (aiError != null)
        ExtractionWarning(
          code: 'ai_extraction_failed',
          message: aiError,
        ),
      if (aiResult?.document != null) ...aiResult!.document!.warnings,
    ];

    final document = NormalizedExtractionDocument(
      schemaVersion: aiResult?.document?.schemaVersion ?? '1.0',
      noteContext: input.request.noteContext,
      ocrSummary: ExtractionOcrSummary(
        fullText: input.request.ocrText,
        lineCount: input.request.ocrText
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .length,
      ),
      entries: mergedEntries,
      warnings: warnings,
      unparsedSegments: aiResult?.document?.unparsedSegments ?? const [],
    );

    if (auditSink != null && aiResult != null && aiRawResponse != null) {
      await auditSink!(
        ExtractionAuditRecord(
          noteId: input.request.noteContext.noteId,
          engineName: aiResult.engineName,
          engineModel: aiResult.modelName ?? 'unknown',
          promptVersion: input.request.promptVersion,
          inputText: input.request.ocrText,
          rawResponseJson: aiRawResponse,
          normalizedEntriesJson: document.toJson(),
          status: aiResult.success ? 'success' : 'failed',
          createdAt: DateTime.now(),
        ),
      );
    }

    return OrchestratedExtractionResult(
      document: document,
      usedRule: input.enableRule && ruleExtractor != null,
      usedAi: input.enableAi,
      ruleError: ruleError,
      aiError: aiError,
      aiRawResponse: aiRawResponse,
      ruleEntriesCount: ruleEntries.length,
      aiEntriesCount: aiEntries.length,
      mergedEntriesCount: mergedEntries.length,
    );
  }
}
