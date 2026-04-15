import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/app/design_system.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/features/records/records_hub_screen.dart';
import 'package:idea_notes/features/records/widgets/finance_summary_charts.dart';
import 'package:idea_notes/features/records/widgets/health_trend_charts.dart';
import 'package:idea_notes/features/records/widgets/task_summary_cards.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

Future<void> _setUpInMemoryDatabase() async {
  databaseFactory = _databaseFactory;

  try {
    await DatabaseHelper.instance.close();
  } catch (_) {}

  final db = await _databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kDatabaseVersion,
      onCreate: createDatabaseSchema,
    ),
  );
  DatabaseHelper.injectDatabase(db);
}

Future<void> _seedRecordsHubData() async {
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
    'id': 'f1',
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

  await db.insert('entries', {
    'id': 'f2',
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

  await db.insert('entries', {
    'id': 'f3',
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

  await db.insert('entries', {
    'id': 't1',
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

  await db.insert('entries', {
    'id': 't2',
    'note_id': 'note-1',
    'entry_type': 'task',
    'domain': 'life',
    'occurred_at': DateTime(2026, 2, 15, 9, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-15',
    'end_at': null,
    'title': '买奶粉',
    'summary': null,
    'raw_text': '买奶粉',
    'normalized_json': null,
    'amount_value': null,
    'amount_currency': null,
    'category_l1': null,
    'category_l2': null,
    'status': 'done',
    'confidence': 0.88,
    'is_user_confirmed': 1,
    'source_engine': 'ai',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 15, 9, 1).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 15, 9, 1).millisecondsSinceEpoch,
  });

  await db.insert('entries', {
    'id': 'h1',
    'note_id': 'note-1',
    'entry_type': 'vaccination',
    'domain': 'health',
    'occurred_at': DateTime(2026, 2, 18, 14, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-18',
    'end_at': null,
    'title': '乙肝疫苗',
    'summary': null,
    'raw_text': '乙肝疫苗',
    'normalized_json': null,
    'amount_value': null,
    'amount_currency': null,
    'category_l1': null,
    'category_l2': null,
    'status': 'recorded',
    'confidence': 0.91,
    'is_user_confirmed': 1,
    'source_engine': 'ai',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 18, 14, 1).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 18, 14, 1).millisecondsSinceEpoch,
  });

  await db.insert('entries', {
    'id': 'h2',
    'note_id': 'note-1',
    'entry_type': 'medication',
    'domain': 'health',
    'occurred_at': DateTime(2026, 2, 19, 8, 0).millisecondsSinceEpoch,
    'occurred_date': '2026-02-19',
    'end_at': null,
    'title': '退烧药',
    'summary': null,
    'raw_text': '退烧药',
    'normalized_json': null,
    'amount_value': null,
    'amount_currency': null,
    'category_l1': null,
    'category_l2': null,
    'status': 'recorded',
    'confidence': 0.9,
    'is_user_confirmed': 1,
    'source_engine': 'ai',
    'source_version': 'v1',
    'created_at': DateTime(2026, 2, 19, 8, 1).millisecondsSinceEpoch,
    'updated_at': DateTime(2026, 2, 19, 8, 1).millisecondsSinceEpoch,
  });
}

Widget _wrapApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _setUpInMemoryDatabase();
    await _seedRecordsHubData();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  testWidgets(
      'records hub renders finance charts, task summary cards, and health charts',
      (tester) async {
    await tester.pumpWidget(
      _wrapApp(const RecordsHubScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FinanceSummaryCharts), findsOneWidget);

    await tester.tap(find.text('待办时间线'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSummaryCards), findsOneWidget);

    await tester.tap(find.text('健康记录'));
    await tester.pumpAndSettle();
    expect(find.byType(HealthTrendCharts), findsOneWidget);
  });
}
