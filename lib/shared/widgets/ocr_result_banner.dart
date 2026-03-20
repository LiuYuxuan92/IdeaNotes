import 'package:flutter/material.dart';

import '../../app/design_system.dart';

enum OcrBannerState { idle, processing, success, warning, error }

class OcrResultBanner extends StatelessWidget {
  final String result;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final bool showSaveButton;
  final OcrBannerState state;
  final String? helperText;

  const OcrResultBanner({
    super.key,
    required this.result,
    this.onCopy,
    this.onEdit,
    this.onSave,
    this.showSaveButton = false,
    this.state = OcrBannerState.idle,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette;
    final hasResult = result.trim().isNotEmpty;

    return AppSurface(
      padding: const EdgeInsets.all(18),
      radius: 30,
      backgroundColor: palette.background,
      border: BorderSide(color: palette.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.pill,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_icon, color: palette.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('识别结果', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _headline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      helperText ?? _defaultHelper,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StateChip(label: _statusLabel, accent: palette.accent),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.copy_all_rounded,
                label: '复制',
                enabled: hasResult,
                onTap: hasResult ? onCopy : null,
              ),
              _ActionChip(
                icon: Icons.edit_outlined,
                label: '编辑',
                enabled: hasResult,
                onTap: hasResult ? onEdit : null,
              ),
              if (showSaveButton)
                _ActionChip(
                  icon: Icons.save_outlined,
                  label: '保存',
                  enabled: hasResult,
                  onTap: hasResult ? onSave : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(
                icon: Icons.notes_rounded,
                label: hasResult ? 'OCR 文本' : '等待识别',
              ),
              _TagChip(
                icon: Icons.rule_rounded,
                label: hasResult ? '建议人工校对' : '可先保存手写内容',
              ),
              const _TagChip(
                icon: Icons.auto_awesome_rounded,
                label: 'AI 解析预留',
                accent: AppColors.aiAccent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.9),
                ),
              ),
              child: hasResult
                  ? Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          result,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.7,
                          ),
                        ),
                      ),
                    )
                  : _EmptyPanel(
                      icon: _icon,
                      accent: palette.accent,
                      title: _emptyTitle,
                      description: helperText ?? _defaultHelper,
                      state: state,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (state) {
      case OcrBannerState.processing:
        return Icons.hourglass_top_rounded;
      case OcrBannerState.success:
        return Icons.check_circle_outline_rounded;
      case OcrBannerState.warning:
        return Icons.info_outline_rounded;
      case OcrBannerState.error:
        return Icons.error_outline_rounded;
      case OcrBannerState.idle:
        return Icons.notes_rounded;
    }
  }

  String get _headline {
    switch (state) {
      case OcrBannerState.processing:
        return '正在识别';
      case OcrBannerState.success:
        return '识别完成';
      case OcrBannerState.warning:
        return '还不能识别';
      case OcrBannerState.error:
        return '识别失败';
      case OcrBannerState.idle:
        return '等待识别';
    }
  }

  String get _statusLabel {
    switch (state) {
      case OcrBannerState.processing:
        return '进行中';
      case OcrBannerState.success:
        return '已完成';
      case OcrBannerState.warning:
        return '需处理';
      case OcrBannerState.error:
        return '异常';
      case OcrBannerState.idle:
        return '待开始';
    }
  }

  String get _emptyTitle {
    switch (state) {
      case OcrBannerState.processing:
        return '正在读取你的笔迹';
      case OcrBannerState.success:
        return '识别完成';
      case OcrBannerState.warning:
        return '暂时没有可识别内容';
      case OcrBannerState.error:
        return '这次识别没有成功';
      case OcrBannerState.idle:
        return '识别结果会显示在这里';
    }
  }

  String get _defaultHelper {
    switch (state) {
      case OcrBannerState.processing:
        return '请稍等几秒，完成后你可以继续编辑、复制或保存。';
      case OcrBannerState.success:
        return '先快速核对，再决定是否继续编辑成可执行信息。';
      case OcrBannerState.warning:
        return '先写几笔更清晰的文字，或确认当前设备支持文字识别。';
      case OcrBannerState.error:
        return '你可以再识别一次；如果仍失败，先检查画布内容是否已成功捕获。';
      case OcrBannerState.idle:
        return '写完后点击右上角“识别”，结果会保留在这里。';
    }
  }

  _BannerPalette get _palette {
    switch (state) {
      case OcrBannerState.processing:
        return const _BannerPalette(
          background: Color(0xFFF2F6F8),
          border: Color(0xFFD7E3EA),
          pill: Color(0xFFDCE8EE),
          accent: AppColors.inkBlue,
        );
      case OcrBannerState.success:
        return const _BannerPalette(
          background: Color(0xFFF3F8F5),
          border: Color(0xFFD6E6DE),
          pill: Color(0xFFDDEEE6),
          accent: AppColors.success,
        );
      case OcrBannerState.warning:
        return const _BannerPalette(
          background: Color(0xFFFAF6EE),
          border: Color(0xFFEADFC7),
          pill: Color(0xFFF3E8D0),
          accent: AppColors.warning,
        );
      case OcrBannerState.error:
        return const _BannerPalette(
          background: Color(0xFFFBF4F4),
          border: Color(0xFFEACFCF),
          pill: Color(0xFFF3DEDE),
          accent: AppColors.error,
        );
      case OcrBannerState.idle:
        return const _BannerPalette(
          background: Color(0xFFF5F7F8),
          border: Color(0xFFDDE3E8),
          pill: Color(0xFFE4EAEE),
          accent: AppColors.slateBlue,
        );
    }
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? AppColors.textPrimary : AppColors.disabled;
    final background = enabled ? Colors.white : const Color(0xFFF1F3F4);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _TagChip({
    required this.icon,
    required this.label,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final background = accent == AppColors.aiAccent
        ? AppColors.aiAccentSoft
        : const Color(0xFFF2F5F6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
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

class _StateChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _StateChip({
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
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

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final OcrBannerState state;

  const _EmptyPanel({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == OcrBannerState.processing)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: accent,
              ),
            )
          else
            Icon(icon, size: 28, color: accent),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BannerPalette {
  final Color background;
  final Color border;
  final Color pill;
  final Color accent;

  const _BannerPalette({
    required this.background,
    required this.border,
    required this.pill,
    required this.accent,
  });
}
