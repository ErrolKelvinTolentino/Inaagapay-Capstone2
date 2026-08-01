// lib/services/groq_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../models/groq_response.dart';
import '../models/ocr_result.dart';

class GroqService {
  // ── Model Configuration ─────────────────────────────────────────────────

  static const String _visionModel = 'qwen/qwen3.6-27b';
  static const List<String> _visionModelFallbacks = [
    'qwen/qwen3.6-27b',
    'llama-3.2-11b-vision-instruct',
    'meta-llama/llama-3.2-11b-vision-instruct',
  ];
  static const String _reasoningModel = 'llama-3.3-70b-versatile';
  static const String _firstFallbackReasoningModel = 'llama-3.1-8b-instant';
  static const String _secondFallbackReasoningModel = 'llama-3.1-70b-versatile';

  static const String childGrowthSystemPrompt =
      'You are a caring, knowledgeable midwife assistant in the Philippines who genuinely cares about every mother and child. '
      'Write as if you are a trusted ate (older sister) sitting beside the mother, gently explaining things.\n\n'
      'CRITICAL GROWTH TRANSLATION RULES:\n'
      '- You must provide the response in both English and Filipino/Tagalog translations.\n'
      '- Your response must use the exact format requested in the prompt, featuring the headers "## English" and "## Filipino" respectively.\n'
      '- Under "## English", write exactly one sentence of warm reassurance.\n'
      '- Under "## Filipino", write exactly one sentence of warm reassurance in simple conversational Tagalog/Filipino.\n'
      '- Use simple, everyday, colloquial Tagalog (mild Taglish is fine) as spoken in typical Filipino homes. Avoid deep, formal, poetic, or archaic words.\n'
      '- Do not write English under the Filipino section, and do not write Filipino under the English section.\n'
      '- Tone must be simple, gentle, comforting, and encouraging. Never be cold or clinical. Do not use medical jargon or z-scores.\n'
      '- Keep the insight extremely concise, direct, and reassuring. Do NOT give medical, dietary, lifestyle, or play suggestions (avoid suggestions like active play, sleep, feeding, or exercises).';

  static const String _sttModelPrimary = 'whisper-large-v3-turbo';
  static const String _sttModelFallback = 'whisper-large-v3';
  static const String _audioTranscriptionUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  // ── API Constraints ─────────────────────────────────────────────────────

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const int _maxBase64Size = 4 * 1024 * 1024;
  static const int _maxImagesPerRequest = 5;

  // ── Debug ───────────────────────────────────────────────────────────────

  final bool _debugMode = true;

  void _log(String message) {
    if (_debugMode && kDebugMode) {
      debugPrint('[GroqService] $message');
    }
  }

  // ── API Key ─────────────────────────────────────────────────────────────

