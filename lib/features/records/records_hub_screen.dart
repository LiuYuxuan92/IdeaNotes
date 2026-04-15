import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/query/analytics_service.dart';
import '../../core/query/entry_query.dart';
import '../../core/query/entry_record.dart';
import '../../core/query/timeline_service.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/entry_repository.dart';
import 'widgets/finance_summary_charts.dart';
import 'widgets/health_trend_charts.dart';
import 'widgets/task_summary_cards.dart';

enum RecordsHubTab { finance, tasks, health }

class RecordsHubScreen extends StatefulWidget {
  final RecordsHubTab initialTab;

  const RecordsHubScreen({
    super.key,
    this.initialTab = RecordsHubTab.finance,
  });

  @override
  State<RecordsHubScreen> createState() => _RecordsHubScreenState();
}

class _RecordsHubScreenState extends State<RecordsHubScreen> {
  static const _ranges = <_RangePreset>[
    _RangePreset(label: '近30天', days: 30),
    _RangePreset(label: '近90天', days: 90),
    _RangePreset(label: '近1年', days: 365),
    _RangePreset(label: '全部', days: null),
  ];

  late final EntryRepository _entryRepository;
  late final AnalyticsService _analyticsService;
  late final TimelineService _timelineService;

  late RecordsHubTab _selectedTab;
  int? _selectedDays = 365;
  late Future<_RecordsHubData> _loadFuture;

  @override
  void initState() {
    super.initState();
    _entryRepository = EntryRepository(databaseHelper: DatabaseHelper.instance);
    _analyticsService = AnalyticsService(entryRepository: _entryRepository);
    _timelineService = TimelineService(entryRepository: _entryRepository);
    _selectedTab = widget.initialTab;
    _loadFuture = _loadCurrentTab();
  }

  Future<_RecordsHubData> _loadCurrentTab() async {
    switch (_selectedTab) {
      case RecordsHubTab.finance:
        return _loadFinanceData();
      case RecordsHubTab.tasks:
        return _loadTaskData();
      case RecordsHubTab.health:
        return _loadHealthData();
    }
  }

  Future<_FinanceHubData> _loadFinanceData() async {
    final query = _buildQuery(
      entryTypes: const {'expense'},
      domains: const {'finance'},
    );
    final summary = await _analyticsService.getAmountSummary(query);
    final categories = await _analyticsService.getAmountByCategory(query);
    final trend = await _analyticsService.getMonthlyAmountTrend(query);
    return _FinanceHubData(
      summary: summary,
      categories: categories,
      trend: trend,
    );
  }

  Future<_TaskHubData> _loadTaskData() async {
    final query = _buildQuery(entryTypes: const {'task'});
    final groups = await _timelineService.getDailyTimeline(query);

    var totalCount = 0;
    var pendingCount = 0;
    var completedCount = 0;

    for (final group in groups) {
      totalCount += group.entries.length;
      for (final entry in group.entries) {
        if (entry.status == 'done') {
          completedCount += 1;
        } else {
          pendingCount += 1;
        }
      }
    }

    return _TaskHubData(
      groups: groups,
      totalCount: totalCount,
      pendingCount: pendingCount,
      completedCount: completedCount,
    );
  }

  Future<_HealthHubData> _loadHealthData() async {
    final query = _buildQuery(domains: const {'health'});
    final groups = await _timelineService.getDailyTimeline(query);
    final typeStats = await _analyticsService.getEntryCountByType(query);
    return _HealthHubData(groups: groups, typeStats: typeStats);
  }

