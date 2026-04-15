import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/config/app_secrets.dart';

void main() {
  group('AppSecrets', () {
    test('returns null when key is missing', () {
      const secrets = AppSecrets();

      expect(secrets.resolvedDeepSeekApiKey, isNull);
    });

    test('trims configured key', () {
      const secrets = AppSecrets(deepSeekApiKey: '  test-key  ');

      expect(secrets.resolvedDeepSeekApiKey, 'test-key');
    });
  });
}
