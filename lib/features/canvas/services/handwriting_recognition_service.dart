import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

import '../bloc/canvas_bloc.dart';

class HandwritingRecognitionResult {
  final String text;
  final String? languageCode;
  final double? score;
  final bool downloadedAnyModel;

  const HandwritingRecognitionResult({
    required this.text,
    required this.languageCode,
    required this.score,
    required this.downloadedAnyModel,
  });

  const HandwritingRecognitionResult.empty({this.downloadedAnyModel = false})
      : text = '',
        languageCode = null,
        score = null;

  bool get hasText => text.trim().isNotEmpty;
}

class HandwritingRecognitionService {
  static const List<String> _languageCodes = <String>[
    'zh-Hani-CN',
    'en',
  ];

  final DigitalInkRecognizerModelManager _modelManager;
  final Map<String, DigitalInkRecognizer> _recognizers =
      <String, DigitalInkRecognizer>{};
  final bool isWifiRequiredForModelDownload;

  /// 单个语言模型下载超时。首次下载可能较慢，留足够时间。
  static const Duration _modelDownloadTimeout = Duration(seconds: 45);

  /// 单语言识别调用超时。识别本身应在数秒内完成。
  static const Duration _recognizeTimeout = Duration(seconds: 15);

  HandwritingRecognitionService({
    DigitalInkRecognizerModelManager? modelManager,
    this.isWifiRequiredForModelDownload = false,
  }) : _modelManager = modelManager ?? DigitalInkRecognizerModelManager();

  Future<HandwritingRecognitionResult> recognize({
    required List<DrawingStroke> strokes,
    required Size writingArea,
  }) async {
    final visibleStrokes = strokes
        .where((stroke) => !stroke.isEraser && stroke.points.isNotEmpty)
        .toList(growable: false);

    if (visibleStrokes.isEmpty) {
      return const HandwritingRecognitionResult.empty();
    }

    debugPrint(
      '[handwriting] recognize start strokes=${visibleStrokes.length}',
    );
    final downloadedAnyModel = await _ensureModelsReady();
    final normalizedInk = _normalizeInk(
      strokes: visibleStrokes,
      writingArea: writingArea,
    );
    debugPrint(
      '[handwriting] ink normalized w=${normalizedInk.width.toStringAsFixed(1)} '
      'h=${normalizedInk.height.toStringAsFixed(1)} '
      'inkStrokes=${normalizedInk.ink.strokes.length}',
    );
    final context = DigitalInkRecognitionContext(
      writingArea: WritingArea(
        width: normalizedInk.width,
        height: normalizedInk.height,
      ),
    );

    final attempts = <_RecognitionAttempt>[];
    for (final languageCode in _languageCodes) {
      final recognizer = _recognizers.putIfAbsent(
        languageCode,
        () => DigitalInkRecognizer(languageCode: languageCode),
      );
      List<RecognitionCandidate> candidates;
      try {
        candidates = await recognizer
            .recognize(normalizedInk.ink, context: context)
            .timeout(_recognizeTimeout);
      } on TimeoutException {
        debugPrint(
          '[handwriting] recognize($languageCode) timeout after '
          '${_recognizeTimeout.inSeconds}s — skipping language',
        );
        continue;
      } catch (error, stack) {
        debugPrint(
          '[handwriting] recognize($languageCode) error: $error\n$stack',
        );
        continue;
      }
      final bestCandidate = candidates
          .where((candidate) => candidate.text.trim().isNotEmpty)
          .fold<RecognitionCandidate?>(
        null,
        (best, candidate) {
          if (best == null) return candidate;
          if (candidate.score < best.score) return candidate;
          if (candidate.score == best.score &&
              candidate.text.trim().length > best.text.trim().length) {
            return candidate;
          }
          return best;
        },
      );
      if (bestCandidate == null) continue;
      attempts.add(
        _RecognitionAttempt(
          text: bestCandidate.text.trim(),
          score: bestCandidate.score,
          languageCode: languageCode,
        ),
      );
    }

    final bestAttempt = _selectBestAttempt(attempts);
    if (bestAttempt == null) {
      return HandwritingRecognitionResult.empty(
        downloadedAnyModel: downloadedAnyModel,
      );
    }

    return HandwritingRecognitionResult(
      text: bestAttempt.text,
      languageCode: bestAttempt.languageCode,
      score: bestAttempt.score,
      downloadedAnyModel: downloadedAnyModel,
    );
  }

