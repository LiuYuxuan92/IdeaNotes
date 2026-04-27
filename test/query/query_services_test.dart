import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/query/analytics_service.dart';
import 'package:idea_notes/core/query/entry_query.dart';
import 'package:idea_notes/core/query/timeline_service.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/core/storage/entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../_helpers/sqflite_test_init.dart';

Future<void> _setUpInMemoryDatabase() async {
  final factory = ensureSqfliteTestFactory();

  try {
    await DatabaseHelper.instance.close();
  } catch (_) {}

  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kDatabaseVersion,
      onCreate: createDatabaseSchema,
    ),
  );
  DatabaseHelper.injectDatabase(db);
}

Future<void> _seedData() async {
  final db = await DatabaseHelper.instance.database;
  final noteCreatedAt = DateTime(2026, 1, 1, 8, 0).millisecondsSinceEpoch;

  await db.insert('notes', {
    'id': 'note-1',
    'notebook_id': 'default-notebook',
    'created_at': noteCreatedAt,
    'updated_at': noteCreatedAt,
    'recognized_text': 'seed',
  });

  await db.insert('entries', {
    'id': 'e1',
    'note_id': 'note-1',
    'entry_type': 'expense',
    'domain': 'finance',
    'occurred_at': DateTime(2026, 1, 10, 10, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-01-10',
    'end_at': null,
    'title': '疫苗费用',
    'summary': null,
    'raw_text': '宝宝打疫苗 100元',
    'normalized_json': null,
    'amount_value': '100',
    'amount_currency': 'CNY',
    'category_l1': '医疗',
    'category_l2': '疫苗',
    'status': 'recorded',
    'confidence': 0.95,
    'is_user_confirmed': 1,
    'source_engine': 'rule',
    'source_version': 'v1',
    'created_at': DateTime(2026, 1, 10, 11, 0).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 1, 10, 11, 0).millisecondsSinceEpoch,
  });
  await db.insert('entry_subjects', {
    'id': 's1',
    'entry_id': 'e1',
    'subject_name': '宝宝',
    'subject_type': 'person',
    'role': 'patient',
    'created_at': noteCreatedAt,
  });
  await db.insert('entry_tags', {
    'id': 't1',
    'entry_id': 'e1',
    'tag': '疫苗',
    'created_at': noteCreatedAt,
  });

  await db.insert('entries', {
    'id': 'e2',
    'note_id': 'note-1',
    'entry_type': 'expense',
    'domain': 'finance',
    'occurred_at': DateTime(2026, 2, 12, 12, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-12',
    'end_at': null,
    'title': '午饭',
    'summary': null,
    'raw_text': '午饭 30',
    'normalized_json': null,
    'amount_value': '30',
    'amount_currency': 'CNY',
    'category_l1': '餐饮',
    'category_l2': null,
    'status': 'recorded',
    'confidence': 0.9,
    'is_user_confirmed': 1,
    'source_engine': 'rule',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 12, 12, 30).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 12, 12, 30).millisecondsSinceEpoch,
  });
  await db.insert('entry_subjects', {
    'id': 's2',
    'entry_id': 'e2',
    'subject_name': '我',
    'subject_type': 'person',
    'role': 'payer',
    'created_at': noteCreatedAt,
  });
  await db.insert('entry_tags', {
    'id': 't2',
    'entry_id': 'e2',
    'tag': '日常',
    'created_at': noteCreatedAt,
  });

  await db.insert('entries', {
    'id': 'e3',
    'note_id': 'note-1',
    'entry_type': 'task',
    'domain': 'life',
    'occurred_at': DateTime(2026, 2, 12, 18, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-12',
    'end_at': null,
    'title': '下个月复查',
    'summary': null,
    'raw_text': '下个月复查',
    'normalized_json': null,
    'amount_value': null,
    'amount_currency': null,
    'category_l1': null,
    'category_l2': null,
    'status': 'pending',
    'confidence': 0.85,
    'is_user_confirmed': 0,
    'source_engine': 'ai',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 12, 18, 1).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 12, 18, 1).millisecondsSinceEpoch,
  });
  await db.insert('entry_subjects', {
    'id': 's3',
    'entry_id': 'e3',
    'subject_name': '宝宝',
    'subject_type': 'person',
    'role': 'patient',
    'created_at': noteCreatedAt,
  });
  await db.insert('entry_tags', {
    'id': 't3',
    'entry_id': 'e3',
    'tag': '健康',
    'created_at': noteCreatedAt,
  });

  await db.insert('entries', {
    'id': 'e4',
    'note_id': 'note-1',
    'entry_type': 'expense',
    'domain': 'finance',
    'occurred_at': DateTime(2026, 2, 20, 10, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-20',
    'end_at': null,
    'title': '奶粉',
    'summary': null,
    'raw_text': '奶粉 20',
    'normalized_json': null,
    'amount_value': '20',
    'amount_currency': 'CNY',
    'category_l1': '餐饮',
    'category_l2': '奶粉',
    'status': 'recorded',
    'confidence': 0.96,
    'is_user_confirmed': 1,
    'source_engine': 'rule',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 20, 10, 10).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 20, 10, 10).millisecondsSinceEpoch,
  });
}

