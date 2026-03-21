import 'package:speech_to_text/speech_to_text.dart' as stt;

typedef VoiceRecognitionResultCallback = void Function(
  String words,
  bool isFinal,
);

abstract class VoiceRecognitionService {
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String message)? onError,
  });

  Future<String?> systemLocaleId();

  bool get isListening;

  Future<void> startListening({
    required VoiceRecognitionResultCallback onResult,
    void Function(String message)? onError,
    String? localeId,
    Duration listenFor = const Duration(seconds: 45),
    Duration pauseFor = const Duration(seconds: 2),
    bool partialResults = true,
  });

  Future<void> stop();

  Future<void> cancel();
}

class SpeechToTextVoiceRecognitionService implements VoiceRecognitionService {
  final stt.SpeechToText speechToText;

  SpeechToTextVoiceRecognitionService({
    stt.SpeechToText? speechToText,
  }) : speechToText = speechToText ?? stt.SpeechToText();

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String message)? onError,
  }) async {
    return speechToText.initialize(
      onStatus: onStatus,
      onError: (error) => onError?.call(error.errorMsg),
    );
  }

  @override
  Future<String?> systemLocaleId() async {
    try {
      final locale = await speechToText.systemLocale();
      return locale.localeId;
    } catch (_) {
      return null;
    }
  }

  @override
  bool get isListening => speechToText.isListening;

  @override
  Future<void> startListening({
    required VoiceRecognitionResultCallback onResult,
    void Function(String message)? onError,
    String? localeId,
    Duration listenFor = const Duration(seconds: 45),
    Duration pauseFor = const Duration(seconds: 2),
    bool partialResults = true,
  }) async {
    final ok = await speechToText.listen(
      onResult: (result) => onResult(
        result.recognizedWords,
        result.finalResult,
      ),
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: partialResults,
      localeId: localeId,
      onSoundLevelChange: null,
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true,
        partialResults: partialResults,
      ),
    );

    if (!ok) {
      onError?.call('语音识别启动失败');
    }
  }

  @override
  Future<void> stop() => speechToText.stop();

  @override
  Future<void> cancel() => speechToText.cancel();
}

