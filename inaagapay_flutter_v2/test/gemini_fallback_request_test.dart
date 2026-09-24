import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/groq_service.dart';

void main() {
  group('a request falls back to Gemini unchanged', () {
    test('system text becomes the system instruction', () {
      final body = GroqService.geminiRequestBody(
        messages: [
          {'role': 'system', 'content': 'You are a caring midwife assistant.'},
          {'role': 'user', 'content': 'Is 110/70 normal?'},
        ],
        temperature: 0.3,
        maxOutputTokens: 512,
        useJsonMode: false,
      );
      expect(body['systemInstruction']['parts'][0]['text'],
          'You are a caring midwife assistant.');
      expect(body['contents'], hasLength(1));
      expect(body['contents'][0]['role'], 'user');
      expect(body['generationConfig']['maxOutputTokens'], 512);
      expect(body['generationConfig'].containsKey('responseMimeType'), isFalse);
    });

    test('an image in a data URL becomes inline data', () {
      final body = GroqService.geminiRequestBody(
        messages: [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Read this card.'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,QUJD'}
              },
            ],
          },
        ],
        temperature: 0.1,
        maxOutputTokens: 4096,
        useJsonMode: true,
      );
      final parts = body['contents'][0]['parts'] as List;
      expect(parts[0], {'text': 'Read this card.'});
      expect(parts[1], {
        'inline_data': {'mime_type': 'image/jpeg', 'data': 'QUJD'}
      });
      expect(body['generationConfig']['responseMimeType'], 'application/json');
    });

    test('assistant turns become model turns', () {
      final body = GroqService.geminiRequestBody(
        messages: [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello!'},
          {'role': 'user', 'content': 'When is my next checkup?'},
        ],
        temperature: 0.5,
        maxOutputTokens: 256,
        useJsonMode: false,
      );
      expect((body['contents'] as List).map((c) => c['role']),
          ['user', 'model', 'user']);
      expect(body.containsKey('systemInstruction'), isFalse);
    });
  });
}
