class ParsedClockTime {
  final int hour;
  final int minute;

  const ParsedClockTime({
    required this.hour,
    required this.minute,
  });
}

class EntryTextRules {
  static final RegExp vaccinationKeywordPattern = RegExp(r'疫苗|接种|打针');
  static final RegExp medicationKeywordPattern = RegExp(
    r'吃药|用药|药片|药丸|退烧药|感冒药|拿药|取药|开药',
  );
  static final RegExp digestiveKeywordPattern = RegExp(
    r'拉屎|便便|大便|排便|腹泻|拉肚子|便秘|拉臭臭',
  );
  static final RegExp healthKeywordPattern = RegExp(
    r'宝宝|孩子|小孩|儿子|女儿|疫苗|接种|打针|复查|体检|医院|就诊|门诊|诊所|发烧|咳嗽|吃药|用药|药店|拿药|取药|开药|拉屎|便便|大便|排便|腹泻|拉肚子|便秘|拉臭臭',
  );
  static final RegExp babyKeywordPattern = RegExp(r'宝宝|孩子|小孩|儿子|女儿');

  static final RegExp expenseVerbPattern = RegExp(
    r'花了?|花费|花销|用了?|消费|支出|付款|付了|买了?|报销',
  );
  static final RegExp expenseCategoryKeywordPattern = RegExp(
    r'买菜|午饭|晚饭|早饭|外卖|水果|零食|饮料|咖啡|奶茶|打车|加油|停车|公交|地铁|高铁|机票|淘宝|京东|衣服|鞋|日用品|购物|医院|药|药店|看病|体检|学费|书|课程|培训|上课|房租|水电|物业|维修|电影|游戏|KTV|旅游',
  );

  static final RegExp reminderKeywordPattern = RegExp(
    r'记得|需要|别忘了|不要忘|别忘|提醒|安排|待办',
  );
  static final RegExp actionKeywordPattern = RegExp(
    r'去|开会|开药|拿药|取药|复查|体检|买|交|上课|处理|办理|看|检查|接种|打疫苗|接娃|送娃|办',
  );
  static final RegExp futureRelativePattern = RegExp(
    r'大后天|后天|明天|下下周|下周|(?<!下)周[一二三四五六日天]|今晚',
  );
  static final RegExp todayPattern = RegExp(r'今天|今日|今早|今晨|今晚');
  static final RegExp pastPattern = RegExp(r'昨天|前天|昨晚');
  static final RegExp timeOfDayPattern = RegExp(
    r'凌晨|早上|上午|中午|下午|傍晚|晚上|今晚',
  );
  static final RegExp completionPattern = RegExp(
    r'已经|已|完成|做完|办完|结束|打了|接种了|吃了|用了|买了|去了|看了|复查了|检查了|花了|拉了|拉屎了|排便了|大便了',
  );

  static bool hasVaccinationKeyword(String text) =>
      vaccinationKeywordPattern.hasMatch(text);

  static bool hasMedicationKeyword(String text) =>
      medicationKeywordPattern.hasMatch(text);

  static bool hasDigestiveKeyword(String text) =>
      digestiveKeywordPattern.hasMatch(text);

  static bool hasHealthKeyword(String text) => healthKeywordPattern.hasMatch(text);

  static bool hasBabyKeyword(String text) => babyKeywordPattern.hasMatch(text);

  static bool hasExpenseVerb(String text) => expenseVerbPattern.hasMatch(text);

  static bool hasExpenseCategoryKeyword(String text) =>
      expenseCategoryKeywordPattern.hasMatch(text);

  static bool hasExpenseContext(String text) =>
      hasExpenseVerb(text) || hasExpenseCategoryKeyword(text);

  static bool hasReminderKeyword(String text) =>
      reminderKeywordPattern.hasMatch(text);

  static bool hasActionKeyword(String text) => actionKeywordPattern.hasMatch(text);

  static bool hasFutureRelativeCue(String text) =>
      futureRelativePattern.hasMatch(text);

  static bool hasTodayCue(String text) => todayPattern.hasMatch(text);

  static bool hasPastCue(String text) => pastPattern.hasMatch(text);

  static bool hasTimeOfDayCue(String text) => timeOfDayPattern.hasMatch(text);

  static bool hasCompletionCue(String text) =>
      completionPattern.hasMatch(text);

  static ParsedClockTime? extractClockTime(String text) {
    final colonMatch = RegExp(r'(?<!\d)(\d{1,2})[:：](\d{1,2})(?!\d)')
        .firstMatch(text);
    if (colonMatch != null) {
      final hour = int.parse(colonMatch.group(1)!);
      final minute = int.parse(colonMatch.group(2)!);
      if (_isValidClockTime(hour, minute)) {
        return _applyTimeQualifier(
          text,
          ParsedClockTime(hour: hour, minute: minute),
        );
      }
    }

    final pointMatch =
        RegExp(r'(?<!\d)(\d{1,2})\s*(?:点|时)(半|(\d{1,2})分?)?(?!\d)')
            .firstMatch(text);
    if (pointMatch != null) {
      final hour = int.parse(pointMatch.group(1)!);
      final minuteGroup = pointMatch.group(2);
      final minute = minuteGroup == null
          ? 0
          : minuteGroup == '半'
              ? 30
              : int.parse(pointMatch.group(3)!);
      if (_isValidClockTime(hour, minute)) {
        return _applyTimeQualifier(
          text,
          ParsedClockTime(hour: hour, minute: minute),
        );
      }
    }

    return null;
  }

  static bool hasExplicitTime(String text) => extractClockTime(text) != null;

  static ParsedClockTime _applyTimeQualifier(
    String text,
    ParsedClockTime time,
  ) {
    final normalized = text.trim();
    var hour = time.hour;

    if ((normalized.contains('下午') ||
            normalized.contains('晚上') ||
            normalized.contains('傍晚') ||
            normalized.contains('今晚')) &&
        hour < 12) {
      hour += 12;
    } else if (normalized.contains('中午') && hour < 11) {
      hour += 12;
    } else if (normalized.contains('凌晨') && hour == 12) {
      hour = 0;
    }

    return ParsedClockTime(hour: hour, minute: time.minute);
  }

  static bool _isValidClockTime(int hour, int minute) {
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
  }
}
