import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/ocr/ocr_engine.dart';
import 'package:idea_notes/features/canvas/services/canvas_ocr_service.dart';

class _FakeOcrEngine implements OcrEngine {
  @override
  String get engineName => 'fake';

  List<String> result;
  Object? error;
  String? lastPath;

  _FakeOcrEngine({this.result = const [], this.error});

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async => result;

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async {
    lastPath = imagePath;
    if (error != null) throw error!;
    return result;
  }

  @override
  void dispose() {}
}

void main() {
  group('CanvasOcrService', () {
    test('ocrEngine 为空时返回引擎不可用错误', () async {
      final service = CanvasOcrService();
      final result = await service.recognize(
        ocrEngine: null,
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, 'OCR 引擎不可用，请确认设备支持文字识别功能');
    });

    test('imageBytes 为空时返回捕获失败错误', () async {
      final service = CanvasOcrService();
      final result = await service.recognize(
        ocrEngine: _FakeOcrEngine(),
        imageBytes: Uint8List(0),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, '识别失败，无法捕获画布图像');
    });

    test('识别成功时会拼接多行文本并清理临时目录', () async {
      final createdDirs = <Directory>[];
      final deletedDirs = <String>[];
      final writtenFiles = <String>[];
      final engine = _FakeOcrEngine(result: ['第一行', '第二行']);

      final service = CanvasOcrService(
        createTempDirectory: (prefix) async {
          final dir = await Directory.systemTemp.createTemp(prefix);
          createdDirs.add(dir);
          return dir;
        },
        writeFile: (path, bytes) async {
          writtenFiles.add(path);
          await File(path).writeAsBytes(bytes);
        },
        deleteDirectory: (dir) async {
          deletedDirs.add(dir.path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        },
      );

      final result = await service.recognize(
        ocrEngine: engine,
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.success, isTrue);
      expect(result.text, '第一行\n第二行');
      expect(writtenFiles, isNotEmpty);
      expect(engine.lastPath, isNotNull);
      expect(deletedDirs, isNotEmpty);
    });

    test('识别异常时返回统一错误信息', () async {
      final service = CanvasOcrService(
        createTempDirectory: (prefix) async => Directory.systemTemp.createTemp(prefix),
        writeFile: (path, bytes) async => File(path).writeAsBytes(bytes),
      );

      final result = await service.recognize(
        ocrEngine: _FakeOcrEngine(error: Exception('boom')),
        imageBytes: Uint8List.fromList([1]),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, '识别失败，请重试');
    });
  });
}
