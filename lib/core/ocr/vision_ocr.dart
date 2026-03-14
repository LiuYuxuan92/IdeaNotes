import 'dart:io';
import 'dart:typed_data';

import 'mlkit_ocr.dart';
import 'ocr_engine.dart';

/// Apple Vision OCR 实现
/// 用于 iOS 系统
class VisionOcr implements OcrEngine {
  dynamic _textRecognizer;
  bool _isInitialized = false;

  @override
  String get engineName => 'Apple Vision OCR';

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize Vision OCR: $e');
      _isInitialized = false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (Platform.isIOS) {
      await _ensureInitialized();
      return _isInitialized;
    }
    return false;
  }

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (!_isInitialized) {
      throw Exception('Vision OCR not initialized');
    }

    try {
      return _mockRecognizeText(imageBytes);
    } catch (e) {
      print('Vision OCR error: $e');
      return [];
    }
  }

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async {
    await _ensureInitialized();

    if (!_isInitialized) {
      throw Exception('Vision OCR not initialized');
    }

    try {
      final file = File(imagePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return _mockRecognizeText(bytes);
      }
      return [];
    } catch (e) {
      print('Vision OCR file error: $e');
      return [];
    }
  }

  Future<List<String>> _mockRecognizeText(Uint8List imageBytes) async {
    return [];
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
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
