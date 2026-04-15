import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/design_system.dart';
import '../../../core/query/analytics_service.dart';

class HealthTrendCharts extends StatelessWidget {
  final List<EntryCountStat> typeStats;

  const HealthTrendCharts({
    super.key,
    required this.typeStats,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '图表',
            title: '健康记录趋势',
            description: '按识别类型查看这段时间的健康记录重点。',
          ),
          const SizedBox(height: 16),
          Text(
            '类型分布',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 32)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= typeStats.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _entryTypeLabel(typeStats[index].entryType),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: typeStats.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.count.toDouble(),
                        width: 22,
                        borderRadius: BorderRadius.circular(8),
                        color: _barColor(entry.value.entryType),
                      ),
                    ],
                  );
                }).toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _entryTypeLabel(String entryType) {
  switch (entryType) {
    case 'task':
      return '待办';
    case 'vaccination':
      return '疫苗';
    case 'medication':
      return '用药';
    case 'health_record':
      return '记录';
    default:
      return entryType;
  }
}

Color _barColor(String entryType) {
  switch (entryType) {
    case 'vaccination':
      return AppColors.success;
    case 'medication':
      return AppColors.inkBlue;
    case 'task':
      return AppColors.warning;
    default:
      return AppColors.slateBlue;
  }
}
