import 'api_key_storage.dart';

class AppSecrets {
  final String deepSeekApiKey;

  const AppSecrets({
    this.deepSeekApiKey = const String.fromEnvironment('DEEPSEEK_API_KEY'),
  });

  String? get resolvedDeepSeekApiKey {
    final trimmed = deepSeekApiKey.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Resolves the API key: runtime storage > dart-define > null.
  static Future<String?> resolveDeepSeekApiKey() async {
    final stored = await ApiKeyStorage.instance.getDeepSeekApiKey();
    if (stored != null && stored.isNotEmpty) return stored;
    return const AppSecrets().resolvedDeepSeekApiKey;
  }
}