  String _getApiKey() {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Groq API Key not found in .env');
    }
    return apiKey;
  }

  // ════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ════════════════════════════════════════════════════════════════════════

  Future<GroqResponse> analyzeUltrasoundImages(
    List<XFile> imageFiles, {
    String? clinicalContext,
    int? aogWeeks,
    String? trimesterLabel,
    String? relevantCategories,
  }) async {
    _validateImageInput(imageFiles);

    final apiKey = _getApiKey();
    final normalizedContext = (clinicalContext ?? '').trim();

    // ── Step 1: Vision Extraction ──────────────────────────────────────
    _log('📸 Step 1/2: Extracting ultrasound observations...');

    final String extractionPrompt = _buildUltrasoundExtractionPrompt(
      imageCount: imageFiles.length,
      clinicalContext: normalizedContext,
      aogWeeks: aogWeeks,
      trimesterLabel: trimesterLabel,
    );

    final String rawExtraction = await _sendVisionRequest(
      imageFiles: imageFiles,
      apiKey: apiKey,
      prompt: extractionPrompt,
      maxTokens: 4096,
    );

    // Log what the vision model actually saw
    _log(
        '📋 Raw extraction (first 500 chars): ${rawExtraction.length > 500 ? '${rawExtraction.substring(0, 500)}...' : rawExtraction}');

    // Validate the extraction contains actual data
    if (!rawExtraction.contains('visible_features') &&
        !rawExtraction.contains('visible_measurements')) {
      _log(
          '⚠️ Warning: Vision model may not have returned expected JSON structure');
    }

    // ── Step 2: Reasoning Analysis ─────────────────────────────────────
    _log('🧠 Step 2/2: Analyzing findings...');

    final String reasoningPrompt = _buildUltrasoundReasoningPrompt(
      rawExtraction: rawExtraction,
      imageCount: imageFiles.length,
      clinicalContext: normalizedContext,
      aogWeeks: aogWeeks,
      trimesterLabel: trimesterLabel,
      relevantCategories: relevantCategories,
    );

    final result = await _sendReasoningRequest(
      apiKey: apiKey,
      prompt: reasoningPrompt,
    );

    _log('✅ Analysis complete');
    return result;
  }

  /// Fast, targeted OCR summary extraction for ultrasound records
  Future<Map<String, dynamic>> extractUltrasoundSummaryOCR(List<XFile> imageFiles) async {
    if (imageFiles.isEmpty) return {};
    try {
      final apiKey = _getApiKey();
      const prompt = '''
You are an expert medical OCR assistant specializing in Philippine Diagnostic & Ultrasound Reports.
Scan this ultrasound document image carefully and extract all key summary information into a single valid JSON object.

Output JSON schema:
{
  "ultrasound_date": "YYYY-MM-DD",
  "ega_weeks": integer (e.g. 16 for 16W0D or 16 weeks),
  "ega_days": integer (0 to 6),
  "location_facility": "facility or location name, e.g. Santa Maria, Mexico, Pampanga or clinic name",
  "institution_name": "diagnostic center or hospital name in header, e.g. austria diagnostic center",
  "sonologist_name": "physician or sonologist name at bottom/header, e.g. DR. RAHMI Detu-Yu, MD",
  "fetal_count": integer (1 for SINGLETON, 2 for TWINS),
  "sonologist_remarks": "Extract ONLY the final IMPRESSION or REMARKS summary sentence if present (e.g. 'Single live intrauterine pregnancy 16 weeks AOG'). DO NOT extract individual biometry measurements like AFI, placental position, fetal weight, NST, etc."
}

Guide for extraction from Philippine Ultrasound Reports:
- Look at the top header logo/title for institution_name (e.g. "austria diagnostic center") and location_facility (e.g. "Mexico, Pampanga").
- Look for Date fields (e.g. "Date: AUGUST 01, 2026") -> convert to "2026-08-01".
- Look for "Average Ultrasound Age" or "AOG" or "AOG: 16W0D" or "16 weeks and 0 days" -> ega_weeks: 16, ega_days: 0.
- Look for "Number of Fetus: SINGLETON" -> fetal_count: 1.
- Look at the bottom signature for sonologist_name (e.g. "DR. RAHMI Detu-Yu, MD").
- For sonologist_remarks: Look for "IMPRESSION:" heading and extract ONLY the summary impression text (e.g. "Single live intrauterine pregnancy 16 weeks AOG"). Do NOT copy individual biometry findings (AFI, Placenta, Weight).

RETURN ONLY THE RAW JSON OBJECT. DO NOT INCLUDE MARKDOWN CODE BLOCKS.
''';

      final String rawOutput = await _sendVisionRequest(
        imageFiles: [imageFiles.first],
        apiKey: apiKey,
        prompt: prompt,
        maxTokens: 2048,
      );

      _log('📄 Raw Ultrasound OCR Vision output: $rawOutput');

      // Clean JSON string
      String cleaned = rawOutput.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (jsonMatch != null) {
        cleaned = jsonMatch.group(0)!;
      }

      Map<String, dynamic> data = {};
      try {
        data = Map<String, dynamic>.from(jsonDecode(cleaned) as Map);
      } catch (e) {
        _log('⚠️ JSON parse failed, applying regex extraction on raw text...');
      }

      // Fallback regex parsing if fields are missing
      if (data['ultrasound_date'] == null || data['ultrasound_date'].toString().isEmpty) {
        final dateMatch = RegExp(r'(?:Date|DATE)[\s:]*([A-Z]+\s+\d{1,2},?\s+\d{4}|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4})', caseSensitive: false).firstMatch(rawOutput);
        if (dateMatch != null) {
          final dtStr = dateMatch.group(1)!.trim();
          try {
            final dt = DateTime.tryParse(dtStr) ?? DateFormat('MMMM d, yyyy').parse(dtStr.replaceAll(',', ''));
            data['ultrasound_date'] = DateFormat('yyyy-MM-dd').format(dt);
          } catch (_) {}
        }
      }

      if (data['ega_weeks'] == null) {
        final aogMatch = RegExp(r'(\d{1,2})\s*(?:weeks|W|WOD)\s*(?:and)?\s*(\d{1,2})?\s*(?:days|D|DOD)?', caseSensitive: false).firstMatch(rawOutput);
        if (aogMatch != null) {
          data['ega_weeks'] = int.tryParse(aogMatch.group(1)!);
          if (aogMatch.group(2) != null) {
            data['ega_days'] = int.tryParse(aogMatch.group(2)!);
          }
        }
      }

      if (data['institution_name'] == null || data['institution_name'].toString().isEmpty) {
        if (rawOutput.toLowerCase().contains('austria diagnostic')) {
          data['institution_name'] = 'Austria Diagnostic Center';
          data['location_facility'] = 'Santa Maria, Mexico, Pampanga';
        }
      }

      if (data['sonologist_name'] == null || data['sonologist_name'].toString().isEmpty) {
        final docMatch = RegExp(r'(?:DR\.|DOCTOR|SONOLOGIST)[\sA-Z\.-]+', caseSensitive: false).firstMatch(rawOutput);
        if (docMatch != null) {
          data['sonologist_name'] = docMatch.group(0)!.trim();
        }
      }

      if (data['fetal_count'] == null) {
        if (rawOutput.toUpperCase().contains('SINGLETON')) {
          data['fetal_count'] = 1;
        } else if (rawOutput.toUpperCase().contains('TWIN')) {
          data['fetal_count'] = 2;
        }
      }

      return data;
    } catch (e) {
      _log('⚠️ Error extracting ultrasound summary OCR: $e');
      return {};
    }
  }

  /// Fast 1-2 sentence mother-friendly growth insight comparing Ultrasound EGA vs Registered AOG on Ultrasound Date
  Future<String?> generateUltrasoundGrowthInsight({
    required DateTime ultrasoundDate,
    required int egaWeeks,
    required int egaDays,
    required double registeredAogWeeksOnScanDate,
    required int registeredAogDaysOnScanDate,
    String? sonologistRemarks,
    int fetalCount = 1,
  }) async {
    try {
      final apiKey = _getApiKey();
      final regWeeks = registeredAogWeeksOnScanDate.floor();
      final regDays = registeredAogDaysOnScanDate % 7;
      final diffDays = (egaWeeks * 7 + egaDays) - (regWeeks * 7 + regDays);

      final prompt = '''
You are a caring midwife assistant in the Philippines explaining ultrasound results to a mother.
Ultrasound Date: ${ultrasoundDate.year}-${ultrasoundDate.month.toString().padLeft(2, '0')}-${ultrasoundDate.day.toString().padLeft(2, '0')}
- Ultrasound Fetal Gestational Age (EGA): $egaWeeks weeks $egaDays days
- Registered Gestational Age on Scan Date: $regWeeks weeks $regDays days
- Difference: ${diffDays.abs()} days (${diffDays >= 0 ? 'larger/further along' : 'smaller/younger'} than registered age)
- Fetal Count: $fetalCount
${sonologistRemarks != null && sonologistRemarks.trim().isNotEmpty ? '- Sonologist Remarks: $sonologistRemarks' : ''}

CRITICAL RULES:
- Write a 1-2 sentence warm, reassuring summary for the mother in mild conversational Tagalog/Taglish.
- Explain whether the baby's size on the scan date matches her expected gestational age for that date.
- Keep it simple, clear, reassuring, and non-alarmist. Never use scary medical terms.
''';

      final response = await _sendReasoningRequest(
        apiKey: apiKey,
        prompt: prompt,
      );
      return response.description;
    } catch (e) {
      _log('⚠️ Error generating growth insight: $e');
      return null;
    }
  }

  Future<GroqResponse> analyzeLabTestImages(
    List<XFile> imageFiles, {
    String? selectedLabType,
    String? notes,
    String? clinicalContext,
  }) async {
    _validateImageInput(imageFiles);

    final apiKey = _getApiKey();
    final normalizedType = (selectedLabType ?? '').trim();
    final normalizedNotes = (notes ?? '').trim();
    final normalizedContext = (clinicalContext ?? '').trim();

    // ── Step 1: Vision Extraction ──────────────────────────────────────
    _log('📸 Step 1/2: Extracting lab test data...');

    final String extractionPrompt = _buildLabExtractionPrompt(
      imageCount: imageFiles.length,
      labType: normalizedType,
      notes: normalizedNotes,
      clinicalContext: normalizedContext,
    );

    final String rawExtraction = await _sendVisionRequest(
      imageFiles: imageFiles,
      apiKey: apiKey,
      prompt: extractionPrompt,
      maxTokens: 4096,
    );

    _log(
        '📋 Raw extraction (first 500 chars): ${rawExtraction.length > 500 ? '${rawExtraction.substring(0, 500)}...' : rawExtraction}');

    // ── Step 2: Reasoning Analysis ─────────────────────────────────────
    _log('🧠 Step 2/2: Analyzing lab results...');

    final String reasoningPrompt = _buildLabReasoningPrompt(
      rawExtraction: rawExtraction,
      imageCount: imageFiles.length,
      labType: normalizedType,
      notes: normalizedNotes,
      clinicalContext: normalizedContext,
    );

    final result = await _sendReasoningRequest(
      apiKey: apiKey,
      prompt: reasoningPrompt,
    );

    _log('✅ Analysis complete');
    return result;
  }

  Future<String> generateTextInsight({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.2,
    int maxOutputTokens = 2048,
  }) async {
    final apiKey = _getApiKey();
    _log('💬 Generating text insight...');

    final sysContent = systemPrompt ??
        'You are a caring, knowledgeable midwife assistant in the Philippines who genuinely cares about every mother and child. '
            'Write as if you are a trusted ate (older sister) sitting beside the mother, gently explaining things. '
            'Celebrate good news warmly. When something needs attention, be honest but gentle and always offer practical next steps. '
            'Use simple Filipino-context language. Explain medical terms by what they mean for the mother and baby. '
            'Give culturally relevant advice (e.g., local foods like malunggay, kangkong, dilis for nutrition). '
            'Never be cold or clinical. Always end with encouragement.\n\n'
            'MATERNAL WEIGHT INTERPRETATION RULES (apply when weight/BMI data is present):\n'
            '- You are NOT responsible for computing BMI or weight gain formulas — the system provides those.\n'
            '- You translate maternal monitoring information into understandable explanations.\n'
            '- NEVER use words like "ideal weight", "perfect weight", "required weight", or "normal pregnancy weight".\n'
            '- Use softer wording: "commonly expected range", "estimated expected range", "appears within range", "appears slightly lower/higher than expected".\n'
            '- NEVER present exact target weights, guaranteed healthy weights, or rigid expectations.\n'
            '- If pre-pregnancy weight is unavailable, do NOT display BMI classifications or overweight/obese labels to the mother. Include disclaimer: "Pre-pregnancy weight information was not provided. Current insights are partially estimated and may have limited BMI-based interpretation."\n'
            '- For FIRST TRIMESTER: note that small weight changes are common in early pregnancy. Do NOT apply weekly rate references yet.\n'
            '- Every weight interpretation must end with: "This AI-assisted interpretation is intended only for healthcare monitoring support and does not replace professional medical consultation."';

    return _sendChatCompletion(
      messages: [
        {
          'role': 'system',
          'content': sysContent,
        },
        {'role': 'user', 'content': prompt}
      ],
      apiKey: apiKey,
      model: _reasoningModel,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
    );
  }

  // ── TTS API ─────────────────────────────────────────────────────────────
  /// Calls the Groq text-to-speech endpoint and returns concatenated WAV bytes.
  /// Uses canopylabs/orpheus-v1-english with "diana" voice.
  /// Handles the 200-char limit by splitting into sentence chunks automatically.
  static const int _ttsMaxChunkChars = 190; // safely under the 200-char limit
  static const int _wavHeaderSize = 44; // standard WAV header bytes

  Future<List<int>> speakWithGroqTts(String text) async {
    final apiKey = _getApiKey();

    // 1. Sanitise markdown
    final clean = text
        .replaceAll(RegExp(r'\*{1,2}'), '')
        .replaceAll(RegExp(r'#{1,6} ?'), '')
        .replaceAll(RegExp(r'-{3,}'), '')
        .replaceAll(RegExp(r'[_`]'), '')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .replaceAll('\n', ' ')
        .trim();

    // 2. Split into ≤190-char chunks on sentence boundaries
    final chunks = _splitIntoTtsChunks(clean);
    _log('🔊 Groq TTS: ${clean.length} chars → ${chunks.length} chunk(s)');

    // 3. Fetch each chunk sequentially and combine the audio
    List<int> combinedAudio = [];

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (chunk.trim().isEmpty) continue;

      _log(
          '   Chunk ${i + 1}/${chunks.length}: "${chunk.substring(0, chunk.length.clamp(0, 50))}..." (${chunk.length} chars)');

      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/audio/speech'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': 'canopylabs/orpheus-v1-english',
              'input': '[cheerful] $chunk',
              'voice': 'autumn',
              'response_format': 'wav',
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        String errMsg;
        try {
          final errData = jsonDecode(response.body);
          errMsg = errData['error']?['message'] ?? response.body;
        } catch (_) {
          errMsg = response.body;
        }
        _log('❌ Groq TTS chunk $i failed (${response.statusCode}): $errMsg');
        throw Exception('Groq TTS Error (${response.statusCode}): $errMsg');
      }

      final bytes = response.bodyBytes;
      _log('   ✅ Chunk ${i + 1}: ${bytes.length} bytes received');

      if (i == 0) {
        // First chunk: keep the full WAV including header
        combinedAudio.addAll(bytes);
      } else {
        // Subsequent chunks: skip the 44-byte WAV header to avoid duplicates
        if (bytes.length > _wavHeaderSize) {
          combinedAudio.addAll(bytes.sublist(_wavHeaderSize));
        }
      }
    }

    _log('✅ Groq TTS complete: ${combinedAudio.length} total bytes');
    return combinedAudio;
  }

  /// Splits text into chunks of at most [_ttsMaxChunkChars] characters,
  /// preferring to break on sentence-ending punctuation (. ! ?) or commas.
  List<String> _splitIntoTtsChunks(String text) {
    if (text.length <= _ttsMaxChunkChars) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = (start + _ttsMaxChunkChars).clamp(0, text.length);
      if (end == text.length) {
        chunks.add(text.substring(start).trim());
        break;
      }

      // Walk back to find a good break point: ". ", "! ", "? ", ", "
      int breakAt = -1;
      for (int j = end; j > start + 30; j--) {
        final ch = text[j];
        if ((ch == '.' || ch == '!' || ch == '?') &&
            j + 1 < text.length &&
            text[j + 1] == ' ') {
          breakAt = j + 1; // include the punctuation, break after it
          break;
        }
        if (ch == ',' && j + 1 < text.length && text[j + 1] == ' ') {
          breakAt = j + 1;
          // don't break yet — prefer sentence-ending punctuation
        }
      }

      if (breakAt == -1) {
        // No good punct found — fall back to last space
        breakAt = text.lastIndexOf(' ', end);
        if (breakAt <= start) breakAt = end; // hard cut
      }

      chunks.add(text.substring(start, breakAt).trim());
      start = breakAt;
      while (start < text.length && text[start] == ' ') {
        start++;
      }
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  Future<String> transcribeAudio({
    required Uint8List audioBytes,
    required String fileName,
    String? language,
  }) async {
    final apiKey = _getApiKey();
    final models = [_sttModelPrimary, _sttModelFallback];
    String? lastError;

    for (final model in models) {
      try {
        return await _sendAudioTranscription(
          audioBytes: audioBytes,
          fileName: fileName,
          apiKey: apiKey,
          model: model,
          language: language,
        );
      } catch (e) {
        lastError = e.toString();
        _log('⚠️ STT model ${model.split('/').last} failed: $e');
      }
    }

    throw Exception(
        'Speech transcription failed: ${lastError ?? 'Unknown error'}');
  }

  Future<String> _sendAudioTranscription({
    required Uint8List audioBytes,
    required String fileName,
    required String apiKey,
    required String model,
    String? language,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse(_audioTranscriptionUrl));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = model;
    if (language != null && language.isNotEmpty) {
      request.fields['language'] = language;
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        audioBytes,
        filename: fileName,
      ),
    );

    final streamedResponse =
        await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      String errorMessage = response.body;
      try {
        final errorData = jsonDecode(response.body);
        errorMessage = errorData['error']?['message'] ?? response.body;
      } catch (_) {}
      throw Exception('Groq STT Error (${response.statusCode}): $errorMessage');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Groq STT returned empty transcription');
    }
    return text.trim();
  }

  Future<String> getChatResponse({
    required List<Map<String, dynamic>> chatHistory,
    double temperature = 0.5,
    int maxOutputTokens = 2048,
  }) async {
    final apiKey = _getApiKey();
    _log('💬 Generating chat response...');

    return _sendChatCompletion(
      messages: chatHistory,
      apiKey: apiKey,
      model: _reasoningModel,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Future<OcrResult> extractMotherRegistrationData(XFile imageFile) async {
    final apiKey = _getApiKey();
    _log('📄 Extracting registration data...');

    const prompt = r'''
You are an OCR assistant that reads maternal health / patient registration forms (printed or handwritten).
Extract every visible field and return ONLY a single JSON object — no markdown, no prose, no code fence.

Output schema (all fields optional, omit if not found):
{
  "first_name": "string",
  "middle_name": "string",
  "last_name": "string",
  "extension_name": "string",
  "phone": "string",
  "email": "string",
  "house_number": "string",
  "street": "string",
  "barangay": "string",
  "city": "string",
  "province": "string",
  "birthdate": "YYYY-MM-DD",
  "height_cm": number,
  "weight_kg": number,
  "blood_type": "A+|A-|B+|B-|AB+|AB-|O+|O-|Unknown",
  "lmp_date": "YYYY-MM-DD",
  "edd_date": "YYYY-MM-DD",
  "emergency_contacts": [
    {
      "first_name": "string",
      "middle_name": "string",
      "last_name": "string",
      "extension_name": "string",
      "phone_number": "string",
      "affiliation": "string"
    }
  ],
  "medical_conditions": [
    {
      "condition_name": "string",
      "diagnosis_date": "YYYY-MM-DD",
      "status": "active|resolved",
      "remarks": "string"
    }
  ],
  "allergies": [
    {
      "allergen": "string",
      "diagnosis_date": "YYYY-MM-DD",
      "status": "active|resolved",
      "treatment": "string",
      "remarks": "string"
    }
  ],
  "past_pregnancies": [
    {
      "outcome": "live_birth|stillbirth|miscarriage|abortion|ectopic",
      "outcome_date": "YYYY-MM-DD",
      "is_estimated": false,
      "gestational_age_at_end": number,
      "place_of_delivery": "string",
      "delivery_method": "Normal Spontaneous Vaginal Delivery|Cesarean Section|Assisted Vaginal Delivery|Other"
    }
  ]
}
Rules:
- Dates must be ISO format (YYYY-MM-DD); infer year if only month/day visible.
- For phone numbers keep Filipino format (09XXXXXXXXX or +639XXXXXXXXX).
- outcome must be exactly one of the listed enum values in lowercase_with_underscores.
- If a field is not visible or illegible, omit it entirely.
- Return ONLY the JSON — no extra text.
''';

    final preparedImage = await _prepareImageForGroq(imageFile);
    final base64Image = base64Encode(preparedImage.bytes);

    final raw = await _sendChatCompletion(
      messages: [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${preparedImage.mimeType};base64,$base64Image'
              }
            }
          ]
        }
      ],
      apiKey: apiKey,
      model: _visionModel,
      temperature: 0.1,
      maxOutputTokens: 4096,
    );

    final cleaned = _stripMarkdownFences(raw);
    final json = _parseJsonResponse(cleaned);
    _log('✅ Registration data extracted');
    return OcrResult.fromJson(json);
  }

  Future<Map<String, dynamic>> extractImmunizationCardData(XFile imageFile) async {
    final apiKey = _getApiKey();
    _log('💉 Extracting immunization card data...');

    const prompt = r'''
You are an expert medical OCR assistant that reads child immunization cards / baby books (handwritten or printed).
Analyze the uploaded image of the immunization card. Extract all vaccines that have dates written next to them (which indicates they have been administered).

Return ONLY a single JSON object — no markdown, no prose, no code fence.

Output schema:
{
  "administered_vaccines": [
    {
      "vaccine_name_raw": "string (e.g. 'BCG Vaccine', 'Pentavalent Vaccine', 'Oral Polio Vaccine', 'Rotavirus')",
      "dose_number": number (e.g. 1, 2, 3),
      "date_raw": "string (exactly as written, e.g. '12-6-24', '1-25-25')",
      "parsed_date": "YYYY-MM-DD (standardized ISO date format, inferring 20XX for 2-digit years. E.g. '12-6-24' -> '2024-12-06', '1-25-25' -> '2025-01-25'. Use null if date is illegible)",
      "remarks": "string (remarks or next-dose dates written in that row/cell, or null)"
    }
  ],
  "image_quality": "CLEAR|MODERATE|POOR",
  "relevance_check": "RELATED|UNRELATED",
  "relevance_reason": "string (if unrelated or poor quality)"
}

Rules:
- Dates on Philippine baby books are typically written in MM-DD-YY or M-D-YY format (e.g. 12-6-24 represents December 6, 2024). Carefully parse these into standard YYYY-MM-DD.
- Extract ONLY the doses that have a date written (administered). Do not list rows that are empty.
- Look out for hand-written vaccine names added at the bottom (like 'Rotavirus' with date '1-25-25').
- Return ONLY the JSON object.
''';

    final preparedImage = await _prepareImageForGroq(imageFile);
    final base64Image = base64Encode(preparedImage.bytes);

    final raw = await _sendChatCompletion(
      messages: [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${preparedImage.mimeType};base64,$base64Image'
              }
            }
          ]
        }
      ],
      apiKey: apiKey,
      model: _visionModel,
      temperature: 0.1,
      maxOutputTokens: 4096,
    );

    final cleaned = _stripMarkdownFences(raw);
    final json = _parseJsonResponse(cleaned);
    _log('✅ Immunization data extracted');
    return json;
  }

  // ════════════════════════════════════════════════════════════════════════
  // PROMPT BUILDERS
  // ════════════════════════════════════════════════════════════════════════

  String _buildUltrasoundExtractionPrompt({
    required int imageCount,
    required String clinicalContext,
    int? aogWeeks,
    String? trimesterLabel,
  }) {
    final trimesterNote = (aogWeeks != null && trimesterLabel != null)
        ? '\nTrimester context: $trimesterLabel ($aogWeeks weeks). Focus measurement observations on biometrics relevant to this trimester.'
        : '';

    return """
You are a medical imaging observer. Your ONLY job is to describe EXACTLY what you see in these ultrasound images.
Do NOT interpret, diagnose, or make recommendations.
Just list EVERY visible feature, measurement, structure, and text annotation you can see.

CRITICAL: Pay special attention to ANY abnormalities, unusual findings, or annotations marked with flags, arrows, or measurements that appear outside normal ranges. Report EVERYTHING you observe, even subtle details.

I am providing $imageCount ultrasound image(s) of the same pregnancy.
Clinical context: ${clinicalContext.isEmpty ? 'Not provided' : clinicalContext}$trimesterNote

Return ONLY valid JSON (no markdown, no explanation outside the JSON):
{
  "visible_features": ["list EVERY feature you see - be exhaustive"],
  "visible_measurements": [
    {
      "name": "measurement name exactly as shown or described",
      "value": "numerical value exactly as shown or 'unclear'",
      "unit": "mm, cm, weeks, days, bpm, etc."
    }
  ],
  "visible_structures": ["list ALL anatomical structures visible - be exhaustive"],
  "text_annotations": ["any text, numbers, labels, or flags visible on the image"],
  "abnormal_indicators": ["any arrows, markers, color highlights, or annotations suggesting abnormalities"],
  "patient_info_visible": {
    "patient_name": "patient name if visible or null",
    "clinic_location": "clinic or hospital name if visible or null",
    "attending_professional": "doctor or sonographer name if visible or null"
  },
  "image_quality": "CLEAR|MODERATE|POOR",
  "raw_observations": "Detailed paragraph describing absolutely everything visible. Include ALL abnormalities, even subtle ones. Describe each structure's appearance."
}

CRITICAL:
- List ALL measurements you can see, even if uncertain. Mark unclear ones with value 'unclear'.
- List ALL structures visible, not just the main ones.
- The abnormal_indicators field is MANDATORY - list any visual cues that might indicate pathology.
- If the image is completely unrelated or unreadable, set image_quality to POOR and explain why.
- If clinical context includes gestational age, trimester, or medical conditions, keep those in mind when listing observations.
""";
  }

  String _buildUltrasoundReasoningPrompt({
    required String rawExtraction,
    required int imageCount,
    required String clinicalContext,
    int? aogWeeks,
    String? trimesterLabel,
    String? relevantCategories,
  }) {
    // Clean the extraction but preserve its content
    final cleaned = _stripMarkdownFences(rawExtraction);

    // Build trimester-aware measurement guidance block
    // Based on: INTERGROWTH-21st (Papageorghiou et al., Lancet 2014)
    //           WHO Fetal Growth Charts (Kiserud et al., PLOS Medicine 2017)
    final trimesterGuidance = (aogWeeks != null && trimesterLabel != null)
        ? '''
--------------------------------------------------
TRIMESTER CONTEXT (from clinical records)
--------------------------------------------------

Gestational Age at Scan: $aogWeeks weeks
Trimester: $trimesterLabel

Clinically Relevant Measurement Categories for This Trimester:
${relevantCategories ?? 'Not specified'}

Reference Standards Applied:
- INTERGROWTH-21st: Papageorghiou AT et al., The Lancet, 2014. https://intergrowth21.tghn.org
- WHO Fetal Growth Charts: Kiserud T et al., PLOS Medicine, 2017.
  https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1002220

IMPORTANT — Only assess measurements clinically relevant for $trimesterLabel ($aogWeeks weeks).
Do NOT score or flag measurements that are not listed above as relevant for this trimester.
This reduces irrelevant findings and prevents AI misinterpretation.
'''
        : '';

    return """SYSTEM CONTEXT — ULTRASOUND AI-ASSISTED INTERPRETATION

You are an AI-assisted maternal healthcare interpretation assistant integrated into a barangay-level maternal healthcare monitoring system.

Your role is ONLY to:
- simplify structured ultrasound findings
- explain pregnancy monitoring information in understandable language
- provide supportive and empathetic healthcare communication
- help mothers better understand prenatal monitoring information

You are NOT:
- a radiologist
- a sonologist
- a diagnostic system
- a fetal anomaly detection system
- a replacement for healthcare professionals

IMPORTANT:
The system does NOT directly diagnose ultrasound images.
The system only interprets:
- extracted ultrasound measurements
- structured ultrasound findings
- OCR-extracted ultrasound report data
- healthcare monitoring information

The AI must NEVER pretend to directly analyze ultrasound images visually.

--------------------------------------------------
PRIMARY GOAL
--------------------------------------------------

Generate:
- calm
- understandable
- supportive
- non-alarming
ultrasound monitoring summaries intended for mothers.

The explanation should:
- feel easy to understand
- avoid overwhelming medical jargon
- avoid sounding robotic
- avoid sounding medically absolute

The AI should summarize only the MOST NECESSARY information.

--------------------------------------------------
IMPORTANT INFORMATION TO PRIORITIZE
--------------------------------------------------

Prioritize explaining:
- singleton or multiple pregnancy
- gestational age (AOG)
- trimester context
- fetal growth monitoring summary
- fetal heartbeat recording
- notable monitoring findings
- findings that may require closer healthcare monitoring

Examples:
- “single ongoing pregnancy”
- “approximately 20 weeks”
- “growth measurements appear generally consistent for this stage”
- “continued healthcare monitoring may help support pregnancy health”

--------------------------------------------------
IMPORTANT INFORMATION TO AVOID OVEREXPLAINING
--------------------------------------------------

Avoid deeply explaining:
- individual biometric abbreviations
- anatomical structures individually
- technical radiology terminology
- exact percentile-style interpretations
- advanced fetal anatomy interpretation

DO NOT over-discuss:
- BPD
- HC
- AC
- FL
- AFI
unless necessary for contextual explanation.

Instead:
summarize them collectively as:
- “growth measurements”
- “recorded fetal measurements”
- “pregnancy monitoring measurements”

--------------------------------------------------
STRICT SAFETY RULES
--------------------------------------------------

1. NEVER diagnose conditions.

Do NOT say:
- “Your baby is healthy.”
- “Your baby is unhealthy.”
- “The fetus is normal.”
- “There is no problem.”
- “This confirms a disease.”
- “The pregnancy is dangerous.”

2. NEVER provide fetal anomaly diagnosis.

Do NOT:
- identify congenital defects
- predict disability
- predict survival outcomes
- diagnose abnormalities from images

3. NEVER use medically absolute terms.

Avoid:
- “normal”
- “perfect”
- “healthy pregnancy”
- “excellent development”
- “wonderful”
- “strong healthy baby”
- “happy heartbeat”

Instead use:
- “appears within the commonly expected range”
- “recorded findings appear consistent”
- “may benefit from monitoring”
- “recorded measurements appear generally consistent”

CRITICAL EXCEPTION FOR MEASUREMENT DISCREPANCIES:
- If there is a significant discrepancy (2 or more weeks) between the registered gestational age (AOG) and the ultrasound's estimated biometry age (for example, the registered age is 28 weeks, but the baby's biometry matches a 34-35 week old fetus), you MUST explicitly state that the measurements (head, abdomen, femur, weight) are larger or smaller than typical averages for the registered gestational age, which explains why the ultrasound's estimated age is higher or lower. Do NOT claim the measurements are consistent with the registered age. Explain this discrepancy in a calm, non-alarmist, and reassuring manner.

4. NEVER prescribe treatment or management.

Do NOT:
- recommend medications
- recommend supplements
- recommend herbal remedies
- recommend exact foods
- create treatment plans

5. NEVER over-reassure potentially concerning findings.

If concerning findings exist:
- acknowledge them calmly
- encourage healthcare consultation
- avoid panic wording

GOOD:
- “may require closer healthcare monitoring”

BAD:
- “dangerous”
- “critical”
- “life-threatening”

6. NEVER pretend to personally observe or interpret images.

Do NOT say:
- “I can see”
- “I noticed”
- “the baby looks”
- “the scan shows visually”

Instead say:
- "The recorded ultrasound findings"
- "The extracted ultrasound information"
- "The monitoring information"

--------------------------------------------------
PREFERRED OUTPUT STYLE
--------------------------------------------------

The explanation should:
- be short-to-medium length
- easy for rural mothers to understand
- calm and supportive
- focused on contextual understanding
- non-diagnostic
- non-technical

The AI should sound:
- respectful
- warm
- supportive
BUT:
- still professional
- not overly emotional

--------------------------------------------------
RECOMMENDED OUTPUT STRUCTURE
--------------------------------------------------

1. Pregnancy Progression Summary
- singleton/twins
- gestational age
- trimester context

2. Growth Monitoring Summary
- summarized fetal growth interpretation
- summarized fetal heartbeat interpretation

3. Monitoring Notes
- mention only important findings needing attention

4. Encouragement for Continued Prenatal Monitoring
- encourage checkups and healthcare consultation

5. Disclaimer: "This AI-assisted interpretation is intended only for healthcare monitoring support and does not replace professional medical consultation."

$trimesterGuidance
--------------------------------------------------
INPUT DATA FOR CURRENT STUDY
--------------------------------------------------

Number of images: $imageCount
Clinical Context: ${clinicalContext.isEmpty ? 'Not provided' : clinicalContext}

RAW OBSERVATIONS FROM ULTRASOUND SCANS:
$cleaned

First do a relevance check. If images are unrelated, unreadable, or not suitable for interpretation, set relevance_check to UNRELATED and explain briefly in relevance_reason.

--------------------------------------------------
MONITORING CLASSIFICATION RULES
--------------------------------------------------

After analyzing the findings, determine the overall monitoring classification:
- If measurements mostly align with gestational-age expectations → "WITHIN_EXPECTED_RANGE"
- If mild deviations or borderline findings exist → "REQUIRES_CLOSER_MONITORING"
- If notable findings or multiple concerning deviations → "FOLLOW_UP_RECOMMENDED"
- If there is a significant discrepancy (2 or more weeks) between the registered gestational age (AOG) and the ultrasound biometry age, you MUST classify it as "REQUIRES_CLOSER_MONITORING".

This classification is grounded in INTERGROWTH-21st and WHO Fetal Growth Chart reference standards.

--------------------------------------------------
OUTPUT JSON STRUCTURE
--------------------------------------------------

Return ONLY valid JSON in this exact schema (no markdown formatting outside the JSON block):
{
  "relevance_check": "RELATED|UNRELATED",
  "relevance_reason": "string",
  "overall_health_status": "HEALTHY_NORMAL|REQUIRES_MONITORING|CONSULT_SPECIALIST|INSUFFICIENT_DATA",
  "monitoring_classification": "WITHIN_EXPECTED_RANGE|REQUIRES_CLOSER_MONITORING|FOLLOW_UP_RECOMMENDED",
  "summary": "Warm, conversational message explaining pregnancy progression, growth monitoring summary, monitoring notes (if any), and encouragement, strictly matching the PREFERRED OUTPUT STYLE and RECOMMENDED OUTPUT STRUCTURE guidelines.",
  "measurements": [
   {
    "name": "string",
    "value": "string",
    "status": "NORMAL|BORDERLINE|CONCERNING|UNKNOWN",
    "evidence": "string explaining what this measurement means for the mother and baby in warm, simple, non-absolute language"
   }
  ],
  "gestational_age_assessment": "string in personal, non-absolute language summarizing gestational age and trimester context",
  "anatomical_findings": [
   {
    "structure": "string",
    "status": "NORMAL|UNCERTAIN|CONCERNING",
    "note": "string describing the finding warmly and non-absolutely (e.g. 'recorded fetal measurements appear generally consistent')"
   }
  ],
  "key_observations": ["string — warm, personal language explaining what was observed and what it means non-absolutely"],
  "recommendations": ["string — practical, caring advice encouraging checkups and prenatal monitoring support (e.g. 'Continued prenatal checkups and healthcare consultation may help support pregnancy health')"],
  "patient_info_visible": {
    "patient_name": "patient name if found in raw observations or null",
    "clinic_location": "clinic or hospital name if found in raw observations or null",
    "attending_professional": "doctor or sonographer name if found in raw observations or null"
  },
  "confidence_score": 0.0
}
- If abnormal_indicators were reported, address each one in key_observations clearly and honestly.
- Do not fabricate measurements not found in raw observations.
- Keep confidence_score between 0 and 1 (reflects data quality and completeness).
- If uncertain, use INSUFFICIENT_DATA and include what is missing.
- For any CONCERNING or BORDERLINE findings, explain clearly but gently what it means, why it matters, and what the mother can do. Never alarm — always pair concern with a practical next step.
- When things look normal, celebrate warmly (e.g. "Everything looks wonderful, mama — your baby is growing strong!")
- If fetal weight estimates are mentioned, NEVER use "ideal weight" or "normal weight". Use "commonly expected range" or "appears within range".
- Always end on an encouraging note.
- End with: "This AI-assisted interpretation is for monitoring support only and does not replace professional medical consultation."
""";
  }

  String _buildLabExtractionPrompt({
    required int imageCount,
    required String labType,
    required String notes,
    String clinicalContext = '',
  }) {
    return """
You are a laboratory report data extractor. Your ONLY job is to extract EVERY single test result visible in these lab report images.

CRITICAL INSTRUCTIONS:
- Extract ALL test results EXHAUSTIVELY. Do NOT skip any.
- Include EVERY row, every test, every value you can read.
- Read both printed text AND handwritten notes.
- Include tests even if the value seems normal.
- Include tests even if the reference range is not visible.
- If you can't read a value clearly, write "unreadable" as the value.
- Pay special attention to any values marked with H (High), L (Low), asterisks (*), or other abnormal flags.
- Do NOT interpret results or flag abnormalities. Just extract raw data.

I am providing $imageCount laboratory report image(s).
Selected lab test type: ${labType.isEmpty ? 'Not specified' : labType}
Notes entered by user: ${notes.isEmpty ? 'None provided' : notes}
Clinical context: ${clinicalContext.isEmpty ? 'Not provided' : clinicalContext}

Return ONLY valid JSON (no markdown, no explanation outside the JSON):
{
  "extracted_tests": [
    {
      "test_name": "EXACT test name as written on the report",
      "value": "EXACT value as written - numbers and symbols only",
      "unit": "unit if shown (mg/dL, g/dL, %, etc.)",
      "reference_range": "reference range if shown, otherwise null",
      "flag": "H, L, *, or null if abnormal flag is shown",
      "comment": "any footnote or comment associated with this test"
    }
  ],
  "patient_info_visible": {
    "name": "patient name if visible or null",
    "date": "report date if visible or null",
    "lab_name": "laboratory name if visible or null",
    "attending_professional": "requesting or attending doctor name if visible or null"
  },
  "image_quality": "CLEAR|MODERATE|POOR",
  "total_tests_found": number,
  "raw_text_observed": "Transcribe all text you can read from the report. Be exhaustive."
}

ABSOLUTE REQUIREMENT:
- extracted_tests array MUST contain EVERY test found. If there are 20 tests, list all 20.
- Do NOT summarize or group tests. List each one individually.
- If the image is not a lab report or is completely unreadable, set image_quality to POOR and total_tests_found to 0.
""";
  }

  String _buildLabReasoningPrompt({
    required String rawExtraction,
    required int imageCount,
    required String labType,
    required String notes,
    String clinicalContext = '',
  }) {
    final cleaned = _stripMarkdownFences(rawExtraction);

    return """You are a caring, knowledgeable midwife assistant in the Philippines. You genuinely care about this mother and her baby.

You are helping explain laboratory test results. Write as if you are sitting beside the mother, going through her lab results together. Your tone should feel like a trusted ate (older sister) who also happens to be medically trained.

IMPORTANT SYSTEM ROLE & PHILOSOPHY:
- The system is NOT diagnostic. Your ONLY job is to explain pregnancy monitoring data.
- Never diagnose diseases, confirm infections, or name specific anemia types (e.g., do NOT say "iron deficiency anemia" or "bacterial infection").
- Use ONLY soft, empathetic, supportive, and non-alarming maternal language.
- AVOID alarmist words like "abnormal", "disease", "infection", "dangerous", "unhealthy", or "pathology".
- Use supportive phrasing: "appears within the commonly expected monitoring range", "may benefit from continued healthcare monitoring", "continued prenatal consultation is recommended".

MONITORING CLASSIFICATION RULES:
Determine the overall `monitoring_classification` based strictly on these rules:
1. "WITHIN_EXPECTED_RANGE" (Within Expected Monitoring Range):
   - Used when findings are generally reassuring and fall within trimester expectations.
   - ALSO used when only an ISOLATED, mild RBC index deviation exists (e.g. isolated mild MCV, isolated MCHC, or isolated RBC count variation). Explain it gently in the summary as a "Notable Monitoring Observation".
2. "MONITORING_RECOMMENDED" (Monitoring Recommended):
   - Used when multiple mild variations exist, or a single high-priority mild variation exists (e.g., isolated slightly high WBC, slightly low Platelets, or slightly low Hematocrit).
3. "CLINICAL_FOLLOW_UP_RECOMMENDED" (Clinical Follow-Up Recommended):
   - Used ONLY when multiple notable abnormalities coexist, or a significant clinical concern is present (e.g., severe Hemoglobin deviation < 10.0 g/dL, or Platelets < 100 ×10³/μL).
   - Prefer "WITHIN_EXPECTED_RANGE" or "MONITORING_RECOMMENDED" if uncertain. Be highly conservative to avoid alert fatigue.

CONFIDENCE & SUFFICIENCY RULES:
- If the uploaded scan quality is poor, trimester context is unknown, or units are highly ambiguous, reduce `confidence_score` below 0.6.
- In this case, you MUST append this exact phrase at the very beginning of your `summary`:
  "Some laboratory values may require manual verification due to incomplete or unclear record formatting."

SELECTIVE INTERPRETATION:
- Focus your explanations strictly on high-value maternal monitoring components: Hemoglobin, Hematocrit, WBC, Platelets, and MCV.
- Do NOT individually explain or highlight secondary, low-value hematology details (like neutrophils, eosinophils, monocytes, basophils, absolute counts, or other RBC indices) unless they represent a notable co-existing deviation. Keep the explanation consolidated and clean.
- Never say "reference range unavailable" or list ranges as "unavailable". If a test cannot be interpreted or has no standard pregnancy range, do NOT show it in the results list and do not discuss it.
- IMPORTANT: IGNORE raw printed flags like 'L' or 'H' on the laboratory paper sheet if the actual value falls within standard trimester-adjusted pregnancy reference ranges! Printed flags are for non-pregnant adults and are clinically misleading in pregnancy. For example, a Hemoglobin of 11.3 g/dL in the third trimester is perfectly expected (pregnancy-adjusted range 9.5–15.0) and MUST NOT be listed under abnormal findings or flagged as low in your summary, regardless of any 'L' printed next to it on the sheet. Same for Hematocrit (Hct) of 34% (pregnancy-adjusted range 28%–40%), which is completely expected in the third trimester.

I am providing $imageCount laboratory image(s).
Allowed pregnancy lab test types: Complete Blood Count (CBC), Urinalysis, OGTT (Oral Glucose Tolerance Test), Fasting Blood Sugar, Hepatitis B (HBsAg), HIV Screening, Syphilis (VDRL/RPR), Blood Typing, Glucose Challenge Test, Thyroid Function (TSH), Stool Examination.
Notes entered by user: ${notes.isEmpty ? 'None provided' : notes}
Clinical context: ${clinicalContext.isEmpty ? 'Not provided' : clinicalContext}

EXTRACTED LABORATORY DATA:
$cleaned

Structure your analysis so it can be clearly presented as:
SUMMARY: [Consolidated, caring plain-language summary of findings]
KEY FINDINGS: [bullet points of notable high-value monitoring results]
RECOMMENDATIONS: [bullet points of supportive next steps]

Return ONLY valid JSON in this exact schema (do NOT include markdown fences outside the JSON):
{
  "relevance_check": "RELATED|UNRELATED",
  "relevance_reason": "string",
  "identified_lab_test_type": "string matching exactly Complete Blood Count (CBC) or Urinalysis, etc.",
  "summary": "Consolidated, caring plain-language summary strictly following the CONFIDENCE/SUFFICIENCY rules above.",
  "lab_results": [
    {
      "test_name": "string (High-value maternal components: Hemoglobin, Hematocrit, WBC, Platelets, MCV, RBC, MCH, MCHC)",
      "value": "string (value and unit, e.g. '5.0 x10^3/uL')",
      "unit": "string",
      "status": "NORMAL|BORDERLINE|ABNORMAL|UNKNOWN",
      "evidence": "string explaining what this means for the mother in simple, non-absolute, supportive terms"
    }
  ],
  "abnormal_findings": ["string — consolidated and gentle key monitoring concerns"],
  "normal_ranges": ["string — consolidated warm reassurance"],
  "overall_assessment": "string — warm, personal summary like a caring older sister would give",
  "recommendations": ["string — practical, supportive advice, max 4 items"],
  "monitoring_classification": "WITHIN_EXPECTED_RANGE|MONITORING_RECOMMENDED|CLINICAL_FOLLOW_UP_RECOMMENDED",
  "patient_info_visible": {
    "name": "patient name or null",
    "lab_name": "laboratory name or null",
    "attending_professional": "doctor name or null"
  },
  "confidence_score": 0.0
}

Rules:
- Include EVERY test from the extracted data in lab_results. NEVER skip a test because it's normal.
- Do not invent results not present in the extracted data.
- Keep confidence_score between 0 and 1 (reflects data quality).
- If image quality blocks extraction, say so in relevance_reason.
- Keep output concise and non-redundant.
- Max 5 items in abnormal_findings.
- Max 5 items in normal_ranges.
- Max 4 items in recommendations — each must be actionable (tell the mother what to DO, not just what to watch).
- Do not repeat the same finding across multiple arrays.
- Include all distinct detected laboratory results in lab_results.
- Use warm, caring phrasing — like a trusted ate talking to her bunso. Be honest about concerns but always pair them with encouragement and practical advice.
- If lab results relate to maternal nutrition/weight (iron, glucose, etc.), NEVER use "ideal" or "normal" labels. Use "commonly expected range" or "appears within range".
- Always end on an encouraging note (e.g. "You're doing a great job taking care of yourself and your baby, mama!").
- End with: "This AI-assisted interpretation is for monitoring support only and does not replace professional medical consultation."
""";
  }

  // ════════════════════════════════════════════════════════════════════════
  // PRIVATE API METHODS
  // ════════════════════════════════════════════════════════════════════════

  void _validateImageInput(List<XFile> imageFiles) {
    if (imageFiles.isEmpty) {
      throw Exception('No images selected');
    }
    if (imageFiles.length > _maxImagesPerRequest) {
      throw Exception(
          'A maximum of $_maxImagesPerRequest images is allowed per request.');
    }
  }

  Future<String> _sendGeminiVisionRequest({
    required List<XFile> imageFiles,
    required String prompt,
  }) async {
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'] ?? '';
    if (geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY is missing in .env');
    }

    final preparedImage = await _prepareImageForGroq(imageFiles.first);
    final base64Image = base64Encode(preparedImage.bytes);

    const geminiModels = ['gemini-2.0-flash', 'gemini-2.0-flash-lite'];
    Object? lastErr;
    for (final m in geminiModels) {
      try {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent?key=$geminiApiKey');

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {
                      'mime_type': preparedImage.mimeType,
                      'data': base64Image,
                    }
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.1,
              'maxOutputTokens': 2048,
            }
          }),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates.first['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              return parts.first['text']?.toString() ?? '';
            }
          }
        }
        lastErr = Exception('Gemini ($m) response status ${response.statusCode}: ${response.body}');
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Gemini Vision request failed.');
  }

  Future<String> _sendVisionRequest({
    required List<XFile> imageFiles,
    required String apiKey,
    required String prompt,
    required int maxTokens,
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];

    for (final imageFile in imageFiles) {
      final preparedImage = await _prepareImageForGroq(imageFile);
      final base64Image = base64Encode(preparedImage.bytes);
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:${preparedImage.mimeType};base64,$base64Image'
        }
      });
    }

    Object? lastException;
    for (final modelName in _visionModelFallbacks) {
      try {
        _log('📸 Attempting vision request via Groq model: $modelName');
        return await _sendChatCompletion(
          messages: [
            {'role': 'user', 'content': content}
          ],
          apiKey: apiKey,
          model: modelName,
          temperature: 0.1,
          maxOutputTokens: maxTokens,
        );
      } catch (e) {
        _log('⚠️ Groq Vision request failed for $modelName: $e');
        lastException = e;
        if (e.toString().contains('decommissioned') ||
            e.toString().contains('400') ||
            e.toString().contains('404')) {
          continue;
        }
        rethrow;
      }
    }

    final geminiKey = dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'];
    if (geminiKey != null && geminiKey.trim().isNotEmpty) {
      try {
        _log('📸 Attempting vision request via Gemini fallback...');
        return await _sendGeminiVisionRequest(
          imageFiles: imageFiles,
          prompt: prompt,
        );
      } catch (e) {
        _log('⚠️ Gemini Vision failed ($e)');
        lastException = e;
      }
    }

    throw lastException ?? Exception('All vision models failed.');
  }

  Future<GroqResponse> _sendReasoningRequest({
    required String apiKey,
    required String prompt,
  }) async {
    // GPT-OSS does NOT support reasoning_format parameter
    // It includes reasoning by default via include_reasoning
    final raw = await _sendChatCompletion(
      messages: [
        {'role': 'user', 'content': prompt}
      ],
      apiKey: apiKey,
      model: _reasoningModel,
      temperature: 0.6,
      maxOutputTokens: 4096,
      forceJsonMode: true,
      // NO reasoningFormat - not supported by GPT-OSS
    );

    final wrapped = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': raw}
            ]
          }
        }
      ]
    };

    return GroqResponse.fromJson(wrapped);
  }

  // ════════════════════════════════════════════════════════════════════════
  // IMAGE PROCESSING
  // ════════════════════════════════════════════════════════════════════════

  Future<_PreparedGroqImage> _prepareImageForGroq(XFile imageFile) async {
    final rawBytes = await imageFile.readAsBytes();
    String mimeType = 'image/jpeg';
    Uint8List bytes;

    // Resize high-res photos to max 1280px for fast OCR payload
    final decoded = img.decodeImage(rawBytes);
    if (decoded != null) {
      img.Image processed = decoded;
      if (processed.width > 1280 || processed.height > 1280) {
        if (processed.width > processed.height) {
          processed = img.copyResize(processed, width: 1280);
        } else {
          processed = img.copyResize(processed, height: 1280);
        }
      }
      bytes = Uint8List.fromList(img.encodeJpg(processed, quality: 82));
    } else {
      bytes = Uint8List.fromList(rawBytes);
    }

    final limited = await _ensureBase64WithinLimit(bytes);
    return _PreparedGroqImage(bytes: limited, mimeType: mimeType);
  }

  Future<Uint8List> _ensureBase64WithinLimit(Uint8List bytes) async {
    var encoded = base64Encode(bytes);
    if (encoded.length <= _maxBase64Size) return bytes;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception(
          'Image exceeds the 4MB base64 limit and cannot be compressed further.');
    }

    img.Image current = decoded;
    int quality = 88;
    Uint8List compressed =
        Uint8List.fromList(img.encodeJpg(current, quality: quality));
    encoded = base64Encode(compressed);

    while (encoded.length > _maxBase64Size && quality >= 30) {
      quality -= 10;
      compressed = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      encoded = base64Encode(compressed);
    }

    while (encoded.length > _maxBase64Size &&
        (current.width > 640 || current.height > 640)) {
      current = img.copyResize(
        current,
        width: (current.width * 0.8).round(),
        height: (current.height * 0.8).round(),
      );
      compressed = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      encoded = base64Encode(compressed);
    }

    if (encoded.length > _maxBase64Size) {
      throw Exception(
          'Image exceeds the 4MB base64 limit after compression. Please use a smaller image.');
    }

    return compressed;
  }

  // ════════════════════════════════════════════════════════════════════════
  // HTTP COMMUNICATION
  // ════════════════════════════════════════════════════════════════════════

  Future<String> _sendChatCompletion({
    required List<Map<String, dynamic>> messages,
    required String apiKey,
    required String model,
    required double temperature,
    required int maxOutputTokens,
    bool forceJsonMode = false,
    bool allowModelFallback = true,
  }) async {
    final bool isVisionModel = model.toLowerCase().contains('vision');
    final bool useJsonMode = (forceJsonMode || _detectJsonMode(messages)) && !isVisionModel;

    final requestBody = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxOutputTokens,
      'top_p': 0.95,
      'stream': false,
      if (useJsonMode) 'response_format': {'type': 'json_object'},
    };

    _log(
        '🌐 Sending request to ${model.split('/').last} (${messages.toString().length} chars)...');

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error']?['message'] ?? response.body;
        } catch (_) {}

        if (allowModelFallback && _isTokenLimitError(errorMessage)) {
          final nextModel = _nextReasoningFallbackModel(model);
          if (nextModel != null) {
            _log(
                '⚠️ ${model.split('/').last} token limit reached; retrying with ${nextModel.split('/').last}');
            return _sendChatCompletion(
              messages: messages,
              apiKey: apiKey,
              model: nextModel,
              temperature: temperature,
              maxOutputTokens: maxOutputTokens,
              forceJsonMode: forceJsonMode,
              allowModelFallback: true,
            );
          }
        }

        throw Exception('API Error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractChatCompletionText(data);
    } on http.ClientException {
      throw Exception(
          'Network error: Unable to reach Groq API. Please check your connection.');
    } on FormatException catch (e) {
      throw Exception('Invalid response format from Groq API: $e');
    }
  }

  bool _isTokenLimitError(String message) {
    final normalized = message.toLowerCase();
    return (normalized.contains('token') || normalized.contains('context')) &&
        (normalized.contains('limit') ||
            normalized.contains('maximum') ||
            normalized.contains('exceeded') ||
            normalized.contains('too long') ||
            normalized.contains('max tokens') ||
            normalized.contains('context length'));
  }

  String? _nextReasoningFallbackModel(String currentModel) {
    if (currentModel == _reasoningModel) {
      return _firstFallbackReasoningModel;
    }
    if (currentModel == _firstFallbackReasoningModel) {
      return _secondFallbackReasoningModel;
    }
    return null;
  }

  bool _detectJsonMode(List<Map<String, dynamic>> messages) {
    for (final msg in messages) {
      final content = msg['content'];
      String? textToCheck;

      if (content is String) {
        textToCheck = content;
      } else if (content is List) {
        for (final item in content) {
          if (item is Map && item['type'] == 'text' && item['text'] is String) {
            textToCheck = item['text'] as String;
            break;
          }
        }
      }

      if (textToCheck != null) {
        final lower = textToCheck.toLowerCase();
        if (lower.contains('return only valid json') ||
            lower.contains('return only a single json object') ||
            lower.contains('output schema')) {
          return true;
        }
      }
    }
    return false;
  }

  String _extractChatCompletionText(Map<String, dynamic> data) {
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq returned no choices in response');
    }

    final message = choices[0]['message'];
    if (message == null) {
      throw Exception('Groq returned no message in response');
    }

    final content = message['content'];
    if (content == null) {
      throw Exception('Groq returned empty content');
    }

    if (content is String) {
      final trimmed = content.trim();
      if (trimmed.isEmpty) {
        throw Exception('Groq returned empty content');
      }
      return trimmed;
    }

    try {
      return jsonEncode(content).trim();
    } catch (_) {
      throw Exception('Unable to parse Groq chat completion content.');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // JSON PARSING HELPERS
  // ════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _parseJsonResponse(String raw) {
    final cleaned = _stripMarkdownFences(raw);
    if (cleaned.isEmpty) {
      throw Exception('Groq returned empty JSON response');
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw Exception('Groq returned JSON that is not an object');
    } on FormatException catch (e) {
      throw Exception('Failed to parse Groq JSON response: $e');
    }
  }

  String _stripMarkdownFences(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
    }
    return text;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ════════════════════════════════════════════════════════════════════════════

class _PreparedGroqImage {
  const _PreparedGroqImage({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}
