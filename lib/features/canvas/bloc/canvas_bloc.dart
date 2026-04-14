import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../models/stroke_style.dart';

// ==================== Events ====================
abstract class CanvasEvent extends Equatable {
  const CanvasEvent();

  @override
  List<Object?> get props => [];
}

class CanvasInitialized extends CanvasEvent {}

class StrokeAdded extends CanvasEvent {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final StrokeStyle style;

  const StrokeAdded({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.style = StrokeStyle.pen,
  });

  @override
  List<Object?> get props => [points, color, strokeWidth, isEraser, style];
}

class StrokeUndone extends CanvasEvent {}

class StrokeRedone extends CanvasEvent {}

class CanvasCleared extends CanvasEvent {}

class CanvasColorChanged extends CanvasEvent {
  final Color color;

  const CanvasColorChanged(this.color);

  @override
  List<Object?> get props => [color];
}

class CanvasStrokeWidthChanged extends CanvasEvent {
  final double strokeWidth;

  const CanvasStrokeWidthChanged(this.strokeWidth);

  @override
  List<Object?> get props => [strokeWidth];
}

class CanvasToolChanged extends CanvasEvent {
  final CanvasTool tool;

  const CanvasToolChanged(this.tool);

  @override
  List<Object?> get props => [tool];
}

class StrokesLoaded extends CanvasEvent {
  final List<DrawingStroke> strokes;

  const StrokesLoaded(this.strokes);

  @override
  List<Object?> get props => [strokes];
}

// ==================== Tool Enum ====================
enum CanvasTool {
  pen, // 黑笔
  bluePen, // 蓝笔
  redPen, // 红笔
  pencil, // 铅笔
  eraser, // 橡皮
}

// ==================== Drawing Stroke ====================
class DrawingStroke extends Equatable {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final StrokeStyle style;

  const DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.style = StrokeStyle.pen,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': color.toARGB32(),
        'strokeWidth': strokeWidth,
        'isEraser': isEraser,
        'style': style.name,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    return DrawingStroke(
      points: (json['points'] as List)
          .map((p) =>
              Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
          .toList(),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      isEraser: json['isEraser'] as bool? ?? false,
      style: json['style'] == null
          ? StrokeStyle.pen
          : StrokeStyle.values.byName(json['style'] as String),
    );
  }

  /// 将笔画列表序列化为 Uint8List（用于数据库 BLOB 存储）
  static Uint8List serializeStrokes(List<DrawingStroke> strokes) {
    final jsonList = strokes.map((s) => s.toJson()).toList();
    return Uint8List.fromList(utf8.encode(jsonEncode(jsonList)));
  }

