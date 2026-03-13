import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'widgets/canvas_painter.dart';
import '../../core/models/note.dart';
import '../../core/parser/entry_parser.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/image_storage.dart';
import '../../core/ocr/vision_ocr.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';

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

class _CanvasImagePaths {
  final String? snapshotPath;
  final String? thumbnailPath;

  const _CanvasImagePaths({
    this.snapshotPath,
    this.thumbnailPath,
  });
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasRepaintKey = GlobalKey();
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;
  String _ocrResult = '';
  bool _isSaving = false;
  bool _isRecognizing = false;
  Note? _existingNote;
  late final CanvasBloc _canvasBloc;
  OcrEngine? _ocrEngine;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _initOcrEngine();
    if (widget.noteId != null) {
      _loadExistingNote();
    }
  }

  Future<void> _initOcrEngine() async {
    try {
      _ocrEngine = OcrEngineFactory.createForPlatform();
      final available = await _ocrEngine!.isAvailable();
      if (!available) {
        _ocrEngine = null;
      }
    } catch (e) {
      _ocrEngine = null;
    }
  }

  Future<void> _loadExistingNote() async {
    final noteData = await DatabaseHelper.instance.getNote(widget.noteId!);
    if (noteData != null) {
      final note = Note.fromMap(noteData);
      setState(() {
        _existingNote = note;
        _ocrResult = note.recognizedText ?? '';
      });
      // 恢复画布笔画
      if (note.canvasData != null && note.canvasData!.isNotEmpty) {
        _canvasBloc.loadFromData(Uint8List.fromList(note.canvasData!));
      }
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
              icon: _isRecognizing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera),
              onPressed: _isRecognizing ? null : _runOcr,
              tooltip: 'OCR 识别',
            ),
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveNote,
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
                      result: _ocrResult,
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
    setState(() => _isSaving = true);

    try {
      final canvasData = _canvasBloc.serializeCurrentStrokes();
      final noteId = _existingNote?.id ?? const Uuid().v4();
      final imagePaths = await _saveCanvasImages(noteId);
      final now = DateTime.now();
      final recognizedText = _ocrResult.isNotEmpty ? _ocrResult : null;

      await _upsertNote(
        noteId: noteId,
        canvasData: canvasData,
        snapshotPath: imagePaths.snapshotPath,
        thumbnailPath: imagePaths.thumbnailPath,
        recognizedText: recognizedText,
        now: now,
      );

      await _replaceEntries(noteId, recognizedText);

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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<_CanvasImagePaths> _saveCanvasImages(String noteId) async {
    String? snapshotPath;
    String? thumbnailPath;

    final snapshotBytes = await _captureCanvas();
    if (snapshotBytes != null) {
      snapshotPath = await ImageStorage.saveSnapshot(snapshotBytes, noteId);
    }

    final thumbnailBytes = await _captureThumbnail();
    if (thumbnailBytes != null) {
      thumbnailPath = await ImageStorage.saveThumbnail(thumbnailBytes, noteId);
    }

    return _CanvasImagePaths(
      snapshotPath: snapshotPath,
      thumbnailPath: thumbnailPath,
    );
  }

  Future<void> _upsertNote({
    required String noteId,
    required Uint8List canvasData,
    required String? snapshotPath,
    required String? thumbnailPath,
    required String? recognizedText,
    required DateTime now,
  }) async {
    if (_existingNote != null) {
      await DatabaseHelper.instance.updateNote(_existingNote!.id, {
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': canvasData,
        'snapshot_image_path': snapshotPath ?? _existingNote!.snapshotImagePath,
        'thumbnail_image_path': thumbnailPath ?? _existingNote!.thumbnailImagePath,
        'recognized_text': recognizedText,
      });

      setState(() {
        _existingNote = _existingNote!.copyWith(
          updatedAt: now,
          canvasData: canvasData,
          snapshotImagePath: snapshotPath ?? _existingNote!.snapshotImagePath,
          thumbnailImagePath: thumbnailPath ?? _existingNote!.thumbnailImagePath,
          recognizedText: recognizedText,
        );
      });
      return;
    }

    await DatabaseHelper.instance.insertNote({
      'id': noteId,
      'notebook_id': 'default-notebook',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
      'canvas_data': canvasData,
      'snapshot_image_path': snapshotPath,
      'thumbnail_image_path': thumbnailPath,
      'recognized_text': recognizedText,
    });

    setState(() {
      _existingNote = Note(
        id: noteId,
        notebookId: 'default-notebook',
        createdAt: now,
        updatedAt: now,
        canvasData: canvasData,
        snapshotImagePath: snapshotPath,
        thumbnailImagePath: thumbnailPath,
        recognizedText: recognizedText,
      );
    });
  }

  Future<void> _replaceEntries(String noteId, String? recognizedText) async {
    await DatabaseHelper.instance.deleteNoteEntries(noteId);

    if (recognizedText == null || recognizedText.isEmpty) {
      return;
    }

    await _saveEntries(noteId, recognizedText);
  }

  /// 将 OCR 结果解析为条目并存储到数据库
  Future<void> _saveEntries(String noteId, String ocrText) async {
    final entries = EntryParser.parseMultiLine(ocrText);
    for (final entry in entries) {
      await DatabaseHelper.instance.insertNoteEntry({
        'id': entry.id,
        'note_id': noteId,
        'type': entry.type.name,
        'raw_text': entry.rawText,
        'amount': entry.expense?.amount.toString(),
        'category': entry.expense?.category,
        'event_title': entry.event?.title,
        'event_date': entry.event?.date?.millisecondsSinceEpoch,
        'is_completed': (entry.event?.isCompleted ?? false) ? 1 : 0,
        'memo_text': entry.memoText,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _runOcr() async {
    setState(() {
      _isRecognizing = true;
      _ocrResult = '正在识别...';
    });

    try {
      if (_ocrEngine == null) {
        // OCR 引擎不可用，提示用户
        setState(() {
          _ocrResult = 'OCR 引擎不可用，请确认设备支持文字识别功能';
        });
        return;
      }

      // 捕获画布为图片
      final imageBytes = await _captureCanvas(pixelRatio: 2.0);
      if (imageBytes == null) {
        setState(() {
          _ocrResult = '识别失败，无法捕获画布图像';
        });
        return;
      }

      // 将图片保存为临时文件，供 OCR 引擎使用
      final tempDir = await Directory.systemTemp.createTemp('ocr_');
      final tempFile = File('${tempDir.path}/canvas.png');
      await tempFile.writeAsBytes(imageBytes);

      final lines = await _ocrEngine!.recognizeTextFromFile(tempFile.path);
      final result = lines.join('\n');

      // 清理临时文件
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      setState(() {
        _ocrResult = result;
      });

      widget.onOcrComplete?.call(result);
    } catch (e) {
      setState(() {
        _ocrResult = '识别失败，请重试';
      });
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<void> _copyOcrResult() async {
    if (_ocrResult.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _ocrResult));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  void _editOcrResult() {
    final controller = TextEditingController(text: _ocrResult);
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
                _ocrResult = controller.text;
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
