import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note_entry.dart';

void main() {
  group('NoteEntry.fromMap', () {
    test('能正确还原 expense entry', () {
      final entry = NoteEntry.fromMap(const {
        'id': 'entry-expense',
        'type': 'expense',
        'raw_text': '买菜 35.5',
        'amount': '35.5',
        'category': '餐饮',
      });

      expect(entry.type, NoteEntryType.expense);
      expect(entry.expense, isNotNull);
      expect(entry.expense!.amount, Decimal.parse('35.5'));
      expect(entry.expense!.category, '餐饮');
    });

    test('能正确还原 event entry', () {
      final millis = DateTime(2026, 3, 15).millisecondsSinceEpoch;
      final entry = NoteEntry.fromMap({
        'id': 'entry-event',
        'type': 'event',
        'raw_text': '明天开会',
        'event_title': '开会',
        'event_date': millis,
        'is_completed': 1,
      });

      expect(entry.type, NoteEntryType.event);
      expect(entry.event, isNotNull);
      expect(entry.event!.title, '开会');
      expect(entry.event!.date, DateTime.fromMillisecondsSinceEpoch(millis));
      expect(entry.event!.isCompleted, isTrue);
    });

    test('能正确还原 memo entry', () {
      final entry = NoteEntry.fromMap(const {
        'id': 'entry-memo',
        'type': 'memo',
        'raw_text': '记一下灵感',
        'memo_text': '记一下灵感',
      });

      expect(entry.type, NoteEntryType.memo);
      expect(entry.memoText, '记一下灵感');
    });
  });
}