  /// 从 Uint8List 反序列化笔画列表
  static List<DrawingStroke> deserializeStrokes(Uint8List data) {
    final jsonList = jsonDecode(utf8.decode(data)) as List;
    return jsonList
        .map((j) => DrawingStroke.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  List<Object?> get props => [points, color, strokeWidth, isEraser, style];
}

// ==================== State ====================
class CanvasState extends Equatable {
  final List<DrawingStroke> strokes;
  final List<DrawingStroke> undoStack;
  final List<DrawingStroke> redoStack;
  final Color currentColor;
  final double currentStrokeWidth;
  final CanvasTool currentTool;
  final StrokeStyle currentStyle;
  final bool isDrawing;

  const CanvasState({
    this.strokes = const [],
    this.undoStack = const [],
    this.redoStack = const [],
    this.currentColor = Colors.black,
    this.currentStrokeWidth = 3.0,
    this.currentTool = CanvasTool.pen,
    this.currentStyle = StrokeStyle.pen,
    this.isDrawing = false,
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  CanvasState copyWith({
    List<DrawingStroke>? strokes,
    List<DrawingStroke>? undoStack,
    List<DrawingStroke>? redoStack,
    Color? currentColor,
    double? currentStrokeWidth,
    CanvasTool? currentTool,
    StrokeStyle? currentStyle,
    bool? isDrawing,
  }) {
    return CanvasState(
      strokes: strokes ?? this.strokes,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      currentColor: currentColor ?? this.currentColor,
      currentStrokeWidth: currentStrokeWidth ?? this.currentStrokeWidth,
      currentTool: currentTool ?? this.currentTool,
      currentStyle: currentStyle ?? this.currentStyle,
      isDrawing: isDrawing ?? this.isDrawing,
    );
  }

  @override
  List<Object?> get props => [
        strokes,
        undoStack,
        redoStack,
        currentColor,
        currentStrokeWidth,
        currentTool,
        currentStyle,
        isDrawing,
      ];
}

// ==================== Bloc ====================
class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  CanvasBloc() : super(const CanvasState()) {
    on<CanvasInitialized>(_onInitialized);
    on<StrokeAdded>(_onStrokeAdded);
    on<StrokeUndone>(_onStrokeUndone);
    on<StrokeRedone>(_onStrokeRedone);
    on<CanvasCleared>(_onCanvasCleared);
    on<CanvasColorChanged>(_onColorChanged);
    on<CanvasStrokeWidthChanged>(_onStrokeWidthChanged);
    on<CanvasToolChanged>(_onToolChanged);
    on<StrokesLoaded>(_onStrokesLoaded);
  }

  void _onInitialized(CanvasInitialized event, Emitter<CanvasState> emit) {
    // 可以在这里加载保存的画布数据
  }

  void _onStrokeAdded(StrokeAdded event, Emitter<CanvasState> emit) {
    final newStroke = DrawingStroke(
      points: event.points,
      color: event.color,
      strokeWidth: event.strokeWidth,
      isEraser: event.isEraser,
      style: event.style,
    );

    emit(state.copyWith(
      strokes: [...state.strokes, newStroke],
      undoStack: [...state.undoStack, newStroke],
      redoStack: [], // 新的笔画后清空重做栈
    ));
  }

  void _onStrokeUndone(StrokeUndone event, Emitter<CanvasState> emit) {
    if (state.undoStack.isEmpty) return;

    final lastStroke = state.undoStack.last;
    final newUndoStack = List<DrawingStroke>.from(state.undoStack)
      ..removeLast();

    emit(state.copyWith(
      strokes: List<DrawingStroke>.from(state.strokes)..removeLast(),
      undoStack: newUndoStack,
      redoStack: [...state.redoStack, lastStroke],
    ));
  }

  void _onStrokeRedone(StrokeRedone event, Emitter<CanvasState> emit) {
    if (state.redoStack.isEmpty) return;

    final strokeToRedo = state.redoStack.last;
    final newRedoStack = List<DrawingStroke>.from(state.redoStack)
      ..removeLast();

    emit(state.copyWith(
      strokes: [...state.strokes, strokeToRedo],
      undoStack: [...state.undoStack, strokeToRedo],
      redoStack: newRedoStack,
    ));
  }

  void _onCanvasCleared(CanvasCleared event, Emitter<CanvasState> emit) {
    emit(state.copyWith(
      strokes: [],
      undoStack: [],
      redoStack: [],
    ));
  }

  void _onColorChanged(CanvasColorChanged event, Emitter<CanvasState> emit) {
    emit(state.copyWith(
      currentColor: event.color,
      currentTool: CanvasTool.pen, // 切换颜色后自动切换到画笔模式
    ));
  }

  void _onStrokeWidthChanged(
      CanvasStrokeWidthChanged event, Emitter<CanvasState> emit) {
    emit(state.copyWith(currentStrokeWidth: event.strokeWidth));
  }

  void _onToolChanged(CanvasToolChanged event, Emitter<CanvasState> emit) {
    Color newColor = state.currentColor;
    double newStrokeWidth = state.currentStrokeWidth;
    StrokeStyle newStyle = state.currentStyle;

    switch (event.tool) {
      case CanvasTool.pen:
        newColor = Colors.black;
        newStrokeWidth = 3.0;
        newStyle = StrokeStyle.pen;
        break;
      case CanvasTool.bluePen:
        newColor = const Color(0xFF1565C0);
        newStrokeWidth = 3.0;
        newStyle = StrokeStyle.pen;
        break;
      case CanvasTool.redPen:
        newColor = const Color(0xFFC62828);
        newStrokeWidth = 3.0;
        newStyle = StrokeStyle.pen;
        break;
      case CanvasTool.pencil:
        newColor = Colors.grey.shade700;
        newStrokeWidth = 1.5;
        newStyle = StrokeStyle.pencil;
        break;
      case CanvasTool.eraser:
        newColor = Colors.white;
        newStrokeWidth = 20.0;
        newStyle = StrokeStyle.pen;
        break;
    }

    emit(state.copyWith(
      currentTool: event.tool,
      currentColor: newColor,
      currentStrokeWidth: newStrokeWidth,
      currentStyle: newStyle,
    ));
  }

  void _onStrokesLoaded(StrokesLoaded event, Emitter<CanvasState> emit) {
    emit(state.copyWith(
      strokes: event.strokes,
      undoStack: event.strokes,
      redoStack: [],
    ));
  }

  /// 序列化当前画布笔画为 BLOB 数据
  Uint8List serializeCurrentStrokes() {
    return DrawingStroke.serializeStrokes(state.strokes);
  }

  /// 从 BLOB 数据加载画布笔画
  void loadFromData(Uint8List data) {
    final strokes = DrawingStroke.deserializeStrokes(data);
    add(StrokesLoaded(strokes));
  }
}
