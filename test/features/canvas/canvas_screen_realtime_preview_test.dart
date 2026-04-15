import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/ocr/ocr_engine.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';
import 'package:idea_notes/core/storage/extraction_preview_repository.dart';
import 'package:idea_notes/features/canvas/canvas_screen.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _databaseFactory = databaseFactoryFfiNoIsolate;

class _FakeOcrEngine implements OcrEngine {
  const _FakeOcrEngine();

  @override
  String get engineName => 'fake';

  @override
  void dispose() {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> recognizeText(Uint8List imageBytes) async => const [];

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async =>
      const [];
}

ExtractionPreview _preview({
  String id = 'preview-1',
  String noteId = 'note-1',
  String text = 'preview-only',
}) {
  return ExtractionPreview(
    id: id,
    noteId: noteId,
    rawText: text,
    mergedExtractionJson: text,
    status: ExtractionPreviewStatus.pending,
    createdAt: DateTime(2026, 1, 1),
  );
}

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

Future<void> _prepareSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2200));
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  group('CanvasScreen realtime preview', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    testWidgets('shows pending preview card passed from constructor',
        (tester) async {
      await _prepareSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CanvasScreen(
            key: const ValueKey('screen-preview-constructor'),
            ocrEngineOverride: const _FakeOcrEngine(),
            initialPendingPreviews: [_preview()],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('preview-only'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('confirm removes pending preview from screen', (tester) async {
      await _prepareSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CanvasScreen(
            key: const ValueKey('screen-preview-remove'),
            ocrEngineOverride: const _FakeOcrEngine(),
            initialPendingPreviews: [_preview()],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('preview-only'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('loads stored pending previews for an existing note',
        (tester) async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await DatabaseHelper.instance.insertNote({
        'id': 'note-db',
        'notebook_id': 'default-notebook',
        'created_at': now,
        'updated_at': now,
        'recognized_text': 'recognized text',
      });
      final repository = ExtractionPreviewRepository(
        databaseHelper: DatabaseHelper.instance,
      );
      await repository.upsertPreview(
        _preview(id: 'preview-db', noteId: 'note-db'),
      );

      await _prepareSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: CanvasScreen(
            key: ValueKey('screen-preview-load'),
            noteId: 'note-db',
            ocrEngineOverride: _FakeOcrEngine(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('preview-only'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('confirm marks stored preview as confirmed', (tester) async {
      final now = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await DatabaseHelper.instance.insertNote({
        'id': 'note-confirm',
        'notebook_id': 'default-notebook',
        'created_at': now,
        'updated_at': now,
        'recognized_text': 'recognized text',
      });
      final repository = ExtractionPreviewRepository(
        databaseHelper: DatabaseHelper.instance,
      );
      await repository.upsertPreview(
        _preview(id: 'preview-confirm', noteId: 'note-confirm'),
      );

      await _prepareSurface(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: CanvasScreen(
            key: ValueKey('screen-preview-confirm'),
            noteId: 'note-confirm',
            ocrEngineOverride: _FakeOcrEngine(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final stored = await repository.getPreview('preview-confirm');
      expect(stored, isNotNull);
      expect(stored!.status, ExtractionPreviewStatus.confirmed);
      expect(find.text('preview-only'), findsNothing);
    });
  });
}
