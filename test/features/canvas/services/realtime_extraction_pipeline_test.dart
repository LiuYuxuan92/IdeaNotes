import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/extraction_preview_repository.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';
import 'package:idea_notes/features/canvas/services/realtime_extraction_pipeline.dart';

class _SyncPreviewStore implements PreviewStore {
  final List<ExtractionPreview> _previews = [];

  @override
  Future<int> upsertPreview(ExtractionPreview preview) async {
    _previews.add(preview);
    return 1;
  }

  @override
  Future<List<ExtractionPreview>> getPendingPreviews(String noteId) async {
    return _previews
        .where((p) =>
            p.noteId == noteId && p.status == ExtractionPreviewStatus.pending)
        .toList();
  }

  @override
  Future<ExtractionPreview?> getPreview(String id) async {
    for (final p in _previews) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> markConfirmed(String id, DateTime confirmedAt) async {
    final idx = _previews.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      final old = _previews[idx];
      _previews[idx] = ExtractionPreview(
        id: old.id,
        noteId: old.noteId,
        rawText: old.rawText,
        mergedExtractionJson: old.mergedExtractionJson,
        status: ExtractionPreviewStatus.confirmed,
        createdAt: old.createdAt,
        confirmedAt: confirmedAt,
      );
    }
  }
}

void main() {
  group('RealtimeExtractionPipeline', () {
    test('multiple submitDelta calls emit multiple previews', () async {
    final repository = _SyncPreviewStore();
    var counter = 0;
    final pipeline = DefaultRealtimeExtractionPipeline(
      previewRepository: repository,
      createId: () => 'id-${counter++}',
    );

    final previews = <ExtractionPreview>[];
    pipeline.previews.listen(previews.add);

    await pipeline.submitDelta(noteId: 'note-1', rawText: 'first');
    await pipeline.submitDelta(noteId: 'note-1', rawText: 'second');

    expect(previews, hasLength(2));
    expect(previews[0].rawText, 'first');
    expect(previews[1].rawText, 'second');
  });

  test('submitDelta stores pending preview and emits it', () async {
    final repository = _SyncPreviewStore();
    var counter = 0;
    final pipeline = DefaultRealtimeExtractionPipeline(
      previewRepository: repository,
      createId: () => 'id-${counter++}',
    );

    final previews = <ExtractionPreview>[];
    pipeline.previews.listen(previews.add);

    await pipeline.submitDelta(noteId: 'note-1', rawText: 'milk 12');

    expect(previews, hasLength(1));
    expect(previews.first.noteId, 'note-1');
    expect(previews.first.rawText, 'milk 12');
    expect(previews.first.status, ExtractionPreviewStatus.pending);

    final stored = await repository.getPendingPreviews('note-1');
    expect(stored, hasLength(1));
    expect(stored.first.rawText, 'milk 12');
  });

  test('submitDelta uses createId for preview id', () async {
    final repository = _SyncPreviewStore();
    var counter = 100;
    final pipeline = DefaultRealtimeExtractionPipeline(
      previewRepository: repository,
      createId: () => 'id-${counter++}',
    );

    await pipeline.submitDelta(noteId: 'note-1', rawText: 'test');

    final stored = await repository.getPendingPreviews('note-1');
    expect(stored.first.id, equals('id-100'));
  });
  });
}
