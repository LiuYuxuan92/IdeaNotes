import 'package:flutter/material.dart';

import '../../../app/design_system.dart';
import '../services/voice_recognition_service.dart';

enum VoiceCaptureWriteMode { append, replace }

class VoiceCaptureResult {
  final String text;
  final VoiceCaptureWriteMode writeMode;

  const VoiceCaptureResult({
    required this.text,
    required this.writeMode,
  });
}

class VoiceCaptureSheet extends StatefulWidget {
  final VoiceRecognitionService service;
  final String existingText;

  const VoiceCaptureSheet({
    super.key,
    required this.service,
    required this.existingText,
  });

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  final TextEditingController _controller = TextEditingController();

  bool _isInitializing = true;
  bool _isListening = false;
  String? _localeId;
  String _status = '准备中';
  String? _error;
  late VoiceCaptureWriteMode _writeMode;

  /// Continuous transcription support.
  ///
  /// `speech_to_text` typically returns the current utterance (and may repeat
  /// partial results). We treat every `finalResult` as one segment and append it
  /// into `_committedSegments`, while keeping `_currentSegment` for live preview.
  final List<String> _committedSegments = <String>[];
  String _currentSegment = '';

  @override
  void initState() {
    super.initState();
    _writeMode = widget.existingText.trim().isEmpty
        ? VoiceCaptureWriteMode.replace
        : VoiceCaptureWriteMode.append;
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    // Best effort: ensure we don't keep listening when sheet is dismissed.
    widget.service.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isInitializing = true;
      _error = null;
      _status = '准备语音识别';
    });

    final available = await widget.service.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          _status = _humanStatus(status);
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          } else if (status == 'listening') {
            _isListening = true;
          }
        });
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _error = message;
          _isListening = false;
          _status = '识别异常';
        });
      },
    );

    if (!mounted) return;
    if (!available) {
      setState(() {
        _isInitializing = false;
        _error = '当前设备或系统服务暂不支持语音识别。';
        _status = '不可用';
      });
      return;
    }

    _localeId = await widget.service.systemLocaleId();
    if (!mounted) return;

    setState(() => _isInitializing = false);
    await _startListening();
  }

  Future<void> _startListening() async {
    setState(() {
      _error = null;
      _isListening = true;
      _status = '正在聆听';
    });

    await widget.service.startListening(
      localeId: _localeId,
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _error = message;
          _isListening = false;
          _status = '识别异常';
        });
      },
      onResult: (words, isFinal) {
        if (!mounted) return;

        final normalized = words.trim();
        final lastCommitted =
            _committedSegments.isEmpty ? null : _committedSegments.last;

        setState(() {
          if (isFinal) {
            _currentSegment = '';

            // Avoid committing duplicates (some engines may emit the same final
            // result more than once).
            if (normalized.isNotEmpty && normalized != lastCommitted) {
              _committedSegments.add(normalized);
            }
            _status = '已识别一段，继续说或点停止';
          } else {
            _currentSegment = normalized;
          }

          _controller.text = _buildPreviewText();
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
    );
  }

  String _buildPreviewText() {
    final committed = _committedSegments.join('\n');
    if (committed.isEmpty) {
      return _currentSegment;
    }
    if (_currentSegment.isEmpty) {
      return committed;
    }
    return '$committed\n$_currentSegment';
  }

  Future<void> _stopListening() async {
    await widget.service.stop();
    if (!mounted) return;

    setState(() {
      // Best-effort: if we stopped in the middle of a sentence, keep whatever
      // we already have as a segment.
      final pending = _currentSegment.trim();
      final lastCommitted =
          _committedSegments.isEmpty ? null : _committedSegments.last;
      if (pending.isNotEmpty && pending != lastCommitted) {
        _committedSegments.add(pending);
      }
      _currentSegment = '';
      _controller.text = _buildPreviewText();
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );

      _isListening = false;
      _status = '已停止，可编辑后写入';
    });
  }

  void _applyAndClose() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(
      VoiceCaptureResult(text: text, writeMode: _writeMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;

    return AppSurface(
      radius: isCompact ? 28 : 32,
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '语音识别',
            title: _isInitializing
                ? '正在准备语音输入'
                : _isListening
                    ? '正在把你说的话变成可搜索文本'
                    : '编辑一下再写入到笔记',
            description: _error != null
                ? _error!
                : '建议一条条说，金额直接说数字，日期词可以说“今天/明天/下周三”。',
            trailing: _StatusPill(
              label: _isListening ? '识别中' : _status,
              accent: _error != null
                  ? AppColors.error
                  : (_isListening ? AppColors.aiAccent : AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeChip(
                selected: _writeMode == VoiceCaptureWriteMode.append,
                label: '追加',
                onTap: () => setState(() => _writeMode = VoiceCaptureWriteMode.append),
              ),
              _ModeChip(
                selected: _writeMode == VoiceCaptureWriteMode.replace,
                label: '覆盖',
                onTap: () =>
                    setState(() => _writeMode = VoiceCaptureWriteMode.replace),
              ),
              if (_localeId != null)
                _MetaChip(
                  icon: Icons.language_rounded,
                  label: _localeId!,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: _isInitializing
                  ? const Center(child: CircularProgressIndicator())
                  : TextField(
                      controller: _controller,
                      readOnly: _isListening,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: _isListening ? '正在听你说话…' : '识别结果会显示在这里',
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            _HintLine(
              icon: Icons.info_outline_rounded,
              text: '可以先检查麦克风权限、系统语音服务是否可用，再重试。',
            )
          else
            _HintLine(
              icon: Icons.lock_outline_rounded,
              text: '语音识别由系统服务完成，可能需要联网。',
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              if (!_isInitializing)
                OutlinedButton.icon(
                  onPressed: _isListening ? _stopListening : _startListening,
                  icon: Icon(_isListening ? Icons.mic_off_rounded : Icons.mic_rounded),
                  label: Text(_isListening ? '停止识别' : '继续识别'),
                ),
              FilledButton.icon(
                onPressed: _isInitializing || _isListening || _controller.text.trim().isEmpty
                    ? null
                    : _applyAndClose,
                icon: const Icon(Icons.subdirectory_arrow_left_rounded),
                label: Text(_writeMode == VoiceCaptureWriteMode.append ? '追加到笔记' : '覆盖写入'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _humanStatus(String status) {
    switch (status) {
      case 'listening':
        return '正在聆听';
      case 'notListening':
        return '已停止';
      case 'done':
        return '完成';
      default:
        return status;
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _StatusPill({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
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

class _ModeChip extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _ModeChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.inkBlue : AppColors.textSecondary;
    final background = selected ? const Color(0xFFDDE8EE) : const Color(0xFFF2F5F6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _HintLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

