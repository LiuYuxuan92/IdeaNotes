import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/core/storage/extraction_preview_repository.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

void main() {
  group('ExtractionPreviewRepository', () {
    late Database db;
    late ExtractionPreviewRepository repository;

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
      repository = ExtractionPreviewRepository(
        databaseHelper: DatabaseHelper.instance,
      );
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('preview round-trips through map', () {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1710000000000);
      final confirmedAt = DateTime.fromMillisecondsSinceEpoch(1710000005000);
      final preview = ExtractionPreview(
        id: 'preview-1',
        noteId: 'note-1',
        rawText: 'milk 12',
        mergedExtractionJson: '{"amount":12}',
        status: ExtractionPreviewStatus.confirmed,
        createdAt: createdAt,
        confirmedAt: confirmedAt,
      );

      final map = preview.toMap();
      final restored = ExtractionPreview.fromMap(map);

      expect(map, {
        'id': 'preview-1',
        'note_id': 'note-1',
        'raw_text': 'milk 12',
        'merged_extraction': '{"amount":12}',
        'status': 'confirmed',
        'created_at': createdAt.millisecondsSinceEpoch,
        'confirmed_at': confirmedAt.millisecondsSinceEpoch,
      });
      expect(restored, preview);
    });

    test('upserts and fetches pending previews for a note', () async {
      final preview = ExtractionPreview(
        id: 'preview-1',
        noteId: 'note-1',
        rawText: 'milk 12',
        mergedExtractionJson: '{"amount":12}',
        status: ExtractionPreviewStatus.pending,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1710000000000),
      );

      await db.insert('notebooks', {
        'id': 'notebook-1',
        'title': 'Default',
        'created_at': 1710000000000,
        'updated_at': 1710000000000,
      });
      await db.insert('notes', {
        'id': 'note-1',
        'notebook_id': 'notebook-1',
        'created_at': 1710000000000,
        'updated_at': 1710000000000,
        'recognized_text': 'milk 12',
      });
      await db.insert('notes', {
        'id': 'note-2',
        'notebook_id': 'notebook-1',
        'created_at': 1710000000001,
        'updated_at': 1710000000001,
        'recognized_text': 'bread 9',
      });

      final updatedPreview = ExtractionPreview(
        id: 'preview-1',
        noteId: 'note-1',
        rawText: 'milk 15',
        mergedExtractionJson: '{"amount":15}',
        status: ExtractionPreviewStatus.pending,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1710000000000),
      );

      await repository.upsertPreview(preview);
      await repository.upsertPreview(updatedPreview);
      await repository.upsertPreview(
        ExtractionPreview(
          id: 'preview-2',
          noteId: 'note-1',
          rawText: 'done',
          mergedExtractionJson: null,
          status: ExtractionPreviewStatus.confirmed,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1710000000002),
          confirmedAt: DateTime.fromMillisecondsSinceEpoch(1710000000003),
        ),
      );
      await repository.upsertPreview(
        ExtractionPreview(
          id: 'preview-3',
          noteId: 'note-2',
          rawText: 'bread 9',
          mergedExtractionJson: '{"amount":9}',
          status: ExtractionPreviewStatus.pending,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1710000000004),
        ),
      );

      final results = await repository.getPendingPreviews('note-1');

      expect(results, [updatedPreview]);
    });
  });
}
