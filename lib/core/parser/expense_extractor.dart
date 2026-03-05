import 'package:decimal/decimal.dart';

class ExpenseExtractor {
  // 分类关键词映射
  static const List<Map<String, dynamic>> categoryKeywords = [
    {'category': '餐饮', 'keywords': ['买菜', '午饭', '晚饭', '早饭', '外卖', '水果', '零食', '饮料', '咖啡', '奶茶']},
    {'category': '交通', 'keywords': ['打车', '加油', '停车', '公交', '地铁', '高铁', '机票']},
    {'category': '购物', 'keywords': ['淘宝', '京东', '衣服', '鞋', '日用品']},
    {'category': '医疗', 'keywords': ['医院', '药', '看病', '体检']},
    {'category': '教育', 'keywords': ['学费', '书', '课程', '培训']},
    {'category': '居住', 'keywords': ['房租', '水电', '物业', '维修']},
    {'category': '娱乐', 'keywords': ['电影', '游戏', 'KTV', '旅游']},
  ];

  /// 从文本中提取金额，返回 null 表示未找到金额
  Decimal? extractAmount(String text) {
    // 匹配 X块Y毛 格式（前面必须有空格、汉字、或者在开头）
    final kuaiRegex = RegExp(r'(?<=[^\d\s]|\s)(\d+)块(\d*)毛?');
    final kuaiMatch = kuaiRegex.firstMatch(text);
    if (kuaiMatch != null) {
      final yuan = kuaiMatch.group(1)!;
      final jiao = kuaiMatch.group(2) ?? '';
      if (jiao.isEmpty) {
        return Decimal.parse(yuan);
      }
      return Decimal.parse('$yuan.$jiao');
    }

    // 匹配 ¥X.XX 或 X.XX元（前面必须有空格、汉字、或者在开头）
    final amountRegex = RegExp(r'(?<=[^\d\s]|\s)¥?(\d+\.?\d*)\s*元?');
    final amountMatch = amountRegex.firstMatch(text);
    if (amountMatch != null) {
      var matched = amountMatch.group(1)!;
      matched = matched.replaceAll('¥', '').replaceAll('元', '').trim();
      try {
        return Decimal.parse(matched);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// 根据关键词匹配消费分类
  String matchCategory(String text) {
    for (var item in categoryKeywords) {
      final category = item['category'] as String;
      final keywords = item['keywords'] as List<String>;
      for (var keyword in keywords) {
        if (text.contains(keyword)) {
          return category;
        }
      }
    }
    return '其他';
  }

  /// 判断文本是否包含金额
  bool hasAmount(String text) {
    return extractAmount(text) != null;
  }
}
