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
  ];
  /// Text reasoning chain, largest first.
  ///
  /// Groq removed the whole Llama 3.x line — `llama-3.3-70b-versatile`,
  /// `llama-3.1-8b-instant` and `llama-3.1-70b-versatile` are no longer served,
  /// which is why every AI insight fell through to its rule-based fallback
  /// while OCR kept working: the vision path had already moved to Qwen.
  ///
  /// Check what an account can actually reach before changing these:
  ///   curl https://api.groq.com/openai/v1/models -H "Authorization: Bearer $GROQ_API_KEY"
  static const String _reasoningModel = 'openai/gpt-oss-120b';
  static const String _firstFallbackReasoningModel = 'openai/gpt-oss-20b';

  /// Deliberately a different model family from the first two, so a fault in
  /// one family does not take the last fallback down with it. It is also the
  /// vision model, so it is the one model here already proven in this app.
  static const String _secondFallbackReasoningModel = 'qwen/qwen3.6-27b';

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

  static const String _groqBaseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  /// NVIDIA NIM speaks the same OpenAI-compatible protocol as Groq, so the
  /// same request body works against either host.
  static const String _nvidiaBaseUrl =
      'https://integrate.api.nvidia.com/v1/chat/completions';

  /// Groq text model → NVIDIA NIM equivalent, used when Groq is rate-limited
  /// or down. These are the same weights on both hosts, so the prompts and
  /// safety rules behave identically on the fallback.
  ///
  /// A model with no entry here simply has no cross-provider fallback —
  /// [_tryNvidiaFallback] logs and returns null rather than guessing at an id
  /// the host may not serve.
  ///
  /// Vision models are deliberately absent: that path already falls back to
  /// Gemini in [_sendVisionRequest], and NVIDIA's VLMs expect a different
  /// image payload shape than the OpenAI-style `image_url` blocks we send.
  static const Map<String, String> _nvidiaModelEquivalents = {
    _reasoningModel: 'openai/gpt-oss-120b',
    _firstFallbackReasoningModel: 'openai/gpt-oss-20b',
  };

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

  /// Optional — returns null when no NVIDIA key is configured, in which case
  /// the provider fallback is simply skipped.
  String? _getNvidiaApiKey() {
    final apiKey = dotenv.env['NVIDIA_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) return null;
    return apiKey.trim();
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
You are a precise document OCR data extractor. Perform text recognition on the provided ultrasound image and return ONLY a raw JSON object matching this exact schema:

{
  "ultrasound_date": "YYYY-MM-DD",
  "ega_weeks": 16,
  "ega_days": 0,
  "location_facility": "Santa Maria, Mexico, Pampanga",
  "institution_name": "Austria Diagnostic Center",
  "sonologist_name": "Dr. Adelyn U. Sahagun",
  "fetal_count": 1,
  "sonologist_remarks": "SINGLE LIVE INTRAUTERINE PREGNANCY 16 WEEKS AOG BY FETAL BIOMETRY"
}

- For sonologist_name: Extract the Physician or Doctor name printed under "Referring Physician" or "Doctor" heading (e.g. Dr. Adelyn U. Sahagun).
- For sonologist_remarks: Look for "IMPRESSION:" heading and extract ONLY the main diagnosis line.

CRITICAL: Extract ONLY actual text printed on the document image. DO NOT write conversational explanations or reasoning notes.

RETURN ONLY THE RAW JSON OBJECT. DO NOT INCLUDE ANY THINKING OR REASONING PROCESS (<think>). DO NOT INCLUDE MARKDOWN CODE BLOCKS.
''';

      final String rawOutput = await _sendVisionRequest(
        imageFiles: [imageFiles.first],
        apiKey: apiKey,
        prompt: prompt,
        maxTokens: 3500,
      );

      _log('📄 Raw Ultrasound OCR Vision output: $rawOutput');

      // Strip thinking process tags (e.g. <think>...</think>) produced by reasoning models
      String cleaned = rawOutput.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();

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

      // Fallback regex parsing if fields are missing or JSON parse failed
      if (data['ultrasound_date'] == null || data['ultrasound_date'].toString().isEmpty) {
        final dateMatch = RegExp(r'(?:ultrasound_date|Date|DATE)[\s\*:="]*([A-Za-z0-9\s,-/]+)', caseSensitive: false).firstMatch(rawOutput);
        if (dateMatch != null) {
          final dtStr = dateMatch.group(1)!.trim().replaceAll('"', '');
          final parsedDt = _parseFlexibleDate(dtStr);
          if (parsedDt != null) {
            data['ultrasound_date'] = DateFormat('yyyy-MM-dd').format(parsedDt);
          } else {
            data['ultrasound_date'] = dtStr;
          }
        }
      }

      if (data['ega_weeks'] == null) {
        final aogMatch = RegExp(r'(?:ega_weeks|AOG|Age)[\s\*:="]*(\d{1,2})', caseSensitive: false).firstMatch(rawOutput);
        if (aogMatch != null) {
          data['ega_weeks'] = int.tryParse(aogMatch.group(1)!);
        }
      }

      if (data['ega_days'] == null) {
        final daysMatch = RegExp(r'(?:ega_days)[\s\*:="]*(\d{1,2})', caseSensitive: false).firstMatch(rawOutput);
        if (daysMatch != null) {
          data['ega_days'] = int.tryParse(daysMatch.group(1)!);
        }
      }

      if (data['institution_name'] == null || data['institution_name'].toString().isEmpty) {
        final instMatch = RegExp(r'(?:institution_name|institution)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (instMatch != null && _cleanExtractedText(instMatch.group(1)) != null) {
          data['institution_name'] = instMatch.group(1)!.trim();
        } else {
          final headerMatch = RegExp(r'([A-Za-z\s]+(?:diagnostic center|diagnostic|center|clinic|hospital|medical center))', caseSensitive: false).firstMatch(rawOutput);
          if (headerMatch != null) {
            data['institution_name'] = headerMatch.group(1)!.trim();
          }
        }
      }

      if (data['location_facility'] == null || data['location_facility'].toString().isEmpty) {
        final locMatch = RegExp(r'(?:location_facility|location|facility)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (locMatch != null && _cleanExtractedText(locMatch.group(1)) != null) {
          data['location_facility'] = locMatch.group(1)!.trim();
        } else {
          final addrMatch = RegExp(r'(\d+[\w\s,]+(?:Pampanga|Mexico|Santa Maria|San Fernando|Angeles|Manila|Bulacan|Cavite|Laguna|Batangas|Rizal|[A-Z][a-z]+))', caseSensitive: false).firstMatch(rawOutput);
          if (addrMatch != null) {
            data['location_facility'] = addrMatch.group(1)!.trim();
          }
        }
      }

      if (data['sonologist_name'] == null || data['sonologist_name'].toString().isEmpty || data['sonologist_name'].toString().toUpperCase().contains('RAHMI')) {
        final physMatch = RegExp(r'(?:referring physician|physician|doctor|attending)[\s\*:="]*"?([A-Za-z\.\s-]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (physMatch != null && _cleanExtractedText(physMatch.group(1)) != null) {
          data['sonologist_name'] = physMatch.group(1)!.trim();
        } else {
          final docMatch = RegExp(r'(?:sonologist_name|sonologist|physician)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
          if (docMatch != null && _cleanExtractedText(docMatch.group(1)) != null) {
            data['sonologist_name'] = docMatch.group(1)!.trim();
          } else {
            final docMatch2 = RegExp(r'(?:DR\.|DOCTOR)[\sA-Za-z\.-]+', caseSensitive: false).firstMatch(rawOutput);
            if (docMatch2 != null) {
              data['sonologist_name'] = docMatch2.group(0)!.trim();
            }
          }
        }
      }

      if (data['fetal_count'] == null) {
        if (rawOutput.toUpperCase().contains('SINGLETON')) {
          data['fetal_count'] = 1;
        } else if (rawOutput.toUpperCase().contains('TWIN')) {
          data['fetal_count'] = 2;
        }
      }

      if (data['sonologist_remarks'] == null || data['sonologist_remarks'].toString().isEmpty) {
        final remMatch = RegExp(r'(?:sonologist_remarks|remarks|IMPRESSION)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (remMatch != null && _cleanExtractedText(remMatch.group(1)) != null) {
          data['sonologist_remarks'] = remMatch.group(1)!.trim();
        }
      }

      data['institution_name'] = _cleanExtractedText(data['institution_name']);
      data['location_facility'] = _cleanExtractedText(data['location_facility']);
      data['sonologist_name'] = _cleanExtractedText(data['sonologist_name']);
      data['sonologist_remarks'] = _cleanExtractedText(data['sonologist_remarks']);

      return data;
    } catch (e) {
      _log('⚠️ Error extracting ultrasound summary OCR: $e');
      return {};
    }
  }

  /// Fast, targeted OCR summary extraction for lab test reports
  Future<Map<String, dynamic>> extractLabTestSummaryOCR(List<XFile> imageFiles) async {
    if (imageFiles.isEmpty) return {};
    try {
      final apiKey = _getApiKey();
      const prompt = '''
ANSWER WITH JSON ONLY. Do not think out loud. Do not write <think> blocks, notes, reasoning, or commentary of any kind. Your entire reply must be the JSON object and nothing else — the first character you write must be { and the last must be }.

This instruction is first because it is the one that matters most: a reply that reasons before answering runs out of room and never produces the JSON, and the extraction is lost even when every value was read correctly.

You are a precise document OCR data extractor for laboratory test reports. Perform text recognition on the provided image and return ONLY a raw JSON object matching this exact schema:

{
  "is_lab_test": true,
  "lab_test_type": "Complete Blood Count (CBC)",
  "lab_test_date": "YYYY-MM-DD",
  "institution_name": "Hi-Precision Diagnostics",
  "location_facility": "Hi-Precision Diagnostics, San Fernando, Pampanga",
  "health_worker_name": "Maria Santos, RMT",
  "health_worker_profession": "Medical Technologist",
  "blood_type": "O Positive",
  "glucose_fasting_mg_dl": 92,
  "glucose_1hr_mg_dl": 180,
  "glucose_2hr_mg_dl": 153,
  "glucose_3hr_mg_dl": null,
  "remarks": "Hemoglobin: 12.5 g/dL (Normal), WBC: 7.2 (Normal), Blood Type: O Positive"
}

Guidance:
- For is_lab_test: Set to true ONLY if the document is a Blood, Urine, Stool, or Clinical Pathology Laboratory Test (e.g. CBC, Urinalysis, Fasting Blood Sugar, OGTT, Blood Type, Hepatitis B, HIV, Syphilis). Set to false if the document is an Ultrasound report, X-Ray, Radiology scan, prescription, photo, or non-lab document.
- For lab_test_type: Identify the primary test title on the report header. Categories include:
  "Complete Blood Count (CBC)", "Urinalysis", "Fasting Blood Sugar (FBS)", "OGTT (Oral Glucose Tolerance Test)",
  "Blood Typing", "HBsAg (Hepatitis B)", "VDRL / Syphilis Test", "HIV Test", "Stool Exam", or "Other".
- For institution_name: Extract ONLY the laboratory, clinic, or hospital name (e.g. Flabs, Hi-Precision Diagnostics).
- For location_facility: Extract the facility name or address.
- For health_worker_name: Look for the Pathologist, Medical Technologist, Doctor, or Examiner signature printed at the bottom or header.
- For blood_type: Return the ABO and Rh result ONLY if the document explicitly prints one, copied exactly as it appears (e.g. "O Positive", "AB-", "B Rh(D) Negative"). Return null if the document does not state a blood type, if only the ABO group is shown without the Rh factor, or if the result is illegible. NEVER infer, guess, or carry over a blood type from any other value on the report — a blood type that is not printed on the document does not exist.
- For the glucose fields: Return plasma glucose values ONLY from a Fasting Blood Sugar, Glucose Challenge, or Oral Glucose Tolerance Test, matching each printed sample to its timing label (fasting/0 hour, 1 hour, 2 hours, 3 hours). Return the number only, WITHOUT units.
  * ALL FOUR VALUES MUST BE IN mg/dL. Philippine laboratories usually report mg/dL (values roughly 70-200). If the report states mmol/L (values roughly 4-11), return null for every glucose field — do NOT convert, and do NOT return the mmol/L number as if it were mg/dL.
  * Return null for any sample the document does not print. A test with only a fasting value returns null for the others.
  * Never infer a glucose value from HbA1c, urine glucose, or any other result. An unprinted value does not exist.
- For remarks: Extract a clean summary of the main lab values, blood type, or impression lines visible on the document. Do NOT interpret or diagnose.

CRITICAL: Extract ONLY actual text printed on the document image. DO NOT write conversational explanations or reasoning notes.

RETURN ONLY THE RAW JSON OBJECT. DO NOT INCLUDE ANY THINKING OR REASONING PROCESS (<think>). DO NOT INCLUDE MARKDOWN CODE BLOCKS.
''';

      // Sized against the tier's tokens-per-minute ceiling, not just against
      // what the reply needs.
      //
      // Groq counts the *whole* request — image, prompt, and the output budget
      // reserved here — against 8000 TPM. A 960px report page is roughly 3,400
      // input tokens, so anything above about 4,000 output returns 413 instead
      // of an answer. 2048 was too tight and truncated the reply mid-thought;
      // 6000 tipped the request over the limit. 3500 clears both, leaving
      // about a thousand spare so a retry inside the same minute does not push
      // it over.
      //
      // The real saving is the JSON-only instruction at the top of the prompt:
      // if the model stops narrating before it answers, this budget is ample.
      final String rawOutput = await _sendVisionRequest(
        imageFiles: [imageFiles.first],
        apiKey: apiKey,
        prompt: prompt,
        maxTokens: 3500,
      );

      _log('📄 Raw Lab Test OCR Vision output: $rawOutput');

      String cleaned = rawOutput.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();

      // Find valid JSON string containing target keys
      Map<String, dynamic> data = {};
      final jsonMatches = RegExp(r'\{[\s\S]*?\}').allMatches(cleaned);

      for (final match in jsonMatches) {
        final matchStr = match.group(0)!;
        if (matchStr.contains('"lab_test_type"') || matchStr.contains('"institution_name"') || matchStr.contains('"remarks"') || matchStr.contains('"is_lab_test"')) {
          try {
            data = Map<String, dynamic>.from(jsonDecode(matchStr) as Map);
            _log('✅ Successfully parsed JSON block from Vision OCR');
            break;
          } catch (_) {}
        }
      }

      // Check for ultrasound/radiology keywords to prevent misclassifying ultrasounds as lab tests
      final lowerRaw = rawOutput.toLowerCase();
      if (lowerRaw.contains('ultrasound') ||
          lowerRaw.contains('radiology') ||
          lowerRaw.contains('biophysical profile') ||
          lowerRaw.contains('sonogram') ||
          lowerRaw.contains('echography') ||
          lowerRaw.contains('obstetric ultrasound')) {
        data['is_lab_test'] = false;
      }

      if (data['lab_test_date'] == null || data['lab_test_date'].toString().isEmpty) {
        final dateMatch = RegExp(r'(?:lab_test_date|Date|DATE)[\s\*:="]*"?([A-Za-z0-9\s,-/]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (dateMatch != null) {
          final dtStr = dateMatch.group(1)!.trim().replaceAll('"', '');
          final parsedDt = _parseFlexibleDate(dtStr);
          if (parsedDt != null) {
            data['lab_test_date'] = DateFormat('yyyy-MM-dd').format(parsedDt);
          } else {
            data['lab_test_date'] = dtStr;
          }
        }
      }

      if (data['lab_test_type'] == null || data['lab_test_type'].toString().isEmpty) {
        final typeMatch = RegExp(r'(?:lab_test_type|test_type|Test|TEST)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (typeMatch != null && _cleanExtractedText(typeMatch.group(1)) != null) {
          data['lab_test_type'] = typeMatch.group(1)!.trim();
        }
      }

      if (data['institution_name'] == null || data['institution_name'].toString().isEmpty || _cleanExtractedText(data['institution_name']) == null) {
        final instMatch = RegExp(r'(?:institution_name|institution|laboratory|hospital|facility)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (instMatch != null && _cleanExtractedText(instMatch.group(1)) != null) {
          data['institution_name'] = instMatch.group(1)!.trim();
        } else {
          final headerMatch = RegExp(r'([A-Za-z\s]+(?:diagnostic center|diagnostic|center|clinic|hospital|laboratory|lab|medical center))', caseSensitive: false).firstMatch(rawOutput);
          if (headerMatch != null) {
            data['institution_name'] = headerMatch.group(1)!.trim();
          }
        }
      }

      if (data['location_facility'] == null || data['location_facility'].toString().isEmpty || _cleanExtractedText(data['location_facility']) == null) {
        final locMatch = RegExp(r'(?:location_facility|location|branch|address)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (locMatch != null && _cleanExtractedText(locMatch.group(1)) != null) {
          data['location_facility'] = locMatch.group(1)!.trim();
        } else if (_cleanExtractedText(data['institution_name']) != null) {
          data['location_facility'] = data['institution_name'];
        }
      }

      if (data['health_worker_name'] == null || data['health_worker_name'].toString().isEmpty || _cleanExtractedText(data['health_worker_name']) == null) {
        final workerMatch = RegExp(r'(?:health_worker_name|pathologist|medtech|technologist|doctor|examiner|physician)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (workerMatch != null && _cleanExtractedText(workerMatch.group(1)) != null) {
          data['health_worker_name'] = workerMatch.group(1)!.trim();
        } else {
          final docMatch = RegExp(r'(?:DR\.|DOCTOR)[\sA-Za-z\.-]+', caseSensitive: false).firstMatch(rawOutput);
          if (docMatch != null) {
            data['health_worker_name'] = docMatch.group(0)!.trim();
          }
        }
      }

      if (data['remarks'] == null || data['remarks'].toString().isEmpty || _cleanExtractedText(data['remarks']) == null) {
        final remMatch = RegExp(r'(?:remarks|findings|results|summary|impression)[\s\*:="]*"?([^"\n\r\*]+)"?', caseSensitive: false).firstMatch(rawOutput);
        if (remMatch != null && _cleanExtractedText(remMatch.group(1)) != null) {
          data['remarks'] = remMatch.group(1)!.trim();
        }
      }

      data['lab_test_type'] = _cleanExtractedText(data['lab_test_type']);
      data['institution_name'] = _cleanExtractedText(data['institution_name']);
      data['location_facility'] = _cleanExtractedText(data['location_facility']);
      data['health_worker_name'] = _cleanExtractedText(data['health_worker_name']);
      data['remarks'] = _cleanExtractedText(data['remarks']);

      return data;
    } catch (e) {
      _log('⚠️ Error extracting lab test summary OCR: $e');
      return {};
    }
  }

  DateTime? _parseFlexibleDate(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final clean = input.trim();
    final dtISO = DateTime.tryParse(clean);
    if (dtISO != null) return dtISO;

    try {
      final monthMap = {
        'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
        'apr': 4, 'april': 4, 'may': 5, 'june': 6, 'jun': 6, 'jul': 7, 'july': 7,
        'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10,
        'nov': 11, 'november': 11, 'dec': 12, 'december': 12
      };
      final match = RegExp(r'([A-Za-z]+)\s+(\d{1,2})[\s,]+(\d{4})').firstMatch(clean);
      if (match != null) {
        final mStr = match.group(1)!.toLowerCase();
        final day = int.tryParse(match.group(2)!);
        final year = int.tryParse(match.group(3)!);
        if (monthMap.containsKey(mStr) && day != null && year != null) {
          return DateTime(year, monthMap[mStr]!, day);
        }
      }
    } catch (_) {}
    return null;
  }

  String? _cleanExtractedText(dynamic input) {
    if (input == null) return null;
    final str = input.toString().trim();
    if (str.isEmpty) return null;
    final lower = str.toLowerCase();

    if (lower.startsWith('looking') ||
        lower.startsWith('see') ||
        lower.startsWith('top header') ||
        lower.startsWith('header says') ||
        lower.startsWith('look for') ||
        lower.startsWith('read the') ||
        lower.startsWith('the section') ||
        lower.startsWith('the impression') ||
        lower.startsWith('section') ||
        lower.startsWith('name:') ||
        lower.startsWith('location:') ||
        lower.startsWith('name and location:') ||
        lower.contains('the user') ||
        lower.contains('user wants') ||
        lower.contains('report image') ||
        lower.contains('into a specific') ||
        lower.contains('json format') ||
        lower.contains('at the bottom') ||
        lower.contains('there are') ||
        lower.contains('signatures') ||
        lower.contains('need to') ||
        lower.contains('summarize') ||
        lower.contains('extract data') ||
        lower.contains('top of the document') ||
        lower.contains('i see a logo') ||
        lower.contains('top header') ||
        lower.contains('header says') ||
        lower.contains('look for') ||
        lower.contains('the section under') ||
        lower.contains('exact facility') ||
        lower.contains('exact diagnostic') ||
        lower.contains('exact physician') ||
        str.endsWith(':') ||
        str.length < 3) {
      return null;
    }
    return str.replaceAll(RegExp(r'^[\s-:\*\"]+'), '').trim();
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
            '- Every weight interpretation must end with: "This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation."';

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

    return """SYSTEM CONTEXT — EXPLAIN MY REPORT

You are a TRANSLATOR, not an interpreter.

A qualified sonologist or radiologist has ALREADY examined this scan and
already reached their conclusions. Their work is finished and it is correct.
Your only job is to put what they found into words a mother can understand.

You are NOT:
- a radiologist
- a sonologist
- a diagnostic system
- a fetal anomaly detection system
- a second opinion
- a replacement for healthcare professionals

--------------------------------------------------
THE ONE RULE THAT OVERRIDES EVERYTHING ELSE
--------------------------------------------------

EVERY statement you make must trace back to something written in the extracted
report below. You may re-word it, simplify it, and explain what it means. You
may NEVER add to it.

Specifically, you must NEVER:
- state a finding that does not appear in the extracted report
- revise, soften, strengthen, contradict or "correct" the sonologist's
  impression — if the report states an impression, restate it faithfully
- work out your own conclusion from the measurements and present it as a
  finding, even if the numbers seem to point somewhere
- guess at anything the report does not mention
- describe an anatomical structure the report does not describe
- claim anything about the baby's health that the report does not claim

If information is missing, say plainly that this scan did not record it. A
mother is better served by "this report does not mention that" than by a
confident answer you constructed yourself.

A wrong reassurance and a wrong alarm are both harmful here. The safe answer is
always the sonologist's answer, in simpler words.

WHAT YOU ADD THAT THE REPORT DOES NOT
The report is written for clinicians. You make it readable: plain language,
Filipino where helpful, and context for what a number means at this stage of
pregnancy. That is the whole of your contribution, and it is a real one — a
mother who understands her own report attends her next visit.

The AI must NEVER pretend to directly analyze ultrasound images visually. You
are reading text that was extracted from a report, not looking at a scan.

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

5. Disclaimer: "This AI-assisted explanation restates the findings recorded by the sonologist in simpler words, adds nothing of its own, and is intended only for healthcare monitoring support and does not replace professional medical consultation."

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
- End with: "This AI-assisted explanation restates the findings already recorded by the sonologist and adds nothing of its own. It is for monitoring support only and does not replace professional medical consultation."
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
- End with: "This AI-assisted explanation restates the findings already recorded by the sonologist and adds nothing of its own. It is for monitoring support only and does not replace professional medical consultation."
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

    const geminiModels = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-2.0-flash-lite'];
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
            {
              'role': 'system',
              'content': 'You are a precise medical OCR data extractor. You MUST output ONLY raw JSON matching the schema. Never write step-by-step reasoning, markdown headers, or thinking text.'
            },
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
            e.toString().contains('404') ||
            e.toString().contains('429') ||
            e.toString().contains('Rate limit') ||
            e.toString().contains('limit')) {
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

    // Resize high-res photos to max 960px for super-fast OCR payload and low TPM consumption
    final decoded = img.decodeImage(rawBytes);
    if (decoded != null) {
      img.Image processed = decoded;
      if (processed.width > 960 || processed.height > 960) {
        if (processed.width > processed.height) {
          processed = img.copyResize(processed, width: 960);
        } else {
          processed = img.copyResize(processed, height: 960);
        }
      }
      bytes = Uint8List.fromList(img.encodeJpg(processed, quality: 78));
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

    try {
      return await _postChatCompletion(
        baseUrl: _groqBaseUrl,
        providerLabel: 'Groq',
        apiKey: apiKey,
        model: model,
        messages: messages,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        useJsonMode: useJsonMode,
      );
    } catch (e) {
      final errorMessage = e.toString();

      // Fallback 1 — same provider, smaller model. The prompt was too large
      // for this model, so switching hosts would not help.
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

      // Fallback 2 — different provider. Groq itself is rate-limited, down,
      // or unreachable, so retry the same request against NVIDIA NIM.
      if (_isProviderOutageError(errorMessage)) {
        final nvidiaResult = await _tryNvidiaFallback(
          messages: messages,
          groqModel: model,
          temperature: temperature,
          maxOutputTokens: maxOutputTokens,
          useJsonMode: useJsonMode,
        );
        if (nvidiaResult != null) return nvidiaResult;
      }

      rethrow;
    }
  }

  /// Raw OpenAI-compatible chat-completion POST. Host-agnostic: both Groq and
  /// NVIDIA NIM accept this exact body shape.
  Future<String> _postChatCompletion({
    required String baseUrl,
    required String providerLabel,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxOutputTokens,
    required bool useJsonMode,
  }) async {
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
        '🌐 Sending request to $providerLabel/${model.split('/').last} (${messages.toString().length} chars)...');

    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
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
        throw Exception('API Error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractChatCompletionText(data);
    } on http.ClientException {
      throw Exception(
          'Network error: Unable to reach $providerLabel API. Please check your connection.');
    } on FormatException catch (e) {
      throw Exception('Invalid response format from $providerLabel API: $e');
    }
  }

  /// Retries a failed Groq text request against NVIDIA NIM.
  ///
  /// Returns null — rather than throwing — whenever the fallback is
  /// unavailable or also fails, so the caller surfaces the original Groq
  /// error instead of a confusing secondary one.
  Future<String?> _tryNvidiaFallback({
    required List<Map<String, dynamic>> messages,
    required String groqModel,
    required double temperature,
    required int maxOutputTokens,
    required bool useJsonMode,
  }) async {
    final nvidiaKey = _getNvidiaApiKey();
    if (nvidiaKey == null) {
      _log('ℹ️ Groq unavailable and no NVIDIA_API_KEY set; skipping fallback.');
      return null;
    }

    final nvidiaModel = _nvidiaModelEquivalents[groqModel];
    if (nvidiaModel == null) {
      _log('ℹ️ No NVIDIA equivalent mapped for $groqModel; skipping fallback.');
      return null;
    }

    _log('🔁 Groq unavailable — falling back to NVIDIA NIM ($nvidiaModel)');

    Future<String> attempt(bool jsonMode) => _postChatCompletion(
          baseUrl: _nvidiaBaseUrl,
          providerLabel: 'NVIDIA',
          apiKey: nvidiaKey,
          model: nvidiaModel,
          messages: messages,
          temperature: temperature,
          maxOutputTokens: maxOutputTokens,
          useJsonMode: jsonMode,
        );

    try {
      return await attempt(useJsonMode);
    } catch (e) {
      final error = e.toString();

      // Not every NIM model accepts response_format. Retry once as plain
      // text — the JSON parsers downstream already tolerate prose and fences.
      if (useJsonMode && error.contains('(400)')) {
        _log('⚠️ NVIDIA rejected JSON mode; retrying without response_format');
        try {
          return await attempt(false);
        } catch (retryError) {
          _log('⚠️ NVIDIA fallback failed after retry: $retryError');
          return null;
        }
      }

      // NVIDIA's free tier returns transient 504s while a model cold-starts.
      // One retry is cheap and this is already the last line of defence.
      if (_isProviderOutageError(error)) {
        _log('⚠️ NVIDIA transient failure; retrying once in 2s...');
        await Future.delayed(const Duration(seconds: 2));
        try {
          return await attempt(useJsonMode);
        } catch (retryError) {
          _log('⚠️ NVIDIA fallback failed after retry: $retryError');
          return null;
        }
      }

      _log('⚠️ NVIDIA fallback failed: $error');
      return null;
    }
  }

  /// True when the failure is about provider availability rather than the
  /// request itself — the only case where retrying on another host helps.
  bool _isProviderOutageError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('network error') ||
        normalized.contains('clientexception') ||
        normalized.contains('timeoutexception') ||
        normalized.contains('rate limit')) {
      return true;
    }
    return RegExp(r'api error \((429|500|502|503|504|529)\)')
        .hasMatch(normalized);
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
