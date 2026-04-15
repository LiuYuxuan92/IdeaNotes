import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/deepseek_ocr_text_correction_engine.dart';
import 'package:idea_notes/core/extraction/ocr_text_correction_engine.dart';

void main() {
  group('DeepSeekOcrTextCorrectionEngine', () {
    final request = OcrTextCorrectionRequest(
      text: '今天吃了3牛肉',
      referenceTime: DateTime(2026, 3, 23, 9, 0),
    );

    test('会按 chat completions 格式请求并返回 corrected_text', () async {
      late Map<String, dynamic> capturedBody;
      late String authorizationHeader;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((HttpRequest incoming) async {
        authorizationHeader =
            incoming.headers.value(HttpHeaders.authorizationHeader) ?? '';
        final body = await utf8.decoder.bind(incoming).join();
        capturedBody = jsonDecode(body) as Map<String, dynamic>;

        incoming.response.headers.contentType = ContentType.json;
        incoming.response.write(
          jsonEncode({
            'model': 'deepseek-chat',
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': jsonEncode({
                    'corrected_text': '今天吃了牛肉',
                  }),
                },
              },
            ],
          }),
        );
        await incoming.response.close();
      });

      final engine = DeepSeekOcrTextCorrectionEngine(
        endpoint:
            'http://${server.address.address}:${server.port}/chat/completions',
        apiKey: 'test-key',
      );

      final result = await engine.correctText(request);

      expect(result.success, isTrue);
      expect(result.correctedText, '今天吃了牛肉');
      expect(result.modelName, 'deepseek-chat');
      expect(authorizationHeader, 'Bearer test-key');
      expect(capturedBody['model'], 'deepseek-chat');
      expect(capturedBody['response_format'], {'type': 'json_object'});
    });

    test('接口非 2xx 时返回可读错误信息', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((HttpRequest incoming) async {
        incoming.response.statusCode = 401;
        incoming.response.headers.contentType = ContentType.json;
        incoming.response.write(
          jsonEncode({
            'error': {'message': 'invalid api key'},
          }),
        );
        await incoming.response.close();
      });

      final engine = DeepSeekOcrTextCorrectionEngine(
        endpoint:
            'http://${server.address.address}:${server.port}/chat/completions',
        apiKey: 'bad-key',
      );

      final result = await engine.correctText(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('invalid api key'));
      expect(result.rawResponse, contains('invalid api key'));
    });

    test('api key 为空时会标记为不可用', () async {
      final engine = DeepSeekOcrTextCorrectionEngine(apiKey: '   ');
      expect(await engine.isAvailable(), isFalse);
    });

    test('默认构造且缺少环境变量 key 时直接返回失败', () async {
      final engine = DeepSeekOcrTextCorrectionEngine();

      final result = await engine.correctText(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Missing DEEPSEEK_API_KEY');
      expect(result.rawResponse, isEmpty);
    });
  });
}