void main() {
  group('query foundation', () {
    late EntryRepository entryRepository;
    late TimelineService timelineService;
    late AnalyticsService analyticsService;

    setUp(() async {
      await _setUpInMemoryDatabase();
      await _seedData();
      entryRepository =
          EntryRepository(databaseHelper: DatabaseHelper.instance);
      timelineService = TimelineService(entryRepository: entryRepository);
      analyticsService = AnalyticsService(entryRepository: entryRepository);
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('EntryRepository supports date/type/category/subject/tag filtering',
        () async {
      final rows = await entryRepository.queryEntries(
        EntryQuery(
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 1, 31),
          entryTypes: {'expense'},
          categoryL1: {'医疗'},
          subjectNames: {'宝宝'},
          tags: {'疫苗'},
        ),
      );

      expect(rows.length, 1);
      expect(rows.first.id, 'e1');
      expect(rows.first.title, '疫苗费用');
    });

    test('TimelineService groups entries by day in descending date order',
        () async {
      final groups = await timelineService.getDailyTimeline(
        EntryQuery(from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28)),
      );

      expect(groups.length, 2);
      expect(groups.first.date, DateTime(2026, 2, 20));
      expect(groups.first.entries.length, 1);
      expect(groups.first.entries.first.id, 'e4');
      expect(groups[1].date, DateTime(2026, 2, 12));
      expect(groups[1].entries.length, 2);
    });

    test('AnalyticsService computes amount summary/category/monthly trend',
        () async {
      final query = EntryQuery(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        domains: {'finance'},
      );

      final summary = await analyticsService.getAmountSummary(query);
      expect(summary.totalAmount, Decimal.parse('150'));
      expect(summary.entryCount, 3);

      final categoryStats = await analyticsService.getAmountByCategory(query);
      expect(categoryStats.length, 2);
      expect(categoryStats.first.category, '医疗');
      expect(categoryStats.first.totalAmount, Decimal.parse('100'));
      expect(categoryStats[1].category, '餐饮');
      expect(categoryStats[1].totalAmount, Decimal.parse('50'));

      final trend = await analyticsService.getMonthlyAmountTrend(query);
      expect(trend.length, 2);
      expect(trend[0].month, '2026-01');
      expect(trend[0].totalAmount, Decimal.parse('100'));
      expect(trend[1].month, '2026-02');
      expect(trend[1].totalAmount, Decimal.parse('50'));
    });

    test('EntryRepository supports keyword/confirmedOnly/limit/offset',
        () async {
      final filtered = await entryRepository.queryEntries(
        const EntryQuery(
          keyword: '复查',
          confirmedOnly: false,
          sortBy: 'created_at',
          descending: false,
        ),
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, 'e3');

      final paged = await entryRepository.queryEntries(
        const EntryQuery(
          sortBy: 'occurred_date',
          descending: true,
          limit: 2,
          offset: 1,
        ),
      );
      expect(paged.length, 2);
      expect(paged.first.id, 'e3');
      expect(paged[1].id, 'e2');
    });

    test('TimelineService getEntriesByDate returns only one day entries',
        () async {
      final rows = await timelineService.getEntriesByDate(
        DateTime(2026, 2, 12),
      );

      expect(rows.length, 2);
      expect(rows.first.id, 'e3');
      expect(rows[1].id, 'e2');
    });

    test('AnalyticsService computes entry counts by type', () async {
      final stats = await analyticsService.getEntryCountByType(
        EntryQuery(from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31)),
      );

      expect(stats.length, 2);
      expect(stats.first.entryType, 'expense');
      expect(stats.first.count, 3);
      expect(stats[1].entryType, 'task');
      expect(stats[1].count, 1);
    });
  });
}
