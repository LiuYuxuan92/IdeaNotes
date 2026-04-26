import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/bloc/canvas_bloc.dart';
import 'package:idea_notes/features/canvas/services/offscreen_canvas_renderer.dart';

void main() {
  group('OffscreenCanvasRenderer.computeInkBounds', () {
    DrawingStroke makeStroke(
      List<Offset> pts, {
      double width = 4.0,
      bool eraser = false,
    }) {
      return DrawingStroke(
        points: pts,
        color: Colors.black,
        strokeWidth: width,
        isEraser: eraser,
      );
    }

    test('空 strokes 返回 null', () {
      expect(OffscreenCanvasRenderer.computeInkBounds([]), isNull);
    });

    test('全是橡皮（无墨迹）返回 null', () {
      final strokes = [
        makeStroke([const Offset(0, 0), const Offset(50, 50)], eraser: true),
      ];
      expect(OffscreenCanvasRenderer.computeInkBounds(strokes), isNull);
    });

    test('单笔画 → 边界包住起止点 + 笔宽外扩', () {
      final strokes = [
        makeStroke(
          [const Offset(10, 10), const Offset(30, 40)],
          width: 4.0,
        ),
      ];
      final bounds = OffscreenCanvasRenderer.computeInkBounds(strokes);
      expect(bounds, isNotNull);
      // 笔宽 4 但 max(width,4) = 4 → 上下左右各扩 4
      expect(bounds!.left, lessThanOrEqualTo(10 - 4));
      expect(bounds.top, lessThanOrEqualTo(10 - 4));
      expect(bounds.right, greaterThanOrEqualTo(30 + 4));
      expect(bounds.bottom, greaterThanOrEqualTo(40 + 4));
    });

    test('多笔画 → 边界覆盖所有点', () {
      final strokes = [
        makeStroke([const Offset(-100, -50)]),
        makeStroke([const Offset(200, 300)]),
        makeStroke([const Offset(50, 50)]),
      ];
      final bounds = OffscreenCanvasRenderer.computeInkBounds(strokes);
      expect(bounds, isNotNull);
      expect(bounds!.left, lessThanOrEqualTo(-100));
      expect(bounds.top, lessThanOrEqualTo(-50));
      expect(bounds.right, greaterThanOrEqualTo(200));
      expect(bounds.bottom, greaterThanOrEqualTo(300));
    });

    test('忽略橡皮笔画', () {
      final strokes = [
        makeStroke([const Offset(0, 0), const Offset(10, 10)]),
        makeStroke(
          [const Offset(1000, 1000)],
          eraser: true,
        ),
      ];
      final bounds = OffscreenCanvasRenderer.computeInkBounds(strokes);
      expect(bounds, isNotNull);
      // 橡皮的 1000,1000 不应被计入
      expect(bounds!.right, lessThan(100));
      expect(bounds.bottom, lessThan(100));
    });

    test('额外 padding 参数生效', () {
      final strokes = [
        makeStroke([const Offset(0, 0)], width: 4),
      ];
      final base = OffscreenCanvasRenderer.computeInkBounds(strokes);
      final padded =
          OffscreenCanvasRenderer.computeInkBounds(strokes, padding: 30);
      expect(base, isNotNull);
      expect(padded, isNotNull);
      expect(padded!.width, greaterThan(base!.width));
      expect(padded.height, greaterThan(base.height));
    });

    test('支持负数 World 坐标（无限画布场景）', () {
      // 用户写到屏幕左上方外（负坐标）
      final strokes = [
        makeStroke([const Offset(-500, -800), const Offset(-400, -700)]),
      ];
      final bounds = OffscreenCanvasRenderer.computeInkBounds(strokes);
      expect(bounds, isNotNull);
      expect(bounds!.left, lessThanOrEqualTo(-500));
      expect(bounds.top, lessThanOrEqualTo(-800));
      expect(bounds.right, greaterThanOrEqualTo(-400));
      expect(bounds.bottom, greaterThanOrEqualTo(-700));
    });
  });
}
