import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../bloc/canvas_bloc.dart';
import '../widgets/canvas_painter.dart';

/// 把全部笔迹离屏渲染为 PNG。
///
/// 适用场景：
/// - 保存笔记时生成完整 snapshot（不受当前视口限制）
/// - 给 OCR 引擎喂一张涵盖所有笔迹的图
/// - 列表缩略图（按笔迹边界缩到目标尺寸）
///
/// 渲染流程：
/// 1. 计算所有笔迹的轴对齐边界 + padding
/// 2. 用 [PictureRecorder] 起一个等于 bounds 大小的离屏 Canvas
/// 3. translate 让 bounds.topLeft 对齐 (0,0)
/// 4. 复用 [CanvasPainter.paintStroke] 逐条画
/// 5. 输出 PNG 字节
class OffscreenCanvasRenderer {
  const OffscreenCanvasRenderer();

  /// 渲染参数。
  ///
  /// - [padding]：笔迹四周保留的空白（World 像素）
  /// - [pixelRatio]：物理像素 / 逻辑像素，越高越清晰，但越占内存
  /// - [maxLongEdgePx]：物理像素长边上限。超过会按比例缩 pixelRatio。
  ///   设为 null 表示不限制。
  /// - [backgroundColor]：背景填色，OCR 一般用纯白
  Future<RenderResult?> render({
    required List<DrawingStroke> strokes,
    double padding = 64,
    double pixelRatio = 3.0,
    int? maxLongEdgePx = 4096,
    Color backgroundColor = Colors.white,
  }) async {
    final bounds = computeInkBounds(strokes, padding: padding);
    if (bounds == null) return null;

    // 钳制 pixelRatio 让长边不超过上限
    final longEdgeLogical = math.max(bounds.width, bounds.height);
    var actualPixelRatio = pixelRatio;
    if (maxLongEdgePx != null && longEdgeLogical > 0) {
      final maxPxRatio = maxLongEdgePx / longEdgeLogical;
      if (actualPixelRatio > maxPxRatio) {
        actualPixelRatio = maxPxRatio;
      }
    }
    if (actualPixelRatio <= 0) actualPixelRatio = 1.0;

    final widthLogical = bounds.width;
    final heightLogical = bounds.height;
    final widthPx = math.max(1, (widthLogical * actualPixelRatio).round());
    final heightPx = math.max(1, (heightLogical * actualPixelRatio).round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widthLogical, heightLogical),
    );

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthLogical, heightLogical),
      Paint()..color = backgroundColor,
    );

    // 用 saveLayer 让橡皮擦 BlendMode.clear 生效（与屏上 painter 一致）
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, widthLogical, heightLogical),
      Paint(),
    );

    // 让 bounds.topLeft 对齐 (0,0)
    canvas.translate(-bounds.left, -bounds.top);

    for (final stroke in strokes) {
      CanvasPainter.paintStroke(canvas, stroke);
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthPx, heightPx);
    picture.dispose();

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;

    return RenderResult(
      pngBytes: byteData.buffer.asUint8List(),
      logicalSize: Size(widthLogical, heightLogical),
      pixelSize: Size(widthPx.toDouble(), heightPx.toDouble()),
      worldBounds: bounds,
    );
  }

  /// 计算所有可见笔迹（去掉橡皮）的轴对齐边界。
  /// 没有可见笔迹时返回 null。
  static Rect? computeInkBounds(
    List<DrawingStroke> strokes, {
    double padding = 0,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var has = false;

    for (final stroke in strokes) {
      if (stroke.isEraser) continue;
      final w = math.max(stroke.strokeWidth, 4.0);
      for (final p in stroke.points) {
        if (p.dx - w < minX) minX = p.dx - w;
        if (p.dy - w < minY) minY = p.dy - w;
        if (p.dx + w > maxX) maxX = p.dx + w;
        if (p.dy + w > maxY) maxY = p.dy + w;
        has = true;
      }
    }
    if (!has) return null;

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }
}

/// 离屏渲染输出。
class RenderResult {
  /// PNG 编码后的字节。
  final Uint8List pngBytes;

  /// 逻辑像素尺寸（DIP）。
  final Size logicalSize;

  /// 物理像素尺寸。
  final Size pixelSize;

  /// 笔迹在 World 坐标系下的边界（含 padding）。
  /// 用于反查"PNG 中某个像素对应 World 哪个位置"。
  final Rect worldBounds;

  const RenderResult({
    required this.pngBytes,
    required this.logicalSize,
    required this.pixelSize,
    required this.worldBounds,
  });
}
