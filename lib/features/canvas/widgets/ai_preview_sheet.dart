import 'package:flutter/material.dart';

import '../../../app/design_system.dart';
import '../../../core/extraction/extraction_models.dart';
import '../services/canvas_ai_preview_service.dart';

/// AI 预览底部抽屉。原来内嵌在 canvas_screen.dart，作为 _AiPreviewSheet 私有类。
class AiPreviewSheet extends StatelessWidget {
  final CanvasAiPreviewResult result;

  const AiPreviewSheet({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final document = result.document;
    final entries = document?.entries ?? const <ExtractedEntry>[];
    final warnings = document?.warnings ?? const <ExtractionWarning>[];
    final unparsedSegments = document?.unparsedSegments ?? const <String>[];
    final correctionApplied = result.correctionApplied;

    ExtractionWarning? aiFallbackWarning;
    for (final w in warnings) {
      if (w.code == 'fallback_local_rules') {
        aiFallbackWarning = w;
        break;
      }
    }

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
          if (aiFallbackWarning != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 提取失败，已使用本地规则解析。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
