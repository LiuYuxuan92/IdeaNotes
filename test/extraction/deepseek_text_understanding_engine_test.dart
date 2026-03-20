import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/extraction/deepseek_text_understanding_engine.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';

void main() {
  group('DeepSeekTextUnderstandingEngine', () {
    final request = ExtractionRequest(
      noteContext: ExtractionNoteContext(
        noteId: 'note-deepseek-1',
        noteCreatedAt: DateTime(2026, 3, 20, 9, 30),
      ),
      ocrText: '明天早上去药店',
      ruleCandidates: [
        ExtractedEntry(
          entryId: 'rule-1',
          entryType: ExtractionEntryType.task,
          domain: 'life',
          title: '去药店',
          rawText: '明天早上去药店',
          occurredDate: DateTime(2026, 3, 21),
        ),
      ],
    );

    test('会按 DeepSeek chat completions 格式发请求并提取 message content', () async {
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
                    'entries': [
                      {
                        'entry_id': 'ai-1',
                        'entry_type': 'task',
                        'domain': 'life',
                        'title': '去药店',
                        'raw_text': '明天早上去药店',
                        'occurred_date': '2026-03-21',
                      },
                    ],
                    'warnings': [],
                    'unparsed_segments': [],
                  }),
                },
              },
            ],
          }),
        );
        await incoming.response.close();
      });

      final engine = DeepSeekTextUnderstandingEngine(
        endpoint:
            'http://${server.address.address}:${server.port}/chat/completions',
        apiKey: 'test-key',
      );

      final result = await engine.extractStructuredData(request);

      expect(result.success, isTrue);
      expect(result.modelName, 'deepseek-chat');
      expect(result.rawResponse, contains('"entry_id":"ai-1"'));
      expect(authorizationHeader, 'Bearer test-key');
      expect(capturedBody['model'], 'deepseek-chat');
      expect(capturedBody['response_format'], {'type': 'json_object'});

      final messages = capturedBody['messages'] as List<dynamic>;
      expect(messages.length, 2);
      expect(messages.first['role'], 'system');
      expect(messages.last['role'], 'user');
      expect(
          messages.last['content'], contains('"note_id": "note-deepseek-1"'));
      expect(messages.last['content'], contains('"rule_candidates"'));
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

      final engine = DeepSeekTextUnderstandingEngine(
        endpoint:
            'http://${server.address.address}:${server.port}/chat/completions',
        apiKey: 'bad-key',
      );

      final result = await engine.extractStructuredData(request);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('invalid api key'));
      expect(result.rawResponse, contains('invalid api key'));
    });

    test('api key 为空时会标记为不可用', () async {
      const engine = DeepSeekTextUnderstandingEngine(apiKey: '   ');
      expect(await engine.isAvailable(), isFalse);
    });
  });
}
