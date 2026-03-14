import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/ocr/vision_ocr.dart';
import '../../core/storage/database_helper.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';
import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'widgets/canvas_painter.dart';
import 'services/canvas_save_service.dart';

class CanvasScreen extends StatefulWidget {
  final String? noteId;
  final VoidCallback? onSave;
  final Function(String)? onOcrComplete;
  final OcrEngine? ocrEngineOverride;
  final Future<Uint8List?> Function()? captureCanvasForOcr;
  final Future<Uint8List?> Function()? captureCanvasForSave;
  final Future<Uint8List?> Function()? captureThumbnailForSave;
  final CanvasSaveService? saveServiceOverride;

  const CanvasScreen({
    super.key,
    this.noteId,
    this.onSave,
    this.onOcrComplete,
    this.ocrEngineOverride,
    this.captureCanvasForOcr,
    this.captureCanvasForSave,
    this.captureThumbnailForSave,
    this.saveServiceOverride,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasRepaintKey = GlobalKey();
  List<Offset> _currentPoints = <Offset>[];
  late final CanvasBloc _canvasBloc;

  String _ocrResult = '';
  String _ocrHelperText = '写完后点一下“识别”，再决定是否复制、编辑或保存。';
  bool _isSaving = false;
  bool _isRecognizing = false;
  Note? _existingNote;
  OcrEngine? _ocrEngine;
  OcrBannerState _ocrBannerState = OcrBannerState.idle;

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
      _ocrEngine = widget.ocrEngineOverride ?? OcrEngineFactory.createForPlatform();
      final available = await _ocrEngine!.isAvailable();
      if (!available && mounted) {
        setState(() {
          _ocrEngine = null;
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = '当前设备暂不支持文字识别。你仍然可以保存手写内容，稍后再换设备识别。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ocrEngine = null;
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = 'OCR 引擎暂时不可用。请先保存手写内容，稍后再尝试识别。';
        });
      }
    }
  }

