import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/query/entry_query.dart';

void main() {
  group('EntryQuery.copyWith', () {
    test('keeps original nullable fields when not provided', () {
      final original = EntryQuery(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        keyword: '疫苗',
        confirmedOnly: true,
        limit: 20,
        offset: 10,
      );

      final copied = original.copyWith(entryTypes: {'expense'});

      expect(copied.from, original.from);
      expect(copied.to, original.to);
      expect(copied.keyword, '疫苗');
      expect(copied.confirmedOnly, isTrue);
      expect(copied.limit, 20);
      expect(copied.offset, 10);
      expect(copied.entryTypes, {'expense'});
    });

    test('can clear nullable fields by setting null explicitly', () {
      final original = EntryQuery(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        keyword: '花费',
        confirmedOnly: false,
        limit: 50,
        offset: 5,
      );

      final copied = original.copyWith(
        from: null,
        to: null,
        keyword: null,
        confirmedOnly: null,
        limit: null,
        offset: null,
      );

      expect(copied.from, isNull);
      expect(copied.to, isNull);
      expect(copied.keyword, isNull);
      expect(copied.confirmedOnly, isNull);
      expect(copied.limit, isNull);
      expect(copied.offset, isNull);
    });
  });
}
