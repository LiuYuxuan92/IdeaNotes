import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/entry_merge_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';

void main() {
  group('EntryMergeService', () {
    const service = EntryMergeService();

    test('当 rule 和 ai 指向同一事实时会合并并补全字段', () {
      final aiEntry = ExtractedEntry(
        entryId: 'ai-1',
        entryType: ExtractionEntryType.expense,
        domain: 'finance',
        title: '买菜',
        rawText: '买菜 35 元',
        occurredDate: DateTime(2026, 3, 20),
        confidence: 0.80,
        tags: const ['家庭'],
      );

      final ruleEntry = ExtractedEntry(
        entryId: 'rule-1',
        entryType: ExtractionEntryType.expense,
        domain: 'finance',
        title: '买菜',
        rawText: '买菜 35 元',
        occurredDate: DateTime(2026, 3, 20),
        amount: const ExtractionAmount(value: '35.00'),
        category: const ExtractionCategory(l1: '餐饮'),
        confidence: 0.65,
        tags: const ['日常', '家庭'],
      );

      final merged = service.merge(
        ruleEntries: [ruleEntry],
        aiEntries: [aiEntry],
      );

      expect(merged.length, 1);
      expect(merged.first.amount?.value, '35.00');
      expect(merged.first.category?.l1, '餐饮');
      expect(merged.first.tags.toSet(), {'家庭', '日常'});
      expect(merged.first.confidence, 0.80);
    });

    test('rule 独有事实会被保留', () {
      final ruleEntry = ExtractedEntry(
        entryId: 'rule-2',
        entryType: ExtractionEntryType.task,
        domain: 'work',
        title: '提交周报',
        rawText: '今天提交周报',
        occurredDate: DateTime(2026, 3, 20),
      );

      final merged = service.merge(
        ruleEntries: [ruleEntry],
        aiEntries: const [],
      );

      expect(merged.length, 1);
      expect(merged.first.entryId, 'rule-2');
      expect(merged.first.entryType, ExtractionEntryType.task);
    });

    test('会按日期倒序输出结果', () {
      final oldEntry = ExtractedEntry(
        entryId: 'old',
        entryType: ExtractionEntryType.memo,
        domain: 'life',
        title: '旧记录',
        rawText: '旧记录',
        occurredDate: DateTime(2026, 3, 1),
      );
      final newEntry = ExtractedEntry(
        entryId: 'new',
        entryType: ExtractionEntryType.memo,
        domain: 'life',
        title: '新记录',
        rawText: '新记录',
        occurredDate: DateTime(2026, 3, 21),
      );

      final merged = service.merge(
        ruleEntries: [oldEntry],
        aiEntries: [newEntry],
      );

      expect(merged.length, 2);
      expect(merged.first.entryId, 'new');
      expect(merged.last.entryId, 'old');
    });
  });
}
