import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/parser/entry_parser.dart';
import 'package:idea_notes/core/models/note_entry.dart';

void main() {
  group('EntryParser - 花费解析测试', () {
    test('解析 买菜 35.5 - 识别为花费', () {
      final entry = EntryParser.parse('买菜 35.5');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense, isNotNull);
      expect(entry.expense!.amount, equals(Decimal.parse('35.5')));
      expect(entry.expense!.category, equals('餐饮'));
      expect(entry.rawText, equals('买菜 35.5'));
    });

    test('解析 打车 ¥30元 - 识别为花费', () {
      final entry = EntryParser.parse('打车 ¥30元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense, isNotNull);
      expect(entry.expense!.amount, equals(Decimal.parse('30')));
      expect(entry.expense!.category, equals('交通'));
      expect(entry.rawText, equals('打车 ¥30元'));
    });

    test('解析 ¥100 购物 - 识别为花费', () {
      final entry = EntryParser.parse('购物 ¥100');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense, isNotNull);
      expect(entry.expense!.amount, equals(Decimal.parse('100')));
      expect(entry.expense!.category, equals('购物'));
    });

    test('解析 加油 200元 - 识别为花费', () {
      final entry = EntryParser.parse('加油 200元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('200')));
      expect(entry.expense!.category, equals('交通'));
    });

    test('解析 买药花了50元 - 识别为花费', () {
      final entry = EntryParser.parse('买药花了50元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('50')));
      expect(entry.expense!.category, equals('医疗'));
    });

    test('解析 10块5毛 - 识别为花费', () {
      final entry = EntryParser.parse('花了10块5毛');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('10.5')));
    });

    test('解析 3块2 - 识别为花费', () {
      final entry = EntryParser.parse('3块2');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('3.2')));
    });

    test('解析 空金额不识别为花费', () {
      final entry = EntryParser.parse('买水果');

      expect(entry.type, equals(NoteEntryType.memo));
    });
  });

  group('EntryParser - 事项解析测试', () {
    test('解析 明天去医院 - 识别为事项', () {
      final entry = EntryParser.parse('明天去医院');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.title, equals('去医院'));

      // 验证日期是明天
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(entry.event!.date!.year, equals(tomorrow.year));
      expect(entry.event!.date!.month, equals(tomorrow.month));
      expect(entry.event!.date!.day, equals(tomorrow.day));
    });

    test('解析 下周三开会 - 识别为事项', () {
      final entry = EntryParser.parse('下周三开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.title, equals('开会'));
      expect(entry.event!.date, isNotNull);
    });

    test('解析 后天去旅行 - 识别为事项', () {
      final entry = EntryParser.parse('后天去旅行');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);

      // 验证日期是后天
      final now = DateTime.now();
      final dayAfterTomorrow = DateTime(now.year, now.month, now.day + 2);
      expect(entry.event!.date!.year, equals(dayAfterTomorrow.year));
      expect(entry.event!.date!.month, equals(dayAfterTomorrow.month));
      expect(entry.event!.date!.day, equals(dayAfterTomorrow.day));
    });

    test('解析 大后天考试 - 识别为事项', () {
      final entry = EntryParser.parse('大后天考试');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.date, isNotNull);

      // 验证日期是大后天
      final now = DateTime.now();
      final dayAfter3Days = DateTime(now.year, now.month, now.day + 3);
      expect(entry.event!.date!.day, equals(dayAfter3Days.day));
    });

    test('解析 下周五看电影 - 识别为事项', () {
      final entry = EntryParser.parse('下周五看电影');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('看电影'));
      expect(entry.event!.date, isNotNull);
    });

    test('解析 下周去开会 - 识别为事项（无具体星期）', () {
      final entry = EntryParser.parse('下周去开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('去开会'));
      expect(entry.event!.date, isNotNull);
    });

    test('解析 记得买牛奶 - 任务关键词识别为事项', () {
      final entry = EntryParser.parse('记得买牛奶');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.title, equals('买牛奶'));
    });

    test('解析 别忘了交电费 - 任务关键词识别为事项', () {
      final entry = EntryParser.parse('别忘了交电费');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.title, equals('交电费'));
    });

    test('解析 需要买菜 - 任务关键词但无金额识别为事项', () {
      final entry = EntryParser.parse('需要买菜');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
    });

    test('解析 提醒我开会 - 任务关键词识别为事项', () {
      final entry = EntryParser.parse('提醒我开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
    });

    test('解析 不要忘交作业 - 任务关键词识别为事项', () {
      final entry = EntryParser.parse('不要忘交作业');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
    });

    test('解析 费用要100元 - 含金额不触发单字要', () {
      final entry = EntryParser.parse('费用要100元');

      // 有金额，应识别为花费而非事项
      expect(entry.type, equals(NoteEntryType.expense));
    });

    test('解析 周三开会 - 本周周三识别为事项', () {
      final entry = EntryParser.parse('周三开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.date, isNotNull);
      expect(entry.event!.date!.weekday, equals(3)); // 3 = 周三
    });

    test('解析 周五聚餐 - 本周周五识别为事项', () {
      final entry = EntryParser.parse('周五聚餐');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.date, isNotNull);
      expect(entry.event!.date!.weekday, equals(5)); // 5 = 周五
    });

    test('解析 下周三开会 - 下周周三不被本周匹配', () {
      final entry = EntryParser.parse('下周三开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event, isNotNull);
      expect(entry.event!.date, isNotNull);
      // 下周三与本周三不同
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final daysUntilNextWeekWed = (7 - now.weekday + 1) + (3 - 1);
      final expectedDate = today.add(Duration(days: daysUntilNextWeekWed));
      expect(entry.event!.date!.day, equals(expectedDate.day));
    });
  });

  group('EntryParser - 备忘解析测试', () {
    test('解析 天气很好 - 识别为备忘', () {
      final entry = EntryParser.parse('天气很好');

      expect(entry.type, equals(NoteEntryType.memo));
      expect(entry.memoText, equals('天气很好'));
    });

    test('解析 一些普通文字 - 识别为备忘', () {
      final entry = EntryParser.parse('今天心情不错');

      expect(entry.type, equals(NoteEntryType.memo));
      expect(entry.memoText, equals('今天心情不错'));
    });

    test('解析 无内容 - 识别为空备忘', () {
      final entry = EntryParser.parse('');

      expect(entry.type, equals(NoteEntryType.memo));
      expect(entry.rawText, equals(''));
    });

    test('解析 纯空格 - 识别为空备忘', () {
      final entry = EntryParser.parse('   ');

      expect(entry.type, equals(NoteEntryType.memo));
    });
  });

  group('EntryParser - 多行解析测试', () {
    test('解析多行文本 - 包含花费、事项、备忘', () {
      final text = '''买菜 35.5
明天去医院
天气很好''';

      final entries = EntryParser.parseMultiLine(text);

      expect(entries.length, equals(3));

      // 第一行：花费
      expect(entries[0].type, equals(NoteEntryType.expense));
      expect(entries[0].expense!.amount, equals(Decimal.parse('35.5')));
      expect(entries[0].expense!.category, equals('餐饮'));

      // 第二行：事项
      expect(entries[1].type, equals(NoteEntryType.event));
      expect(entries[1].event!.title, equals('去医院'));

      // 第三行：备忘
      expect(entries[2].type, equals(NoteEntryType.memo));
      expect(entries[2].memoText, equals('天气很好'));
    });

    test('解析多行文本 - 包含空行', () {
      final text = '''买菜 35.5

明天去医院

天气很好''';

      final entries = EntryParser.parseMultiLine(text);

      // 应该跳过空行，只有3条记录
      expect(entries.length, equals(3));
    });

    test('解析多行文本 - 只有空行', () {
      final text = '''

''';

      final entries = EntryParser.parseMultiLine(text);

      expect(entries.length, equals(0));
    });

    test('解析多行文本 - 纯空格行应跳过', () {
      final text = '''买菜 35.5

明天去医院''';

      final entries = EntryParser.parseMultiLine(text);

      expect(entries.length, equals(2));
    });
  });

  group('EntryParser - 空行跳过测试', () {
    test('空行应创建空备忘', () {
      final entry = EntryParser.parse('');

      expect(entry.type, equals(NoteEntryType.memo));
    });

    test('纯空格应创建空备忘', () {
      final entry = EntryParser.parse('  ');

      expect(entry.type, equals(NoteEntryType.memo));
    });

    test('多行解析跳过空行', () {
      final entries = EntryParser.parseMultiLine('a\n\nb');

      expect(entries.length, equals(2));
    });
  });

  group('EntryParser - 边界情况测试', () {
    test('带小数点的金额 - 0.5元', () {
      final entry = EntryParser.parse('买咖啡 0.5元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('0.5')));
    });

    test('大金额 - 10000元', () {
      final entry = EntryParser.parse('买电脑 10000元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('10000')));
    });

    test('无空格连续文字 - 明天去医院', () {
      final entry = EntryParser.parse('明天去医院');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('去医院'));
    });

    test('日期格式 - 5月20日', () {
      final entry = EntryParser.parse('5月20日开会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('开会'));
      expect(entry.event!.date!.month, equals(5));
      expect(entry.event!.date!.day, equals(20));
    });

    test('日期格式 - 12/25', () {
      final entry = EntryParser.parse('12/25聚会');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('聚会'));
      expect(entry.event!.date!.month, equals(12));
      expect(entry.event!.date!.day, equals(25));
    });

    test('下下周周一 - 下下周上课', () {
      final entry = EntryParser.parse('下下周上课');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('上课'));
      expect(entry.event!.date, isNotNull);
    });

    test('下下周三是 - 下下周考试', () {
      final entry = EntryParser.parse('下周三考试');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('考试'));
    });

    test('金额描述包含文字 - 花了100块吃饭', () {
      final entry = EntryParser.parse('花了100块吃饭');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('100')));
    });

    test('特殊字符 - 打车费30元', () {
      final entry = EntryParser.parse('打车费30元');

      expect(entry.type, equals(NoteEntryType.expense));
      expect(entry.expense!.amount, equals(Decimal.parse('30')));
    });

    test('事项无标题 - 明天', () {
      final entry = EntryParser.parse('明天');

      expect(entry.type, equals(NoteEntryType.event));
      expect(entry.event!.title, equals('明天'));
    });
  });
}
