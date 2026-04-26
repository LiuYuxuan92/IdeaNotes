import 'package:flutter/material.dart';
import '../bloc/canvas_bloc.dart';

/// CustomPainter 实现 - 负责绘制手写笔迹
class CanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset>? currentPoints;
  final List<double>? currentPressures;
  final Color currentColor;
  final double currentStrokeWidth;
  final bool isErasing;

  /// 视图变换（World → Screen）。默认单位矩阵=不变换。
  /// 笔迹的 [points] 始终在 World 坐标系下，绘制时通过 transform 映射到屏。
  final Matrix4 viewTransform;

  /// 是否绘制 World 坐标系下的网格背景，给用户提供空间感参考。
  final bool showGrid;

  CanvasPainter({
    required this.strokes,
    this.currentPoints,
    this.currentPressures,
    required this.currentColor,
    required this.currentStrokeWidth,
    this.isErasing = false,
    Matrix4? viewTransform,
    this.showGrid = true,
  }) : viewTransform = viewTransform ?? Matrix4.identity();

  @override
  void paint(Canvas canvas, Size size) {
    // 屏幕白底（纸张背景）
    _drawBackground(canvas, size);

    // 应用视图变换：之后所有 draw 调用都在 World 坐标系下
    canvas.save();
    canvas.transform(viewTransform.storage);

    // 在 World 坐标系下绘制网格（仅在网格位于可视范围时绘）
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // 使用 saveLayer 以支持橡皮擦的 BlendMode.clear
    // saveLayer 边界用一个保守大矩形包住可视区（避免裁掉 stroke）
    final layerBounds = _visibleWorldRect(size).inflate(64);
    canvas.saveLayer(layerBounds, Paint());

    // 绘制已完成的笔画
    for (final stroke in strokes) {
      paintStroke(canvas, stroke);
    }

    // 绘制当前正在绘制的笔画
    if (currentPoints != null && currentPoints!.isNotEmpty) {
      final currentStroke = DrawingStroke(
        points: currentPoints!,
        color: currentColor,
        strokeWidth: currentStrokeWidth,
        isEraser: isErasing,
        pressures: currentPressures,
      );
      paintStroke(canvas, currentStroke);
    }

    canvas.restore(); // saveLayer
    canvas.restore(); // viewTransform
  }

  void _drawBackground(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
  }

  /// World 空间下的网格：每 80px 一格，淡灰；缩放时随之放大缩小。
  void _drawGrid(Canvas canvas, Size screenSize) {
    final visible = _visibleWorldRect(screenSize);
    const gridSize = 80.0;
    final scale = _currentScale();
    // 缩放过小（<0.4）时网格变密集导致视觉嘈杂，干脆不画
    if (scale < 0.4) return;

    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 0.5 / scale; // 屏上保持 ~0.5px

    final startX = (visible.left / gridSize).floor() * gridSize;
    final endX = (visible.right / gridSize).ceil() * gridSize;
    final startY = (visible.top / gridSize).floor() * gridSize;
    final endY = (visible.bottom / gridSize).ceil() * gridSize;

    for (double x = startX; x <= endX; x += gridSize) {
      canvas.drawLine(
        Offset(x, visible.top),
        Offset(x, visible.bottom),
        paint,
      );
    }
    for (double y = startY; y <= endY; y += gridSize) {
      canvas.drawLine(
        Offset(visible.left, y),
        Offset(visible.right, y),
        paint,
      );
    }
  }

  /// 把屏幕矩形 (0,0) - (size) 反向映射回 World 坐标矩形。
  Rect _visibleWorldRect(Size screenSize) {
    final inverse = Matrix4.tryInvert(viewTransform);
    if (inverse == null) {
      return Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    }
    final tl = MatrixUtils.transformPoint(inverse, Offset.zero);
    final tr = MatrixUtils.transformPoint(
      inverse,
      Offset(screenSize.width, 0),
    );
    final bl = MatrixUtils.transformPoint(
      inverse,
      Offset(0, screenSize.height),
    );
    final br = MatrixUtils.transformPoint(
      inverse,
      Offset(screenSize.width, screenSize.height),
    );
    final minX = [tl.dx, tr.dx, bl.dx, br.dx].reduce((a, b) => a < b ? a : b);
    final maxX = [tl.dx, tr.dx, bl.dx, br.dx].reduce((a, b) => a > b ? a : b);
    final minY = [tl.dy, tr.dy, bl.dy, br.dy].reduce((a, b) => a < b ? a : b);
    final maxY = [tl.dy, tr.dy, bl.dy, br.dy].reduce((a, b) => a > b ? a : b);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _currentScale() {
    // 取均匀缩放（变换矩阵第一列向量长度）。我们的 viewTransform 不支持旋转。
    final storage = viewTransform.storage;
    final s = storage[0];
    return s.abs() < 1e-6 ? 1.0 : s;
  }

  /// 绘制单条笔画（公开静态方法，供离屏渲染器复用）。
  ///
  /// 调用方需自行决定 [canvas] 的变换与 saveLayer 时机；本方法只负责把笔画的
  /// 点序列、压力、橡皮等正确画到 canvas 上。
  static void paintStroke(Canvas canvas, DrawingStroke stroke) {
    _drawStrokeImpl(canvas, stroke);
  }

  static void _drawStrokeImpl(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

    final basePaint = Paint()
      ..color = stroke.isEraser ? Colors.transparent : stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    if (stroke.points.length == 1) {
      // 单点绘制圆点
      final point = stroke.points.first;
      final pressure = stroke.pressures != null && stroke.pressures!.isNotEmpty
          ? stroke.pressures!.first
          : 1.0;
      final radius = stroke.strokeWidth * (0.5 + 0.5 * pressure) / 2;
      canvas.drawCircle(
        point,
        radius,
        basePaint..style = PaintingStyle.fill,
      );
      return;
    }

    final hasPressure = stroke.pressures != null &&
        stroke.pressures!.length == stroke.points.length;

    // 橡皮 / 无压力数据 → 单 Path 平滑（原算法）
    if (stroke.isEraser || !hasPressure) {
      basePaint.strokeWidth = stroke.strokeWidth;
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length - 1; i++) {
        final p0 = stroke.points[i];
        final p1 = stroke.points[i + 1];
        final midPoint = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
      canvas.drawPath(path, basePaint);
      return;
    }

    // 压力感应模式：按段分别用平滑后的宽度绘制（笔锋效果）
    final pressures = stroke.pressures!;
    final pts = stroke.points;
    // 平滑压力值（前后窗口平均）以避免突变
    final smoothed = List<double>.generate(pressures.length, (i) {
      final start = (i - 1).clamp(0, pressures.length - 1);
      final end = (i + 1).clamp(0, pressures.length - 1);
      double sum = 0;
      int count = 0;
      for (int k = start; k <= end; k++) {
        sum += pressures[k];
        count++;
      }
      return sum / count;
    });

    double widthFor(double p) => stroke.strokeWidth * (0.55 + 0.45 * p);

    // 用相邻三点画 quadratic 段，宽度取段两端均值
    Path makeSegmentPath(Offset a, Offset b, Offset c) {
      final mid = Offset((b.dx + c.dx) / 2, (b.dy + c.dy) / 2);
      return Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(b.dx, b.dy, mid.dx, mid.dy);
    }

    Offset prev = pts.first;
    for (int i = 1; i < pts.length - 1; i++) {
      final w = (widthFor(smoothed[i - 1]) + widthFor(smoothed[i])) / 2;
      final segPath = makeSegmentPath(prev, pts[i], pts[i + 1]);
      canvas.drawPath(segPath, Paint()
        ..color = basePaint.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..blendMode = basePaint.blendMode);
      prev = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
    }
    // 最后一段
    final lastW = widthFor(smoothed.last);
    canvas.drawLine(
      prev,
      pts.last,
      Paint()
        ..color = basePaint.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = lastW
        ..blendMode = basePaint.blendMode,
    );
  }

  @override
  bool shouldRepaint(covariant CanvasPainter oldDelegate) {
    // 当笔画数据或视图变换发生变化时需要重绘
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentPoints != currentPoints ||
        oldDelegate.currentPressures != currentPressures ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth ||
        oldDelegate.isErasing != isErasing ||
        oldDelegate.viewTransform != viewTransform ||
        oldDelegate.showGrid != showGrid;
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
