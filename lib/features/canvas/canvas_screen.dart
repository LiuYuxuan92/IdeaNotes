import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/ocr/vision_ocr.dart';
import '../../core/storage/database_helper.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';
import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'services/handwriting_recognition_service.dart';
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
  late final HandwritingRecognitionService _handwritingRecognitionService;

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
    _handwritingRecognitionService = HandwritingRecognitionService();
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
    unawaited(_handwritingRecognitionService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompactViewport = MediaQuery.sizeOf(context).width < 720;

    return BlocProvider.value(
      value: _canvasBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.noteId == null ? '新建手写笔记' : '继续编辑笔记'),
          actions: [
            IconButton(
              onPressed: isCompactViewport
                  ? _showCompactResultSheet
                  : _toggleResultPanel,
              tooltip: isCompactViewport
                  ? '查看识别结果'
                  : (_isResultPanelExpanded ? '收起识别面板' : '展开识别面板'),
              icon: Icon(
                isCompactViewport
                    ? Icons.notes_rounded
                    : context.isLarge
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
              final isCompact = context.isCompact;
              final horizontal =
                  context.isLarge ? 24.0 : (isCompact ? 12.0 : 16.0);

              if (isCompact) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 16),
                  child: Column(
                    children: [
                      Expanded(child: _buildCanvasStage(context)),
                      const SizedBox(height: 12),
                      _buildCompactResultCard(context),
                      const SizedBox(height: 12),
                      const CanvasToolbar(),
                    ],
                  ),
                );
              }

              final largePanelWidth =
                  (constraints.maxWidth * 0.34).clamp(340.0, 420.0).toDouble();
              final phoneDrawerBodyHeight =
                  (constraints.maxHeight * 0.24).clamp(168.0, 220.0).toDouble();
              final phoneDrawerOffset =
                  _isResultPanelExpanded ? phoneDrawerBodyHeight + 82.0 : 68.0;
              final phoneToolbarHeight = isCompact ? 78.0 : 88.0;
              final canvasRightPadding =
                  context.isLarge && _isResultPanelExpanded
                      ? largePanelWidth + 18
                      : 0.0;
              final canvasBottomPadding = context.isLarge
                  ? 124.0
                  : phoneDrawerOffset + phoneToolbarHeight + 12.0;

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
    final isCompact = context.isCompact;
    final hasInk = _hasInk;
    final hasResult = _ocrResult.trim().isNotEmpty;

    return AppSurface(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 12 : 18,
        isCompact ? 12 : 18,
        isCompact ? 12 : 18,
        isCompact ? 12 : 18,
      ),
      radius: isCompact ? 28 : 34,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompact) ...[
            _buildCompactCanvasHeader(
              context,
              hasInk: hasInk,
              hasResult: hasResult,
            ),
            const SizedBox(height: 10),
          ] else ...[
            AppSectionHeader(
              eyebrow: '主画布',
              title: '把注意力放在书写本身',
              description: context.isLarge
                  ? '右侧结果面板会在你需要时展开，平时让画布保持更沉浸。'
                  : '手机端会优先保留更多书写空间，识别结果只在需要时从底部展开。',
              trailing: _CanvasStatusPill(noteId: _existingNote?.id),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CanvasMetaPill(
                  icon: Icons.draw_rounded,
                  label: hasInk ? '已有手写内容' : '尚未落笔',
                ),
                _CanvasMetaPill(
                  icon: Icons.text_snippet_outlined,
                  label: hasResult ? '已生成识别文本' : '等待识别',
                  accent:
                      hasResult ? AppColors.success : AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isCompact ? 22 : 28),
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
                borderRadius: BorderRadius.circular(isCompact ? 22 : 28),
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

  Widget _buildCompactCanvasHeader(
    BuildContext context, {
    required bool hasInk,
    required bool hasResult,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '先把关键内容写清楚',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                hasInk
                    ? '手机端已优先保留画布空间，写完后直接点右上角“识别”。'
                    : '先开始书写，尽量把关键字写大一点，识别会更稳。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _CanvasMetaPill(
          icon: hasResult
              ? Icons.check_circle_outline_rounded
              : Icons.draw_rounded,
          label: hasResult ? '已识别' : (hasInk ? '可识别' : '未落笔'),
          accent: hasResult ? AppColors.success : AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildCompactResultCard(BuildContext context) {
    final hasResult = _ocrResult.trim().isNotEmpty;
    final previewText =
        hasResult ? _previewResultText(_ocrResult) : _ocrHelperText;

    return AppSurface(
      padding: const EdgeInsets.all(14),
      radius: 26,
      backgroundColor: Colors.white.withValues(alpha: 0.96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('识别结果',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _panelTitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              _PanelStatusPill(state: _ocrBannerState),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_ocrBannerState == OcrBannerState.processing) ...[
                  const LinearProgressIndicator(minHeight: 4),
                  const SizedBox(height: 12),
                ],
                Text(
                  previewText,
                  maxLines: hasResult ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: hasResult
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        height: 1.55,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: _isRecognizing ? null : _runOcr,
                icon: const Icon(Icons.text_snippet_outlined),
                label: Text(hasResult ? '重新识别' : '识别当前页'),
              ),
              if (hasResult)
                TextButton.icon(
                  onPressed: _showCompactResultSheet,
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('查看全文'),
                ),
              if (hasResult)
                TextButton.icon(
                  onPressed: _editOcrResult,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑文本'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _previewResultText(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return text.trim();
    }
    return lines.take(4).join('\n');
  }

  Future<void> _showCompactResultSheet() async {
    if (!mounted) return;

    final media = MediaQuery.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            height: media.size.height * 0.74,
            child: OcrResultBanner(
              result: _ocrResult,
              state: _ocrBannerState,
              helperText: _ocrHelperText,
              onCopy: _copyOcrResult,
              onEdit: _editOcrResult,
            ),
          ),
        );
      },
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

  Future<Uint8List?> _captureCanvasForOcr() async {
    final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final devicePixelRatio =
        MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3.0;
    final pixelRatio = devicePixelRatio.clamp(3.0, 4.5).toDouble();
    final imageBytes = await _captureCanvas(pixelRatio: pixelRatio);
    if (imageBytes == null) return null;

    final inkBounds = _calculateInkBounds(_canvasBloc.state);
    if (inkBounds == null) {
      return imageBytes;
    }

    return _cropInkImageForOcr(
      pngBytes: imageBytes,
      logicalCanvasSize: boundary.size,
      inkBounds: inkBounds,
      pixelRatio: pixelRatio,
    );
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

  bool get _hasInk {
    final state = _canvasBloc.state;
    final hasSavedStrokes = state.strokes.any(
      (stroke) => !stroke.isEraser && stroke.points.isNotEmpty,
    );
    final hasCurrentStroke =
        _currentPoints.isNotEmpty && state.currentTool != CanvasTool.eraser;
    return hasSavedStrokes || hasCurrentStroke;
  }

  bool get _hasEraserEdits {
    return _canvasBloc.state.strokes.any((stroke) => stroke.isEraser);
  }

  Rect? _calculateInkBounds(CanvasState state) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;
    var hasPoints = false;

    void addStrokePoints(List<Offset> points, double strokeWidth) {
      if (points.isEmpty) return;
      hasPoints = true;
      final padding = math.max(strokeWidth, 8);
      for (final point in points) {
        minX = math.min(minX, point.dx - padding);
        minY = math.min(minY, point.dy - padding);
        maxX = math.max(maxX, point.dx + padding);
        maxY = math.max(maxY, point.dy + padding);
      }
    }

    for (final stroke in state.strokes) {
      if (stroke.isEraser) continue;
      addStrokePoints(stroke.points, stroke.strokeWidth);
    }

    if (_currentPoints.isNotEmpty && state.currentTool != CanvasTool.eraser) {
      addStrokePoints(_currentPoints, state.currentStrokeWidth);
    }

    if (!hasPoints) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Uint8List _cropInkImageForOcr({
    required Uint8List pngBytes,
    required Size logicalCanvasSize,
    required Rect inkBounds,
    required double pixelRatio,
  }) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;

    final logicalPadding = math.min(
      math.max(logicalCanvasSize.shortestSide * 0.12, 28.0),
      72.0,
    );
    final expandedBounds = Rect.fromLTRB(
      math.max(0, inkBounds.left - logicalPadding),
      math.max(0, inkBounds.top - logicalPadding),
      math.min(logicalCanvasSize.width, inkBounds.right + logicalPadding),
      math.min(logicalCanvasSize.height, inkBounds.bottom + logicalPadding),
    );

    final cropX = (expandedBounds.left * pixelRatio).floor();
    final cropY = (expandedBounds.top * pixelRatio).floor();
    final cropWidth = math.max(1, (expandedBounds.width * pixelRatio).ceil());
    final cropHeight = math.max(1, (expandedBounds.height * pixelRatio).ceil());

    var cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    final longEdge = math.max(cropped.width, cropped.height);
    if (longEdge < 1600) {
      cropped = cropped.width >= cropped.height
          ? img.copyResize(
              cropped,
              width: 1600,
              interpolation: img.Interpolation.linear,
            )
          : img.copyResize(
              cropped,
              height: 1600,
              interpolation: img.Interpolation.linear,
            );
    }

    return Uint8List.fromList(img.encodePng(cropped));
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
    if (!_hasInk) {
      setState(() {
        _ocrResult = '';
        _ocrBannerState = OcrBannerState.warning;
        _ocrHelperText = '还没有可识别的手写内容。先写几笔，再点右上角“识别”。';
        _isResultPanelExpanded = true;
      });
      return;
    }

    final hasEraserEdits = _hasEraserEdits;
    setState(() {
      _isRecognizing = true;
      _ocrResult = '';
      _ocrBannerState = OcrBannerState.processing;
      _ocrHelperText = hasEraserEdits
          ? '正在优先做手写识别。检测到你用过橡皮，必要时会回退到图片识别。'
          : '正在准备手写识别模型并识别你的笔迹。必要时会自动回退到图片识别。';
      _isResultPanelExpanded = true;
    });

    try {
      final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final writingArea = boundary?.size ?? const Size(1080, 1440);

      HandwritingRecognitionResult? handwritingResult;
      Object? handwritingError;
      try {
        handwritingResult = await _handwritingRecognitionService.recognize(
          strokes: _canvasBloc.state.strokes,
          writingArea: writingArea,
        );
      } catch (error) {
        handwritingError = error;
      }

      var result = handwritingResult?.text.trim() ?? '';
      var usedImageFallback = false;

      if (result.isEmpty) {
        setState(() {
          _ocrHelperText = handwritingError == null
              ? '手写识别没有读出结果，正在回退到图片识别。'
              : '手写识别暂时不可用，正在回退到图片识别。';
        });
        result = await _runImageOcrFallback();
        usedImageFallback = true;
      }

      setState(() {
        _ocrResult = result;
        if (result.isEmpty) {
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = handwritingError == null
              ? '这次仍没有读清文本。请把数字或关键字写大一些、分开一点，再试一次。'
              : '当前设备上的手写识别没有完成，图片识别也没读到文本。请把字写得更大更清楚后重试。';
        } else {
          _ocrBannerState = OcrBannerState.success;
          if (usedImageFallback) {
            _ocrHelperText = '本次由图片识别兜底完成。建议先快速校对，再决定是否保存。';
          } else if (handwritingResult?.downloadedAnyModel == true) {
            _ocrHelperText = '首次手写识别模型已准备完成，识别成功。建议先快速校对再保存。';
          } else if (hasEraserEdits) {
            _ocrHelperText = '手写识别完成。你用过橡皮，建议多看一眼结果再保存。';
          } else {
            _ocrHelperText = '手写识别完成。建议先快速改一下错字，再决定是否保存到笔记。';
          }
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
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<String> _runImageOcrFallback() async {
    if (_ocrEngine == null) {
      return '';
    }

    final imageBytes = widget.captureCanvasForOcr != null
        ? await widget.captureCanvasForOcr!.call()
        : await _captureCanvasForOcr();
    if (imageBytes == null || imageBytes.isEmpty) {
      return '';
    }

    final lines = await _ocrEngine!.recognizeText(imageBytes);
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
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