  Future<void> _loadExistingNote() async {
    final noteData = await DatabaseHelper.instance.getNote(widget.noteId!);
    if (noteData == null || !mounted) return;

    final note = Note.fromMap(noteData);
    setState(() {
      _existingNote = note;
      _ocrResult = note.recognizedText ?? '';
      if (_ocrResult.trim().isNotEmpty) {
        _ocrBannerState = OcrBannerState.success;
        _ocrHelperText = '这是上次识别并保存的文本。你可以继续补写，再重新识别更新结果。';
      }
    });

    if (note.canvasData != null && note.canvasData!.isNotEmpty) {
      _canvasBloc.loadFromData(Uint8List.fromList(note.canvasData!));
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
          title: Text(widget.noteId == null ? '新建手写笔记' : '继续编辑笔记'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isRecognizing ? null : _runOcr,
                    tooltip: '识别当前画布',
                    icon: _isRecognizing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.text_snippet_outlined),
                  ),
                  IconButton(
                    onPressed: _isSaving ? null : _saveNote,
                    tooltip: '保存当前笔记',
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const CanvasToolbar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: context.isLarge
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                                flex: 11, child: _buildCanvasPanel(context)),
                            const SizedBox(width: 16),
                            Expanded(
                                flex: 7, child: _buildResultPanel(context)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                                flex: 7, child: _buildCanvasPanel(context)),
                            const SizedBox(height: 16),
                            Expanded(
                                flex: 4, child: _buildResultPanel(context)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasPanel(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '主画布',
            title: '把注意力放在书写本身',
            description: '先自由记录，再进行识别和整理。画布会保留完整手写笔迹。',
            trailing: _CanvasStatusPill(noteId: _existingNote?.id),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFFAFBFC)],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: RepaintBoundary(
                  key: _canvasRepaintKey,
                  child: _buildCanvas(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: OcrResultBanner(
            result: _ocrResult,
            state: _ocrBannerState,
            helperText: _ocrHelperText,
            onCopy: _copyOcrResult,
            onEdit: _editOcrResult,
          ),
        ),
      ],
    );
  }

  Widget _buildCanvas() {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPanStart(details),
          onPanUpdate: (details) => _onPanUpdate(details),
          onPanEnd: (_) => _onPanEnd(context, state),
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

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentPoints = <Offset>[details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints = <Offset>[..._currentPoints, details.localPosition];
    });
  }

  void _onPanEnd(BuildContext context, CanvasState state) {
    if (_currentPoints.isNotEmpty) {
      context.read<CanvasBloc>().add(
            StrokeAdded(
              points: _currentPoints,
              color: state.currentColor,
              strokeWidth: state.currentStrokeWidth,
              isEraser: state.currentTool == CanvasTool.eraser,
            ),
          );
    }
    setState(() {
      _currentPoints = <Offset>[];
    });
  }

  Future<Uint8List?> _captureCanvas({double pixelRatio = 2.0}) async {
    try {
      final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _captureThumbnail() async {
    try {
      final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 0.6);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveNote() async {
    setState(() => _isSaving = true);
    try {
      final saveService =
          widget.saveServiceOverride ?? CanvasSaveService(databaseHelper: DatabaseHelper.instance);
      final canvasData = _canvasBloc.serializeCurrentStrokes();
      final snapshotBytes = widget.captureCanvasForSave != null
          ? await widget.captureCanvasForSave!.call()
          : await _captureCanvas();
      final thumbnailBytes = widget.captureThumbnailForSave != null
          ? await widget.captureThumbnailForSave!.call()
          : await _captureThumbnail();

      _existingNote = await saveService.save(
        CanvasSaveInput(
          existingNote: _existingNote,
          canvasData: canvasData,
          snapshotBytes: snapshotBytes,
          thumbnailBytes: thumbnailBytes,
          recognizedText: _ocrResult,
          now: DateTime.now(),
        ),
      );

      if (!mounted) return;
      try {
        context.read<NoteListBloc>().add(LoadNotes());
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记已保存，可以回到列表继续查看。')),
      );
      widget.onSave?.call();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败，请稍后再试：$e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runOcr() async {
    setState(() {
      _isRecognizing = true;
      _ocrResult = '';
      _ocrBannerState = OcrBannerState.processing;
      _ocrHelperText = '正在读取当前画布。识别完成后，你可以直接复制或手动修正。';
    });

    Directory? tempDir;
    try {
      if (_ocrEngine == null) {
        setState(() {
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = '当前设备暂不支持文字识别。你仍然可以先保存手写内容。';
        });
        return;
      }

      final imageBytes = widget.captureCanvasForOcr != null
          ? await widget.captureCanvasForOcr!.call()
          : await _captureCanvas(pixelRatio: 2.0);
      if (imageBytes == null) {
        setState(() {
          _ocrBannerState = OcrBannerState.error;
          _ocrHelperText = '没有成功捕获到画布图像。请先确认画布已渲染完成，再重试一次。';
        });
        return;
      }

      tempDir = await Directory.systemTemp.createTemp('ideanotes_ocr_');
      final tempFile = File('${tempDir.path}/canvas.png');
      await tempFile.writeAsBytes(imageBytes);

      final lines = await _ocrEngine!.recognizeTextFromFile(tempFile.path);
      final result = lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');

      setState(() {
        _ocrResult = result;
        if (result.isEmpty) {
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = '这次没有读到清晰文本。你可以写得更满一些，或把关键字写得更工整后再试。';
        } else {
          _ocrBannerState = OcrBannerState.success;
          _ocrHelperText = '识别完成。建议先快速检查错字，再决定是否保存到笔记。';
        }
      });

      widget.onOcrComplete?.call(result);
    } catch (_) {
      setState(() {
        _ocrBannerState = OcrBannerState.error;
        _ocrResult = '';
        _ocrHelperText = '识别没有完成。你可以再试一次；如果持续失败，先保存当前手写内容。';
      });
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<void> _copyOcrResult() async {
    if (_ocrResult.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _ocrResult));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('识别文本已复制。')),
    );
  }

  void _editOcrResult() {
    final controller = TextEditingController(text: _ocrResult);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑识别文本'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          minLines: 6,
          decoration: const InputDecoration(hintText: '在这里修正识别结果'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('先不改'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _ocrResult = controller.text.trim();
                _ocrBannerState = _ocrResult.isEmpty
                    ? OcrBannerState.idle
                    : OcrBannerState.success;
                _ocrHelperText = _ocrResult.isEmpty
                    ? '写完后点一下“识别”，再决定是否复制、编辑或保存。'
                    : '你已手动调整识别文本，保存后会覆盖旧结果。';
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }
}

class _CanvasStatusPill extends StatelessWidget {
  final String? noteId;

  const _CanvasStatusPill({required this.noteId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_clock_outlined,
              size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            noteId == null ? '尚未保存' : '已载入历史内容',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
