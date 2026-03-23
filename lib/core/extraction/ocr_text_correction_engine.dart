class OcrTextCorrectionRequest {
  final String text;
  final DateTime referenceTime;
  final String timezone;
  final String locale;

  const OcrTextCorrectionRequest({
    required this.text,
    required this.referenceTime,
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'reference_time': referenceTime.toIso8601String(),
      'timezone': timezone,
      'locale': locale,
    };
  }
}

class OcrTextCorrectionResult {
  final bool success;
  final String correctedText;
  final String rawResponse;
  final String? errorMessage;
  final Duration latency;
  final String? modelName;

  const OcrTextCorrectionResult._({
    required this.success,
    required this.correctedText,
    required this.rawResponse,
    required this.errorMessage,
    required this.latency,
    required this.modelName,
  });

  const OcrTextCorrectionResult.success({
    required String correctedText,
    required String rawResponse,
    required Duration latency,
    String? modelName,
  }) : this._(
          success: true,
          correctedText: correctedText,
          rawResponse: rawResponse,
          errorMessage: null,
          latency: latency,
          modelName: modelName,
        );

  const OcrTextCorrectionResult.failure({
    required String message,
    Duration latency = Duration.zero,
    String rawResponse = '',
    String correctedText = '',
    String? modelName,
  }) : this._(
          success: false,
          correctedText: correctedText,
          rawResponse: rawResponse,
          errorMessage: message,
          latency: latency,
          modelName: modelName,
        );
}

abstract class OcrTextCorrectionEngine {
  String get engineName;

  Future<bool> isAvailable();

  Future<OcrTextCorrectionResult> correctText(
    OcrTextCorrectionRequest request,
  );
}
