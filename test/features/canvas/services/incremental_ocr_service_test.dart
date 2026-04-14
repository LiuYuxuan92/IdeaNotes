import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/ocr/ocr_engine.dart';
import 'package:idea_notes/features/canvas/services/incremental_ocr_service.dart';

class _FakeOcrEngine implements OcrEngine {
  final List<String> _result;

  _FakeOcrEngine(this._result);

  @override
  String get engineName => 'fake';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async => _result;

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async => _result;

  @override
  void dispose() {}
}

void main() {
  group('IncrementalOcrService', () {
    test('returns full text from OCR engine', () async {
      final service = IncrementalOcrService(
        engine: _FakeOcrEngine(['第一行', '第二行']),
      );

      final delta = await service.recognizeRegion(
        Uint8List.fromList([1, 2, 3]),
      );

      expect(delta.fullText, '第一行\n第二行');
    });

    test('returns delta text when new text extends previous', () async {
      final service = IncrementalOcrService(
        engine: _FakeOcrEngine(['第一行', '第二行', '第三行']),
      );

      final delta = await service.recognizeRegion(
        Uint8List.fromList([1, 2, 3]),
        previousText: '第一行\n第二行',
      );

      expect(delta.fullText, '第一行\n第二行\n第三行');
      expect(delta.deltaText, '第三行');
    });

    test('returns full text as delta when text does not extend previous', () async {
      final service = IncrementalOcrService(
        engine: _FakeOcrEngine(['全新内容']),
      );

      final delta = await service.recognizeRegion(
        Uint8List.fromList([1, 2, 3]),
        previousText: '旧内容',
      );

      expect(delta.fullText, '全新内容');
      expect(delta.deltaText, '全新内容');
    });

    test('returns empty delta when text unchanged', () async {
      final service = IncrementalOcrService(
        engine: _FakeOcrEngine(['第一行', '第二行']),
      );

      final delta = await service.recognizeRegion(
        Uint8List.fromList([1, 2, 3]),
        previousText: '第一行\n第二行',
      );

      expect(delta.fullText, '第一行\n第二行');
      expect(delta.deltaText, '');
    });
  });
}
