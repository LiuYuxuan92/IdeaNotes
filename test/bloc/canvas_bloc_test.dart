import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/bloc/canvas_bloc.dart';

void main() {
  group('CanvasBloc', () {
    late CanvasBloc bloc;

    setUp(() {
      bloc = CanvasBloc();
    });

    tearDown(() {
      bloc.close();
    });

    // ==================== 1. 初始状态 ====================

    test('初始状态 strokes 为空列表', () {
      expect(bloc.state.strokes, isEmpty);
    });

    test('初始状态 selectedTool 为 CanvasTool.pen', () {
      expect(bloc.state.currentTool, equals(CanvasTool.pen));
    });

    test('初始状态 undoStack 和 redoStack 均为空', () {
      expect(bloc.state.undoStack, isEmpty);
      expect(bloc.state.redoStack, isEmpty);
    });

    test('初始状态 canUndo 为 false，canRedo 为 false', () {
      expect(bloc.state.canUndo, isFalse);
      expect(bloc.state.canRedo, isFalse);
    });

    // ==================== 2. StrokeAdded ====================

    test('发送 StrokeAdded 后，strokes 列表包含该笔画', () async {
      const points = [Offset(0, 0), Offset(10, 10), Offset(20, 20)];

      bloc.add(const StrokeAdded(
        points: points,
        color: Colors.black,
        strokeWidth: 3.0,
      ));

      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, hasLength(1));
      expect(bloc.state.strokes.first.points, equals(points));
    });

    test('发送 StrokeAdded 后，笔画的颜色和宽度正确', () async {
      const testColor = Color(0xFF1565C0);
      const testWidth = 5.0;
      const points = [Offset(1, 2), Offset(3, 4)];

      bloc.add(const StrokeAdded(
        points: points,
        color: testColor,
        strokeWidth: testWidth,
      ));

      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes.first.color, equals(testColor));
      expect(bloc.state.strokes.first.strokeWidth, equals(testWidth));
    });

    test('发送 StrokeAdded 后，undoStack 同样增加该笔画', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));

      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.undoStack, hasLength(1));
    });

    test('发送 StrokeAdded 后，redoStack 被清空', () async {
      // 先添加一笔，再撤销，再添加新笔 => redoStack 应被清空
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(StrokeUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.redoStack, hasLength(1));

      bloc.add(const StrokeAdded(
        points: [Offset(5, 5)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.redoStack, isEmpty);
    });

    test('连续发送多个 StrokeAdded，strokes 按顺序累积', () async {
      for (int i = 0; i < 3; i++) {
        bloc.add(StrokeAdded(
          points: [Offset(i.toDouble(), i.toDouble())],
          color: Colors.black,
          strokeWidth: 3.0,
        ));
        await Future<void>.delayed(Duration.zero);
      }

      expect(bloc.state.strokes, hasLength(3));
    });

    // ==================== 3. StrokeUndone ====================

    test('发送 StrokeUndone 后，最后一笔从 strokes 移除', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(StrokeUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, isEmpty);
    });

    test('发送 StrokeUndone 后，被撤销的笔画移入 redoStack', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(1, 1)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(StrokeUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.redoStack, hasLength(1));
      expect(bloc.state.canRedo, isTrue);
    });

    test('undoStack 为空时发送 StrokeUndone，状态不变', () async {
      final stateBefore = bloc.state;

      bloc.add(StrokeUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, equals(stateBefore));
    });

    // ==================== 4. StrokeRedone ====================

    test('发送 StrokeRedone 后，笔画重新加入 strokes', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(StrokeUndone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, isEmpty);

      bloc.add(StrokeRedone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, hasLength(1));
    });

    test('redoStack 为空时发送 StrokeRedone，状态不变', () async {
      final stateBefore = bloc.state;

      bloc.add(StrokeRedone());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, equals(stateBefore));
    });

    // ==================== 5. CanvasCleared ====================

    test('发送 CanvasCleared 后，strokes 为空', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      bloc.add(const StrokeAdded(
        points: [Offset(10, 10)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(CanvasCleared());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, isEmpty);
    });

    test('发送 CanvasCleared 后，undoStack 和 redoStack 均为空', () async {
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      await Future<void>.delayed(Duration.zero);

      bloc.add(CanvasCleared());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.undoStack, isEmpty);
      expect(bloc.state.redoStack, isEmpty);
    });

    // ==================== 6. 序列化往返 ====================

    test('serializeCurrentStrokes() 后 loadFromData() 笔画数量一致', () async {
      // 添加两笔
      bloc.add(const StrokeAdded(
        points: [Offset(0, 0), Offset(10, 10)],
        color: Colors.black,
        strokeWidth: 3.0,
      ));
      bloc.add(const StrokeAdded(
        points: [Offset(20, 20), Offset(30, 30)],
        color: Colors.red,
        strokeWidth: 5.0,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, hasLength(2));

      // 序列化
      final data = bloc.serializeCurrentStrokes();

      // 清空再恢复
      bloc.add(CanvasCleared());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, isEmpty);

      bloc.loadFromData(data);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, hasLength(2));
    });

    test('序列化往返后，笔画点坐标和颜色保持一致', () async {
      const testPoints = [Offset(1.5, 2.5), Offset(3.5, 4.5)];
      const testColor = Color(0xFFC62828);
      const testWidth = 2.0;

      bloc.add(const StrokeAdded(
        points: testPoints,
        color: testColor,
        strokeWidth: testWidth,
      ));
      await Future<void>.delayed(Duration.zero);

      final data = bloc.serializeCurrentStrokes();

      bloc.add(CanvasCleared());
      await Future<void>.delayed(Duration.zero);

      bloc.loadFromData(data);
      await Future<void>.delayed(Duration.zero);

      final restored = bloc.state.strokes.first;
      expect(restored.points.length, equals(testPoints.length));
      expect(restored.points[0].dx, closeTo(testPoints[0].dx, 0.001));
      expect(restored.points[0].dy, closeTo(testPoints[0].dy, 0.001));
      expect(restored.color, equals(testColor));
      expect(restored.strokeWidth, closeTo(testWidth, 0.001));
    });

    test('空 strokes 序列化再反序列化后仍为空列表', () async {
      final data = bloc.serializeCurrentStrokes();

      bloc.loadFromData(data);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, isEmpty);
    });

    // ==================== 7. SelectTool ====================

    test('切换到 bluePen 后，currentTool 更新为 bluePen', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.bluePen));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentTool, equals(CanvasTool.bluePen));
    });

    test('切换到 eraser 后，currentTool 更新为 eraser', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.eraser));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentTool, equals(CanvasTool.eraser));
    });

    test('切换到 pencil 后，strokeWidth 更新为 1.5', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.pencil));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentStrokeWidth, closeTo(1.5, 0.001));
    });

    test('切换到 eraser 后，strokeWidth 更新为 20.0', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.eraser));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentStrokeWidth, closeTo(20.0, 0.001));
    });

    test('切换到 redPen 后，currentColor 更新为红色', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.redPen));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentColor, equals(const Color(0xFFC62828)));
    });

    test('切换到 bluePen 后，currentColor 更新为蓝色', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.bluePen));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentColor, equals(const Color(0xFF1565C0)));
    });

    // ==================== 8. CanvasColorChanged ====================

    test('发送 CanvasColorChanged 后，currentColor 更新', () async {
      const newColor = Color(0xFF4CAF50);

      bloc.add(const CanvasColorChanged(newColor));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentColor, equals(newColor));
    });

    test('发送 CanvasColorChanged 后，currentTool 自动切换回 pen', () async {
      bloc.add(const CanvasToolChanged(CanvasTool.eraser));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const CanvasColorChanged(Colors.green));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.currentTool, equals(CanvasTool.pen));
    });

    // ==================== 9. StrokesLoaded ====================

    test('发送 StrokesLoaded 后，strokes 被替换为指定列表', () async {
      final preloadedStrokes = [
        const DrawingStroke(
          points: [Offset(0, 0), Offset(5, 5)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        const DrawingStroke(
          points: [Offset(10, 10)],
          color: Colors.red,
          strokeWidth: 2.0,
        ),
      ];

      bloc.add(StrokesLoaded(preloadedStrokes));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.strokes, hasLength(2));
      expect(bloc.state.strokes[0].color, equals(Colors.black));
      expect(bloc.state.strokes[1].color, equals(Colors.red));
    });
  });
}
