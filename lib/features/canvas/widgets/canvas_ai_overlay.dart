import 'package:flutter/material.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';

class CanvasAiOverlay extends StatelessWidget {
  final List<ExtractionPreview> previews;
  final ValueChanged<ExtractionPreview> onConfirm;

  const CanvasAiOverlay({
    super.key,
    required this.previews,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: previews.map((preview) {
        return Card(
          child: ListTile(
            title: Text(preview.rawText),
            trailing: FilledButton(
              onPressed: () => onConfirm(preview),
              child: const Text('确认'),
            ),
          ),
        );
      }).toList(),
    );
  }
}
