import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

void main() {
  group('DatabaseHelper search', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = _databaseFactory;
      db = await _databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: kDatabaseVersion,
          onCreate: createDatabaseSchema,
          onUpgrade: migrateDatabaseSchema,
        ),
      );
      DatabaseHelper.injectDatabase(db);
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('escapeLikePattern escapes backslash, percent, and underscore', () {
      expect(
        DatabaseHelper.escapeLikePattern(r'100%_done'),
        r'100\%\_done',
      );
    });

    test('searchNotes treats percent and underscore literally', () async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await db.insert('notes', {
        'id': 'literal-match',
        'notebook_id': 'default-notebook',
        'created_at': now,
        'updated_at': now,
        'recognized_text': r'progress 100%_done',
      });
      await db.insert('notes', {
        'id': 'wildcard-only-match',
        'notebook_id': 'default-notebook',
        'created_at': now + 1,
        'updated_at': now + 1,
        'recognized_text': 'progress 100Xdone',
      });

      final results = await DatabaseHelper.instance.searchNotes(r'100%_done');

      expect(results.map((row) => row['id']), ['literal-match']);
    });
  });
}
