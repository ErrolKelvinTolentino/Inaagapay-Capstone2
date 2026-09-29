// lib/services/ai_model_trail.dart
//
// Which AI provider and model actually produced a result.
//
// The AI audit tables (ai_responses.ai_model, ai_prompt_logs.model_used) are
// how a reviewer tells an AI-written explanation from a rule-engine one and
// traces it to the model that wrote it. Screens used to write literals
// instead: the ultrasound analyzer logged "Gemini 1.5 Flash", a retired model
// the request never reached, and the growth screens logged "groq" whichever
// of the fallback models had answered. GroqService records every completed
// request here, and screens store [AiModelTrail.summary] with the output.

/// The providers and models that answered during one AI call, in order.
class AiModelTrail {
  final List<String> _entries = [];

  /// Forgets the previous call. GroqService does this at the start of every
  /// public request, so a request that fails cannot inherit the models of an
  /// earlier one.
  void start() => _entries.clear();

  /// A request to [provider] with [model] returned a usable answer.
  void record(String provider, String model) {
    final entry = '${provider.toLowerCase()}/$model';
    if (!_entries.contains(entry)) _entries.add(entry);
  }

  /// "provider/model", joined with " + " when the call chained models (image
  /// analysis reads with the vision model, then reasons over the extraction
  /// with a language model). Null when nothing answered, which means the
  /// output came from a rule-based fallback rather than from AI.
  String? get summary => _entries.isEmpty ? null : _entries.join(' + ');
}
