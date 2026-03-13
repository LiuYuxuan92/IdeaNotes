import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';

void main() {
  group('Note model', () {
    test('fromMap 能正确读取 thumbnail_image_path', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final note = Note.fromMap({
        'id': 'note-1',
        'notebook_id': 'default-notebook',
        'created_at': now,
        'updated_at': now,
        'canvas_data': null,
        'snapshot_image_path': '/tmp/snapshot.png',
        'thumbnail_image_path': '/tmp/thumbnail.png',
        'recognized_text': 'hello',
      });

      expect(note.id, 'note-1');
      expect(note.snapshotImagePath, '/tmp/snapshot.png');
      expect(note.thumbnailImagePath, '/tmp/thumbnail.png');
      expect(note.recognizedText, 'hello');
    });

    test('toMap 会保留 thumbnail_image_path', () {
      final note = Note(
        id: 'note-2',
        notebookId: 'default-notebook',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        snapshotImagePath: '/tmp/snapshot-2.png',
        thumbnailImagePath: '/tmp/thumbnail-2.png',
        recognizedText: 'world',
      );

      final map = note.toMap();
      expect(map['thumbnail_image_path'], '/tmp/thumbnail-2.png');
      expect(map['snapshot_image_path'], '/tmp/snapshot-2.png');
      expect(map['recognized_text'], 'world');
    });
  });
}
