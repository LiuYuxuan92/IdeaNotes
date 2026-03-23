import 'package:uuid/uuid.dart';
import '../models/note_entry.dart';
import 'expense_extractor.dart';
import 'entry_text_rules.dart';

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

    // 尝试解析为待办
    final eventEntry = _tryParseEvent(text);
    if (eventEntry != null) {
      return eventEntry;
    }

    // 尝试解析为健康记录
    final healthEntry = _tryParseHealth(text);
    if (healthEntry != null) {
      return healthEntry;
    }

    // 默认为记录
    return _createEntry(NoteEntryType.memo, text, memoText: text);
  }

  /// 尝试解析为花费
  static NoteEntry? _tryParseExpense(String text) {
    final amount = _expenseExtractor.extractAmount(text);
    if (amount != null) {
      final category = _expenseExtractor.matchCategory(text);
      var description = text
          .replaceAll(
            RegExp(
              r'(?:花了?|花费|花销|用了?|消费|支出|付款|付了|买了?|报销)\s*',
            ),
            '',
          )
          .replaceAll(RegExp(r'¥?\s*\d+\.?\d*\s*元?'), '')
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

  /// 尝试解析为待办
  static NoteEntry? _tryParseEvent(String text) {
    final temporal = _parseTemporalInfo(text);

    // 检测明确的多字任务关键词
    final hasClearKeyword = _clearTaskKeywords.any((kw) => text.contains(kw));

    // 单字"要"只在行首或标点后才触发（避免"费用要xxx"误匹配）
    final hasSingleYao = RegExp(r'(^|[，。！？、])要').hasMatch(text);

    final hasTaskKeyword = hasClearKeyword || hasSingleYao;

    final hasFutureCue = EntryTextRules.hasFutureRelativeCue(text) ||
        (temporal.date != null && _isAfterDay(temporal.date!, temporal.today));
    final hasSameDayScheduleCue = (EntryTextRules.hasTodayCue(text) ||
            EntryTextRules.hasTimeOfDayCue(text) ||
            temporal.hasExplicitTime) &&
        EntryTextRules.hasActionKeyword(text) &&
        !EntryTextRules.hasCompletionCue(text);
    final hasStandaloneExplicitTime = temporal.hasExplicitTime &&
        (EntryTextRules.hasActionKeyword(text) || hasTaskKeyword) &&
        !EntryTextRules.hasCompletionCue(text);

    if (hasTaskKeyword ||
        hasFutureCue ||
        hasSameDayScheduleCue ||
        hasStandaloneExplicitTime) {
      var title = _cleanEventTitle(text);
      title = title.isEmpty ? text : title;

      return _createEntry(
        NoteEntryType.event,
        text,
        event: EventRecord(
          title: title,
          date: temporal.date,
        ),
      );
    }
    return null;
  }

  /// 尝试解析为健康记录
  static NoteEntry? _tryParseHealth(String text) {
    if (!_looksLikeHealthRecord(text)) {
      return null;
    }

    final memoText = _cleanHealthText(text);
    return _createEntry(
      NoteEntryType.health,
      text,
      memoText: memoText.isEmpty ? text : memoText,
    );
  }

  /// 解析日期
  static DateTime? _parseDate(
    String text, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);

    if (RegExp(r'今天|今日|今早|今晨|今晚').hasMatch(text)) {
      return today;
    }

    if (text.contains('昨天') || text.contains('昨晚')) {
      return today.subtract(const Duration(days: 1));
    }

    if (text.contains('前天')) {
      return today.subtract(const Duration(days: 2));
    }

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
      int daysUntil = 14 - current.weekday + 1; // 下下周一

      if (dayOfWeek != null) {
        final targetDay = _chineseToWeekday(dayOfWeek);
        daysUntil = (14 - current.weekday + 1) + (targetDay - 1);
      }

      return today.add(Duration(days: daysUntil));
    }

    // 匹配 "下周X" 或 "下周"
    final nextWeekMatch = RegExp(r'下周([一二三四五六日])?').firstMatch(text);
    if (nextWeekMatch != null) {
      final dayOfWeek = nextWeekMatch.group(1);
      int daysUntilNextWeek = 7 - current.weekday + 1; // 下周一

      if (dayOfWeek != null) {
        final targetDay = _chineseToWeekday(dayOfWeek);
        daysUntilNextWeek = (7 - current.weekday + 1) + (targetDay - 1);
      }

      return today.add(Duration(days: daysUntilNextWeek));
    }

    // 匹配"周X"（本周，不含"下周"前缀）
    final thisWeekMatch = RegExp(r'(?<!下)周([一二三四五六日])').firstMatch(text);
    if (thisWeekMatch != null) {
      final dayOfWeek = thisWeekMatch.group(1)!;
      final targetDay = _chineseToWeekday(dayOfWeek);
      int daysUntil = targetDay - current.weekday;
      if (daysUntil <= 0) daysUntil += 7; // 如果已过，取下周同一天
      return today.add(Duration(days: daysUntil));
    }

    // 匹配 "X月X日" 或 "X/X"
    final monthDayMatch = RegExp(r'(\d+)月(\d+)日').firstMatch(text);
    if (monthDayMatch != null) {
      final month = int.parse(monthDayMatch.group(1)!);
      final day = int.parse(monthDayMatch.group(2)!);
      var year = current.year;
      if (month < current.month ||
          (month == current.month && day < current.day)) {
        year = current.year + 1;
      }
      return DateTime(year, month, day);
    }

    final slashMatch = RegExp(r'(\d+)/(\d+)').firstMatch(text);
    if (slashMatch != null) {
      final month = int.parse(slashMatch.group(1)!);
      final day = int.parse(slashMatch.group(2)!);
      var year = current.year;
      if (month < current.month ||
          (month == current.month && day < current.day)) {
        year = current.year + 1;
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

  static _TemporalInfo _parseTemporalInfo(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final baseDate = _parseDate(text, now: now);
    final clockTime = EntryTextRules.extractClockTime(text);

    var date = baseDate;
    if (date == null &&
        (EntryTextRules.hasTodayCue(text) || clockTime != null) &&
        !EntryTextRules.hasPastCue(text)) {
      date = today;
    }

    if (date != null && clockTime != null) {
      date = DateTime(
        date.year,
        date.month,
        date.day,
        clockTime.hour,
        clockTime.minute,
      );
    }

    return _TemporalInfo(
      today: today,
      date: date,
      hasExplicitTime: clockTime != null,
    );
  }

  static String _cleanEventTitle(String text) {
    return text
        .replaceAll(
          RegExp(r'大后天|后天|明天|今天|今日|今早|今晨|今晚|昨天|前天|昨晚'),
          '',
        )
        .replaceAll(RegExp(r'下下周[一二三四五六日]?'), '')
        .replaceAll(RegExp(r'下周[一二三四五六日]?'), '')
        .replaceAll(RegExp(r'(?<!下)周[一二三四五六日]'), '')
        .replaceAll(RegExp(r'\d+月\d+日'), '')
        .replaceAll(RegExp(r'\d+/\d+'), '')
        .replaceAll(RegExp(r'(?<!\d)\d{1,2}[:：]\d{1,2}(?!\d)'), '')
        .replaceAll(
            RegExp(r'(?<!\d)\d{1,2}\s*(?:点|时)(?:半|\d{1,2}分?)?(?!\d)'), '')
        .replaceAll(RegExp(r'凌晨|早上|上午|中午|下午|傍晚|晚上'), '')
        .replaceAll(RegExp(r'记得|需要|别忘了|不要忘|别忘|提醒'), '')
        .replaceAll(RegExp(r'(^|[，。！？、])要'), r'\1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanHealthText(String text) {
    return text
        .replaceAll(RegExp(r'今天|今日|今早|今晨|昨晚|昨天|前天'), '')
        .replaceAll(RegExp(r'凌晨|早上|上午|中午|下午|傍晚|晚上|今晚'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _looksLikeHealthRecord(String text) {
    if (EntryTextRules.hasHealthKeyword(text)) {
      return true;
    }

    if (EntryTextRules.hasDietRecordKeyword(text)) {
      return true;
    }

    return false;
  }

  static bool _isAfterDay(DateTime value, DateTime today) {
    final day = DateTime(value.year, value.month, value.day);
    return day.isAfter(today);
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
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return lines.map((line) => parse(line)).toList();
  }
}

class _TemporalInfo {
  final DateTime today;
  final DateTime? date;
  final bool hasExplicitTime;

  const _TemporalInfo({
    required this.today,
    required this.date,
    required this.hasExplicitTime,
  });
}