  EntryQuery _buildQuery({
    Set<String> entryTypes = const <String>{},
    Set<String> domains = const <String>{},
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = _selectedDays == null
        ? null
        : today.subtract(Duration(days: _selectedDays! - 1));

    return EntryQuery(
      from: from,
      to: today,
      entryTypes: entryTypes,
      domains: domains,
    );
  }

  void _switchTab(RecordsHubTab tab) {
    if (_selectedTab == tab) return;
    setState(() {
      _selectedTab = tab;
      _loadFuture = _loadCurrentTab();
    });
  }

  void _switchRange(int? days) {
    if (_selectedDays == days) return;
    setState(() {
      _selectedDays = days;
      _loadFuture = _loadCurrentTab();
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = context.isCompact ? 16.0 : 20.0;

    return Scaffold(
      appBar: AppBar(title: const Text('结构化记录')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<_RecordsHubData>(
                  future: _loadFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return EmptyStateView(
                        icon: Icons.data_array_rounded,
                        title: '结构化记录暂时打不开',
                        description: '请稍后重试。如果问题持续，再检查本地数据库是否正常。',
                        action: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _loadFuture = _loadCurrentTab();
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新加载'),
                        ),
                      );
                    }

                    final data = snapshot.data;
                    if (data == null) {
                      return const SizedBox.shrink();
                    }

                    return _buildTabBody(context, data);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return AppSurface(
      padding: EdgeInsets.all(context.isCompact ? 16 : 20),
      radius: context.isCompact ? 28 : 32,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '查询中心',
            title: _selectedTab.title,
            description: _selectedTab.description,
          ),
          const SizedBox(height: 14),
          if (context.isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTabSelector(context),
                const SizedBox(height: 12),
                _buildRangeSelector(context),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTabSelector(context)),
                const SizedBox(width: 12),
                Expanded(child: _buildRangeSelector(context)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RecordsHubTab.values
          .map(
            (tab) => _ChoicePill(
              label: tab.shortLabel,
              selected: _selectedTab == tab,
              onTap: () => _switchTab(tab),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _ranges
          .map(
            (range) => _ChoicePill(
              label: range.label,
              selected: _selectedDays == range.days,
              onTap: () => _switchRange(range.days),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildTabBody(BuildContext context, _RecordsHubData data) {
    switch (data) {
      case _FinanceHubData financeData:
        return _buildFinanceBody(context, financeData);
      case _TaskHubData taskData:
        return _buildTaskBody(context, taskData);
      case _HealthHubData healthData:
        return _buildHealthBody(context, healthData);
    }
  }

  Widget _buildFinanceBody(BuildContext context, _FinanceHubData data) {
    if (data.summary.entryCount == 0) {
      return const EmptyStateView(
        icon: Icons.attach_money_rounded,
        title: '这段时间还没有可汇总的花费',
        description: '先在手写页里记录金额与内容，识别并保存后，这里就会自动归类展示。',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      children: [
        _MetricGrid(
          items: [
            _MetricItem(
              label: '总支出',
              value: _formatAmount(data.summary.totalAmount),
              icon: Icons.account_balance_wallet_outlined,
              accent: AppColors.warning,
            ),
            _MetricItem(
              label: '记录条数',
              value: '${data.summary.entryCount} 条',
              icon: Icons.receipt_long_rounded,
              accent: AppColors.inkBlue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        FinanceSummaryCharts(
          totalAmount: data.summary.totalAmount,
          categories: data.categories,
          trend: data.trend,
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                eyebrow: '分类',
                title: '按分类看支出',
                description: '你记录下来的花费会优先按一级分类汇总。',
              ),
              const SizedBox(height: 16),
              ...data.categories.map(
                (stat) => _RecordLine(
                  title: stat.category,
                  subtitle: '${stat.entryCount} 条记录',
                  trailing: _formatAmount(stat.totalAmount),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                eyebrow: '趋势',
                title: '按月份回看',
                description: '适合快速定位哪几个月的花费更集中。',
              ),
              const SizedBox(height: 16),
              ...data.trend.map(
                (point) => _RecordLine(
                  title: _monthLabel(point.month),
                  subtitle: '${point.entryCount} 条记录',
                  trailing: _formatAmount(point.totalAmount),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskBody(BuildContext context, _TaskHubData data) {
    if (data.totalCount == 0) {
      return const EmptyStateView(
        icon: Icons.event_note_rounded,
        title: '这段时间还没有可回看的待办',
        description: '把提醒、安排或时间点写进笔记并保存后，这里会按日期整理时间线。',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      children: [
        TaskSummaryCards(
          totalCount: data.totalCount,
          pendingCount: data.pendingCount,
          completedCount: data.completedCount,
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                eyebrow: '时间线',
                title: '按日期回看待办',
                description: '这里收录被识别为待办的内容，例如未来安排、提醒词和明确时点。',
              ),
              const SizedBox(height: 16),
              ...data.groups.map(
                (group) => _TimelineDayCard(
                  dateLabel: _fullDateLabel(group.date),
                  entries: group.entries,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthBody(BuildContext context, _HealthHubData data) {
    final totalCount = data.groups.fold<int>(
      0,
      (sum, group) => sum + group.entries.length,
    );

    if (totalCount == 0) {
      return const EmptyStateView(
        icon: Icons.health_and_safety_outlined,
        title: '这段时间还没有健康记录',
        description: '比如疫苗、就诊、发烧、用药等内容，保存后都会集中到这里。',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      children: [
        HealthTrendCharts(typeStats: data.typeStats),
        const SizedBox(height: 12),
        _MetricGrid(
          items: data.typeStats
              .map(
                (stat) => _MetricItem(
                  label: _healthEntryTypeLabel(stat.entryType),
                  value: '${stat.count} 条',
                  icon: _entryTypeIcon(stat.entryType),
                  accent: _entryTypeAccent(stat.entryType),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                eyebrow: '记录',
                title: '按日期回看健康记录',
                description: '疫苗、用药、就诊、排便、饮食和相关健康待办都会按天归档。',
              ),
              const SizedBox(height: 16),
              ...data.groups.map(
                (group) => _TimelineDayCard(
                  dateLabel: _fullDateLabel(group.date),
                  entries: group.entries,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatAmount(Decimal amount) {
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

  static String _monthLabel(String rawMonth) {
    final parts = rawMonth.split('-');
    if (parts.length != 2) {
      return rawMonth;
    }
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  static String _fullDateLabel(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  static String _entryTypeLabel(String entryType) {
    switch (entryType) {
      case 'expense':
        return '花费';
      case 'task':
        return '待办';
      case 'vaccination':
        return '疫苗';
      case 'medication':
        return '用药';
      case 'health_record':
        return '健康记录';
      case 'memo':
        return '记录';
      default:
        return entryType;
    }
  }

  static String _healthEntryTypeLabel(String entryType) {
    if (entryType == 'task') {
      return '健康待办';
    }
    return _entryTypeLabel(entryType);
  }

  static String _timelineEntryLabel(EntryRecord entry) {
    if (entry.entryType == 'task' && entry.domain == 'health') {
      return '健康待办';
    }
    return _entryTypeLabel(entry.entryType);
  }

  static String? _timelineTimeLabel(EntryRecord entry) {
    final occurredAt = entry.occurredAt;
    if (occurredAt == null) {
      return null;
    }
    if (occurredAt.hour == 0 && occurredAt.minute == 0) {
      return null;
    }
    return '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';
  }

  static IconData _entryTypeIcon(String entryType) {
    switch (entryType) {
      case 'expense':
        return Icons.attach_money_rounded;
      case 'task':
        return Icons.event_note_rounded;
      case 'vaccination':
        return Icons.vaccines_rounded;
      case 'medication':
        return Icons.medication_outlined;
      case 'health_record':
        return Icons.favorite_border_rounded;
      default:
        return Icons.notes_rounded;
    }
  }

  static Color _entryTypeAccent(String entryType) {
    switch (entryType) {
      case 'expense':
        return AppColors.warning;
      case 'task':
        return AppColors.inkBlue;
      case 'vaccination':
      case 'medication':
      case 'health_record':
        return AppColors.success;
      default:
        return AppColors.slateBlue;
    }
  }
}

extension on RecordsHubTab {
  String get shortLabel {
    switch (this) {
      case RecordsHubTab.finance:
        return '支出分类';
      case RecordsHubTab.tasks:
        return '待办时间线';
      case RecordsHubTab.health:
        return '健康记录';
    }
  }

  String get title {
    switch (this) {
      case RecordsHubTab.finance:
        return '支出分类查询';
      case RecordsHubTab.tasks:
        return '待办时间线查询';
      case RecordsHubTab.health:
        return '健康记录查询';
    }
  }

  String get description {
    switch (this) {
      case RecordsHubTab.finance:
        return '查近一段时间的花费总额、分类占比和按月回看。';
      case RecordsHubTab.tasks:
        return '收录被识别为待办的内容：未来安排、提醒词和明确时点。';
      case RecordsHubTab.health:
        return '收录健康相关内容：疫苗、用药、就诊、排便、饮食等，也包含健康待办。';
    }
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.inkBlue : AppColors.textSecondary;
    final background =
        selected ? const Color(0xFFDDE8EE) : const Color(0xFFF2F5F6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricItem> items;

  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) {
      return Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MetricCard(item: item),
              ),
            )
            .toList(growable: false),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => SizedBox(
              width: 180,
              child: _MetricCard(item: item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _MetricItem item;

  const _MetricCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      isFlat: true,
      padding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFF8FAFB),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: item.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineDayCard extends StatelessWidget {
  final String dateLabel;
  final List<EntryRecord> entries;

  const _TimelineDayCard({
    required this.dateLabel,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          ...entries.map(
            (entry) => _RecordLine(
              title: entry.title,
              subtitle: [
                _RecordsHubScreenState._timelineEntryLabel(entry),
                if (_RecordsHubScreenState._timelineTimeLabel(entry) != null)
                  _RecordsHubScreenState._timelineTimeLabel(entry)!,
                if (entry.categoryL1?.trim().isNotEmpty == true)
                  entry.categoryL1!.trim(),
                if (entry.status == 'done')
                  '已完成'
                else if (entry.status == 'pending')
                  '待处理',
              ].join(' · '),
              trailing: entry.amountValue == null
                  ? null
                  : _RecordsHubScreenState._formatAmount(entry.amountValue!),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordLine extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;

  const _RecordLine({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing?.trim().isNotEmpty == true) ...[
            const SizedBox(width: 12),
            Text(
              trailing!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.inkBlue,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricItem {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });
}

class _RangePreset {
  final String label;
  final int? days;

  const _RangePreset({
    required this.label,
    required this.days,
  });
}

sealed class _RecordsHubData {}

class _FinanceHubData extends _RecordsHubData {
  final AmountSummary summary;
  final List<CategoryAmountStat> categories;
  final List<MonthlyTrendPoint> trend;

  _FinanceHubData({
    required this.summary,
    required this.categories,
    required this.trend,
  });
}

class _TaskHubData extends _RecordsHubData {
  final List<TimelineDayGroup> groups;
  final int totalCount;
  final int pendingCount;
  final int completedCount;

  _TaskHubData({
    required this.groups,
    required this.totalCount,
    required this.pendingCount,
    required this.completedCount,
  });
}

class _HealthHubData extends _RecordsHubData {
  final List<TimelineDayGroup> groups;
  final List<EntryCountStat> typeStats;

  _HealthHubData({
    required this.groups,
    required this.typeStats,
  });
}
