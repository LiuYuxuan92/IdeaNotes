class AppSecrets {
  static const String defaultDeepSeekApiKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
  );

  final String deepSeekApiKey;

  const AppSecrets({
    this.deepSeekApiKey = defaultDeepSeekApiKey,
  });

  String? get resolvedDeepSeekApiKey {
    final trimmed = deepSeekApiKey.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
