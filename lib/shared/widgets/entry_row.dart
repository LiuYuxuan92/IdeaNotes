import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/models/note_entry.dart';
import '../../core/parser/entry_text_rules.dart';

class EntryRow extends StatelessWidget {
  final NoteEntry entry;
  final VoidCallback? onTap;
  final void Function(bool)? onCompletedChanged;

  const EntryRow({
    super.key,
    required this.entry,
    this.onTap,
    this.onCompletedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette;

    return AppSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      backgroundColor: palette.background,
      border: BorderSide(color: palette.border),
      boxShadow: const [],
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
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
                  Text(
                    _title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (_subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    entry.rawText,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (entry.type == NoteEntryType.event && onCompletedChanged != null)
              Checkbox.adaptive(
                value: entry.event?.isCompleted ?? false,
                onChanged: (value) => onCompletedChanged?.call(value ?? false),
              ),
          ],
        ),
      ),
    );
  }

  String get _title {
    switch (entry.type) {
      case NoteEntryType.expense:
        final expense = entry.expense;
        if (expense == null) return '支出记录';
        return '¥${expense.amount.toDouble().toStringAsFixed(2)}';
      case NoteEntryType.event:
        return entry.event?.title.isNotEmpty == true
            ? entry.event!.title
            : '待办事项';
      case NoteEntryType.health:
        return entry.memoText?.trim().isNotEmpty == true
            ? entry.memoText!.trim()
            : '健康记录';
      case NoteEntryType.memo:
        return entry.memoText?.trim().isNotEmpty == true
            ? entry.memoText!.trim()
            : '备忘内容';
    }
  }

  String? get _subtitle {
    switch (entry.type) {
      case NoteEntryType.expense:
        final expense = entry.expense;
        if (expense == null) return null;
        return expense.category;
      case NoteEntryType.event:
        final event = entry.event;
        if (event == null) return null;
        if (event.date != null) {
          final hasClockTime =
              event.date!.hour != 0 || event.date!.minute != 0;
          final dateLabel = hasClockTime
              ? '${event.date!.month}月${event.date!.day}日 ${event.date!.hour.toString().padLeft(2, '0')}:${event.date!.minute.toString().padLeft(2, '0')}'
              : '${event.date!.month}月${event.date!.day}日';
          return '${event.isCompleted ? '已完成' : '待处理'} · $dateLabel';
        }
        return event.isCompleted ? '已完成' : '待处理';
      case NoteEntryType.health:
        if (EntryTextRules.hasVaccinationKeyword(entry.rawText)) {
          return '健康记录 · 疫苗';
        }
        if (EntryTextRules.hasMedicationKeyword(entry.rawText)) {
          return '健康记录 · 用药';
        }
        if (EntryTextRules.hasDigestiveKeyword(entry.rawText)) {
          return '健康记录 · 排便';
        }
        return '健康记录';
      case NoteEntryType.memo:
        return '备忘';
    }
  }

  _EntryPalette get _palette {
    switch (entry.type) {
      case NoteEntryType.expense:
        return const _EntryPalette(
          background: Color(0xFFFAF6EE),
          border: Color(0xFFEADFC7),
          pill: Color(0xFFF3E8D0),
          accent: AppColors.warning,
          icon: Icons.payments_outlined,
        );
      case NoteEntryType.event:
        return _EntryPalette(
          background: entry.event?.isCompleted == true
              ? const Color(0xFFF3F8F5)
              : const Color(0xFFF1F5F7),
          border: entry.event?.isCompleted == true
              ? const Color(0xFFD6E6DE)
              : const Color(0xFFD9E4EA),
          pill: entry.event?.isCompleted == true
              ? const Color(0xFFDDEEE6)
              : const Color(0xFFDDE8EE),
          accent: entry.event?.isCompleted == true
              ? AppColors.success
              : AppColors.inkBlue,
          icon: entry.event?.isCompleted == true
              ? Icons.task_alt_rounded
              : Icons.event_note_rounded,
        );
      case NoteEntryType.health:
        return const _EntryPalette(
          background: Color(0xFFF1F7F3),
          border: Color(0xFFD6E8DD),
          pill: Color(0xFFDCEFE4),
          accent: AppColors.success,
          icon: Icons.health_and_safety_outlined,
        );
      case NoteEntryType.memo:
        return const _EntryPalette(
          background: Color(0xFFF5F7F8),
          border: Color(0xFFDDE3E8),
          pill: Color(0xFFE4EAEE),
          accent: AppColors.slateBlue,
          icon: Icons.sticky_note_2_outlined,
        );
    }
  }
}

class _EntryPalette {
  final Color background;
  final Color border;
  final Color pill;
  final Color accent;
  final IconData icon;

  const _EntryPalette({
    required this.background,
    required this.border,
    required this.pill,
    required this.accent,
    required this.icon,
  });
}