  Future<bool> _ensureModelsReady() async {
    var downloadedAnyModel = false;
    for (final languageCode in _languageCodes) {
      bool downloaded;
      try {
        downloaded = await _modelManager
            .isModelDownloaded(languageCode)
            .timeout(_modelDownloadTimeout);
      } on TimeoutException {
        debugPrint(
          '[handwriting] isModelDownloaded($languageCode) timeout — '
          'skipping language',
        );
        continue;
      } catch (error) {
        debugPrint(
          '[handwriting] isModelDownloaded($languageCode) error: $error',
        );
        continue;
      }
      if (downloaded) {
        debugPrint('[handwriting] model $languageCode already downloaded');
        continue;
      }
      debugPrint('[handwriting] downloading model $languageCode ...');
      try {
        final success = await _modelManager
            .downloadModel(
              languageCode,
              isWifiRequired: isWifiRequiredForModelDownload,
            )
            .timeout(_modelDownloadTimeout);
        debugPrint(
          '[handwriting] model $languageCode download success=$success',
        );
        downloadedAnyModel = downloadedAnyModel || success;
      } on TimeoutException {
        debugPrint(
          '[handwriting] downloadModel($languageCode) timeout after '
          '${_modelDownloadTimeout.inSeconds}s — skipping language',
        );
      } catch (error) {
        debugPrint(
          '[handwriting] downloadModel($languageCode) error: $error',
        );
      }
    }
    return downloadedAnyModel;
  }

  _NormalizedInk _normalizeInk({
    required List<DrawingStroke> strokes,
    required Size writingArea,
  }) {
    final bounds = _strokeBounds(strokes);
    final maxStrokeWidth = strokes.fold<double>(
      3,
      (maxWidth, stroke) => math.max(maxWidth, stroke.strokeWidth),
    );

    final strokePadding = math.max(maxStrokeWidth * 4, 18);
    final canvasPadding = math.max(maxStrokeWidth * 5, 32);
    final contentWidth = math.max(bounds.width, 1.0);
    final contentHeight = math.max(bounds.height, 1.0);
    final sourceWidth = contentWidth + canvasPadding * 2;
    final sourceHeight = contentHeight + canvasPadding * 2;
    final longEdge = math.max(sourceWidth, sourceHeight);
    final targetLongEdge = writingArea.shortestSide < 480 ? 960.0 : 1280.0;
    final scale = longEdge <= 0 ? 1.0 : targetLongEdge / longEdge;

    final ink = Ink();
    var timestamp = 0;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final normalizedStroke = Stroke();
      var previousPoint = stroke.points.first;

      for (var index = 0; index < stroke.points.length; index += 1) {
        final point = stroke.points[index];
        if (index > 0) {
          final distance = (point - previousPoint).distance;
          timestamp += math.max(12, math.min(48, (distance * 2).round()));
        }
        normalizedStroke.points.add(
          StrokePoint(
            x: (point.dx - bounds.left + canvasPadding) * scale,
            y: (point.dy - bounds.top + canvasPadding) * scale,
            t: timestamp,
          ),
        );
        previousPoint = point;
      }

      timestamp += 96;
      ink.strokes.add(normalizedStroke);
    }

    return _NormalizedInk(
      ink: ink,
      width: sourceWidth * scale + strokePadding,
      height: sourceHeight * scale + strokePadding,
    );
  }

  Rect _strokeBounds(List<DrawingStroke> strokes) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final stroke in strokes) {
      for (final point in stroke.points) {
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    final width = math.max(maxX - minX, 1.0);
    final height = math.max(maxY - minY, 1.0);
    return Rect.fromLTWH(minX, minY, width, height);
  }

  _RecognitionAttempt? _selectBestAttempt(List<_RecognitionAttempt> attempts) {
    if (attempts.isEmpty) return null;

    attempts.sort((left, right) {
      final leftChinese = _containsChinese(left.text);
      final rightChinese = _containsChinese(right.text);
      if (leftChinese != rightChinese) {
        return leftChinese ? -1 : 1;
      }

      final leftAscii = _isMostlyAscii(left.text);
      final rightAscii = _isMostlyAscii(right.text);
      if (leftAscii != rightAscii &&
          (left.languageCode == 'en' || right.languageCode == 'en')) {
        return leftAscii ? -1 : 1;
      }

      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) return scoreCompare;

      return right.text.length.compareTo(left.text.length);
    });

    return attempts.first;
  }

  bool _containsChinese(String text) {
    return RegExp(r'[\u3400-\u9FFF]').hasMatch(text);
  }

  bool _isMostlyAscii(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return false;
    final asciiCount =
        cleaned.runes.where((rune) => rune >= 0x20 && rune <= 0x7E).length;
    return asciiCount / cleaned.runes.length >= 0.8;
  }

  Future<void> dispose() async {
    for (final recognizer in _recognizers.values) {
      await recognizer.close();
    }
    _recognizers.clear();
  }
}

class _RecognitionAttempt {
  final String text;
  final double score;
  final String languageCode;

  const _RecognitionAttempt({
    required this.text,
    required this.score,
    required this.languageCode,
  });
}

class _NormalizedInk {
  final Ink ink;
  final double width;
  final double height;

  const _NormalizedInk({
    required this.ink,
    required this.width,
    required this.height,
  });
}
