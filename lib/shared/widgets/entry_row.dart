import 'package:flutter/material.dart';
import '../../core/models/note_entry.dart';

/// 条目行组件 - 用于展示解析后的笔记条目
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
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 类型图标
              Text(
                _typeIcon,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 12),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.rawText,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    _buildSubInfo(theme),
                  ],
                ),
              ),
              // 复选框（仅事件类型显示）
              if (entry.type == NoteEntryType.event && onCompletedChanged != null)
                Checkbox(
                  value: entry.event?.isCompleted ?? false,
                  onChanged: (value) => onCompletedChanged?.call(value ?? false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubInfo(ThemeData theme) {
    switch (entry.type) {
      case NoteEntryType.expense:
        if (entry.expense != null) {
          return Text(
            '${entry.expense!.category} · ¥${entry.expense!.amount.toDouble().toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          );
        }
        return const SizedBox.shrink();
      case NoteEntryType.event:
        if (entry.event != null) {
          return Text(
            entry.event!.isCompleted ? '已完成' : '待办',
            style: theme.textTheme.bodySmall?.copyWith(
              color: entry.event!.isCompleted 
                  ? Colors.green 
                  : Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          );
        }
        return const SizedBox.shrink();
      case NoteEntryType.memo:
        return const SizedBox.shrink();
    }
  }

  String get _typeIcon {
    switch (entry.type) {
      case NoteEntryType.expense:
        return '💰';
      case NoteEntryType.event:
        return '📌';
      case NoteEntryType.memo:
        return '📝';
    }
  }
}
