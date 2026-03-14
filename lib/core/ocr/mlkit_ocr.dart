import 'dart:io';
import 'dart:typed_data';

import 'ocr_engine.dart';

/// Google MLKit OCR 实现
/// 用于 Android 系统
class MlKitOcr implements OcrEngine {
  // MLKit 依赖 flutter_mlkit_text_recognition
  // 注意：实际使用时需要在 pubspec.yaml 中添加依赖：
  // flutter_mlkit_text_recognition: ^0.11.0

  dynamic _textRecognizer;
  bool _isInitialized = false;

  @override
  String get engineName => 'MLKit OCR';

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      // 尝试导入并初始化 MLKit
      // import 'package:flutter_mlkit_text_recognition/flutter_mlkit_text_recognition.dart';
      // _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      _isInitialized = true;
    } catch (e) {
      print('Failed to initialize MLKit: $e');
      _isInitialized = false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (Platform.isAndroid) {
      await _ensureInitialized();
      return _isInitialized;
    }
    return false;
  }

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async {
    await _ensureInitialized();

    if (!_isInitialized) {
      throw Exception('MLKit OCR not initialized');
    }

    try {
      return _mockRecognizeText(imageBytes);
    } catch (e) {
      print('MLKit OCR error: $e');
      return [];
    }
  }

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async {
    await _ensureInitialized();

    if (!_isInitialized) {
      throw Exception('MLKit OCR not initialized');
    }

    try {
      final file = File(imagePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return _mockRecognizeText(bytes);
      }
      return [];
    } catch (e) {
      print('MLKit OCR file error: $e');
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

class MlKitOcrOptions {
  final String script;
  final bool enableLanguageDetection;

  const MlKitOcrOptions({
    this.script = 'latin',
    this.enableLanguageDetection = false,
  });
}
