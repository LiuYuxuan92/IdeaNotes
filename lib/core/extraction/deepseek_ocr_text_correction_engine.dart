import 'dart:convert';
import 'dart:io';

import 'deepseek_api_defaults.dart';
import 'ocr_text_correction_engine.dart';

class DeepSeekOcrTextCorrectionEngine implements OcrTextCorrectionEngine {
  final String endpoint;
  final String apiKey;
  final String model;
  final Duration requestTimeout;
  final HttpClient Function()? httpClientFactory;

  const DeepSeekOcrTextCorrectionEngine({
    this.endpoint = DeepSeekApiDefaults.endpoint,
    this.apiKey = DeepSeekApiDefaults.apiKey,
    this.model = DeepSeekApiDefaults.model,
    this.requestTimeout = const Duration(seconds: 20),
    this.httpClientFactory,
  });

  @override
  String get engineName => 'deepseek';

  @override
  Future<bool> isAvailable() async {
    if (apiKey.trim().isEmpty) {
      return false;
    }
    return !Platform.environment.containsKey('FLUTTER_TEST');
  }

  @override
  Future<OcrTextCorrectionResult> correctText(
    OcrTextCorrectionRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    final client = httpClientFactory?.call() ?? HttpClient();
    client.connectionTimeout = requestTimeout;

    try {
      final httpRequest =
          await client.postUrl(Uri.parse(endpoint)).timeout(requestTimeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $apiKey',
      );
      httpRequest.add(utf8.encode(jsonEncode(_buildPayload(request))));

      final httpResponse = await httpRequest.close().timeout(requestTimeout);
      final responseBody =
          await utf8.decodeStream(httpResponse).timeout(requestTimeout);

      if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        return OcrTextCorrectionResult.failure(
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
        return OcrTextCorrectionResult.failure(
          message: 'DeepSeek response is not a JSON object',
          latency: stopwatch.elapsed,
          rawResponse: responseBody,
          modelName: model,
        );
      }

      final content = _extractAssistantContent(decoded);
      if (content == null || content.trim().isEmpty) {
        return OcrTextCorrectionResult.failure(
          message: 'DeepSeek response does not contain message content',
          latency: stopwatch.elapsed,
          rawResponse: responseBody,
          modelName: decoded['model']?.toString() ?? model,
        );
      }

      final payload = jsonDecode(content);
      if (payload is! Map<String, dynamic>) {
        return OcrTextCorrectionResult.failure(
          message: 'DeepSeek correction payload is not a JSON object',
          latency: stopwatch.elapsed,
          rawResponse: content,
          modelName: decoded['model']?.toString() ?? model,
        );
      }

      final correctedText = payload['corrected_text']?.toString().trim();
      if (correctedText == null || correctedText.isEmpty) {
        return OcrTextCorrectionResult.failure(
          message: 'DeepSeek correction payload is missing corrected_text',
          latency: stopwatch.elapsed,
          rawResponse: content,
          modelName: decoded['model']?.toString() ?? model,
        );
      }

      return OcrTextCorrectionResult.success(
        correctedText: correctedText,
        rawResponse: content,
        latency: stopwatch.elapsed,
        modelName: decoded['model']?.toString() ?? model,
      );
    } on SocketException catch (error) {
      return OcrTextCorrectionResult.failure(
        message: 'DeepSeek network error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } on HttpException catch (error) {
      return OcrTextCorrectionResult.failure(
        message: 'DeepSeek HTTP error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } on FormatException catch (error) {
      return OcrTextCorrectionResult.failure(
        message: 'DeepSeek response format error: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } catch (error) {
      return OcrTextCorrectionResult.failure(
        message: 'DeepSeek request failed: $error',
        latency: stopwatch.elapsed,
        modelName: model,
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _buildPayload(OcrTextCorrectionRequest request) {
    return {
      'model': model,
      'temperature': 0,
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

  String _buildUserPrompt(OcrTextCorrectionRequest request) {
    final inputJson =
        const JsonEncoder.withIndent('  ').convert(request.toMap());
    return '''
请校对下面的手写 OCR 文本。

要求：
1. 只修正明显识别错误，例如数字/字母混入、错别字、漏字、重复字、明显断句问题。
2. 保持原意、语气和句式，不要润色，不要扩写，不要总结。
3. 如果拿不准，宁可保留原文，不要自作主张改写。
4. 输出必须且只能是一个 JSON 对象，包含字段 corrected_text。

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
你是一个中文手写 OCR 文本校对器。你只输出 JSON，不输出解释、Markdown、代码块。

输出 schema：
- corrected_text: string

约束：
- 只修正明显 OCR 误识别。
- 不要改写成摘要或更正式的表达。
- 不要凭空补充原文没有的信息。
- 如果文本已经通顺，就原样返回。
''';
