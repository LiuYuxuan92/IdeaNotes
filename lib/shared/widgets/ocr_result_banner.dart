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
      margin: const EdgeInsets.all(0),
      padding: const EdgeInsets.all(18),
      backgroundColor: palette.background,
      border: BorderSide(color: palette.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.pill,
                  borderRadius: BorderRadius.circular(14),
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
                    if ((helperText ?? _defaultHelper).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        helperText ?? _defaultHelper,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: hasResult ? onCopy : null,
                    tooltip: '复制识别文本',
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                  ),
                  IconButton(
                    onPressed: hasResult ? onEdit : null,
                    tooltip: '编辑识别文本',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  if (showSaveButton)
                    IconButton(
                      onPressed: hasResult ? onSave : null,
                      tooltip: '保存识别文本',
                      icon: const Icon(Icons.save_outlined, size: 18),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.78),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border.withOpacity(0.9)),
              ),
              child: hasResult
                  ? SingleChildScrollView(
                      child: SelectableText(
                        result,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.65,
                        ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state == OcrBannerState.processing)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          else
                            Icon(_icon, size: 28, color: palette.accent),
                          const SizedBox(height: 12),
                          Text(
                            _emptyTitle,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: AppColors.textPrimary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            helperText ?? _defaultHelper,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
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
        return Icons.text_snippet_outlined;
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
