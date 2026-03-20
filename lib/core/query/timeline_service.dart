import 'package:idea_notes/core/storage/entry_repository.dart';

import 'entry_query.dart';
import 'entry_record.dart';

class TimelineDayGroup {
  final DateTime date;
  final List<EntryRecord> entries;

  const TimelineDayGroup({
    required this.date,
    required this.entries,
  });
}

class TimelineService {
  final EntryRepository entryRepository;

  const TimelineService({
    required this.entryRepository,
  });

  Future<List<TimelineDayGroup>> getDailyTimeline(EntryQuery query) async {
    final entries = await entryRepository.queryEntries(query);
    final grouped = <String, List<EntryRecord>>{};

    for (final entry in entries) {
      final dateKey = _formatDate(entry.occurredDate);
      grouped.putIfAbsent(dateKey, () => <EntryRecord>[]).add(entry);
    }

    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map(
          (key) => TimelineDayGroup(
            date: _parseDate(key),
            entries: grouped[key]!..sort(
              (a, b) => b.createdAt.compareTo(a.createdAt),
            ),
          ),
        )
        .toList();
  }

  Future<List<EntryRecord>> getEntriesByDate(
    DateTime day, {
    EntryQuery baseQuery = const EntryQuery(),
  }) {
    return entryRepository.queryEntriesByDate(day, baseQuery: baseQuery);
  }

  static String _formatDate(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }

  static DateTime _parseDate(String raw) {
    final parts = raw.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
