import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/features/canvas/services/canvas_load_service.dart';
import 'package:idea_notes/features/canvas/services/canvas_save_service.dart';
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

void main() {
  group('Canvas flow contract', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('save 后再 load，note 与 entry 数据保持一致', () async {
      final saveService = CanvasSaveService(
        databaseHelper: DatabaseHelper.instance,
        createId: () => 'flow-note-1',
        saveSnapshot: (_, noteId) async => '/tmp/$noteId-snapshot.png',
        saveThumbnail: (_, noteId) async => '/tmp/$noteId-thumb.png',
      );
      final loadService =
          CanvasLoadService(databaseHelper: DatabaseHelper.instance);

      final now = DateTime(2026, 3, 13, 17, 10);
      await saveService.save(
        CanvasSaveInput(
          existingNote: null,
          canvasData: Uint8List.fromList([1, 2, 3, 4]),
          snapshotBytes: Uint8List.fromList([7, 7]),
          thumbnailBytes: Uint8List.fromList([8, 8]),
          recognizedText: '买菜 35.5\n记得买牛奶',
          now: now,
        ),
      );

      final loaded = await loadService.load('flow-note-1');

      expect(loaded.note, isNotNull);
      expect(loaded.note!.snapshotImagePath, '/tmp/flow-note-1-snapshot.png');
      expect(loaded.note!.thumbnailImagePath, '/tmp/flow-note-1-thumb.png');
      expect(loaded.ocrResult, '买菜 35.5\n记得买牛奶');
      expect(loaded.canvasData, Uint8List.fromList([1, 2, 3, 4]));

      final db = await DatabaseHelper.instance.database;
      final structuredEntries = await db.query(
        'entries',
        where: 'note_id = ?',
        whereArgs: ['flow-note-1'],
      );
      expect(structuredEntries.length, 2);
      expect(
        structuredEntries.map((row) => row['entry_type']).toSet(),
        {'expense', 'task'},
      );
    });
  });
}
