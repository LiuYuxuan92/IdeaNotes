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
import 'services/canvas_save_service.dart';
import 'widgets/canvas_painter.dart';

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
  bool _isResultPanelExpanded = false;
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
      _ocrEngine =
          widget.ocrEngineOverride ?? OcrEngineFactory.createForPlatform();
      final available = await _ocrEngine!.isAvailable();
      if (!available && mounted) {
        setState(() {
          _ocrEngine = null;
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = '当前设备暂不支持文字识别。你仍然可以保存手写内容，稍后再换设备识别。';
          _isResultPanelExpanded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ocrEngine = null;
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = 'OCR 引擎暂时不可用。请先保存手写内容，稍后再尝试识别。';
          _isResultPanelExpanded = true;
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
        _isResultPanelExpanded = true;
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
            IconButton(
              onPressed: _toggleResultPanel,
              tooltip: _isResultPanelExpanded ? '收起识别面板' : '展开识别面板',
              icon: Icon(
                context.isLarge
                    ? Icons.view_sidebar_rounded
                    : Icons.vertical_align_top_rounded,
              ),
            ),
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
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
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
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = context.isLarge ? 24.0 : 16.0;
              final largePanelWidth =
                  (constraints.maxWidth * 0.34).clamp(340.0, 420.0).toDouble();
              final phoneDrawerBodyHeight =
                  (constraints.maxHeight * 0.32).clamp(220.0, 320.0).toDouble();
              final phoneDrawerOffset =
                  _isResultPanelExpanded ? phoneDrawerBodyHeight + 112 : 108.0;
              final canvasRightPadding =
                  context.isLarge && _isResultPanelExpanded
                      ? largePanelWidth + 18
                      : 0.0;
              final canvasBottomPadding =
                  context.isLarge ? 124.0 : phoneDrawerOffset + 92.0;

              return Stack(
                children: [
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      8,
                      horizontal + canvasRightPadding,
                      canvasBottomPadding,
                    ),
                    child: _buildCanvasStage(context),
                  ),
                  Positioned(
                    left: horizontal,
                    right: horizontal + canvasRightPadding,
                    bottom: context.isLarge ? 24 : phoneDrawerOffset,
                    child: const CanvasToolbar(),
                  ),
                  if (context.isLarge)
                    Positioned(
                      top: 8,
                      right: horizontal,
                      bottom: 24,
                      child: _buildLargeResultDock(
                        context,
                        width: largePanelWidth,
                      ),
                    )
                  else
                    Positioned(
                      left: horizontal,
                      right: horizontal,
                      bottom: 16,
                      child: AppBottomDrawer(
                        expanded: _isResultPanelExpanded,
                        onToggle: _toggleResultPanel,
                        eyebrow: '识别面板',
                        title: _panelTitle,
                        description: _panelDescription,
                        trailing: _PanelStatusPill(state: _ocrBannerState),
                        child: SizedBox(
                          height: phoneDrawerBodyHeight,
                          child: OcrResultBanner(
                            result: _ocrResult,
                            state: _ocrBannerState,
                            helperText: _ocrHelperText,
                            onCopy: _copyOcrResult,
                            onEdit: _editOcrResult,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasStage(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      radius: 34,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '主画布',
            title: '把注意力放在书写本身',
            description: context.isLarge
                ? '右侧结果面板会在你需要时展开，平时让画布保持更沉浸。'
                : '识别结果会从底部抽屉展开，书写时尽量让画布保持完整。',
            trailing: _CanvasStatusPill(noteId: _existingNote?.id),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CanvasMetaPill(
                icon: Icons.draw_rounded,
                label: _canvasBloc.state.strokes.isEmpty ? '尚未落笔' : '已有手写内容',
              ),
              _CanvasMetaPill(
                icon: Icons.auto_awesome_rounded,
                label: _ocrResult.trim().isEmpty ? '等待识别' : '已生成可编辑文本',
                accent: _ocrResult.trim().isEmpty
                    ? AppColors.textSecondary
                    : AppColors.aiAccent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFFBFCFD)],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
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

  Widget _buildLargeResultDock(BuildContext context, {required double width}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isResultPanelExpanded
          ? SizedBox(
              key: const ValueKey('expanded-ocr-panel'),
              width: width,
              child: OcrResultBanner(
                result: _ocrResult,
                state: _ocrBannerState,
                helperText: _ocrHelperText,
                onCopy: _copyOcrResult,
                onEdit: _editOcrResult,
              ),
            )
          : SizedBox(
              key: const ValueKey('collapsed-ocr-panel'),
              width: 64,
              child: Align(
                alignment: Alignment.topRight,
                child: Tooltip(
                  message: '展开识别面板',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x100D1B26),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _toggleResultPanel,
                      icon: const Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCanvas() {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
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

  void _toggleResultPanel() {
    setState(() {
      _isResultPanelExpanded = !_isResultPanelExpanded;
    });
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
      final saveService = widget.saveServiceOverride ??
          CanvasSaveService(databaseHelper: DatabaseHelper.instance);
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
      _isResultPanelExpanded = true;
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
                _isResultPanelExpanded = true;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  String get _panelTitle {
    if (_ocrResult.trim().isNotEmpty) return '已生成可编辑文本';
    switch (_ocrBannerState) {
      case OcrBannerState.processing:
        return '正在识别当前手写内容';
      case OcrBannerState.warning:
        return '暂时还不能识别';
      case OcrBannerState.error:
        return '这次识别没有成功';
      case OcrBannerState.success:
        return '识别完成';
      case OcrBannerState.idle:
        return '识别结果会从这里展开';
    }
  }

  String get _panelDescription {
    if (_ocrResult.trim().isNotEmpty) {
      return '先快速核对结果，再决定是否复制、编辑或保存到笔记。';
    }
    return _ocrHelperText;
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
          const Icon(
            Icons.lock_clock_outlined,
            size: 14,
            color: AppColors.textSecondary,
          ),
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

class _CanvasMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _CanvasMetaPill({
    required this.icon,
    required this.label,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent == AppColors.aiAccent
            ? AppColors.aiAccentSoft
            : const Color(0xFFF3F5F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _PanelStatusPill extends StatelessWidget {
  final OcrBannerState state;

  const _PanelStatusPill({required this.state});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color accent;

    switch (state) {
      case OcrBannerState.processing:
        label = '识别中';
        accent = AppColors.inkBlue;
        break;
      case OcrBannerState.success:
        label = '已完成';
        accent = AppColors.success;
        break;
      case OcrBannerState.warning:
        label = '需处理';
        accent = AppColors.warning;
        break;
      case OcrBannerState.error:
        label = '异常';
        accent = AppColors.error;
        break;
      case OcrBannerState.idle:
        label = '待开始';
        accent = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent == AppColors.textSecondary
            ? const Color(0xFFF3F5F6)
            : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
