import 'package:decimal/decimal.dart';
import 'package:idea_notes/core/storage/entry_repository.dart';

import 'entry_query.dart';

class AmountSummary {
  final Decimal totalAmount;
  final int entryCount;

  const AmountSummary({
    required this.totalAmount,
    required this.entryCount,
  });
}

class CategoryAmountStat {
  final String category;
  final Decimal totalAmount;
  final int entryCount;

  const CategoryAmountStat({
    required this.category,
    required this.totalAmount,
    required this.entryCount,
  });
}

class MonthlyTrendPoint {
  final String month;
  final Decimal totalAmount;
  final int entryCount;

  const MonthlyTrendPoint({
    required this.month,
    required this.totalAmount,
    required this.entryCount,
  });
}

class EntryCountStat {
  final String entryType;
  final int count;

  const EntryCountStat({
    required this.entryType,
    required this.count,
  });
}

class AnalyticsService {
  final EntryRepository entryRepository;

  const AnalyticsService({
    required this.entryRepository,
  });

  Future<AmountSummary> getAmountSummary(EntryQuery query) async {
    final entries = await entryRepository.queryEntries(query);
    var total = Decimal.zero;
    var count = 0;

    for (final entry in entries) {
      if (entry.amountValue == null) {
        continue;
      }
      total += entry.amountValue!;
      count += 1;
    }

    return AmountSummary(totalAmount: total, entryCount: count);
  }

  Future<List<CategoryAmountStat>> getAmountByCategory(EntryQuery query) async {
    final entries = await entryRepository.queryEntries(query);
    final grouped = <String, _AmountAccumulator>{};

    for (final entry in entries) {
      if (entry.amountValue == null) {
        continue;
      }
      final category = entry.categoryL1?.trim().isNotEmpty == true
          ? entry.categoryL1!.trim()
          : '其他';
      final acc = grouped.putIfAbsent(category, _AmountAccumulator.new);
      acc.amount += entry.amountValue!;
      acc.count += 1;
    }

    final stats = grouped.entries
        .map(
          (it) => CategoryAmountStat(
            category: it.key,
            totalAmount: it.value.amount,
            entryCount: it.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return stats;
  }

  Future<List<MonthlyTrendPoint>> getMonthlyAmountTrend(
      EntryQuery query) async {
    final entries = await entryRepository.queryEntries(query);
    final grouped = <String, _AmountAccumulator>{};

    for (final entry in entries) {
      if (entry.amountValue == null) {
        continue;
      }
      final key = _monthKey(entry.occurredDate);
      final acc = grouped.putIfAbsent(key, _AmountAccumulator.new);
      acc.amount += entry.amountValue!;
      acc.count += 1;
    }

    final points = grouped.entries
        .map(
          (it) => MonthlyTrendPoint(
            month: it.key,
            totalAmount: it.value.amount,
            entryCount: it.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    return points;
  }

  Future<List<EntryCountStat>> getEntryCountByType(EntryQuery query) async {
    final entries = await entryRepository.queryEntries(query);
    final grouped = <String, int>{};

    for (final entry in entries) {
      grouped.update(
        entry.entryType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final stats = grouped.entries
        .map((it) => EntryCountStat(entryType: it.key, count: it.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return stats;
  }

  static String _monthKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }
}

class _AmountAccumulator {
  Decimal amount = Decimal.zero;
  int count = 0;
}
