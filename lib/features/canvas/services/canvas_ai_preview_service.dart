import 'package:idea_notes/core/extraction/ai_extraction_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';
import 'package:idea_notes/core/models/note.dart';

class CanvasAiPreviewResult {
  final bool success;
  final String engineName;
  final String? modelName;
  final Duration latency;
  final String? errorMessage;
  final NormalizedExtractionDocument? document;

  const CanvasAiPreviewResult._({
    required this.success,
    required this.engineName,
    required this.modelName,
    required this.latency,
    required this.errorMessage,
    required this.document,
  });

  const CanvasAiPreviewResult.success({
    required String engineName,
    required String? modelName,
    required Duration latency,
    required NormalizedExtractionDocument document,
  }) : this._(
          success: true,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          errorMessage: null,
          document: document,
        );

  const CanvasAiPreviewResult.failure({
    required String engineName,
    required String message,
    String? modelName,
    Duration latency = Duration.zero,
  }) : this._(
          success: false,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          errorMessage: message,
          document: null,
        );
}

class CanvasAiPreviewService {
  final AiExtractionService aiExtractionService;
  final String timezone;
  final String locale;

  CanvasAiPreviewService({
    required TextUnderstandingEngine engine,
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
      );
    }

    final noteContext = ExtractionNoteContext(
      noteId: existingNote?.id ?? 'preview-${now.millisecondsSinceEpoch}',
      noteCreatedAt: existingNote?.createdAt ?? now,
      timezone: timezone,
      locale: locale,
    );

    final result = await aiExtractionService.extract(
      ExtractionRequest(
        noteContext: noteContext,
        ocrText: normalizedText,
      ),
    );

    if (!result.success || result.document == null) {
      return CanvasAiPreviewResult.failure(
        engineName: result.engineName,
        modelName: result.modelName,
        latency: result.latency,
        message: result.errorMessage ?? 'AI 预览失败',
      );
    }

    return CanvasAiPreviewResult.success(
      engineName: result.engineName,
      modelName: result.modelName,
      latency: result.latency,
      document: result.document!,
    );
  }
}
