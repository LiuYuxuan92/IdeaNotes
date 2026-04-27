import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';

void main() {
  group('DatabaseHelper.escapeSqlLike', () {
    test('普通文本不变', () {
      expect(DatabaseHelper.escapeSqlLike('记得买牛奶'), '记得买牛奶');
    });

    test('% 与 _ 被转义', () {
      expect(
        DatabaseHelper.escapeSqlLike('折扣 50% 到 70%'),
        r'折扣 50\% 到 70\%',
      );
      expect(
        DatabaseHelper.escapeSqlLike('文件_备份_20260427'),
        r'文件\_备份\_20260427',
      );
    });

    test('反斜杠先于通配符转义', () {
      expect(
        DatabaseHelper.escapeSqlLike(r'C:\path\50%_test'),
        r'C:\\path\\50\%\_test',
      );
    });

    test('空字符串返回空字符串', () {
      expect(DatabaseHelper.escapeSqlLike(''), '');
    });
  });
}
