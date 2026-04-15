import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import 'package:idea_notes/features/canvas/models/extraction_preview.dart';

import '../../app/design_system.dart';
import '../../core/extraction/deepseek_ocr_text_correction_engine.dart';
import '../../core/extraction/extraction_models.dart';
import '../../core/extraction/deepseek_text_understanding_engine.dart';
import '../../core/models/note.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/ocr/vision_ocr.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/extraction_preview_repository.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';
import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'services/canvas_ai_preview_service.dart';
import 'services/handwriting_recognition_service.dart';
import 'services/canvas_save_service.dart';
import 'services/incremental_ocr_service.dart';
import 'services/ink_stability_detector.dart';
import 'services/realtime_extraction_pipeline.dart';
import 'services/region_capture_service.dart';
import 'services/voice_recognition_service.dart';
import 'widgets/canvas_ai_overlay.dart';
import 'widgets/canvas_bottom_toolbar.dart';
import 'widgets/canvas_painter.dart';
import 'widgets/canvas_responsive_layout.dart';
import 'widgets/canvas_stage.dart';
import 'widgets/voice_capture_sheet.dart';

class CanvasScreen extends StatefulWidget {
  final String? noteId;
  final VoidCallback? onSave;
  final Function(String)? onOcrComplete;
  final OcrEngine? ocrEngineOverride;
  final Future<Uint8List?> Function()? captureCanvasForOcr;
  final Future<Uint8List?> Function()? captureCanvasForSave;
  final Future<Uint8List?> Function()? captureThumbnailForSave;
  final CanvasSaveService? saveServiceOverride;
  final CanvasAiPreviewService? aiPreviewServiceOverride;
  final VoiceRecognitionService? voiceRecognitionServiceOverride;
  final bool openVoiceOnStart;
  final List<ExtractionPreview> initialPendingPreviews;
  final InkStabilityDetector? stabilityDetectorOverride;
  final RegionCaptureService? regionCaptureServiceOverride;
  final DefaultRealtimeExtractionPipeline? realtimePipelineOverride;

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
    this.aiPreviewServiceOverride,
    this.voiceRecognitionServiceOverride,
    this.openVoiceOnStart = false,
    this.initialPendingPreviews = const [],
    this.stabilityDetectorOverride,
    this.regionCaptureServiceOverride,
    this.realtimePipelineOverride,
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
  String _ocrHelperText = '写完后点一下”识别”，再决定是否复制、编辑或保存。';
  bool _isSaving = false;
  bool _isRecognizing = false;
  bool _isPreviewingAi = false;
  bool _isResultPanelExpanded = false;
  bool _hasUnsavedChanges = false;
  List<ExtractionPreview> _pendingPreviews = [];
  Note? _existingNote;
  OcrEngine? _ocrEngine;
  OcrBannerState _ocrBannerState = OcrBannerState.idle;

  // Realtime preview services
  late final InkStabilityDetector _stabilityDetector;
  late final RegionCaptureService _regionCaptureService;
  late final DefaultRealtimeExtractionPipeline _realtimePipeline;
  StreamSubscription<StableRegion>? _stabilitySubscription;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _handwritingRecognitionService = HandwritingRecognitionService();
    _pendingPreviews =
        List<ExtractionPreview>.from(widget.initialPendingPreviews);

    // Initialize realtime preview services
    _stabilityDetector =
        widget.stabilityDetectorOverride ?? InkStabilityDetector();
    _regionCaptureService =
        widget.regionCaptureServiceOverride ?? RegionCaptureService();
    _realtimePipeline = widget.realtimePipelineOverride ??
        DefaultRealtimeExtractionPipeline(
          previewRepository: ExtractionPreviewRepository(
            databaseHelper: DatabaseHelper.instance,
          ),
          createId: () =>
              '${DateTime.now().millisecondsSinceEpoch}-${_currentPoints.length}',
        );
    _listenForStableRegions();

