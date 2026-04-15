import 'dart:convert';
import 'dart:io';

import '../config/app_secrets.dart';
import 'deepseek_api_defaults.dart';
import 'extraction_models.dart';
import 'text_understanding_engine.dart';

class DeepSeekTextUnderstandingEngine implements TextUnderstandingEngine {
  final String endpoint;
  final String? apiKey;
  final String model;
  final Duration requestTimeout;
  final HttpClient Function()? httpClientFactory;

  DeepSeekTextUnderstandingEngine({
    this.endpoint = DeepSeekApiDefaults.endpoint,
    String? apiKey,
    this.model = DeepSeekApiDefaults.model,
    this.requestTimeout = const Duration(seconds: 45),
    this.httpClientFactory,
  }) : apiKey = apiKey ?? const AppSecrets().resolvedDeepSeekApiKey;

  @override
  String get engineName => 'deepseek';

  @override
  Future<bool> isAvailable() async {
    if (apiKey == null) {
      return false;
    }
    return !Platform.environment.containsKey('FLUTTER_TEST');
  }

  @override
  Future<TextUnderstandingResult> extractStructuredData(
    ExtractionRequest request,
  ) async {
    final resolvedApiKey = apiKey;
    if (resolvedApiKey == null) {
      return const TextUnderstandingResult.failure(
        message: 'Missing DEEPSEEK_API_KEY',
      );
    }

    final stopwatch = Stopwatch()..start();
    final client = httpClientFactory?.call() ?? HttpClient();
    client.connectionTimeout = requestTimeout;

    try {
      final httpRequest =
          await client.postUrl(Uri.parse(endpoint)).timeout(requestTimeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $resolvedApiKey',
      );
      httpRequest.add(
        utf8.encode(
          jsonEncode(_buildPayload(request)),
        ),
      );

      final httpResponse = await httpRequest.close().timeout(requestTimeout);
      final responseBody =
          await utf8.decodeStream(httpResponse).timeout(requestTimeout);

      if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        return TextUnderstandingResult.failure(
          message: _buildHttpErrorMessage(
            statusCode: httpResponse.statusCode,
            body: responseBody,
          ),
          latency: stopwatch.elapsed,
          rawResponse: responseBody,
          modelName: model,
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        return TextUnderstandingResult.failure(
          message: 'DeepSeek response is not a JSON object',
          latency: stopwatch.elapsed,
          rawResponse: responseBody,
          modelName: model,
        );
      }

      final content = _extractAssistantContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return TextUnderstandingResult.failure(
          message: 'DeepSeek response does not contain message content',
          latency: stopwatch.elapsed,
          rawResponse: responseBody,
          modelName: decoded['model']?.toString() ?? model,
        );
      }

      return TextUnderstandingResult.success(
        rawResponse: content,
        latency: stopwatch.elapsed,
        modelName: decoded['model']?.toString() ?? model,
      );
    } on SocketException catch (error) {
      return TextUnderstandingResult.failure(
        message: 'DeepSeek network error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } on HttpException catch (error) {
      return TextUnderstandingResult.failure(
        message: 'DeepSeek HTTP error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } on FormatException catch (error) {
      return TextUnderstandingResult.failure(
        message: 'DeepSeek response format error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } catch (error) {
      return TextUnderstandingResult.failure(
        message: 'DeepSeek request failed: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _buildPayload(ExtractionRequest request) {
    return {
      'model': model,
      'temperature': 0.1,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content': _systemPrompt,
        },
        {
          'role': 'user',
          'content': _buildUserPrompt(request),
        },
      ],
    };
  }

  String _buildUserPrompt(ExtractionRequest request) {
    final inputJson =
        const JsonEncoder.withIndent('  ').convert(request.toMap());
    return '''
请根据下面的输入，提取可查询的结构化 entries。

要求：
1. 输出必须且只能是一个 JSON 对象。
2. 必须包含字段：schema_version、note_context、ocr_summary、entries、warnings、unparsed_segments。
3. note_context 与 ocr_summary 直接沿用输入信息。
4. 可结合 rule_candidates，但要主动纠正明显误判，不要机械照抄。
5. 对相对日期（今天、明天、后天、昨晚、今晚、早上、下午等）要基于 note_context.note_created_at 和 timezone 解析。
6. 如果文本同时包含多个事实，可以拆成多个 entries；同一事实不要重复输出。
7. 无法确定时宁可保守归为 memo，也不要编造金额、时间或类别。

输入 JSON：
$inputJson
''';
  }

  String? _extractAssistantContent(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return null;
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }

    final content = message['content'];
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['text'] != null) {
          buffer.write(part['text'].toString());
        } else if (part != null) {
          buffer.write(part.toString());
        }
      }
      final merged = buffer.toString().trim();
      return merged.isEmpty ? null : merged;
    }
    return content?.toString();
  }

  String _buildHttpErrorMessage({
    required int statusCode,
    required String body,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            return 'DeepSeek API error ($statusCode): $message';
          }
        }
      }
    } catch (_) {}
    return 'DeepSeek API error ($statusCode)';
  }
}

const String _systemPrompt = '''
你是一个手写笔记 OCR 结构化抽取器。你只输出 JSON，不输出解释、Markdown、代码块。

输出 schema：
- schema_version: string
- note_context: object
- ocr_summary: object
- entries: array
- warnings: array
- unparsed_segments: array

每个 entry 必须包含：
- entry_id: string
- entry_type: expense | income | task | appointment | health_record | vaccination | medication | metric | purchase | travel | document | memo | custom
- domain: 简短英文域名，例如 finance、life、work、health、family、baby、travel、admin
- title: string
- raw_text: 来自 OCR 的原文片段
- occurred_date: YYYY-MM-DD

可选字段：
- summary
- occurred_at
- end_at
- status
- amount: { "value": "number", "currency": "CNY" }
- category: { "l1": "一级分类", "l2": "二级分类" }
- subjects: [{ "name": "...", "type": "person|pet|organization|place|item|custom", "role": "..." }]
- tags: ["..."]
- links: [{ "target_entry_temp_id": "...", "type": "related|depends_on|caused_by" }]
- normalized: object
- confidence: 0 到 1

分类规则：
- 花费、付款、消费、报销、买东西等，优先用 expense 或 purchase。
- 将来要做的事情、提醒、待办，优先用 task；有明确约见或就诊时间可用 appointment。
- 疫苗、接种、防疫针，优先用 vaccination。
- 吃药、服药、开药，优先用 medication。
- 排便、发烧、咳嗽、症状、检查结果、复查、宝宝身体状态等，优先用 health_record。
- 身高、体重、体温、血压等数值记录，优先用 metric。
- 纯说明、随手记、无明确动作或结构化信息不足时，使用 memo。

约束：
- 不要编造未出现的金额、时间、人物、分类。
- 相同事实不要重复生成多条。
- 如果 rule_candidates 明显更准确，可以沿用其类型、日期、金额、分类。
- 如果 rule_candidates 明显错误，要按 OCR 原文纠正。
- warnings 和 unparsed_segments 没有内容时返回空数组。
''';
