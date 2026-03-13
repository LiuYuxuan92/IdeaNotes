import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/note.dart';
import '../../core/models/note_entry.dart';

/// 笔记列表项组件
/// 显示缩略图、日期、摘要等信息
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
    final dateStr = _formatDate(note.updatedAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图
              _buildThumbnail(),
              const SizedBox(width: 12),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部：日期 + 删除
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        if (onDelete != null)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () => _confirmDelete(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: '删除',
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 摘要内容
                    _buildSummary(theme),
                    const SizedBox(height: 8),
                    // 底部统计行
                    _buildStatsRow(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建缩略图
  Widget _buildThumbnail() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: (note.thumbnailImagePath ?? note.snapshotImagePath) != null
            ? Image.file(
                File(note.thumbnailImagePath ?? note.snapshotImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  /// 构建占位符
  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.edit_note,
          size: 32,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }

  /// 构建摘要内容
  Widget _buildSummary(ThemeData theme) {
    final text = note.recognizedText;
    
    if (text == null || text.isEmpty) {
      return Text(
        '暂无识别内容',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    // 提取前两行作为摘要
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final summary = lines.take(2).join('\n');

    return Text(
      summary.isEmpty ? '暂无识别内容' : summary,
      style: theme.textTheme.bodyMedium,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${_padZero(date.hour)}:${_padZero(date.minute)}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  Widget _buildStatsRow(ThemeData theme) {
    final text = note.recognizedText;
    final charCount = text?.trim().isNotEmpty == true ? text!.trim().length : 0;
    
    // 优先用 entries 数据，如果没有就用轻量级解析
    int expenseCount = 0, eventCount = 0, memoCount = 0;
    
    if (note.entries.isNotEmpty) {
      expenseCount = note.entries.where((e) => e.type == NoteEntryType.expense).length;
      eventCount = note.entries.where((e) => e.type == NoteEntryType.event).length;
      memoCount = note.entries.where((e) => e.type == NoteEntryType.memo).length;
    } else if (text != null && text.isNotEmpty) {
      // 轻量级启发式解析
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (final line in lines) {
        // 消费：包含金额模式如 ¥100、100元、100块
        if (RegExp(r'[¥¥]\s*\d|[\d]+\s*(元|块|圆|美元)').hasMatch(line)) {
          expenseCount++;
        } 
        // 事项：包含时间或todo标记
        else if (RegExp(r'\d{1,2}[:点时]|\d{1,2}[/-]\d{1,2}|[]【】|TODO|FIXME').hasMatch(line)) {
          eventCount++;
        } 
        // 其他视为备忘
        else {
          memoCount++;
        }
      }
    }

    final hasStats = charCount > 0 || expenseCount > 0 || eventCount > 0 || memoCount > 0;
    if (!hasStats) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (charCount > 0)
          _buildStatChip('$charCount 字', Icons.text_fields, Colors.blue.shade400),
        if (expenseCount > 0)
          _buildStatChip('$expenseCount 消费', Icons.attach_money, Colors.orange.shade600),
        if (eventCount > 0)
          _buildStatChip('$eventCount 事项', Icons.event, Colors.purple.shade400),
        if (memoCount > 0)
          _buildStatChip('$memoCount 备忘', Icons.note, Colors.green.shade500),
      ],
    );
  }

  Widget _buildStatChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _padZero(int value) => value.toString().padLeft(2, '0');

  /// 确认删除
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这条笔记吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
