import 'package:idea_notes/core/diagnostics/error_log.dart';
import 'package:idea_notes/core/extraction/ai_extraction_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/ocr_text_correction_engine.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';
import 'package:idea_notes/core/models/note.dart';

class CanvasAiPreviewResult {
  final bool success;
  final String engineName;
  final String? modelName;
  final Duration latency;
  final String? errorMessage;
  final NormalizedExtractionDocument? document;
  final String originalText;
  final String correctedText;

  const CanvasAiPreviewResult._({
    required this.success,
    required this.engineName,
    required this.modelName,
    required this.latency,
    required this.errorMessage,
    required this.document,
    required this.originalText,
    required this.correctedText,
  });

  const CanvasAiPreviewResult.success({
    required String engineName,
    required String? modelName,
    required Duration latency,
    required NormalizedExtractionDocument document,
    required String originalText,
    required String correctedText,
  }) : this._(
          success: true,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          errorMessage: null,
          document: document,
          originalText: originalText,
          correctedText: correctedText,
        );

  const CanvasAiPreviewResult.failure({
    required String engineName,
    required String message,
    required String originalText,
    required String correctedText,
    String? modelName,
    Duration latency = Duration.zero,
  }) : this._(
          success: false,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          errorMessage: message,
          document: null,
          originalText: originalText,
          correctedText: correctedText,
        );

  bool get correctionApplied => originalText != correctedText;
}

class CanvasAiPreviewService {
  final AiExtractionService aiExtractionService;
  final OcrTextCorrectionEngine? correctionEngine;
  final String timezone;
  final String locale;

  CanvasAiPreviewService({
    required TextUnderstandingEngine engine,
    this.correctionEngine,
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
  }) : aiExtractionService = AiExtractionService(engine: engine);

  Future<CanvasAiPreviewResult> preview({
    required Note? existingNote,
    required String recognizedText,
    required DateTime now,
  }) async {
    final normalizedText = recognizedText.trim();
    if (normalizedText.isEmpty) {
      return const CanvasAiPreviewResult.failure(
        engineName: 'none',
        message: '当前还没有可供 AI 整理的识别文本',
        originalText: '',
        correctedText: '',
      );
    }

    final correctedText = await _maybeCorrectText(
      text: normalizedText,
      referenceTime: existingNote?.createdAt ?? now,
    );

    final noteContext = ExtractionNoteContext(
      noteId: existingNote?.id ?? 'preview-${now.millisecondsSinceEpoch}',
      noteCreatedAt: existingNote?.createdAt ?? now,
      timezone: timezone,
      locale: locale,
    );

    final result = await aiExtractionService.extract(
      ExtractionRequest(
        noteContext: noteContext,
        ocrText: correctedText,
      ),
    );

    if (!result.success || result.document == null) {
      return CanvasAiPreviewResult.failure(
        engineName: result.engineName,
        modelName: result.modelName,
        latency: result.latency,
        message: result.errorMessage ?? 'AI 预览失败',
        originalText: normalizedText,
        correctedText: correctedText,
      );
    }

    return CanvasAiPreviewResult.success(
      engineName: result.engineName,
      modelName: result.modelName,
      latency: result.latency,
      document: result.document!,
      originalText: normalizedText,
      correctedText: correctedText,
    );
  }

  Future<String> _maybeCorrectText({
    required String text,
    required DateTime referenceTime,
  }) async {
    if (correctionEngine == null) {
      return text;
    }

    try {
      final available = await correctionEngine!.isAvailable();
      if (!available) {
        return text;
      }

      final result = await correctionEngine!.correctText(
        OcrTextCorrectionRequest(
          text: text,
          referenceTime: referenceTime,
          timezone: timezone,
          locale: locale,
        ),
      );
      final correctedText = result.correctedText.trim();
      if (!result.success || correctedText.isEmpty) {
        return text;
      }
      return correctedText;
    } catch (e, st) {
      ErrorLog.instance.warn('ai.text_correction', 'OCR 文本纠错失败，回退到原文',
          error: e, stack: st);
      return text;
    }
  }
}
