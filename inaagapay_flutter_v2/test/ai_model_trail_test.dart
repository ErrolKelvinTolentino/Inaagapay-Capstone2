import 'package:flutter_test/flutter_test.dart';
import 'package:inaagapay_flutter_v2/services/ai_model_trail.dart';

void main() {
  group('the AI audit log names the model that answered', () {
    test('nothing answered means no model, not a guessed one', () {
      expect(AiModelTrail().summary, isNull);
    });

    test('one completion is recorded as provider/model', () {
      final trail = AiModelTrail()..record('Groq', 'openai/gpt-oss-120b');
      expect(trail.summary, 'groq/openai/gpt-oss-120b');
    });

    test('a fallback is recorded as the model that actually answered', () {
      final trail = AiModelTrail()..record('NVIDIA', 'openai/gpt-oss-20b');
      expect(trail.summary, 'nvidia/openai/gpt-oss-20b');
    });

    test('image analysis names both the vision and the reasoning model', () {
      final trail = AiModelTrail()
        ..record('Groq', 'qwen/qwen3.8-27b')
        ..record('Groq', 'openai/gpt-oss-120b');
      expect(trail.summary,
          'groq/qwen/qwen3.8-27b + groq/openai/gpt-oss-120b');
    });

    test('the same model answering twice is listed once', () {
      final trail = AiModelTrail()
        ..record('gemini', 'gemini-3.8-flash')
        ..record('gemini', 'gemini-3.8-flash');
      expect(trail.summary, 'gemini/gemini-3.8-flash');
    });

    test('a new call does not inherit the previous call\'s models', () {
      final trail = AiModelTrail()..record('Groq', 'qwen/qwen3.8-27b');
      trail.start();
      expect(trail.summary, isNull);
    });
  });
}
