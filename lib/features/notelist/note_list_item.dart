import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/note.dart';

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
                    // 日期
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
                        // 删除按钮
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
        child: note.snapshotImagePath != null
            ? Image.file(
                File(note.snapshotImagePath!),
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
