import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/bloc/canvas_bloc.dart';
import 'package:idea_notes/features/canvas/models/stroke_style.dart';
import 'package:idea_notes/features/canvas/widgets/canvas_painter.dart';

void main() {
  test('highlighter style is translucent', () {
    expect(StrokeStyle.highlighter.opacity, 0.35);
  });

  testWidgets('CanvasPainter uses style opacity', (tester) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(40, 40);
    const stroke = DrawingStroke(
      points: [Offset(4, 4), Offset(20, 20), Offset(36, 36)],
      color: Colors.blue,
      strokeWidth: 10,
      style: StrokeStyle.highlighter,
    );

    CanvasPainter(
      strokes: const [stroke],
      currentColor: Colors.black,
      currentStrokeWidth: 1,
    ).paint(canvas, size);

    final pixel = await tester.runAsync(() async {
      final image = await recorder.endRecording().toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
      return image.toByteData();
    });
    final center = pixel!.getUint32((20 * size.width.toInt() + 20) * 4);
    final color = Color(center);

    expect(color.a, lessThan(1.0));
    expect(color.b, greaterThan(0.0));
  });

  testWidgets('CanvasPainter applies widthMultiplier to stroke width', (
    tester,
  ) async {
    const size = Size(100, 40);

    // Draw a horizontal pen stroke (widthMultiplier = 1.0)
    final penRecorder = PictureRecorder();
    final penCanvas = Canvas(penRecorder);
    const penStroke = DrawingStroke(
      points: [Offset(10, 20), Offset(90, 20)],
      color: Colors.black,
      strokeWidth: 4,
      style: StrokeStyle.pen, // widthMultiplier = 1.0
    );
    CanvasPainter(
      strokes: const [penStroke],
      currentColor: Colors.black,
      currentStrokeWidth: 4,
    ).paint(penCanvas, size);

    final penPixels = await tester.runAsync(() async {
      final image = await penRecorder.endRecording().toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
      return image.toByteData();
    });

    // Draw a horizontal highlighter stroke (widthMultiplier = 2.4)
    final hlRecorder = PictureRecorder();
    final hlCanvas = Canvas(hlRecorder);
    const hlStroke = DrawingStroke(
      points: [Offset(10, 20), Offset(90, 20)],
      color: Colors.black,
      strokeWidth: 4,
      style: StrokeStyle.highlighter, // widthMultiplier = 2.4
    );
    CanvasPainter(
      strokes: const [hlStroke],
      currentColor: Colors.black,
      currentStrokeWidth: 4,
    ).paint(hlCanvas, size);

    final hlPixels = await tester.runAsync(() async {
      final image = await hlRecorder.endRecording().toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
      return image.toByteData();
    });

    // Count non-white pixels in each image
    int penCount = 0;
    int hlCount = 0;
    for (int i = 0; i < size.width.toInt() * size.height.toInt(); i++) {
      final penColor = Color(penPixels!.getUint32(i * 4));
      if (penColor != Colors.white) penCount++;

      final hlColor = Color(hlPixels!.getUint32(i * 4));
      if (hlColor != Colors.white) hlCount++;
    }

    // Highlighter with 2.4x width multiplier should cover significantly
    // more pixels than pen with 1.0x multiplier at the same strokeWidth.
    expect(hlCount, greaterThan(penCount * 2));
  });
}
