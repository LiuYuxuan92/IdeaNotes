import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/canvas_bloc.dart';
import '../canvas_toolbar.dart';
import '../../shared/widgets/ocr_result_banner.dart';

/// 手写画布主页面
/// 70% 画布 / 30% OCR 结果分割布局
class CanvasScreen extends StatefulWidget {
  final String? noteId;
  final VoidCallback? onSave;
  final Function(String)? onOcrComplete;

  const CanvasScreen({
    super.key,
    this.noteId,
    this.onSave,
    this.onOcrComplete,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;
  String _ocrResult = '';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CanvasBloc(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('手写笔记'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveNote,
              tooltip: '保存',
            ),
            IconButton(
              icon: const Icon(Icons.photo_camera),
              onPressed: _runOcr,
              tooltip: 'OCR 识别',
            ),
          ],
        ),
        body: Column(
          children: [
            // 工具栏
            const CanvasToolbar(),
            
            // 主内容区域：70% 画布 / 30% OCR 结果
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      // 画布区域 (70%)
                      Expanded(
                        flex: 7,
                        child: Container(
                          key: _canvasKey,
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildCanvas(constraints),
                          ),
                        ),
                      ),
                      
                      // OCR 结果区域 (30%)
                      Expanded(
                        flex: 3,
                        child: OcrResultBanner(
                          result: _ocrResult,
                          onCopy: _copyOcrResult,
                          onEdit: _editOcrResult,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return GestureDetector(
          onPanStart: (details) => _onPanStart(context, details, state),
          onPanUpdate: (details) => _onPanUpdate(context, details, state),
          onPanEnd: (details) => _onPanEnd(context, state),
          child: CustomPaint(
            painter: _CanvasPainter(
              strokes: state.strokes,
              currentPoints: _currentPoints,
              currentColor: state.currentColor,
              currentStrokeWidth: state.currentStrokeWidth,
              isErasing: state.currentTool == CanvasTool.eraser,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }

  void _onPanStart(BuildContext context, DragStartDetails details, CanvasState state) {
    setState(() {
      _isDrawing = true;
      _currentPoints = [details.localPosition];
    });
  }

  void _onPanUpdate(BuildContext context, DragUpdateDetails details, CanvasState state) {
    setState(() {
      _currentPoints = [..._currentPoints, details.localPosition];
    });
  }

  void _onPanEnd(BuildContext context, CanvasState state) {
    if (_currentPoints.isNotEmpty) {
      context.read<CanvasBloc>().add(StrokeAdded(
        points: _currentPoints,
        color: state.currentColor,
        strokeWidth: state.currentStrokeWidth,
        isEraser: state.currentTool == CanvasTool.eraser,
      ));
    }
    setState(() {
      _isDrawing = false;
      _currentPoints = [];
    });
  }

  Future<void> _saveNote() async {
    // TODO: 实现保存笔记功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('笔记已保存')),
    );
    widget.onSave?.call();
  }

  Future<void> _runOcr() async {
    // TODO: 调用 OCR 引擎识别画布内容
    setState(() {
      _ocrResult = '正在识别...';
    });
    
    // 模拟 OCR 结果
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _ocrResult = '示例识别结果：\n\n早餐：15元\n午餐：28元\n晚餐：45元\n\n总计：88元';
    });
    
    widget.onOcrComplete?.call(_ocrResult);
  }

  void _copyOcrResult() {
    // TODO: 复制到剪贴板
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  void _editOcrResult() {
    // TODO: 打开编辑对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑 OCR 结果'),
        content: TextField(
          maxLines: 5,
          controller: TextEditingController(text: _ocrResult),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 简化的 Canvas Painter（用于 CanvasScreen）
class _CanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentStrokeWidth;
  final bool isErasing;

  _CanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentStrokeWidth,
    required this.isErasing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // 绘制所有笔画
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // 绘制当前正在绘制的笔画
    if (currentPoints.isNotEmpty) {
      _drawStroke(
        canvas,
        DrawingStroke(
          points: currentPoints,
          color: currentColor,
          strokeWidth: currentStrokeWidth,
          isEraser: isErasing,
        ),
      );
    }
  }

  void _drawStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.isEraser ? Colors.white : stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentPoints != currentPoints ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth ||
        oldDelegate.isErasing != isErasing;
  }
}
