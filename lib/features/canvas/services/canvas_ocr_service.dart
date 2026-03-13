import 'dart:io';
import 'dart:typed_data';

import 'package:idea_notes/core/ocr/ocr_engine.dart';

class CanvasOcrResult {
  final bool success;
  final String text;
  final String? errorMessage;

  const CanvasOcrResult._({
    required this.success,
    required this.text,
    required this.errorMessage,
  });

  const CanvasOcrResult.success(String text)
      : this._(success: true, text: text, errorMessage: null);

  const CanvasOcrResult.failure(String message)
      : this._(success: false, text: '', errorMessage: message);
}

class CanvasOcrService {
  final Future<Directory> Function(String prefix) createTempDirectory;
  final Future<void> Function(String path, Uint8List bytes) writeFile;
  final Future<void> Function(Directory directory) deleteDirectory;

  CanvasOcrService({
    Future<Directory> Function(String prefix)? createTempDirectory,
    Future<void> Function(String path, Uint8List bytes)? writeFile,
    Future<void> Function(Directory directory)? deleteDirectory,
  })  : createTempDirectory = createTempDirectory ?? _defaultCreateTempDirectory,
        writeFile = writeFile ?? _defaultWriteFile,
        deleteDirectory = deleteDirectory ?? _defaultDeleteDirectory;

  Future<CanvasOcrResult> recognize({
    required OcrEngine? ocrEngine,
    required Uint8List? imageBytes,
  }) async {
    if (ocrEngine == null) {
      return const CanvasOcrResult.failure('OCR 引擎不可用，请确认设备支持文字识别功能');
    }

    if (imageBytes == null || imageBytes.isEmpty) {
      return const CanvasOcrResult.failure('识别失败，无法捕获画布图像');
    }

    Directory? tempDir;
    try {
      tempDir = await createTempDirectory('ocr_');
      final tempFilePath = '${tempDir.path}/canvas.png';
      await writeFile(tempFilePath, imageBytes);

      final lines = await ocrEngine.recognizeTextFromFile(tempFilePath);
      return CanvasOcrResult.success(lines.join('\n'));
    } catch (_) {
      return const CanvasOcrResult.failure('识别失败，请重试');
    } finally {
      if (tempDir != null) {
        try {
          await deleteDirectory(tempDir);
        } catch (_) {}
      }
    }
  }

  static Future<Directory> _defaultCreateTempDirectory(String prefix) {
    return Directory.systemTemp.createTemp(prefix);
  }

  static Future<void> _defaultWriteFile(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes);
  }

  static Future<void> _defaultDeleteDirectory(Directory directory) async {
    await directory.delete(recursive: true);
  }
}
