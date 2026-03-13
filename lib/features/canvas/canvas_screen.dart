import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'models/canvas_editor_state.dart';
import 'widgets/canvas_painter.dart';
import '../../core/models/note.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/storage/database_helper.dart';
import '../../core/ocr/vision_ocr.dart';
import 'services/canvas_load_service.dart';
import 'services/canvas_ocr_service.dart';
import 'services/canvas_save_service.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';

/// 手写画布主页面
/// 70% 画布 / 30% OCR 结果分割布局
class CanvasScreen extends StatefulWidget {
  final String? noteId;
  final VoidCallback? onSave;
  final Function(String)? onOcrComplete;
  final CanvasOcrService? ocrService;
  final OcrEngine? ocrEngineOverride;
  final Future<Uint8List?> Function()? captureCanvasForOcr;

  const CanvasScreen({
    super.key,
    this.noteId,
    this.onSave,
    this.onOcrComplete,
    this.ocrService,
    this.ocrEngineOverride,
    this.captureCanvasForOcr,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasRepaintKey = GlobalKey();
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;
  CanvasEditorState _editorState = const CanvasEditorState();
  late final CanvasBloc _canvasBloc;
  OcrEngine? _ocrEngine;
  late final CanvasLoadService _canvasLoadService;
  late final CanvasSaveService _canvasSaveService;
  late final CanvasOcrService _canvasOcrService;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _canvasLoadService = CanvasLoadService(databaseHelper: DatabaseHelper.instance);
    _canvasSaveService = CanvasSaveService(databaseHelper: DatabaseHelper.instance);
    _canvasOcrService = widget.ocrService ?? CanvasOcrService();
    _initOcrEngine();
    if (widget.noteId != null) {
      _loadExistingNote();
    }
  }

  Future<void> _initOcrEngine() async {
    try {
      _ocrEngine = widget.ocrEngineOverride ?? OcrEngineFactory.createForPlatform();
      final available = await _ocrEngine!.isAvailable();
      if (!available) {
        _ocrEngine = null;
      }
    } catch (e) {
      _ocrEngine = null;
    }
  }

  Future<void> _loadExistingNote() async {
    final result = await _canvasLoadService.load(widget.noteId!);
    if (result.note == null) return;

    setState(() {
      _editorState = _editorState.copyWith(
        existingNote: result.note,
        ocrResult: result.ocrResult,
      );
    });

    if (result.canvasData != null) {
      _canvasBloc.loadFromData(result.canvasData!);
    }
  }

  @override
  void dispose() {
    _canvasBloc.close();
    _ocrEngine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _canvasBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('手写笔记'),
          actions: [
            IconButton(
              icon: _editorState.isRecognizing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera),
              onPressed: _editorState.isRecognizing ? null : _runOcr,
              tooltip: 'OCR 识别',
            ),
            IconButton(
              icon: _editorState.isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: _editorState.isSaving ? null : _saveNote,
              tooltip: '保存',
            ),
          ],
        ),
        body: Column(
          children: [
            // 工具栏
            const CanvasToolbar(),

            // 主内容区域：70% 画布 / 30% OCR 结果
            Expanded(
              child: Column(
                children: [
                  // 画布区域 (70%)
                  Expanded(
                    flex: 7,
                    child: Container(
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
                        child: RepaintBoundary(
                          key: _canvasRepaintKey,
                          child: _buildCanvas(),
                        ),
                      ),
                    ),
                  ),

                  // OCR 结果区域 (30%)
                  Expanded(
                    flex: 3,
                    child: OcrResultBanner(
                      result: _editorState.ocrResult,
                      onCopy: _copyOcrResult,
                      onEdit: _editOcrResult,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return GestureDetector(
          onPanStart: (details) => _onPanStart(context, details, state),
          onPanUpdate: (details) => _onPanUpdate(context, details, state),
          onPanEnd: (details) => _onPanEnd(context, state),
          child: CustomPaint(
            painter: CanvasPainter(
              strokes: state.strokes,
              currentPoints: _currentPoints,
              currentColor: state.currentColor,
              currentStrokeWidth: state.currentStrokeWidth,
              isErasing: state.currentTool == CanvasTool.eraser,
            ),
            size: Size.infinite,
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

  /// 捕获画布为 PNG 字节
  Future<Uint8List?> _captureCanvas({double pixelRatio = 2.0}) async {
    try {
      final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  /// 生成缩略图（200x200）
  Future<Uint8List?> _captureThumbnail() async {
    try {
      final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // 用较低的分辨率捕获
      final image = await boundary.toImage(pixelRatio: 0.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveNote() async {
    setState(() {
      _editorState = _editorState.copyWith(isSaving: true);
    });

    try {
      final savedNote = await _canvasSaveService.save(
        CanvasSaveInput(
          existingNote: _editorState.existingNote,
          canvasData: _canvasBloc.serializeCurrentStrokes(),
          snapshotBytes: await _captureCanvas(),
          thumbnailBytes: await _captureThumbnail(),
          recognizedText: _editorState.ocrResult,
          now: DateTime.now(),
        ),
      );

      setState(() {
        _editorState = _editorState.copyWith(existingNote: savedNote);
      });

      if (mounted) {
        context.read<NoteListBloc>().add(LoadNotes());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记已保存')),
        );
        widget.onSave?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _editorState = _editorState.copyWith(isSaving: false);
        });
      }
    }
  }

  Future<void> _runOcr() async {
    setState(() {
      _editorState = _editorState.copyWith(
        isRecognizing: true,
        ocrResult: '正在识别...',
      );
    });

    final result = await _canvasOcrService.recognize(
      ocrEngine: _ocrEngine,
      imageBytes: widget.captureCanvasForOcr != null
          ? await widget.captureCanvasForOcr!()
          : await _captureCanvas(pixelRatio: 2.0),
    );

    if (!mounted) return;

    setState(() {
      _editorState = _editorState.copyWith(
        ocrResult: result.success ? result.text : (result.errorMessage ?? '识别失败，请重试'),
        isRecognizing: false,
      );
    });

    if (result.success) {
      widget.onOcrComplete?.call(result.text);
    }
  }

  Future<void> _copyOcrResult() async {
    if (_editorState.ocrResult.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _editorState.ocrResult));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  void _editOcrResult() {
    final controller = TextEditingController(text: _editorState.ocrResult);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑识别结果'),
        content: TextField(
          maxLines: 8,
          controller: controller,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _editorState = _editorState.copyWith(ocrResult: controller.text);
              });
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
