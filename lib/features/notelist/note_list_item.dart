import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';

class NoteListItem extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const NoteListItem({
    super.key,
    required this.note,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;
    final hasText = summary != _emptySummary;

    return AppSurface(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(context),
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
                              hasText ? summary.split('\n').first : '未命名笔记',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onDelete != null)
                        IconButton(
                          onPressed: () => _confirmDelete(context),
                          tooltip: '删除这条笔记',
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hasText
                          ? AppColors.textSecondary
                          : AppColors.textMuted,
                      fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatsRow(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final borderRadius = BorderRadius.circular(18);
    return Container(
      width: 88,
      height: 104,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: const Color(0xFFF3F5F7),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: note.snapshotImagePath != null
            ? Image.file(
                File(note.snapshotImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(context),
              )
            : _buildPlaceholder(context),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F5F1), Color(0xFFE3E9ED)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.draw_rounded,
              color: AppColors.textMuted.withOpacity(0.8), size: 30),
          const SizedBox(height: 8),
          Text(
            '手写页',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
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
        .toList();
    if (lines.isEmpty) return _emptySummary;
    return lines.take(3).join('\n');
  }

  Widget _buildStatsRow(BuildContext context) {
    final text = note.recognizedText;
    final charCount = text?.trim().isNotEmpty == true ? text!.trim().length : 0;

    int expenseCount = 0, eventCount = 0, memoCount = 0;

    if (note.entries.isNotEmpty) {
      expenseCount = note.entries
          .where((entry) => entry.type == NoteEntryType.expense)
          .length;
      eventCount = note.entries
          .where((entry) => entry.type == NoteEntryType.event)
          .length;
      memoCount = note.entries
          .where((entry) => entry.type == NoteEntryType.memo)
          .length;
    } else if (text != null && text.isNotEmpty) {
      final lines = text.split('\n').where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        if (RegExp(r'[¥￥]\s*\d|\d+\s*(元|块|圆|美元)').hasMatch(line)) {
          expenseCount++;
        } else if (RegExp(r'\d{1,2}[:点时]|\d{1,2}[/-]\d{1,2}|TODO|FIXME|待办').hasMatch(line)) {
          eventCount++;
        } else {
          memoCount++;
        }
      }
    }

    final chips = <Widget>[];
    if (charCount > 0) {
      chips.add(_StatChip(label: '$charCount 字', icon: Icons.text_fields_rounded, color: AppColors.inkBlue));
    }
    if (expenseCount > 0) {
      chips.add(_StatChip(label: '$expenseCount 消费', icon: Icons.attach_money_rounded, color: AppColors.warning));
    }
    if (eventCount > 0) {
      chips.add(_StatChip(label: '$eventCount 事项', icon: Icons.event_note_rounded, color: const Color(0xFF6E7BC7)));
    }
    if (memoCount > 0) {
      chips.add(_StatChip(label: '$memoCount 备忘', icon: Icons.sticky_note_2_outlined, color: AppColors.success));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  int _lineCount(String text) =>
      text.split('\n').where((line) => line.trim().isNotEmpty).length;

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

  String _padZero(int value) => value.toString().padLeft(2, '0');

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
        color: color.withOpacity(0.12),
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

  const _MetaChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFDDE8EE) : const Color(0xFFF2F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: emphasized ? AppColors.inkBlue : AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      emphasized ? AppColors.inkBlue : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

const String _emptySummary = '还没有识别内容，打开笔记后可继续书写或识别。';
