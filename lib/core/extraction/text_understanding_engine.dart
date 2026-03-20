import 'extraction_models.dart';

class TextUnderstandingResult {
  final bool success;
  final String rawResponse;
  final String? errorMessage;
  final Duration latency;
  final String? modelName;

  const TextUnderstandingResult._({
    required this.success,
    required this.rawResponse,
    required this.errorMessage,
    required this.latency,
    required this.modelName,
  });

  const TextUnderstandingResult.success({
    required String rawResponse,
    required Duration latency,
    String? modelName,
  }) : this._(
          success: true,
          rawResponse: rawResponse,
          errorMessage: null,
          latency: latency,
          modelName: modelName,
        );

  const TextUnderstandingResult.failure({
    required String message,
    Duration latency = Duration.zero,
    String rawResponse = '',
    String? modelName,
  }) : this._(
          success: false,
          rawResponse: rawResponse,
          errorMessage: message,
          latency: latency,
          modelName: modelName,
        );
}

abstract class TextUnderstandingEngine {
  String get engineName;

  Future<bool> isAvailable();

  Future<TextUnderstandingResult> extractStructuredData(
    ExtractionRequest request,
  );
}
