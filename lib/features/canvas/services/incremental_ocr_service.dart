import 'dart:typed_data';

import 'package:idea_notes/core/ocr/ocr_engine.dart';

class OcrDelta {
  final String fullText;
  final String deltaText;

  const OcrDelta({required this.fullText, required this.deltaText});
}

class IncrementalOcrService {
  final OcrEngine engine;

  const IncrementalOcrService({required this.engine});

  Future<OcrDelta> recognizeRegion(
    Uint8List bytes, {
    String previousText = '',
  }) async {
    final lines = await engine.recognizeText(bytes);
    final fullText = lines.join('\n').trim();
    final trimmedPrevious = previousText.trim();

    final String deltaText;
    if (fullText == trimmedPrevious) {
      deltaText = '';
    } else if (trimmedPrevious.isNotEmpty &&
        fullText.startsWith(trimmedPrevious)) {
      deltaText = fullText.substring(trimmedPrevious.length).trim();
    } else {
      deltaText = fullText;
    }

    return OcrDelta(fullText: fullText, deltaText: deltaText);
  }
}
