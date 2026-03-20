import 'dart:convert';

import 'extraction_models.dart';

class ExtractionSchemaParser {
  const ExtractionSchemaParser();

  NormalizedExtractionDocument parse(
    String rawResponse, {
    required ExtractionNoteContext fallbackNoteContext,
    required String fallbackOcrText,
  }) {
    final payload = _extractPayload(rawResponse);
    final schemaVersion = payload['schema_version']?.toString() ?? '1.0';

    final noteContext = _parseNoteContext(
      payload['note_context'],
      fallback: fallbackNoteContext,
    );
    final ocrSummary = _parseOcrSummary(
      payload['ocr_summary'],
      fallbackText: fallbackOcrText,
    );

    final warnings = <ExtractionWarning>[
      ..._parseWarnings(payload['warnings']),
    ];
    final entries = <ExtractedEntry>[];

    final entriesRaw = payload['entries'];
    if (entriesRaw is List) {
      for (final item in entriesRaw) {
        if (item is! Map<String, dynamic>) {
          warnings.add(
            const ExtractionWarning(
              code: 'invalid_entry_shape',
              message: 'AI entry item is not a valid object',
            ),
          );
          continue;
        }

        try {
          entries.add(ExtractedEntry.fromMap(item));
        } catch (error) {
          warnings.add(
            ExtractionWarning(
              code: 'invalid_entry_payload',
              message: error.toString(),
              entryId: item['entry_id']?.toString(),
            ),
          );
        }
      }
    } else {
      warnings.add(
        const ExtractionWarning(
          code: 'entries_missing',
          message: 'AI payload does not contain entries[]',
        ),
      );
    }

    return NormalizedExtractionDocument(
      schemaVersion: schemaVersion,
      noteContext: noteContext,
      ocrSummary: ocrSummary,
      entries: entries,
      warnings: warnings,
      unparsedSegments: _parseUnparsedSegments(payload['unparsed_segments']),
    );
  }

  Map<String, dynamic> _extractPayload(String rawResponse) {
    final decoded = _decodeJsonObject(rawResponse);
    if (decoded.containsKey('candidates')) {
      final inner = _extractFromGeminiWrapper(decoded);
      return _decodeJsonObject(inner);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeJsonObject(String input) {
    final sanitized = _stripMarkdownFence(input.trim());
    final decoded = jsonDecode(sanitized);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI response root must be a JSON object');
    }
    return decoded;
  }

  String _extractFromGeminiWrapper(Map<String, dynamic> wrapper) {
    final candidates = wrapper['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const FormatException('Gemini wrapper contains no candidates');
    }
    final first = candidates.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('Gemini candidate format is invalid');
    }
    final content = first['content'];
    if (content is! Map<String, dynamic>) {
      throw const FormatException('Gemini content format is invalid');
    }
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const FormatException('Gemini content parts are missing');
    }
    for (final part in parts) {
      if (part is Map<String, dynamic> && part['text'] != null) {
        return part['text'].toString();
      }
    }
    throw const FormatException('No text part in Gemini response');
  }

  String _stripMarkdownFence(String input) {
    if (!input.startsWith('```')) {
      return input;
    }

    final lines = input.split('\n');
    if (lines.isEmpty) return input;
    final firstLine = lines.first.trim();
    final lastLine = lines.last.trim();
    if (firstLine.startsWith('```') && lastLine == '```' && lines.length >= 3) {
      return lines.sublist(1, lines.length - 1).join('\n').trim();
    }
    return input;
  }

  ExtractionNoteContext _parseNoteContext(
    Object? raw, {
    required ExtractionNoteContext fallback,
  }) {
    if (raw is! Map<String, dynamic>) {
      return fallback;
    }
    try {
      return ExtractionNoteContext.fromMap(raw);
    } catch (_) {
      return fallback;
    }
  }

  ExtractionOcrSummary _parseOcrSummary(
    Object? raw, {
    required String fallbackText,
  }) {
    if (raw is Map<String, dynamic>) {
      return ExtractionOcrSummary.fromMap(raw);
    }
    return ExtractionOcrSummary(
      fullText: fallbackText,
      lineCount: fallbackText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .length,
    );
  }

  List<ExtractionWarning> _parseWarnings(Object? raw) {
    if (raw is! List) return const [];
    final items = <ExtractionWarning>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      try {
        items.add(ExtractionWarning.fromMap(item));
      } catch (_) {}
    }
    return items;
  }

  List<String> _parseUnparsedSegments(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