    // Subscribe to pipeline preview stream for UI updates
    _realtimePipeline.previews.listen((preview) {
      if (!mounted) return;
      setState(() {
        _pendingPreviews = List.from(_pendingPreviews)..add(preview);
        _hasUnsavedChanges = true;
      });
    });

    _initOcrEngine();
    if (widget.noteId != null) {
      _loadExistingNote();
    }
    if (widget.openVoiceOnStart && widget.noteId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openVoiceCapture());
      });
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
      _hasUnsavedChanges = false;
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
    _stabilitySubscription?.cancel();
    _stabilityDetector.dispose();
    _realtimePipeline.dispose();
    _canvasBloc.close();
    _ocrEngine?.dispose();
    unawaited(_handwritingRecognitionService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _canvasBloc,
      child: PopScope<void>(
        canPop: !_hasUnsavedChanges || _isSaving,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _isSaving || !_hasUnsavedChanges) {
            return;
          }
          unawaited(_handleAttemptedPop());
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.noteId == null ? '新建手写笔记' : '继续编辑笔记'),
            actions: [
              IconButton(
                onPressed: _handleResultAction,
                tooltip: context.isLarge
                    ? (_isResultPanelExpanded ? '收起识别面板' : '展开识别面板')
                    : '查看识别结果',
                icon: Icon(
                  context.isLarge
                      ? Icons.view_sidebar_rounded
                      : Icons.article_outlined,
                ),
              ),
              IconButton(
                onPressed: (_isSaving || _isRecognizing || _isPreviewingAi)
                    ? null
                    : _openVoiceCapture,
                tooltip: '语音转文字',
                icon: const Icon(Icons.mic_rounded),
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
              if (_ocrResult.trim().isNotEmpty || _isPreviewingAi)
                IconButton(
                  onPressed: _isPreviewingAi ? null : _previewAiExtraction,
                  tooltip: 'AI校对并整理',
                  icon: _isPreviewingAi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
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
                final showLargeResultDock = context.isLarge;
                final showCompactResultPeek =
                    !showLargeResultDock && _shouldShowCompactResultPeek;
                final horizontal =
                    showLargeResultDock ? 24.0 : (isCompact ? 12.0 : 16.0);

                final largePanelWidth = (constraints.maxWidth * 0.34)
                    .clamp(340.0, 420.0)
                    .toDouble();
                final phoneToolbarHeight = isCompact ? 78.0 : 88.0;
                final compactPeekSpacing = showCompactResultPeek ? 82.0 : 0.0;
                final canvasRightPadding =
                    showLargeResultDock && _isResultPanelExpanded
                        ? largePanelWidth + 18
                        : 0.0;
                final canvasBottomPadding = showLargeResultDock
                    ? 124.0
                    : phoneToolbarHeight + compactPeekSpacing + 28.0;

                return CanvasResponsiveLayout(
                  stage: AnimatedPadding(
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
                  overlay: Stack(
                    children: [
                      if (showCompactResultPeek)
                        Positioned(
                          left: horizontal,
                          right: horizontal,
                          bottom: phoneToolbarHeight + 32,
                          child: _buildCompactResultPeek(context),
                        ),
                      if (_pendingPreviews.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: horizontal,
                          width: largePanelWidth,
                          child: CanvasAiOverlay(
                            previews: _pendingPreviews,
                            onConfirm: _confirmPreview,
                          ),
                        ),
                      if (showLargeResultDock)
                        Positioned(
                          top: 8,
                          right: horizontal,
                          bottom: 24,
                          child: _buildLargeResultDock(
                            context,
                            width: largePanelWidth,
                          ),
                        ),
                    ],
                  ),
                  toolbar: Positioned(
                    left: horizontal,
                    right: horizontal + canvasRightPadding,
                    bottom: showLargeResultDock ? 24 : 20,
                    child: const CanvasBottomToolbar(
                      child: CanvasToolbar(),
                    ),
                  ),
                );
              },
            ),
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
                child: CanvasStage(
                  painter: RepaintBoundary(
                    key: _canvasRepaintKey,
                    child: _buildCanvas(),
                  ),
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

  Future<void> _previewAiExtraction() async {
    final recognizedText = _ocrResult.trim();
    if (recognizedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先识别出文本，AI 才能继续整理。')),
      );
      return;
    }

    setState(() {
      _isPreviewingAi = true;
      _isResultPanelExpanded = true;
    });

    CanvasAiPreviewResult result;
    try {
      final previewService = widget.aiPreviewServiceOverride ??
          CanvasAiPreviewService(
            engine: DeepSeekTextUnderstandingEngine(),
            correctionEngine: DeepSeekOcrTextCorrectionEngine(),
          );
      result = await previewService.preview(
        existingNote: _existingNote,
        recognizedText: recognizedText,
        now: DateTime.now(),
      );
    } catch (error) {
      result = CanvasAiPreviewResult.failure(
        engineName: 'deepseek',
        message: 'AI 预览失败，请稍后再试：$error',
        originalText: recognizedText,
        correctedText: recognizedText,
      );
    }

    if (!mounted) {
      return;
    }

    final correctionApplied = result.correctionApplied;
    if (correctionApplied) {
      setState(() {
        _ocrResult = result.correctedText;
        _ocrBannerState = OcrBannerState.success;
        _ocrHelperText = 'AI 已先校对 OCR 文本，再继续整理。请确认后保存。';
        _hasUnsavedChanges = true;
        _isResultPanelExpanded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI 已校对识别文本，当前展示的是校对后的结果。'),
        ),
      );
    }

    setState(() => _isPreviewingAi = false);
    await _showAiPreviewSheet(result);
  }

  Future<void> _openVoiceCapture() async {
    final ok = await _ensureVoicePermissions();
    if (!ok || !mounted) return;

    final service = widget.voiceRecognitionServiceOverride ??
        SpeechToTextVoiceRecognitionService();

    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * (context.isCompact ? 0.82 : 0.78);

    final result = await showModalBottomSheet<VoiceCaptureResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            height: sheetHeight,
            child: VoiceCaptureSheet(
              service: service,
              existingText: _ocrResult,
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    final incoming = result.text.trim();
    if (incoming.isEmpty) return;

    setState(() {
      _ocrResult = _mergeVoiceText(
        existing: _ocrResult,
        incoming: incoming,
        mode: result.writeMode,
      );
      _ocrBannerState = OcrBannerState.success;
      _ocrHelperText = '语音转写已写入。建议先快速校对，再决定是否保存或进行 AI 整理预览。';
      _hasUnsavedChanges = true;
      _isResultPanelExpanded = true;
    });

    if (!mounted || context.isLarge) return;
    await _showCompactResultSheet();
  }

  String _mergeVoiceText({
    required String existing,
    required String incoming,
    required VoiceCaptureWriteMode mode,
  }) {
    final trimmedExisting = existing.trimRight();
    if (mode != VoiceCaptureWriteMode.append ||
        trimmedExisting.trim().isEmpty) {
      return incoming;
    }
    final needsNewline = !trimmedExisting.endsWith('\n');
    return needsNewline
        ? '$trimmedExisting\n$incoming'
        : '$trimmedExisting$incoming';
  }

  Future<bool> _ensureVoicePermissions() async {
    // Voice permission is only meaningful on mobile platforms.
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return true;
    }

    Future<bool> requestPermission(Permission permission, String name) async {
      final status = await permission.status;
      if (status.isGranted) return true;
      final requested = await permission.request();
      if (requested.isGranted) return true;

      if (!mounted) return false;
      if (requested.isPermanentlyDenied || requested.isRestricted) {
        await _showPermissionDialog(
          title: '需要$name权限',
          message: '语音转文字需要使用$name。请在系统设置中开启权限后再试。',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未获得$name权限，无法开始语音识别。')),
        );
      }
      return false;
    }

    try {
      final micOk = await requestPermission(Permission.microphone, '麦克风');
      if (!micOk) return false;

      if (Platform.isIOS) {
        final speechOk = await requestPermission(Permission.speech, '语音识别');
        if (!speechOk) return false;
      }

      return true;
    } on MissingPluginException {
      // Widget tests or platforms without plugin registration.
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法获取语音权限：$error')),
      );
      return false;
    }
  }

  Future<void> _showPermissionDialog({
    required String title,
    required String message,
  }) async {
    final goToSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );

    if (goToSettings == true) {
      await openAppSettings();
    }
  }

  Future<void> _showAiPreviewSheet(CanvasAiPreviewResult result) async {
    if (!mounted) return;

    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * (context.isCompact ? 0.82 : 0.88);

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
            height: sheetHeight,
            child: _AiPreviewSheet(result: result),
          ),
        );
      },
    );
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
            height: media.size.height * 0.84,
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
    final hasResult = _ocrResult.trim().isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isResultPanelExpanded
          ? SizedBox(
              key: const ValueKey('expanded-ocr-panel'),
              width: width,
              child: Column(
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
                  if (hasResult) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed:
                            _isPreviewingAi ? null : _previewAiExtraction,
                        icon: _isPreviewingAi
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded),
                        label: const Text('AI校对+整理'),
                      ),
                    ),
                  ],
                ],
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
              currentStyle: state.currentStyle,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  Widget _buildCompactResultPeek(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 24,
      backgroundColor: Colors.white.withValues(alpha: 0.97),
      border: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      boxShadow: AppShadows.floating,
      child: InkWell(
        onTap: _showCompactResultSheet,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            _PanelStatusPill(state: _ocrBannerState),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _panelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _panelDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_up_rounded),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowCompactResultPeek =>
      _ocrBannerState != OcrBannerState.idle || _ocrResult.trim().isNotEmpty;

  Future<void> _handleResultAction() async {
    if (context.isLarge) {
      _toggleResultPanel();
      return;
    }
    await _showCompactResultSheet();
  }

  void _toggleResultPanel() {
    setState(() {
      _isResultPanelExpanded = !_isResultPanelExpanded;
    });
  }

  Future<void> _handleAttemptedPop() async {
    final shouldDiscard = await _confirmDiscardChanges();
    if (!mounted || !shouldDiscard) return;
    setState(() => _hasUnsavedChanges = false);
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscardChanges() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这次修改？'),
        content: const Text('你还没有保存这页内容。现在返回会丢失刚刚的手写、识别结果或编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('直接返回'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _confirmPreview(ExtractionPreview preview) {
    setState(() {
      _pendingPreviews =
          _pendingPreviews.where((p) => p.id != preview.id).toList();
    });
  }

  void _listenForStableRegions() {
    _stabilitySubscription =
        _stabilityDetector.onRegionStabilized.listen((region) async {
      if (!mounted) return;

      final bytes = await _regionCaptureService.capture(
        repaintKey: _canvasRepaintKey,
        region: region.bounds,
      );
      if (bytes == null || !mounted) return;

      // Skip OCR if no engine available
      if (_ocrEngine == null) return;

      try {
        final incrementalOcr = IncrementalOcrService(engine: _ocrEngine!);
        final delta = await incrementalOcr.recognizeRegion(
          bytes,
          previousText: _ocrResult,
        );
        if (delta.deltaText.isEmpty || !mounted) return;

        _ocrResult = delta.fullText;

        final noteId = _existingNote?.id ??
            'draft-${DateTime.now().millisecondsSinceEpoch}';
        await _realtimePipeline.submitDelta(
          noteId: noteId,
          rawText: delta.deltaText,
        );
      } catch (_) {
        // Silently ignore realtime OCR failures; user can still use manual OCR.
      }
    });
  }

  Rect? _boundsForPoints(List<Offset> points) {
    if (points.isEmpty) return null;
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _onPanStart(DragStartDetails details) {
    if (_isResultPanelExpanded) setState(() => _isResultPanelExpanded = false);
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
      final bounds = _boundsForPoints(_currentPoints);
      context.read<CanvasBloc>().add(
            StrokeAdded(
              points: _currentPoints,
              color: state.currentColor,
              strokeWidth: state.currentStrokeWidth,
              isEraser: state.currentTool == CanvasTool.eraser,
              style: state.currentStyle,
            ),
          );
      if (bounds != null && state.currentTool != CanvasTool.eraser) {
        _stabilityDetector.registerStrokeBounds(bounds);
      }
      _hasUnsavedChanges = true;
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
          CanvasSaveService(
            databaseHelper: DatabaseHelper.instance,
            textUnderstandingEngine: DeepSeekTextUnderstandingEngine(),
          );
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
      setState(() {
        _hasUnsavedChanges = false;
        _isResultPanelExpanded = false;
      });
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

    final shouldUseCompactSheet = !context.isLarge;
    var shouldOpenCompactSheet = false;

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
        _hasUnsavedChanges = true;
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
      shouldOpenCompactSheet = shouldUseCompactSheet;
    } catch (_) {
      setState(() {
        _ocrBannerState = OcrBannerState.error;
        _ocrResult = '';
        _ocrHelperText = '识别没有完成。你可以再试一次；如果持续失败，先保存当前手写内容。';
      });
      shouldOpenCompactSheet = shouldUseCompactSheet;
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }

    if (mounted && shouldOpenCompactSheet) {
      await _showCompactResultSheet();
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
                _hasUnsavedChanges = true;
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

class _AiPreviewSheet extends StatelessWidget {
  final CanvasAiPreviewResult result;

  const _AiPreviewSheet({required this.result});

  @override
  Widget build(BuildContext context) {
    final document = result.document;
    final entries = document?.entries ?? const <ExtractedEntry>[];
    final warnings = document?.warnings ?? const <ExtractionWarning>[];
    final unparsedSegments = document?.unparsedSegments ?? const <String>[];
    final correctionApplied = result.correctionApplied;

    return AppSurface(
      radius: context.isCompact ? 28 : 32,
      padding: EdgeInsets.all(context.isCompact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: 'AI校对与整理',
            title: result.success
                ? (correctionApplied ? 'AI 已先校对文本，再给出整理结果' : '这是保存前的 AI 整理结果')
                : '这次 AI 预览没有成功',
            description: result.success
                ? correctionApplied
                    ? '当前 OCR 文本已经按 AI 校对结果写回编辑区；这里展示的是基于校对文本生成的整理结果。'
                    : '这里先给你看模型当前理解的条目；真正保存时，系统会把 AI 结果和规则解析合并后再写入。'
                : (result.errorMessage ?? 'AI 没有返回可用结果。你仍然可以继续编辑或直接保存 OCR 文本。'),
          ),
          const SizedBox(height: 16),
          if (correctionApplied) ...[
            _AiCorrectionPreviewCard(result: result),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AiPreviewMetaChip(
                icon: Icons.auto_awesome_rounded,
                label:
                    '${result.engineName} · ${result.modelName ?? 'unknown'}',
                accent: AppColors.aiAccent,
              ),
              _AiPreviewMetaChip(
                icon: Icons.fact_check_outlined,
                label: '${entries.length} 条结构化结果',
                accent: result.success ? AppColors.success : AppColors.warning,
              ),
              if (correctionApplied)
                const _AiPreviewMetaChip(
                  icon: Icons.spellcheck_rounded,
                  label: '已校对 OCR 文本',
                  accent: AppColors.success,
                ),
              _AiPreviewMetaChip(
                icon: Icons.schedule_rounded,
                label: '${result.latency.inMilliseconds} ms',
                accent: AppColors.inkBlue,
              ),
              const _AiPreviewMetaChip(
                icon: Icons.lock_outline_rounded,
                label: '仅预览，未保存',
                accent: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!result.success)
                      _AiPreviewNoticeCard(
                        title: 'AI 没有返回可用结构',
                        accent: AppColors.error,
                        icon: Icons.error_outline_rounded,
                        bullets: [
                          result.errorMessage ?? '这次预览失败。',
                          '你仍然可以手动编辑 OCR 文本后保存，保存流程不会因为预览失败而中断。',
                        ],
                      )
                    else if (entries.isEmpty)
                      const EmptyStateView(
                        icon: Icons.layers_clear_outlined,
                        title: 'AI 还没有整理出条目',
                        description: '模型这次没有提取出可复用的信息。你可以先修改 OCR 文本，再预览一次。',
                      )
                    else ...[
                      Text(
                        '结构化条目',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...entries.map(
                        (entry) => _AiPreviewEntryCard(entry: entry),
                      ),
                    ],
                    if (warnings.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _AiPreviewNoticeCard(
                        title: '模型提醒',
                        accent: AppColors.warning,
                        icon: Icons.info_outline_rounded,
                        bullets: warnings
                            .map((warning) => warning.message)
                            .toList(growable: false),
                      ),
                    ],
                    if (unparsedSegments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _AiPreviewNoticeCard(
                        title: '未完全解析的片段',
                        accent: AppColors.slateBlue,
                        icon: Icons.segment_rounded,
                        bullets: unparsedSegments,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCorrectionPreviewCard extends StatelessWidget {
  final CanvasAiPreviewResult result;

  const _AiCorrectionPreviewCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD7E9DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 文本校对',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '下面是 AI 校对前后的文本。保存时会以校对后的版本为准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _AiCorrectionBlock(
            label: '原始 OCR',
            text: result.originalText,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 10),
          _AiCorrectionBlock(
            label: 'AI 校对后',
            text: result.correctedText,
            backgroundColor: const Color(0xFFF1F7F3),
          ),
        ],
      ),
    );
  }
}

class _AiCorrectionBlock extends StatelessWidget {
  final String label;
  final String text;
  final Color backgroundColor;

  const _AiCorrectionBlock({
    required this.label,
    required this.text,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _AiPreviewEntryCard extends StatelessWidget {
  final ExtractedEntry entry;

  const _AiPreviewEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette;
    final metadata = <String>[
      _entryTypeLabel(entry),
      _timeLabel(entry),
      if (entry.category?.l1.trim().isNotEmpty == true) entry.category!.l1,
      if (_statusLabel(entry) != null) _statusLabel(entry)!,
    ];

    return AppSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      backgroundColor: palette.background,
      border: BorderSide(color: palette.border),
      boxShadow: const [],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.pill,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(palette.icon, color: palette.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_amountLabel(entry) != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        _amountLabel(entry)!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.inkBlue,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  metadata.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.summary?.trim().isNotEmpty == true
                      ? entry.summary!.trim()
                      : entry.rawText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AiPreviewMetaChip(
                      icon: Icons.folder_open_outlined,
                      label: entry.domain,
                      accent: AppColors.textSecondary,
                    ),
                    if (entry.category?.l2?.trim().isNotEmpty == true)
                      _AiPreviewMetaChip(
                        icon: Icons.label_outline_rounded,
                        label: entry.category!.l2!,
                        accent: AppColors.slateBlue,
                      ),
                    _AiPreviewMetaChip(
                      icon: Icons.tune_rounded,
                      label:
                          '置信 ${(entry.confidence * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      accent: AppColors.aiAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _entryTypeLabel(ExtractedEntry entry) {
    switch (entry.entryType) {
      case ExtractionEntryType.expense:
        return '花费';
      case ExtractionEntryType.income:
        return '收入';
      case ExtractionEntryType.purchase:
        return '消费';
      case ExtractionEntryType.task:
        return entry.domain == 'health' ? '健康待办' : '待办';
      case ExtractionEntryType.appointment:
        return '预约';
      case ExtractionEntryType.vaccination:
        return '疫苗';
      case ExtractionEntryType.medication:
        return '用药';
      case ExtractionEntryType.healthRecord:
        return '健康记录';
      case ExtractionEntryType.metric:
        return '健康指标';
      case ExtractionEntryType.travel:
        return '出行';
      case ExtractionEntryType.document:
        return '资料';
      case ExtractionEntryType.memo:
        return '记录';
      case ExtractionEntryType.custom:
        return '自定义';
    }
  }

  static String _timeLabel(ExtractedEntry entry) {
    final occurredAt = entry.occurredAt;
    if (occurredAt == null) {
      return '${entry.occurredDate.month}月${entry.occurredDate.day}日';
    }

    final dateLabel = '${occurredAt.month}月${occurredAt.day}日';
    if (occurredAt.hour == 0 && occurredAt.minute == 0) {
      return dateLabel;
    }
    final timeLabel =
        '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';
    return '$dateLabel $timeLabel';
  }

  static String? _amountLabel(ExtractedEntry entry) {
    final amount = entry.amount;
    if (amount == null) {
      return null;
    }
    if (amount.currency == 'CNY') {
      return '¥${amount.value}';
    }
    return '${amount.currency} ${amount.value}';
  }

  static String? _statusLabel(ExtractedEntry entry) {
    switch (entry.status) {
      case 'done':
        return '已完成';
      case 'pending':
        return '待处理';
      case 'recorded':
        return null;
      default:
        return entry.status.trim().isEmpty ? null : entry.status;
    }
  }

  _PreviewPalette get _palette {
    switch (entry.entryType) {
      case ExtractionEntryType.expense:
      case ExtractionEntryType.purchase:
      case ExtractionEntryType.income:
        return const _PreviewPalette(
          background: Color(0xFFFAF6EE),
          border: Color(0xFFEADFC7),
          pill: Color(0xFFF3E8D0),
          accent: AppColors.warning,
          icon: Icons.payments_outlined,
        );
      case ExtractionEntryType.task:
      case ExtractionEntryType.appointment:
        return _PreviewPalette(
          background: entry.domain == 'health'
              ? const Color(0xFFF1F7F3)
              : const Color(0xFFF1F5F7),
          border: entry.domain == 'health'
              ? const Color(0xFFD6E8DD)
              : const Color(0xFFD9E4EA),
          pill: entry.domain == 'health'
              ? const Color(0xFFDCEFE4)
              : const Color(0xFFDDE8EE),
          accent:
              entry.domain == 'health' ? AppColors.success : AppColors.inkBlue,
          icon: entry.domain == 'health'
              ? Icons.health_and_safety_outlined
              : Icons.event_note_rounded,
        );
      case ExtractionEntryType.vaccination:
        return const _PreviewPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.vaccines_rounded,
        );
      case ExtractionEntryType.medication:
        return const _PreviewPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.medication_outlined,
        );
      case ExtractionEntryType.healthRecord:
      case ExtractionEntryType.metric:
        return const _PreviewPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.favorite_border_rounded,
        );
      default:
        return const _PreviewPalette(
          background: Color(0xFFF5F7F8),
          border: Color(0xFFDDE3E8),
          pill: Color(0xFFE4EAEE),
          accent: AppColors.slateBlue,
          icon: Icons.sticky_note_2_outlined,
        );
    }
  }
}

class _AiPreviewNoticeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<String> bullets;

  const _AiPreviewNoticeCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      backgroundColor: accent.withValues(alpha: 0.08),
      border: BorderSide(color: accent.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: accent,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bullet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiPreviewMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _AiPreviewMetaChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent == AppColors.textSecondary
            ? const Color(0xFFF3F5F6)
            : accent.withValues(alpha: 0.12),
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

class _PreviewPalette {
  final Color background;
  final Color border;
  final Color pill;
  final Color accent;
  final IconData icon;

  const _PreviewPalette({
    required this.background,
    required this.border,
    required this.pill,
    required this.accent,
    required this.icon,
  });
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
