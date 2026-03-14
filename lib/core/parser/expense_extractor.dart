import 'package:decimal/decimal.dart';

class ExpenseExtractor {
  static const List<Map<String, dynamic>> categoryKeywords = [
    {
      'category': '餐饮',
      'keywords': ['买菜', '午饭', '晚饭', '早饭', '外卖', '水果', '零食', '饮料', '咖啡', '奶茶']
    },
    {
      'category': '交通',
      'keywords': ['打车', '加油', '停车', '公交', '地铁', '高铁', '机票']
    },
    {
      'category': '购物',
      'keywords': ['淘宝', '京东', '衣服', '鞋', '日用品', '购物']
    },
    {
      'category': '医疗',
      'keywords': ['医院', '药', '看病', '体检']
    },
    {
      'category': '教育',
      'keywords': ['学费', '书', '课程', '培训', '上课']
    },
    {
      'category': '居住',
      'keywords': ['房租', '水电', '物业', '维修']
    },
    {
      'category': '娱乐',
      'keywords': ['电影', '游戏', 'KTV', '旅游']
    },
  ];

  Decimal? extractAmount(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;

    // 避免把日期识别成金额，如 5月20日 / 12/25
    if (RegExp(r'\d+月\d+日').hasMatch(normalized) ||
        RegExp(r'\d+/\d+').hasMatch(normalized)) {
      return null;
    }

    final kuaiJiaoMatch =
        RegExp(r'(^|[^\d])(\d+)块(\d+)?(?:毛)?(?!\d)').firstMatch(normalized);
    if (kuaiJiaoMatch != null) {
      final yuan = kuaiJiaoMatch.group(2)!;
      final jiao = kuaiJiaoMatch.group(3);
      return Decimal.parse(jiao == null || jiao.isEmpty ? yuan : '$yuan.$jiao');
    }

    final yuanMatch = RegExp(
      r'¥\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*元',
    ).firstMatch(normalized);
    if (yuanMatch != null) {
      final raw = yuanMatch.group(1) ?? yuanMatch.group(2);
      if (raw == null) return null;
      try {
        return Decimal.parse(raw);
      } catch (_) {
        return null;
      }
    }

    final plainNumberMatch = RegExp(
      r'(^|\s)(\d+(?:\.\d+)?)(?=\s|$)',
    ).firstMatch(normalized);
    if (plainNumberMatch != null) {
      final raw = plainNumberMatch.group(2);
      if (raw == null) return null;
      try {
        return Decimal.parse(raw);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  String matchCategory(String text) {
    for (final item in categoryKeywords) {
      final category = item['category'] as String;
      final keywords = item['keywords'] as List<String>;
      for (final keyword in keywords) {
        if (text.contains(keyword)) {
          return category;
        }
      }
    }
    return '其他';
  }

  bool hasAmount(String text) => extractAmount(text) != null;
}
