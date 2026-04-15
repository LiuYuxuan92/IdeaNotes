import 'package:equatable/equatable.dart';

enum ExtractionPreviewStatus {
  pending,
  confirmed,
  corrected,
  dismissed,
}

class ExtractionPreview extends Equatable {
  final String id;
  final String noteId;
  final String rawText;
  final String? mergedExtractionJson;
  final ExtractionPreviewStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const ExtractionPreview({
    required this.id,
    required this.noteId,
    required this.rawText,
    required this.mergedExtractionJson,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
  });

  factory ExtractionPreview.fromMap(Map<String, dynamic> map) {
    return ExtractionPreview(
      id: map['id'] as String,
      noteId: map['note_id'] as String,
      rawText: map['raw_text'] as String,
      mergedExtractionJson: map['merged_extraction'] as String?,
      status: ExtractionPreviewStatus.values.byName(map['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      confirmedAt: map['confirmed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['confirmed_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'raw_text': rawText,
      'merged_extraction': mergedExtractionJson,
      'status': status.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'confirmed_at': confirmedAt?.millisecondsSinceEpoch,
    };
  }

  @override
  List<Object?> get props => [
        id,
        noteId,
        rawText,
        mergedExtractionJson,
        status,
        createdAt,
        confirmedAt,
      ];
}
