import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/parser/expense_extractor.dart';

void main() {
  group('ExpenseExtractor - 金额提取测试', () {
    final extractor = ExpenseExtractor();

    test('提取 ¥28', () {
      final result = extractor.extractAmount('花费 ¥28');
      expect(result, Decimal.parse('28'));
    });

    test('提取 ¥28.5', () {
      final result = extractor.extractAmount('花费 ¥28.5');
      expect(result, Decimal.parse('28.5'));
    });

    test('提取 35.5元', () {
      final result = extractor.extractAmount('花了35.5元');
      expect(result, Decimal.parse('35.5'));
    });

    test('提取 10块5毛', () {
      final result = extractor.extractAmount('用了10块5毛');
      expect(result, Decimal.parse('10.5'));
    });

    test('提取 10块（无毛）', () {
      final result = extractor.extractAmount('花了10块');
      expect(result, Decimal.parse('10'));
    });

    test('提取纯数字 100', () {
      final result = extractor.extractAmount('100元');
      expect(result, Decimal.parse('100'));
    });

    test('提取纯数字 0.5', () {
      final result = extractor.extractAmount('0.5元');
      expect(result, Decimal.parse('0.5'));
    });

    test('无金额时返回 null', () {
      final result = extractor.extractAmount('这是备忘');
      expect(result, isNull);
    });

    test('无金额只有文字返回 null', () {
      final result = extractor.extractAmount('买水果');
      expect(result, isNull);
    });

    test('提取 5毛（无元）', () {
      final result = extractor.extractAmount('5毛');
      expect(result, isNull); // 因为前面没有数字，无法匹配
    });

    test('提取 3块2', () {
      final result = extractor.extractAmount('3块2');
      expect(result, Decimal.parse('3.2'));
    });

    test('提取数字开头', () {
      final result = extractor.extractAmount('28块');
      expect(result, Decimal.parse('28'));
    });
  });

  group('ExpenseExtractor - 分类匹配测试', () {
    final extractor = ExpenseExtractor();

    test('餐饮分类 - 买菜', () {
      expect(extractor.matchCategory('今天去买菜'), '餐饮');
    });

    test('餐饮分类 - 外卖', () {
      expect(extractor.matchCategory('点外卖'), '餐饮');
    });

    test('餐饮分类 - 水果', () {
      expect(extractor.matchCategory('买水果'), '餐饮');
    });

    test('餐饮分类 - 咖啡', () {
      expect(extractor.matchCategory('喝咖啡'), '餐饮');
    });

    test('交通分类 - 打车', () {
      expect(extractor.matchCategory('打车上班'), '交通');
    });

    test('交通分类 - 加油', () {
      expect(extractor.matchCategory('去加油'), '交通');
    });

    test('交通分类 - 地铁', () {
      expect(extractor.matchCategory('坐地铁'), '交通');
    });

    test('购物分类 - 淘宝', () {
      expect(extractor.matchCategory('淘宝购物'), '购物');
    });

    test('购物分类 - 衣服', () {
      expect(extractor.matchCategory('买衣服'), '购物');
    });

    test('医疗分类 - 医院', () {
      expect(extractor.matchCategory('去医院'), '医疗');
    });

    test('医疗分类 - 药', () {
      expect(extractor.matchCategory('买药'), '医疗');
    });

    test('教育分类 - 学费', () {
      expect(extractor.matchCategory('交学费'), '教育');
    });

    test('教育分类 - 课程', () {
      expect(extractor.matchCategory('上课'), '教育');
    });

    test('居住分类 - 房租', () {
      expect(extractor.matchCategory('交房租'), '居住');
    });

    test('居住分类 - 水电', () {
      expect(extractor.matchCategory('水电费'), '居住');
    });

    test('娱乐分类 - 电影', () {
      expect(extractor.matchCategory('看电影'), '娱乐');
    });

    test('娱乐分类 - 游戏', () {
      expect(extractor.matchCategory('玩游戏'), '娱乐');
    });

    test('无关键词时返回 其他', () {
      expect(extractor.matchCategory('一些其他内容'), '其他');
    });

    test('空文本返回 其他', () {
      expect(extractor.matchCategory(''), '其他');
    });
  });

  group('ExpenseExtractor - hasAmount 测试', () {
    final extractor = ExpenseExtractor();

    test('有金额返回 true - ¥28', () {
      expect(extractor.hasAmount('¥28'), isTrue);
    });

    test('有金额返回 true - 35.5元', () {
      expect(extractor.hasAmount('35.5元'), isTrue);
    });

    test('有金额返回 true - 10块5毛', () {
      expect(extractor.hasAmount('10块5毛'), isTrue);
    });

    test('有金额返回 true - 纯数字', () {
      expect(extractor.hasAmount('100元'), isTrue);
    });

    test('无金额返回 false', () {
      expect(extractor.hasAmount('这是备忘'), isFalse);
    });

    test('无金额只有文字返回 false', () {
      expect(extractor.hasAmount('买水果'), isFalse);
    });

    test('空文本返回 false', () {
      expect(extractor.hasAmount(''), isFalse);
    });
  });
}
