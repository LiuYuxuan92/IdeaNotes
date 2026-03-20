import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/extraction_schema_parser.dart';

void main() {
  group('ExtractionSchemaParser', () {
    const parser = ExtractionSchemaParser();
    final fallbackContext = ExtractionNoteContext(
      noteId: 'note-1',
      noteCreatedAt: DateTime(2026, 3, 20, 10, 0),
    );

    test('能解析标准 schema 并构建 entries', () {
      final payload = {
        'schema_version': '1.0',
        'note_context': fallbackContext.toMap(),
        'ocr_summary': {
          'full_text': '今天买菜 35 元',
          'line_count': 1,
        },
        'entries': [
          {
            'entry_id': 'entry-1',
            'entry_type': 'expense',
            'domain': 'finance',
            'title': '买菜',
            'raw_text': '今天买菜 35 元',
            'occurred_date': '2026-03-20',
            'amount': {'value': '35', 'currency': 'CNY'},
            'confidence': 0.92,
          },
        ],
      };

      final result = parser.parse(
        jsonEncode(payload),
        fallbackNoteContext: fallbackContext,
        fallbackOcrText: 'fallback text',
      );

      expect(result.schemaVersion, '1.0');
      expect(result.entries.length, 1);
      expect(result.entries.first.entryType, ExtractionEntryType.expense);
      expect(result.entries.first.amount?.value, '35');
      expect(result.warnings, isEmpty);
    });

    test('支持解析 markdown code fence 中的 JSON', () {
      const fenced = '''
```json
{
  "entries": [
    {
      "entry_id": "entry-2",
      "entry_type": "memo",
      "domain": "life",
      "title": "记录",
      "raw_text": "记录一下",
      "occurred_date": "2026-03-20"
    }
  ]
}
```
''';

      final result = parser.parse(
        fenced,
        fallbackNoteContext: fallbackContext,
        fallbackOcrText: '记录一下',
      );

      expect(result.entries.length, 1);
      expect(result.entries.first.title, '记录');
      expect(result.noteContext.noteId, 'note-1');
      expect(result.ocrSummary.fullText, '记录一下');
    });

    test('支持解析 Gemini wrapper 并提取 text payload', () {
      final wrapped = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'entries': [
                      {
                        'entry_id': 'entry-3',
                        'entry_type': 'task',
                        'domain': 'work',
                        'title': '提交评审',
                        'raw_text': '明天提交评审',
                        'occurred_date': '2026-03-21',
                      },
                    ],
                  }),
                },
              ],
            },
          },
        ],
      });

      final result = parser.parse(
        wrapped,
        fallbackNoteContext: fallbackContext,
        fallbackOcrText: '明天提交评审',
      );

      expect(result.entries.length, 1);
      expect(result.entries.first.entryType, ExtractionEntryType.task);
      expect(result.warnings,
          isNot(contains(predicate((ExtractionWarning warning) {
        return warning.code == 'entries_missing';
      }))));
    });

    test('无效 entry 会被跳过并记录 warning', () {
      final payload = {
        'entries': [
          {
            'entry_id': '',
            'entry_type': 'memo',
          },
          {
            'entry_id': 'valid-1',
            'entry_type': 'memo',
            'domain': 'life',
            'title': '有效',
            'raw_text': '有效',
            'occurred_date': '2026-03-20',
          },
        ],
      };

      final result = parser.parse(
        jsonEncode(payload),
        fallbackNoteContext: fallbackContext,
        fallbackOcrText: '',
      );

      expect(result.entries.length, 1);
      expect(result.entries.first.entryId, 'valid-1');
      expect(
        result.warnings
            .any((warning) => warning.code == 'invalid_entry_payload'),
        isTrue,
      );
    });
  });
}
