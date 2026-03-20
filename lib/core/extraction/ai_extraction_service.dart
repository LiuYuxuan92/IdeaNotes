import 'extraction_models.dart';
import 'extraction_schema_parser.dart';
import 'text_understanding_engine.dart';

class AiExtractionResult {
  final bool success;
  final String engineName;
  final String? modelName;
  final Duration latency;
  final String rawResponse;
  final String? errorMessage;
  final NormalizedExtractionDocument? document;

  const AiExtractionResult._({
    required this.success,
    required this.engineName,
    required this.modelName,
    required this.latency,
    required this.rawResponse,
    required this.errorMessage,
    required this.document,
  });

  const AiExtractionResult.success({
    required String engineName,
    required String? modelName,
    required Duration latency,
    required String rawResponse,
    required NormalizedExtractionDocument document,
  }) : this._(
          success: true,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          rawResponse: rawResponse,
          errorMessage: null,
          document: document,
        );

  const AiExtractionResult.failure({
    required String engineName,
    required String message,
    String? modelName,
    Duration latency = Duration.zero,
    String rawResponse = '',
  }) : this._(
          success: false,
          engineName: engineName,
          modelName: modelName,
          latency: latency,
          rawResponse: rawResponse,
          errorMessage: message,
          document: null,
        );
}

class AiExtractionService {
  final TextUnderstandingEngine? engine;
  final ExtractionSchemaParser schemaParser;

  const AiExtractionService({
    required this.engine,
    this.schemaParser = const ExtractionSchemaParser(),
  });

  Future<AiExtractionResult> extract(ExtractionRequest request) async {
    if (engine == null) {
      return const AiExtractionResult.failure(
        engineName: 'none',
        message: 'AI engine is not configured',
      );
    }

    final available = await engine!.isAvailable();
    if (!available) {
      return AiExtractionResult.failure(
        engineName: engine!.engineName,
        message: 'AI engine is unavailable',
      );
    }

    final result = await engine!.extractStructuredData(request);
    if (!result.success) {
      return AiExtractionResult.failure(
        engineName: engine!.engineName,
        modelName: result.modelName,
        message: result.errorMessage ?? 'AI extraction failed',
        latency: result.latency,
        rawResponse: result.rawResponse,
      );
    }

    try {
      final document = schemaParser.parse(
        result.rawResponse,
        fallbackNoteContext: request.noteContext,
        fallbackOcrText: request.ocrText,
      );
      return AiExtractionResult.success(
        engineName: engine!.engineName,
        modelName: result.modelName,
        latency: result.latency,
        rawResponse: result.rawResponse,
        document: document,
      );
    } catch (error) {
      return AiExtractionResult.failure(
        engineName: engine!.engineName,
        modelName: result.modelName,
        message: 'Invalid AI schema: $error',
        latency: result.latency,
        rawResponse: result.rawResponse,
      );
    }
  }
}
