import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';
import '../../core/parser/entry_parser.dart';

class NoteListItem extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool isGridMode;

  const NoteListItem({
    super.key,
    required this.note,
    this.onTap,
    this.onDelete,
    this.isGridMode = false,
  });

  // Determine accent color from dominant entry type
  Color get _cardAccent {
    if (note.entries.isEmpty) {
      final hasText = (note.recognizedText ?? '').trim().isNotEmpty;
      return hasText
          ? AppColors.inkBlue.withValues(alpha: 0.35)
          : AppColors.line.withValues(alpha: 0.5);
    }
    var expenseCount = 0;
    var eventCount = 0;
    var healthCount = 0;
    for (final entry in note.entries) {
      switch (entry.type) {
        case NoteEntryType.expense:
          expenseCount++;
          break;
        case NoteEntryType.event:
          eventCount++;
          break;
        case NoteEntryType.health:
          healthCount++;
          break;
        case NoteEntryType.memo:
          break;
      }
    }
    if (expenseCount > 0 &&
        expenseCount >= eventCount &&
        expenseCount >= healthCount) {
      return AppColors.warning;
    }
    if (healthCount > 0 && healthCount >= eventCount) {
      return AppColors.success;
    }
    if (eventCount > 0) return AppColors.inkBlue;
    return AppColors.inkBlue.withValues(alpha: 0.35);
  }

  @override
  Widget build(BuildContext context) {
    if (isGridMode) {
      return AppSurface(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(14),
        radius: 28,
        backgroundColor: Colors.white,
        border: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: AppShadows.soft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: _GridCardBody(
            note: note,
            summary: _summary,
            onDelete: onDelete,
            onConfirmDelete: () => _confirmDelete(context),
          ),
        ),
      );
    }

    // List mode: custom container with left accent stripe
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27.5),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent stripe — colour encodes dominant content type
              Container(width: 3.5, color: _cardAccent),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _ListCardBody(
                        note: note,
                        summary: _summary,
                        onDelete: onDelete,
                        onConfirmDelete: () => _confirmDelete(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _summary {
    final text = note.recognizedText?.trim();
    if (text == null || text.isEmpty) return _emptySummary;
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return _emptySummary;
    return lines.take(3).join('\n');
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条笔记？'),
        content: const Text('删除后，手写内容和识别结果都会一起移除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('先保留'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }
}

class _ListCardBody extends StatelessWidget {
  final Note note;
  final String summary;
  final VoidCallback? onDelete;
  final VoidCallback onConfirmDelete;

  const _ListCardBody({
    required this.note,
    required this.summary,
    required this.onDelete,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = summary != _emptySummary;
    final title = hasText ? summary.split('\n').first : '未命名笔记';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NoteThumbnail(
          note: note,
          width: context.isCompact ? 88 : 102,
          height: context.isCompact ? 110 : 126,
        ),
        const SizedBox(width: 16),
        Expanded(
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
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaChip(
                              icon: Icons.schedule_rounded,
                              label: _formatDate(note.updatedAt),
                            ),
                            _MetaChip(
                              icon: Icons.text_snippet_outlined,
                              label: hasText
                                  ? '${_lineCount(summary)} 行识别结果'
                                  : '待识别',
                              emphasized: hasText,
                            ),
                            if (hasText && !context.isCompact)
                              const _MetaChip(
                                icon: Icons.auto_awesome_rounded,
                                label: '已可查询',
                                highlightedColor: AppColors.aiAccent,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onConfirmDelete,
                      tooltip: '删除这条笔记',
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      hasText ? AppColors.textSecondary : AppColors.textMuted,
                  fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              _InsightRow(note: note),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridCardBody extends StatelessWidget {
  final Note note;
  final String summary;
  final VoidCallback? onDelete;
  final VoidCallback onConfirmDelete;

  const _GridCardBody({
    required this.note,
    required this.summary,
    required this.onDelete,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = summary != _emptySummary;
    final title = hasText ? summary.split('\n').first : '未命名笔记';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            _NoteThumbnail(
              note: note,
              width: double.infinity,
              height: 186,
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Row(
                children: [
                  _GlassPill(label: _formatDate(note.updatedAt)),
                  const Spacer(),
                  if (onDelete != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        onPressed: onConfirmDelete,
                        tooltip: '删除这条笔记',
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
              icon: Icons.text_snippet_outlined,
              label: hasText ? '${_lineCount(summary)} 行识别结果' : '待识别',
              emphasized: hasText,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          summary,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hasText ? AppColors.textSecondary : AppColors.textMuted,
            fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
          ),
        ),
        const Spacer(),
        const SizedBox(height: 14),
        _InsightRow(note: note),
      ],
    );
  }
}

class _NoteThumbnail extends StatelessWidget {
  final Note note;
  final double width;
  final double height;

  const _NoteThumbnail({
    required this.note,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(22);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCFAF6), Color(0xFFE5EBEF)],
        ),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: note.snapshotImagePath != null
            ? Image.file(
                File(note.snapshotImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ThumbnailPlaceholder(),
              )
            : const _ThumbnailPlaceholder(),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F3EF), Color(0xFFE5ECF2)],
        ),
      ),
      child: Stack(
        children: [
          // Notepad ruled-line grid
          Positioned.fill(
            child: CustomPaint(painter: _NotepadLinePainter()),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.inkBlue.withValues(alpha: 0.10),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.draw_rounded,
                    color: AppColors.inkBlue.withValues(alpha: 0.55),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '手写页',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotepadLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD8E0).withOpacity(0.45)
      ..strokeWidth = 0.6;

    const step = 16.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Faint left margin line
    final marginPaint = Paint()
      ..color = const Color(0xFFE8B4B4).withOpacity(0.40)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      const Offset(20, 0),
      Offset(20, size.height),
      marginPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InsightRow extends StatelessWidget {
  final Note note;

  const _InsightRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final text = note.recognizedText;
    final charCount = text?.trim().isNotEmpty == true ? text!.trim().length : 0;

    var expenseCount = 0;
    var eventCount = 0;
    var healthCount = 0;
    var memoCount = 0;

    if (note.entries.isNotEmpty) {
      expenseCount = note.entries
          .where((entry) => entry.type == NoteEntryType.expense)
          .length;
      eventCount = note.entries
          .where((entry) => entry.type == NoteEntryType.event)
          .length;
      healthCount = note.entries
          .where((entry) => entry.type == NoteEntryType.health)
          .length;
      memoCount = note.entries
          .where((entry) => entry.type == NoteEntryType.memo)
          .length;
    } else if (text != null && text.isNotEmpty) {
      final lines = text.split('\n').where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        final entry = EntryParser.parse(line);
        switch (entry.type) {
          case NoteEntryType.expense:
            expenseCount += 1;
            break;
          case NoteEntryType.event:
            eventCount += 1;
            break;
          case NoteEntryType.health:
            healthCount += 1;
            break;
          case NoteEntryType.memo:
            memoCount += 1;
            break;
        }
      }
    }

    final chips = <Widget>[];
    if (charCount > 0) {
      chips.add(
        _StatChip(
          label: '$charCount 字',
          icon: Icons.text_fields_rounded,
          color: AppColors.inkBlue,
        ),
      );
    }
    if (expenseCount > 0) {
      chips.add(
        _StatChip(
          label: '$expenseCount 消费',
          icon: Icons.attach_money_rounded,
          color: AppColors.warning,
        ),
      );
    }
    if (eventCount > 0) {
      chips.add(
        _StatChip(
          label: '$eventCount 事项',
          icon: Icons.event_note_rounded,
          color: const Color(0xFF6E7BC7),
        ),
      );
    }
    if (healthCount > 0) {
      chips.add(
        _StatChip(
          label: '$healthCount 健康',
          icon: Icons.health_and_safety_outlined,
          color: AppColors.success,
        ),
      );
    }
    if (memoCount > 0) {
      chips.add(
        _StatChip(
          label: '$memoCount 备忘',
          icon: Icons.sticky_note_2_outlined,
          color: AppColors.success,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
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
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;
  final Color? highlightedColor;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
    this.highlightedColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = highlightedColor ??
        (emphasized ? AppColors.inkBlue : AppColors.textMuted);
    final background = highlightedColor != null
        ? AppColors.aiAccentSoft
        : emphasized
            ? const Color(0xFFDDE8EE)
            : const Color(0xFFF2F4F6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: highlightedColor != null || emphasized
                      ? accent
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final String label;

  const _GlassPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;

  if (diff == 0) {
    return '今天 ${_padZero(date.hour)}:${_padZero(date.minute)}';
  }
  if (diff == 1) return '昨天 ${_padZero(date.hour)}:${_padZero(date.minute)}';
  if (diff < 7) return '$diff 天前';
  return '${date.month}月${date.day}日';
}

int _lineCount(String text) =>
    text.split('\n').where((line) => line.trim().isNotEmpty).length;

String _padZero(int value) => value.toString().padLeft(2, '0');

const String _emptySummary = '还没有识别内容，打开笔记后可继续书写或识别。';
