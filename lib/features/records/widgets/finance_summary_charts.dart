import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';

import '../../../app/design_system.dart';
import '../../../core/query/analytics_service.dart';

class FinanceSummaryCharts extends StatelessWidget {
  final Decimal totalAmount;
  final List<CategoryAmountStat> categories;
  final List<MonthlyTrendPoint> trend;

  const FinanceSummaryCharts({
    super.key,
    required this.totalAmount,
    required this.categories,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '图表',
            title: '分类占比',
            description: '用图形快速查看分类分布和月度变化。',
          ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty) ...[
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 40,
                  sectionsSpace: 3,
                  sections: _buildCategorySections(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.asMap().entries.map((entry) {
                final color = _palette[entry.key % _palette.length];
                final stat = entry.value;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${stat.category} ${_formatAmount(stat.totalAmount)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 20),
          ],
          if (trend.isNotEmpty) ...[
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: true, reservedSize: 44)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _monthShortLabel(trend[index].month),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.inkBlue,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.inkBlue.withValues(alpha: 0.10),
                      ),
                      spots: trend.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          _decimalToDouble(entry.value.totalAmount),
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '总支出 ${_formatAmount(totalAmount)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildCategorySections() {
    final total = categories.fold<double>(
      0,
      (sum, stat) => sum + _decimalToDouble(stat.totalAmount),
    );

    return categories.asMap().entries.map((entry) {
      final stat = entry.value;
      final value = _decimalToDouble(stat.totalAmount);
      final percentage = total == 0 ? 0 : (value / total * 100).round();
      return PieChartSectionData(
        color: _palette[entry.key % _palette.length],
        value: value,
        radius: 58,
        title: '$percentage%',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }).toList(growable: false);
  }
}

const _palette = <Color>[
  AppColors.warning,
  AppColors.inkBlue,
  AppColors.success,
  AppColors.slateBlue,
  AppColors.deepTeal,
];

String _monthShortLabel(String rawMonth) {
  final parts = rawMonth.split('-');
  if (parts.length != 2) {
    return rawMonth;
  }
  return '${int.parse(parts[1])}月';
}

String _formatAmount(Decimal amount) {
  final raw = amount.toString();
  if (!raw.contains('.')) {
    return '¥$raw';
  }
  final parts = raw.split('.');
  final trimmedFraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  if (trimmedFraction.isEmpty) {
    return '¥${parts[0]}';
  }
  return '¥${parts[0]}.$trimmedFraction';
}

double _decimalToDouble(Decimal value) => double.parse(value.toString());
