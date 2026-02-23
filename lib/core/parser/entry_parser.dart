import 'package:uuid/uuid.dart';
import '../models/note_entry.dart';
import 'expense_extractor.dart';

class EntryParser {
  static const _uuid = Uuid();
  static final _expenseExtractor = ExpenseExtractor();

  /// 解析文本为 NoteEntry
  static NoteEntry parse(String text) {
    text = text.trim();
    if (text.isEmpty) {
      return _createEntry(NoteEntryType.memo, text, memoText: text);
    }

    // 尝试解析为花费
    final expenseEntry = _tryParseExpense(text);
    if (expenseEntry != null) {
      return expenseEntry;
    }

    // 尝试解析为事项
    final eventEntry = _tryParseEvent(text);
    if (eventEntry != null) {
      return eventEntry;
    }

    // 默认为备忘
    return _createEntry(NoteEntryType.memo, text, memoText: text);
  }

  /// 尝试解析为花费
  static NoteEntry? _tryParseExpense(String text) {
    final amount = _expenseExtractor.extractAmount(text);
    if (amount != null) {
      final category = _expenseExtractor.matchCategory(text);
      // 提取金额后的剩余文本作为描述
      var description = text
          .replaceAll(RegExp(r'¥?\d+\.?\d*\s*元?'), '')
          .replaceAll(RegExp(r'\d+块\d*毛?'), '')
          .trim();
      if (description.isEmpty) {
        description = text;
      }
      
      return _createEntry(
        NoteEntryType.expense,
        text,
        expense: ExpenseRecord(
          amount: amount,
          category: category,
          description: description,
        ),
      );
    }
    return null;
  }

  /// 尝试解析为事项
  static NoteEntry? _tryParseEvent(String text) {
    final date = _parseDate(text);
    if (date != null) {
      // 提取日期后的剩余文本作为标题
      var title = text
          .replaceAll(RegExp(r'明天|后天|大后天'), '')
          .replaceAll(RegExp(r'下周[一二三四五六日]?'), '')
          .replaceAll(RegExp(r'下下周[一二三四五六日]?'), '')
          .replaceAll(RegExp(r'\d+月\d+日'), '')
          .replaceAll(RegExp(r'\d+/\d+'), '')
          .trim();
      
      if (title.isEmpty) {
        title = text;
      }

      return _createEntry(
        NoteEntryType.event,
        text,
        event: EventRecord(
          title: title,
          date: date,
        ),
      );
    }
    return null;
  }

  /// 解析日期
  static DateTime? _parseDate(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 匹配 "明天"
    if (text.contains('明天')) {
      return today.add(const Duration(days: 1));
    }

    // 匹配 "后天"
    if (text.contains('后天')) {
      return today.add(const Duration(days: 2));
    }

    // 匹配 "大后天"
    if (text.contains('大后天')) {
      return today.add(const Duration(days: 3));
    }

    // 匹配 "下周X" 或 "下周"
    final nextWeekMatch = RegExp(r'下周([一二三四五六日])?').firstMatch(text);
    if (nextWeekMatch != null) {
      final dayOfWeek = nextWeekMatch.group(1);
      int daysUntilNextWeek = 7 - now.weekday + 1; // 下周一
      
      if (dayOfWeek != null) {
        final targetDay = _chineseToWeekday(dayOfWeek);
        daysUntilNextWeek = (7 - now.weekday + 1) + (targetDay - 1);
      }
      
      return today.add(Duration(days: daysUntilNextWeek));
    }

    // 匹配 "下下周X" 或 "下下周"
    final nextNextWeekMatch = RegExp(r'下下周([一二三四五六日])?').firstMatch(text);
    if (nextNextWeekMatch != null) {
      final dayOfWeek = nextNextWeekMatch.group(1);
      int daysUntil = 14 - now.weekday + 1; // 下下周一
      
      if (dayOfWeek != null) {
        final targetDay = _chineseToWeekday(dayOfWeek);
        daysUntil = (14 - now.weekday + 1) + (targetDay - 1);
      }
      
      return today.add(Duration(days: daysUntil));
    }

    // 匹配 "X月X日" 或 "X/X"
    final monthDayMatch = RegExp(r'(\d+)月(\d+)日').firstMatch(text);
    if (monthDayMatch != null) {
      final month = int.parse(monthDayMatch.group(1)!);
      final day = int.parse(monthDayMatch.group(2)!);
      var year = now.year;
      if (month < now.month || (month == now.month && day < now.day)) {
        year = now.year + 1;
      }
      return DateTime(year, month, day);
    }

    final slashMatch = RegExp(r'(\d+)/(\d+)').firstMatch(text);
    if (slashMatch != null) {
      final month = int.parse(slashMatch.group(1)!);
      final day = int.parse(slashMatch.group(2)!);
      var year = now.year;
      if (month < now.month || (month == now.month && day < now.day)) {
        year = now.year + 1;
      }
      return DateTime(year, month, day);
    }

    return null;
  }

  /// 中文数字转星期
  static int _chineseToWeekday(String chinese) {
    const map = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
    };
    return map[chinese] ?? 1;
  }

  /// 创建 NoteEntry
  static NoteEntry _createEntry(
    NoteEntryType type,
    String rawText, {
    ExpenseRecord? expense,
    EventRecord? event,
    String? memoText,
  }) {
    return NoteEntry(
      id: _uuid.v4(),
      type: type,
      rawText: rawText,
      expense: expense,
      event: event,
      memoText: memoText,
    );
  }

  /// 解析多行文本
  static List<NoteEntry> parseMultiLine(String text) {
    final lines = text.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    
    return lines.map((line) => parse(line)).toList();
  }
}
