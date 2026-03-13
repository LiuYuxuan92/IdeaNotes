import 'package:equatable/equatable.dart';
import 'note_entry.dart';

class Note extends Equatable {
  final String id;
  final String? notebookId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int>? canvasData;
  final String? snapshotImagePath;
  final String? thumbnailImagePath;
  final String? recognizedText;
  final List<NoteEntry> entries;

  const Note({
    required this.id,
    this.notebookId,
    required this.createdAt,
    required this.updatedAt,
    this.canvasData,
    this.snapshotImagePath,
    this.thumbnailImagePath,
    this.recognizedText,
    this.entries = const [],
  });

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as String,
      notebookId: map['notebook_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      canvasData: map['canvas_data'] as List<int>?,
      snapshotImagePath: map['snapshot_image_path'] as String?,
      thumbnailImagePath: map['thumbnail_image_path'] as String?,
      recognizedText: map['recognized_text'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'notebook_id': notebookId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'canvas_data': canvasData,
      'snapshot_image_path': snapshotImagePath,
      'thumbnail_image_path': thumbnailImagePath,
      'recognized_text': recognizedText,
    };
  }

  Note copyWith({
    String? id,
    String? notebookId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<int>? canvasData,
    String? snapshotImagePath,
    String? thumbnailImagePath,
    String? recognizedText,
    List<NoteEntry>? entries,
  }) {
    return Note(
      id: id ?? this.id,
      notebookId: notebookId ?? this.notebookId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      canvasData: canvasData ?? this.canvasData,
      snapshotImagePath: snapshotImagePath ?? this.snapshotImagePath,
      thumbnailImagePath: thumbnailImagePath ?? this.thumbnailImagePath,
      recognizedText: recognizedText ?? this.recognizedText,
      entries: entries ?? this.entries,
    );
  }

  @override
  List<Object?> get props => [
        id,
        notebookId,
        createdAt,
        updatedAt,
        canvasData,
        snapshotImagePath,
        thumbnailImagePath,
        recognizedText,
        entries,
      ];
}
