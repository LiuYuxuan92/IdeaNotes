import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/design_system.dart';
import '../../core/extraction/deepseek_ocr_text_correction_engine.dart';
import '../../core/extraction/extraction_models.dart';
import '../../core/extraction/deepseek_text_understanding_engine.dart';
import '../../core/models/note.dart';
import '../../core/ocr/ocr_engine.dart';
import '../../core/ocr/vision_ocr.dart';
import '../../core/storage/database_helper.dart';
import '../../shared/widgets/ocr_result_banner.dart';
import '../notelist/bloc/note_list_bloc.dart';
import 'bloc/canvas_bloc.dart';
import 'canvas_toolbar.dart';
import 'services/canvas_ai_preview_service.dart';
import 'services/handwriting_recognition_service.dart';
import 'services/canvas_save_service.dart';
import 'services/local_rule_fallback_service.dart';
import 'services/offscreen_canvas_renderer.dart';
import 'services/voice_recognition_service.dart';
import 'widgets/canvas_painter.dart';
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
  /// 预填识别文本（例如从系统分享入口进入时，其他 App 传过来的文本）。
  /// 填了会直接作为 OCR 结果呈现。
  final String? initialOcrText;

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
    this.initialOcrText,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasRepaintKey = GlobalKey();
  List<Offset> _currentPoints = <Offset>[];
  List<double> _currentPressures = <double>[];
  double _lastPointerPressure = 1.0;
  late final CanvasBloc _canvasBloc;
  late final HandwritingRecognitionService _handwritingRecognitionService;

  String _ocrResult = '';
  String _ocrHelperText = '写完后点一下“识别”，再决定是否复制、编辑或保存。';
  bool _isSaving = false;
  bool _isRecognizing = false;
  bool _isPreviewingAi = false;
  bool _isResultPanelExpanded = false;
  bool _hasUnsavedChanges = false;
  // ── Autosave ──
  Timer? _autosaveTimer;
  bool _isAutoSaving = false;
  DateTime? _lastSavedAt;
  static const Duration _autosaveDebounce = Duration(seconds: 2);
  Note? _existingNote;
  OcrEngine? _ocrEngine;
  OcrBannerState _ocrBannerState = OcrBannerState.idle;

  // Palm rejection & multi-finger tracking
  bool _stylusActive = false;
  final Set<int> _activePointers = {};
  final Map<int, Offset> _pointerDownPositions = {};
  int _maxSimultaneousPointers = 0;
  bool _didShowGestureHint = false;
  final TransformationController _transformController = TransformationController();

  // ── 手势状态（用于 ScaleGestureRecognizer 区分画/拖/缩放） ──
  /// 当前是否正在画一笔（单指接触且未被多指打断）
  bool _isDrawing = false;
  /// 二指手势开始时的视图 transform
  Matrix4 _gestureStartTransform = Matrix4.identity();
  /// 二指开始时焦点对应的 World 坐标（缩放/平移的锚点）
  Offset _gestureStartWorldAnchor = Offset.zero;
  /// 缩放钳制范围
  static const double _minScale = 0.25;
  static const double _maxScale = 4.0;

  /// 当前画布视口尺寸（由 LayoutBuilder 写入）
  Size? _canvasViewportSize;

  /// 老笔记加载后需要在下一次 layout 自动居中
  bool _pendingFitToInkOnLayout = false;

  @override
  void initState() {
    super.initState();
    _canvasBloc = CanvasBloc();
    _handwritingRecognitionService = HandwritingRecognitionService();
    _initOcrEngine();
    if (widget.noteId != null) {
      _loadExistingNote();
    }
    final initial = widget.initialOcrText?.trim();
    if (initial != null && initial.isNotEmpty && widget.noteId == null) {
      _ocrResult = initial;
      _ocrBannerState = OcrBannerState.success;
      _ocrHelperText = '从其他 App 分享过来的文本，已直接放入识别结果。';
      _hasUnsavedChanges = true;
      _isResultPanelExpanded = true;
    }
    if (widget.openVoiceOnStart && widget.noteId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openVoiceCapture());
      });
    }
    // 首次进入新笔记 → 提示无限画布手势（per-session）
    if (widget.noteId == null && !_didShowInfiniteCanvasHint) {
      _didShowInfiniteCanvasHint = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('提示：单指写字、二指拖动 / 捏合缩放；写到屏幕外也不会丢'),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  /// session 级标记：本次进程内是否已经展示过"无限画布手势"提示。
  /// 这是 static，所以多次打开 CanvasScreen 都只展示一次。
  static bool _didShowInfiniteCanvasHint = false;

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
      // 老笔记可能整体偏离当前视口（旧的屏幕坐标系），等下一次 layout 拿到尺寸后居中。
      _pendingFitToInkOnLayout = true;
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _transformController.dispose();
    _canvasBloc.close();
    _ocrEngine?.dispose();
    unawaited(_handwritingRecognitionService.dispose());
    super.dispose();
  }

  /// 在每次内容变化后调用，重启 debounce 计时器
  void _scheduleAutosave() {
    if (_isSaving) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDebounce, _performAutosave);
  }

  /// 静默保存：不弹提示、不返回上一页
  Future<void> _performAutosave() async {
    if (!mounted) return;
    if (!_hasUnsavedChanges) return;
    if (_isSaving || _isAutoSaving) return;

    setState(() => _isAutoSaving = true);
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
        _lastSavedAt = DateTime.now();
      });
    } catch (_) {
      // 静默失败：不打扰用户，下次变更后再尝试
    } finally {
      if (mounted) setState(() => _isAutoSaving = false);
    }
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
              _AutosaveStatusPill(
                isSaving: _isAutoSaving || _isSaving,
                hasUnsavedChanges: _hasUnsavedChanges,
                lastSavedAt: _lastSavedAt,
              ),
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
            top: false,
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
                    if (showCompactResultPeek)
                      Positioned(
                        left: horizontal,
                        right: horizontal,
                        bottom: phoneToolbarHeight + 32,
                        child: _buildCompactResultPeek(context),
                      ),
                    Positioned(
                      left: horizontal,
                      right: horizontal + canvasRightPadding,
                      bottom: showLargeResultDock ? 24 : 20,
                      child: CanvasToolbar(
                        onFitToScreen: _resetCanvasTransform,
                        onFitToInk: _fitToInk,
                        viewTransform: _transformController,
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

  Future<void> _previewAiExtraction() async {
    final recognizedText = _ocrResult.trim();
    if (recognizedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先识别出文本，AI 才能继续整理。')),
      );
      return;
    }

    // 送 AI 之前给用户一次手动修正机会（中文手写 OCR 错误率较高）
    final confirmedText = await _confirmTextBeforeAi(recognizedText);
    if (confirmedText == null) return; // 用户取消
    if (confirmedText != recognizedText) {
      setState(() {
        _ocrResult = confirmedText;
        _hasUnsavedChanges = true;
        _ocrBannerState = OcrBannerState.success;
        _ocrHelperText = '你已在送 AI 前手动修正识别文本。';
      });
      _scheduleAutosave();
    }

    setState(() {
      _isPreviewingAi = true;
      _isResultPanelExpanded = true;
    });

    // 显示带进度的非阻塞 modal（AI 完成后自动关闭）
    final progressEntry = _showAiProgressOverlay();

    CanvasAiPreviewResult result;
    String? aiFailureMessage;
    try {
      final previewService = widget.aiPreviewServiceOverride ??
          CanvasAiPreviewService(
            engine: DeepSeekTextUnderstandingEngine(),
            correctionEngine: const DeepSeekOcrTextCorrectionEngine(),
          );
      result = await previewService.preview(
        existingNote: _existingNote,
        recognizedText: confirmedText,
        now: DateTime.now(),
      );
      if (!result.success) {
        aiFailureMessage = result.errorMessage;
      }
    } catch (error) {
      aiFailureMessage = error.toString();
      result = CanvasAiPreviewResult.failure(
        engineName: 'deepseek',
        message: 'AI 预览失败：$error',
        originalText: confirmedText,
        correctedText: confirmedText,
      );
    }

    // 本地规则兜底：AI 失败时仍给用户一份基础结构化结果
    if (!result.success) {
      final fallback = LocalRuleFallbackService().buildPreview(
        existingNote: _existingNote,
        recognizedText: confirmedText,
        now: DateTime.now(),
        upstreamErrorMessage: aiFailureMessage,
      );
      result = fallback;
    }

    if (!mounted) {
      progressEntry.remove();
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
    progressEntry.remove();
    await _showAiPreviewSheet(result);
  }

  /// 在画布上覆盖一个进度条 OverlayEntry，AI 完成后调用 .remove() 关闭。
  /// 显示已耗时 + 轮播提示，让用户在等待期间不至于面对空白。
  OverlayEntry _showAiProgressOverlay() {
    final entry = OverlayEntry(
      builder: (_) => const _AiProgressOverlay(),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return entry;
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

  // ── Pointer tracking (Listener) – only tracks finger count, stylus, palm ──

  void _trackPointerDown(PointerEvent event) {
    _activePointers.add(event.pointer);
    _pointerDownPositions[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      _maxSimultaneousPointers = 1;
    } else {
      _maxSimultaneousPointers =
          math.max(_maxSimultaneousPointers, _activePointers.length);
    }

    if (event.kind == ui.PointerDeviceKind.stylus) {
      _stylusActive = true;
    }

    // Track pressure for variable-width drawing (most Android phones report 0..1).
    if (event.pressure > 0 && event.pressureMin != event.pressureMax) {
      final range = event.pressureMax - event.pressureMin;
      _lastPointerPressure =
          ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
    } else {
      _lastPointerPressure = 1.0;
    }
  }

  void _trackPointerUp(
      PointerEvent event, BuildContext context, CanvasState state) {
    final downPos = _pointerDownPositions.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (event.kind == ui.PointerDeviceKind.stylus && _activePointers.isEmpty) {
      _stylusActive = false;
    }

    // Multi-finger tap gesture detection (undo / redo)
    if (_activePointers.isEmpty && _pointerDownPositions.isEmpty) {
      final wasMultiFinger = _maxSimultaneousPointers >= 2;
      final noDisplacement =
          downPos != null && (event.localPosition - downPos).distance < 20;

      if (wasMultiFinger && noDisplacement) {
        if (_maxSimultaneousPointers == 2 && state.canUndo) {
          HapticFeedback.selectionClick();
          context.read<CanvasBloc>().add(StrokeUndone());
          _hasUnsavedChanges = true;
          _scheduleAutosave();
          if (!_didShowGestureHint) {
            _didShowGestureHint = true;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('双指轻拍 = 撤销，三指轻拍 = 重做'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (_maxSimultaneousPointers >= 3 && state.canRedo) {
          HapticFeedback.selectionClick();
          context.read<CanvasBloc>().add(StrokeRedone());
          _hasUnsavedChanges = true;
          _scheduleAutosave();
          if (!_didShowGestureHint) {
            _didShowGestureHint = true;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('双指轻拍 = 撤销，三指轻拍 = 重做'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
        setState(() => _currentPoints = <Offset>[]);
        _maxSimultaneousPointers = 0;
        return;
      }
      _maxSimultaneousPointers = 0;
    }
  }

  // ── Drawing & viewport callbacks (ScaleGestureRecognizer) ──
  //
  // 设计：ScaleGestureRecognizer 同时支持 1+ 个手指。
  // - pointerCount == 1：单指画画（在 World 坐标系下）
  // - pointerCount >= 2：二指拖动 + 捏合缩放
  // - 1 指画到一半 2 指介入：丢弃当前未完成笔迹，切换到拖动模式

  /// 屏幕坐标 → World 坐标（应用 viewTransform 的逆变换）
  Offset _screenToWorld(Offset screen) {
    final inverse = Matrix4.tryInvert(_transformController.value);
    if (inverse == null) return screen;
    return MatrixUtils.transformPoint(inverse, screen);
  }

  void _onScaleStart(ScaleStartDetails details, CanvasState state) {
    // 不论开局是单指还是多指，先把当前 transform 和锚点存起来
    _gestureStartTransform = _transformController.value.clone();
    _gestureStartWorldAnchor = _screenToWorld(details.localFocalPoint);

    if (details.pointerCount == 1) {
      // 单指：尝试开始画一笔
      if (state.stylusOnlyMode && !_stylusActive) return;
      if (_isResultPanelExpanded) {
        setState(() => _isResultPanelExpanded = false);
      }
      final worldPoint = _screenToWorld(details.localFocalPoint);
      setState(() {
        _isDrawing = true;
        _currentPoints = <Offset>[worldPoint];
        _currentPressures = <double>[_lastPointerPressure];
      });
    }
    // pointerCount >= 2：直接进入拖动/缩放模式，不画
  }

  void _onScaleUpdate(ScaleUpdateDetails details, CanvasState state) {
    // 画笔中途多指介入：撤销当前笔迹，切到拖动模式
    if (_isDrawing && details.pointerCount > 1) {
      setState(() {
        _isDrawing = false;
        _currentPoints = <Offset>[];
        _currentPressures = <double>[];
      });
      // 多指开始的瞬间重置 anchor，避免拖动跳变
      _gestureStartTransform = _transformController.value.clone();
      _gestureStartWorldAnchor = _screenToWorld(details.localFocalPoint);
      return;
    }

    if (_isDrawing) {
      if (state.stylusOnlyMode && !_stylusActive) return;
      final worldPoint = _screenToWorld(details.localFocalPoint);
      setState(() {
        _currentPoints = <Offset>[..._currentPoints, worldPoint];
        _currentPressures = <double>[..._currentPressures, _lastPointerPressure];
      });
      return;
    }

    // 拖动 + 缩放：重新构造 transform，保证 worldAnchor 始终落在当前 focal 点下
    final initialScale = _gestureStartTransform.storage[0];
    final rawScale = initialScale * details.scale;
    final newScale = rawScale.clamp(_minScale, _maxScale);
    _transformController.value = Matrix4.identity()
      ..translateByDouble(
        details.localFocalPoint.dx,
        details.localFocalPoint.dy,
        0,
        1,
      )
      ..scaleByDouble(newScale, newScale, 1, 1)
      ..translateByDouble(
        -_gestureStartWorldAnchor.dx,
        -_gestureStartWorldAnchor.dy,
        0,
        1,
      );
  }

  void _onScaleEnd(
    ScaleEndDetails details,
    BuildContext context,
    CanvasState state,
  ) {
    if (_isDrawing && _currentPoints.isNotEmpty) {
      final pressures = (_currentPressures.length == _currentPoints.length)
          ? List<double>.from(_currentPressures)
          : null;
      context.read<CanvasBloc>().add(
            StrokeAdded(
              points: _currentPoints,
              color: state.currentColor,
              strokeWidth: state.currentStrokeWidth,
              isEraser: state.currentTool == CanvasTool.eraser,
              pressures: pressures,
            ),
          );
      _hasUnsavedChanges = true;
      setState(() {
        _isDrawing = false;
        _currentPoints = <Offset>[];
        _currentPressures = <double>[];
      });
      _scheduleAutosave();
    } else {
      _isDrawing = false;
    }
  }

  /// 复位视图（100%、回到 World 原点）
  void _resetCanvasTransform() {
    _transformController.value = Matrix4.identity();
  }

  /// 把所有笔迹适配到当前视口（居中 + 等比缩放）。
  /// 没有可见笔迹或视口未知时直接返回。
  void _fitToInk() {
    final viewport = _canvasViewportSize;
    if (viewport == null ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }

    final strokes = _canvasBloc.state.strokes;
    final bounds =
        OffscreenCanvasRenderer.computeInkBounds(strokes, padding: 32);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;

    final scaleX = viewport.width / bounds.width;
    final scaleY = viewport.height / bounds.height;
    final fitScale = math.min(scaleX, scaleY).clamp(_minScale, _maxScale);

    // 想要 bounds.center 落到 viewport.center：
    // T(P) = P*s + d；P = bounds.center → 期望 = viewport.center
    // d = viewport.center - bounds.center * s
    final dx = viewport.width / 2 - bounds.center.dx * fitScale;
    final dy = viewport.height / 2 - bounds.center.dy * fitScale;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(fitScale, fitScale, 1, 1);
  }

  Widget _buildCanvas() {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // 记录视口尺寸供 _fitToInk 使用
            _canvasViewportSize =
                Size(constraints.maxWidth, constraints.maxHeight);

            // 老笔记加载后第一次拿到尺寸 → 自动居中
            if (_pendingFitToInkOnLayout && state.strokes.isNotEmpty) {
              _pendingFitToInkOnLayout = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitToInk();
              });
            }

            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) => _trackPointerDown(event),
              onPointerUp: (event) =>
                  _trackPointerUp(event, context, state),
              child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              ScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                () => ScaleGestureRecognizer(),
                (ScaleGestureRecognizer instance) {
                  instance.onStart = (details) {
                    _onScaleStart(details, state);
                  };
                  instance.onUpdate = (details) {
                    _onScaleUpdate(details, state);
                  };
                  instance.onEnd = (details) {
                    _onScaleEnd(details, context, state);
                  };
                },
              ),
            },
            child: Semantics(
              label: '手写画布，${state.strokes.length}笔',
              child: AnimatedBuilder(
                animation: _transformController,
                builder: (context, _) => CustomPaint(
                  painter: CanvasPainter(
                    strokes: state.strokes,
                    currentPoints: _currentPoints,
                    currentPressures: _currentPressures,
                    currentColor: state.currentColor,
                    currentStrokeWidth: state.currentStrokeWidth,
                    isErasing: state.currentTool == CanvasTool.eraser,
                    viewTransform: _transformController.value,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        );
          },
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

  /// 把全部笔迹离屏渲染为 PNG 字节，用于保存 snapshot。
  ///
  /// 与之前 RepaintBoundary 截图不同，本方法**不受当前视口/缩放限制**：
  /// 无论用户写到画布的哪个位置、缩放到什么比例，都会渲染完整笔迹边界。
  Future<Uint8List?> _captureCanvas({double pixelRatio = 2.0}) async {
    final result = await const OffscreenCanvasRenderer().render(
      strokes: _canvasBloc.state.strokes,
      pixelRatio: pixelRatio,
      maxLongEdgePx: 3200,
      padding: 64,
    );
    return result?.pngBytes;
  }

  /// 给 OCR 引擎喂的图：高 pixelRatio + 1600 长边上限以保证清晰度。
  Future<Uint8List?> _captureCanvasForOcr() async {
    final result = await const OffscreenCanvasRenderer().render(
      strokes: _canvasBloc.state.strokes,
      pixelRatio: 4.0,
      maxLongEdgePx: 2400,
      padding: 72,
    );
    return result?.pngBytes;
  }

  /// 列表卡片缩略图：长边最多 600px，体积小。
  Future<Uint8List?> _captureThumbnail() async {
    final result = await const OffscreenCanvasRenderer().render(
      strokes: _canvasBloc.state.strokes,
      pixelRatio: 1.0,
      maxLongEdgePx: 600,
      padding: 32,
    );
    return result?.pngBytes;
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
      HapticFeedback.lightImpact();
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
        // 外层 60s 兜底：服务内部已对模型下载 / 单语言识别分别加了超时；
        // 这里再加一层保险，万一 ML Kit native 卡住也不会锁死 UI。
        handwritingResult = await _handwritingRecognitionService
            .recognize(
              strokes: _canvasBloc.state.strokes,
              writingArea: writingArea,
            )
            .timeout(const Duration(seconds: 60));
      } on TimeoutException catch (error) {
        handwritingError = error;
      } catch (error) {
        handwritingError = error;
      }

      var result = handwritingResult?.text.trim() ?? '';
      var usedImageFallback = false;
      String? fallbackFailureReason;

      if (result.isEmpty) {
        setState(() {
          _ocrHelperText = handwritingError == null
              ? '手写识别没有读出结果，正在回退到图片识别。'
              : '手写识别暂时不可用，正在回退到图片识别。';
        });
        try {
          result = await _runImageOcrFallback();
          usedImageFallback = true;
        } catch (error) {
          fallbackFailureReason = '$error';
          result = '';
        }
      }

      setState(() {
        _ocrResult = result;
        _hasUnsavedChanges = true;
        if (result.isEmpty) {
          _ocrBannerState = OcrBannerState.warning;
          _ocrHelperText = _buildOcrFailureMessage(
            handwritingError: handwritingError,
            fallbackFailureReason: fallbackFailureReason,
            handwritingResult: handwritingResult,
            hasEraserEdits: hasEraserEdits,
          );
        } else {
          _ocrBannerState = OcrBannerState.success;
          if (usedImageFallback) {
            _ocrHelperText = handwritingError == null
                ? '本次由图片识别兜底完成。建议先快速校对，再决定是否保存。'
                : '手写识别异常，已改用图片识别兜底。建议先快速校对，再决定是否保存。';
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
    } catch (error) {
      setState(() {
        _ocrBannerState = OcrBannerState.error;
        _ocrResult = '';
        _ocrHelperText = '识别没有完成：$error。你可以再试一次；如果持续失败，先保存当前手写内容。';
      });
      shouldOpenCompactSheet = shouldUseCompactSheet;
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }

    if (mounted && shouldOpenCompactSheet) {
      await _showCompactResultSheet();
    }
  }

  String _buildOcrFailureMessage({
    required Object? handwritingError,
    required String? fallbackFailureReason,
    required HandwritingRecognitionResult? handwritingResult,
    required bool hasEraserEdits,
  }) {
    if (handwritingError != null) {
      if (handwritingError is TimeoutException) {
        return '手写识别超时（可能是模型下载或网络问题）。已尝试图片识别回退，但这次也没读到文本。建议联网后重试，或把字写大一点。';
      }
      return '手写识别失败：$handwritingError。已尝试回退到图片识别，但这次仍没有读到文本。建议把字写大一点、拉开间距后再试。';
    }

    if (fallbackFailureReason != null) {
      return '手写识别没有结果，图片识别回退也失败了：$fallbackFailureReason。建议检查识别引擎或稍后重试。';
    }

    if (handwritingResult != null && !handwritingResult.hasText) {
      return hasEraserEdits
          ? '手写识别没有读出内容。检测到你用过橡皮，笔迹可能被打断了，建议重写关键字后再试。'
          : '手写识别没有读出内容。建议把关键字写大一些、分开一点，再试一次。';
    }

    return '这次仍没有读清文本。建议把数字或关键字写大一些、分开一点，再试一次。';
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

  /// 送 AI 之前的确认/编辑步骤。
  /// 返回用户确认后的文本（可能编辑过）；返回 null 表示用户取消，AI 流程应中止。
  Future<String?> _confirmTextBeforeAi(String initialText) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('送 AI 整理前确认一下'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '中文手写识别可能有错。请快速扫一眼下方文本，错的字现在改一下，AI 就能整理得更准。',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: false,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '在这里修正识别结果',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(dialogContext, null);
              } else {
                Navigator.pop(dialogContext, text);
              }
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('送 AI 整理'),
          ),
        ],
      ),
    );
    return result;
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

/// AI 整理进度浮层：显示已耗时 + 轮播提示文案。
class _AiProgressOverlay extends StatefulWidget {
  const _AiProgressOverlay();

  @override
  State<_AiProgressOverlay> createState() => _AiProgressOverlayState();
}

class _AiProgressOverlayState extends State<_AiProgressOverlay> {
  static const _tips = <String>[
    'AI 正在阅读你的文本…',
    '识别金额、日期和分类…',
    '提取待办和健康关键词…',
    '生成结构化结果…',
    '快好了，复杂笔记可能要 5-10 秒…',
  ];

  Timer? _timer;
  int _seconds = 0;
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds += 1;
        // 每 2 秒切一次提示
        _tipIndex = (_seconds ~/ 2) % _tips.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.aiAccent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: Text(
                          _tips[_tipIndex],
                          key: ValueKey(_tipIndex),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已等待 ${_seconds}s',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部自动保存状态指示器：保存中 / 已保存 HH:mm / 待保存
class _AutosaveStatusPill extends StatelessWidget {
  final bool isSaving;
  final bool hasUnsavedChanges;
  final DateTime? lastSavedAt;

  const _AutosaveStatusPill({
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.lastSavedAt,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String label;
    final Color color;

    if (isSaving) {
      icon = Icons.cloud_sync_rounded;
      label = '保存中';
      color = AppColors.inkBlue;
    } else if (hasUnsavedChanges) {
      icon = Icons.edit_note_rounded;
      label = '待保存';
      color = AppColors.warning;
    } else if (lastSavedAt != null) {
      final t = lastSavedAt!;
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      icon = Icons.cloud_done_rounded;
      label = '已保存 $hh:$mm';
      color = AppColors.success;
    } else {
      return const SizedBox(width: 0);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSaving)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
