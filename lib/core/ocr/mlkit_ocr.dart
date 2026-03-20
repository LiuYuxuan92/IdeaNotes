import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_engine.dart';

/// Google ML Kit OCR 实现
/// 当前用于 Android 与 iOS 的本地文字识别。
class MlKitOcr implements OcrEngine {
  TextRecognizer? _chineseRecognizer;
  TextRecognizer? _latinRecognizer;
  bool _isInitialized = false;

  @override
  String get engineName => 'ML Kit OCR';

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      _chineseRecognizer ??=
          TextRecognizer(script: TextRecognitionScript.chinese);
      _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      _isInitialized = true;
    } catch (e, stackTrace) {
      debugPrint('Failed to initialize ML Kit OCR: $e');
      debugPrintStack(stackTrace: stackTrace);
      _chineseRecognizer = null;
      _latinRecognizer = null;
      _isInitialized = false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    await _ensureInitialized();
    return _isInitialized;
  }

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return [];

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('ideanotes_mlkit_ocr_');
      final tempFile = File('${tempDir.path}/canvas.png');
      await tempFile.writeAsBytes(imageBytes, flush: true);
      return recognizeTextFromFile(tempFile.path);
    } catch (e, stackTrace) {
      debugPrint('ML Kit OCR bytes error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return [];
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async {
    await _ensureInitialized();

    if (!_isInitialized) {
      throw Exception('ML Kit OCR not initialized');
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      return [];
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final chineseLines = await _processWith(_chineseRecognizer, inputImage);
      final latinLines = await _processWith(_latinRecognizer, inputImage);
      return _mergeResults(primary: chineseLines, secondary: latinLines);
    } catch (e, stackTrace) {
      debugPrint('ML Kit OCR file error: $e');
      debugPrintStack(stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<String>> _processWith(
    TextRecognizer? recognizer,
    InputImage inputImage,
  ) async {
    if (recognizer == null) return const [];

    final recognizedText = await recognizer.processImage(inputImage);
    return _normalizeLines(recognizedText.text);
  }

  List<String> _normalizeLines(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _mergeResults({
    required List<String> primary,
    required List<String> secondary,
  }) {
    if (primary.isEmpty) return secondary;
    if (secondary.isEmpty) return primary;

    final primaryJoined = primary.join('\n');
    final secondaryJoined = secondary.join('\n');

    if (primaryJoined == secondaryJoined) {
      return primary;
    }
    if (primaryJoined.contains(secondaryJoined)) {
      return primary;
    }
    if (secondaryJoined.contains(primaryJoined)) {
      return secondary;
    }

    final merged = <String>[];
    final seen = <String>{};
    for (final line in [...primary, ...secondary]) {
      final signature = line.replaceAll(RegExp(r'\s+'), '');
      if (signature.isEmpty || !seen.add(signature)) continue;
      merged.add(line);
    }
    return merged;
  }

  @override
  void dispose() {
    _chineseRecognizer?.close();
    _latinRecognizer?.close();
    _chineseRecognizer = null;
    _latinRecognizer = null;
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
