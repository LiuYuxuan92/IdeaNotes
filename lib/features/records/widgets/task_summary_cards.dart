import 'package:flutter/material.dart';

import '../../../app/design_system.dart';

class TaskSummaryCards extends StatelessWidget {
  final int totalCount;
  final int pendingCount;
  final int completedCount;

  const TaskSummaryCards({
    super.key,
    required this.totalCount,
    required this.pendingCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _TaskSummaryItem(
        label: '全部待办',
        value: '$totalCount',
        accent: AppColors.inkBlue,
        icon: Icons.list_alt_rounded,
      ),
      _TaskSummaryItem(
        label: '待处理',
        value: '$pendingCount',
        accent: AppColors.warning,
        icon: Icons.pending_actions_rounded,
      ),
      _TaskSummaryItem(
        label: '已完成',
        value: '$completedCount',
        accent: AppColors.success,
        icon: Icons.task_alt_rounded,
      ),
    ];

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '摘要',
            title: '完成率',
            description: '快速查看总量、待处理数量与已完成数量。',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: items
                .map(
                  (item) => SizedBox(
                    width: context.isCompact ? double.infinity : 180,
                    child: _TaskSummaryCard(item: item),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _TaskSummaryCard extends StatelessWidget {
  final _TaskSummaryItem item;

  const _TaskSummaryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: item.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '${item.value} 条',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
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

class _TaskSummaryItem {
  final String label;
  final String value;
  final Color accent;
  final IconData icon;

  const _TaskSummaryItem({
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
  });
}
