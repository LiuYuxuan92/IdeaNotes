import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Captures a sub-region of a [RepaintBoundary] and returns cropped PNG bytes.
///
/// Typical usage:
/// ```dart
/// final bytes = await RegionCaptureService().capture(
///   repaintKey: _canvasRepaintKey,
///   region: bounds,
/// );
/// ```
class RegionCaptureService {
  /// Captures the given [region] from the widget tree identified by [repaintKey].
  ///
  /// Returns `null` if the boundary cannot be found or the capture fails.
  Future<Uint8List?> capture({
    required GlobalKey repaintKey,
    required Rect region,
    double pixelRatio = 3.0,
  }) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final fullImage = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await fullImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return null;

    final fullBytes = byteData.buffer.asUint8List();
    return _cropRegion(fullBytes, region, boundary.size, pixelRatio);
  }

  /// Crops a logical [region] out of [pngBytes] using [logicalCanvasSize] and
  /// [pixelRatio] to convert logical coordinates to pixel coordinates.
  Uint8List? _cropRegion(
    Uint8List pngBytes,
    Rect region,
    Size logicalCanvasSize,
    double pixelRatio,
  ) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return null;

    final padding = math.min(
      math.max(logicalCanvasSize.shortestSide * 0.06, 12.0),
      36.0,
    );
    final expanded = Rect.fromLTRB(
      math.max(0, region.left - padding),
      math.max(0, region.top - padding),
      math.min(logicalCanvasSize.width, region.right + padding),
      math.min(logicalCanvasSize.height, region.bottom + padding),
    );

    final cropX = (expanded.left * pixelRatio).floor();
    final cropY = (expanded.top * pixelRatio).floor();
    final cropWidth = math.max(1, (expanded.width * pixelRatio).ceil());
    final cropHeight = math.max(1, (expanded.height * pixelRatio).ceil());

    var cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    final longEdge = math.max(cropped.width, cropped.height);
    if (longEdge < 1200) {
      cropped = cropped.width >= cropped.height
          ? img.copyResize(
              cropped,
              width: 1200,
              interpolation: img.Interpolation.linear,
            )
          : img.copyResize(
              cropped,
              height: 1200,
              interpolation: img.Interpolation.linear,
            );
    }

    return Uint8List.fromList(img.encodePng(cropped));
  }
}
