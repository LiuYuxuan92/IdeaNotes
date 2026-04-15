import 'dart:async';

import 'package:idea_notes/core/storage/extraction_preview_repository.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';

class DefaultRealtimeExtractionPipeline {
  final PreviewStore previewRepository;
  final String Function() createId;
  late final StreamController<ExtractionPreview> _controller;

  DefaultRealtimeExtractionPipeline({
    required this.previewRepository,
    required this.createId,
  }) {
    _controller = StreamController<ExtractionPreview>.broadcast(sync: true);
  }

  Stream<ExtractionPreview> get previews => _controller.stream;

  Future<ExtractionPreview> submitDelta({
    required String noteId,
    required String rawText,
  }) async {
    final preview = ExtractionPreview(
      id: createId(),
      noteId: noteId,
      rawText: rawText,
      status: ExtractionPreviewStatus.pending,
      createdAt: DateTime.now(),
      mergedExtractionJson: rawText,
    );

    // New notes may not exist in the database yet, so preview persistence is
    // best-effort. The UI should still receive the preview even if storage
    // fails and the note has not been saved.
    try {
      await previewRepository.upsertPreview(preview);
    } catch (_) {}

    _controller.add(preview);
    return preview;
  }

  void dispose() {
    _controller.close();
  }
}
