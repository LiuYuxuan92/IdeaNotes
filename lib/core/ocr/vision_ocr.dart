import 'dart:io';
import 'dart:typed_data';

import 'mlkit_ocr.dart';
import 'ocr_engine.dart';

/// iOS OCR 入口。
/// 当前统一复用 ML Kit 的跨平台实现，避免平台分支出现空实现。
class VisionOcr implements OcrEngine {
  final MlKitOcr _delegate = MlKitOcr();

  @override
  String get engineName => 'iOS OCR';

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    return _delegate.isAvailable();
  }

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) {
    return _delegate.recognizeText(imageBytes);
  }

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) {
    return _delegate.recognizeTextFromFile(imagePath);
  }

  @override
  void dispose() {
    _delegate.dispose();
  }
}

class VisionOcrOptions {
  final String language;
  final bool enableLanguageDetection;
  final String accuracy;

  const VisionOcrOptions({
    this.language = 'en',
    this.enableLanguageDetection = false,
    this.accuracy = 'accurate',
  });
}

class OcrEngineFactory {
  static OcrEngine createForPlatform() {
    if (Platform.isAndroid) {
      return MlKitOcr();
    }
    if (Platform.isIOS) {
      return VisionOcr();
    }
    return MlKitOcr();
  }

  static OcrEngine create(String type) {
    switch (type) {
      case 'mlkit':
        return MlKitOcr();
      case 'vision':
        return VisionOcr();
      default:
        return createForPlatform();
    }
  }
}
