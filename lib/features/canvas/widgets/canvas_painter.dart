import 'package:flutter/material.dart';
import 'bloc/canvas_bloc.dart';

/// CustomPainter 实现 - 负责绘制手写笔迹
class CanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset>? currentPoints;
  final Color currentColor;
  final double currentStrokeWidth;
  final bool isErasing;

  CanvasPainter({
    required this.strokes,
    this.currentPoints,
    required this.currentColor,
    required this.currentStrokeWidth,
    this.isErasing = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制背景
    _drawBackground(canvas, size);

    // 绘制已完成的笔画
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // 绘制当前正在绘制的笔画
    if (currentPoints != null && currentPoints!.isNotEmpty) {
      final currentStroke = DrawingStroke(
        points: currentPoints!,
        color: currentColor,
        strokeWidth: currentStrokeWidth,
        isEraser: isErasing,
      );
      _drawStroke(canvas, currentStroke);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.isEraser ? Colors.white : stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.srcOver : BlendMode.srcOver;

    if (stroke.points.length == 1) {
      // 单点绘制圆点
      final point = stroke.points.first;
      canvas.drawCircle(point, stroke.strokeWidth / 2, paint..style = PaintingStyle.fill);
    } else {
      // 使用贝塞尔曲线绘制平滑笔画
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length - 1; i++) {
        final p0 = stroke.points[i];
        final p1 = stroke.points[i + 1];
        final midPoint = Offset(
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
        path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
      }

      // 连接最后一个点
      if (stroke.points.length > 1) {
        final lastPoint = stroke.points.last;
        path.lineTo(lastPoint.dx, lastPoint.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    // 当笔画数据发生变化时需要重绘
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentPoints != currentPoints ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth ||
        oldDelegate.isErasing != isErasing;
  }
}

/// 用于绘制网格背景的 CustomPainter（可选）
class GridPainter extends CustomPainter {
  final double gridSize;
  final Color gridColor;

  GridPainter({
    this.gridSize = 20.0,
    this.gridColor = const Color(0xFFE0E0E0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // 绘制垂直线
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // 绘制水平线
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize || oldDelegate.gridColor != gridColor;
  }
}
