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

  /// 任务关键词（明确的多字关键词）
  static final _clearTaskKeywords = ['记得', '需要', '别忘了', '不要忘', '别忘', '提醒'];

  /// 尝试解析为事项
  static NoteEntry? _tryParseEvent(String text) {
    final date = _parseDate(text);

    // 检测明确的多字任务关键词
    final hasClearKeyword = _clearTaskKeywords.any((kw) => text.contains(kw));

    // 单字"要"只在行首或标点后才触发（避免"费用要xxx"误匹配）
    final hasSingleYao = RegExp(r'(^|[，。！？、])要').hasMatch(text);

    final hasTaskKeyword = hasClearKeyword || hasSingleYao;

    if (date != null || hasTaskKeyword) {
      // 提取日期和关键词后的剩余文本作为标题
      var title = text
          .replaceAll(RegExp(r'大后天|后天|明天'), '')
          .replaceAll(RegExp(r'下下周[一二三四五六日]?'), '')
          .replaceAll(RegExp(r'下周[一二三四五六日]?'), '')
          .replaceAll(RegExp(r'(?<!下)周[一二三四五六日]'), '')
          .replaceAll(RegExp(r'\d+月\d+日'), '')
          .replaceAll(RegExp(r'\d+/\d+'), '')
          .replaceAll(RegExp(r'记得|需要|别忘了|不要忘|别忘|提醒'), '')
          .replaceAll(RegExp(r'(^|[，。！？、])要'), r'\1')
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

    // 匹配 "大后天"（必须在"后天"之前检查）
    if (text.contains('大后天')) {
      return today.add(const Duration(days: 3));
    }

    // 匹配 "后天"
    if (text.contains('后天')) {
      return today.add(const Duration(days: 2));
    }

    // 匹配 "明天"
    if (text.contains('明天')) {
      return today.add(const Duration(days: 1));
    }

    // 匹配 "下下周X" 或 "下下周"（必须在"下周"之前检查，否则"下下周"会被"下周"先匹配）
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

    // 匹配"周X"（本周，不含"下周"前缀）
    final thisWeekMatch = RegExp(r'(?<!下)周([一二三四五六日])').firstMatch(text);
    if (thisWeekMatch != null) {
      final dayOfWeek = thisWeekMatch.group(1)!;
      final targetDay = _chineseToWeekday(dayOfWeek);
      int daysUntil = targetDay - now.weekday;
      if (daysUntil <= 0) daysUntil += 7; // 如果已过，取下周同一天
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
