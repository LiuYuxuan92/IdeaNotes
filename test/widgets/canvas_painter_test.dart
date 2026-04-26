import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/bloc/canvas_bloc.dart';
import 'package:idea_notes/features/canvas/widgets/canvas_painter.dart';

void main() {
  group('CanvasPainter viewTransform', () {
    DrawingStroke stroke({Color color = Colors.black, double w = 3.0}) {
      return DrawingStroke(
        points: const [Offset(0, 0), Offset(10, 10)],
        color: color,
        strokeWidth: w,
      );
    }

    test('默认 viewTransform 为单位矩阵', () {
      final p = CanvasPainter(
        strokes: [stroke()],
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
      );
      expect(p.viewTransform.isIdentity(), isTrue);
    });

    test('shouldRepaint 检测 viewTransform 变化', () {
      final s = [stroke()];
      final a = CanvasPainter(
        strokes: s,
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
      );
      final b = CanvasPainter(
        strokes: s,
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
        viewTransform: Matrix4.identity()..scaleByDouble(2, 2, 1, 1),
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('shouldRepaint 检测 strokes 变化', () {
      final a = CanvasPainter(
        strokes: const <DrawingStroke>[],
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
      );
      final b = CanvasPainter(
        strokes: [stroke()],
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('shouldRepaint 检测 showGrid 变化', () {
      final a = CanvasPainter(
        strokes: const <DrawingStroke>[],
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
        showGrid: false,
      );
      final b = CanvasPainter(
        strokes: const <DrawingStroke>[],
        currentColor: Colors.black,
        currentStrokeWidth: 3.0,
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });
}
