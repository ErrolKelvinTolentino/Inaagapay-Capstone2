// lib/screens/mother/mother_chatbot_page.dart

import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../services/language_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/groq_service.dart';
import '../../services/auth_storage.dart';
import '../../models/chatbot_models.dart';
import 'mother_journal_screen.dart';
import 'mother_children_screen.dart';
import 'records_screen.dart';

class MotherChatbotPage extends StatefulWidget {
  final String firstName;
  final int week;
  final String trimester;
  final String riskLevel;
  final List<String>? riskFactors;
  final List<String>? suggestedActions;
  final bool hasPregnancy;

  const MotherChatbotPage({
    super.key,
    required this.firstName,
    required this.week,
    required this.trimester,
    required this.riskLevel,
    this.riskFactors,
    this.suggestedActions,
    required this.hasPregnancy,
  });

  @override
  State<MotherChatbotPage> createState() => _MotherChatbotPageState();
}

class _MotherChatbotPageState extends State<MotherChatbotPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GroqService _groqService = GroqService();

  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  List<ChatMessage> _messages = [];

  bool _loadingSessions = true;
  bool _loadingMessages = false;
  bool _isTyping = false;
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  Timer? _amplitudeTimer;
  double _currentAmplitude = 0.0;
  late AnimationController _recordingGlowController;
  bool _isVoiceActionPending = false;

  List<String> _activeAllergies = [];
  List<String> _activeMedicalConditions = [];
  bool _hidePregnancyInfo = false;
  List<String> _hiddenAllergies = [];
  List<String> _hiddenMedicalConditions = [];
  bool _showPrivacyBanner = true;

  // TTS & Search State
  late AudioPlayer _audioPlayer;
  String? _currentlyReadingMessageId;
  String? _loadingTtsMessageId; // shows spinner while fetching audio
  final TextEditingController _drawerSearchController = TextEditingController();
  String _drawerSearchQuery = '';

  String _t(String english, String filipino) {
    return LanguageService.translate(english, filipino);
  }

  String _tCategory(String cat) {
    switch (cat) {
      case 'Nutrisyon / Nutrition':
        return _t('Nutrition', 'Nutrisyon');
      case 'Prenatal Care / Pagpapasuri':
        return _t('Prenatal Care', 'Pagpapasuri');
      case 'Mga Babala / Danger Signs':
        return _t('Danger Signs', 'Mga Babala');
      case 'Pamamanas / Swelling':
        return _t('Swelling', 'Pamamanas');
      case 'Morning Sickness / Pagduduwal':
        return _t('Morning Sickness', 'Pagduduwal');
      default:
        return cat;
    }
  }

  String get _onlyFirstName {
    if (widget.firstName.isEmpty) return '';
    return widget.firstName.trim().split(' ').first;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _audioPlayer = AudioPlayer();
    _audioRecorder = AudioRecorder();
    _recordingGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _initAudioPlayer();
    _loadMotherMedicalInfo().then((_) {
      _initializeChat();
    });
  }

  /// The phone's own text-to-speech, used when the hosted voice cannot be.
  ///
  /// `flutter_tts` has been a dependency all along and was never wired to
  /// anything — the app carried an offline, key-free, Filipino-capable
  /// speech engine and used a gated English-only web service instead.
  FlutterTts? _deviceTts;

  /// Names that identify a female voice across the engines we see in practice.
  ///
  /// There is no gender field in Android's TTS voice API and none in what
  /// `flutter_tts` returns, so this matches on the name — which is the only
  /// signal available. Google's Android voices encode it in codes like
  /// `en-us-x-tpf-local` (the `f`); iOS uses given names.
  ///
  /// Edit this list to change which voice Ate uses on a device. Anything not
  /// matched leaves the engine's default alone rather than guessing.
  static const List<String> _femaleVoiceHints = <String>[
    'female',
    // Google / Android voice-quality codes that denote the female set.
    '-x-tpf-', '-x-sfg-', '-x-iof-', '-x-iog-', '-x-fic-',
    // iOS and Samsung given names.
    'samantha', 'karen', 'moira', 'tessa', 'fiona', 'nicky', 'ava',
    'allison', 'susan', 'zoe', 'serena',
  ];

  /// Picks a female voice for [locale] where the device has one.
  ///
  /// Silent no-op when it cannot find one — a male voice reading her message
  /// is still better than no voice, so this never fails the speak attempt.
  Future<void> _preferFemaleVoice(FlutterTts tts, String locale) async {
    try {
      // Asked twice, because on web the first answer is empty.
      //
      // Flutter web routes this to the browser's speechSynthesis, whose voice
      // list loads asynchronously — `getVoices` before the `voiceschanged`
      // event returns []. That is exactly what the log showed: "no female en
      // voice on this device ... Available: []" on a machine that has plenty.
      var raw = await tts.getVoices;
      if (raw is! List || raw.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        raw = await tts.getVoices;
      }
      if (raw is! List || raw.isEmpty) return;

      final lang = locale.split('-').first.toLowerCase();
      Map<String, String>? match;

      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString() ?? '';
        final voiceLocale = entry['locale']?.toString() ?? '';
        if (name.isEmpty || voiceLocale.isEmpty) continue;
        if (!voiceLocale.toLowerCase().startsWith(lang)) continue;

        final needle = name.toLowerCase();
        if (_femaleVoiceHints.any(needle.contains)) {
          match = {'name': name, 'locale': voiceLocale};
          // An exact locale match beats a language-only one — fil-PH over a
          // generic Filipino voice, en-US over en-GB.
          if (voiceLocale.toLowerCase() == locale.toLowerCase()) break;
        }
      }

      if (match != null) {
        await tts.setVoice(match);
        debugPrint('[MotherChatbotPage] device voice: ${match['name']}');
      } else {
        // Logged rather than hidden: if Ate sounds like a man on a test
        // device, this line is the reason and it names what was available.
        debugPrint('[MotherChatbotPage] no female $lang voice on this device; '
            'using the engine default. Available: '
            '${raw.whereType<Map>().map((v) => v['name']).take(12).toList()}');
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] voice selection skipped: $e');
    }
  }

  /// Reads [text] with the device engine. Returns false if it could not.
  ///
  /// Never throws: this is the path taken when something else has already
  /// gone wrong, so a failure here has to be quiet and let the caller show
  /// the plain message.
  Future<bool> _speakOnDevice(String text, String messageId) async {
    try {
      final tts = _deviceTts ??= FlutterTts();

      // fil-PH where the device has it, en-US otherwise. isLanguageAvailable
      // is asked rather than assumed — a phone without the Filipino voice
      // would otherwise read Tagalog in an English accent silently.
      final wanted = LanguageService.isFilipino ? 'fil-PH' : 'en-US';
      final available = await tts.isLanguageAvailable(wanted);
      final locale = available == true ? wanted : 'en-US';
      await tts.setLanguage(locale);

      // Ate is a woman.
      //
      // The hosted voice is "autumn", which is female, but the device engine
      // hands out whatever its default is — on many Android builds that is a
      // man. Ate is written as an older sister and every other word in the app
      // treats her as one, so a male voice on the fallback path made the
      // assistant change sex depending on whether the API was reachable.
      await _preferFemaleVoice(tts, locale);

      // Slower than default. This is health guidance being read to someone who
      // may be hearing it while holding a baby.
      await tts.setSpeechRate(0.45);
      await tts.setPitch(1.0);

      tts.setCompletionHandler(() {
        if (mounted) setState(() => _currentlyReadingMessageId = null);
      });

      if (mounted) {
        setState(() {
          _loadingTtsMessageId = null;
          _currentlyReadingMessageId = messageId;
        });
      }

      // Markdown reads badly aloud — asterisks become "asterisk".
      final clean = text
          .replaceAll(RegExp(r'[*#_`]'), '')
          .replaceAll(RegExp(r'\n{2,}'), '. ')
          .replaceAll('\n', ' ')
          .trim();

      // An error handler, so a browser SpeechSynthesisErrorEvent is not left
      // to surface as a bare "[object SpeechSynthesisErrorEvent]" with the
      // reading state stuck on.
      tts.setErrorHandler((dynamic message) {
        debugPrint('[MotherChatbotPage] device TTS error: $message');
        if (mounted) {
          setState(() {
            _loadingTtsMessageId = null;
            _currentlyReadingMessageId = null;
          });
        }
      });

      final result = await tts.speak(clean);
      return result == 1;
    } catch (e) {
      debugPrint('[MotherChatbotPage] device TTS unavailable: $e');
      if (mounted) {
        setState(() {
          _loadingTtsMessageId = null;
          _currentlyReadingMessageId = null;
        });
      }
      return false;
    }
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyReadingMessageId = null;
        });
      }
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_isVoiceActionPending) return;
    _isVoiceActionPending = true;
    try {
      if (_isRecording) {
        await _stopVoiceRecording();
      } else {
        await _startVoiceRecording();
      }
    } finally {
      _isVoiceActionPending = false;
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_t(
                'Microphone permission is required to record your voice.',
                'Kailangang payagan ang mikropono para maitala ang iyong boses.',
              )),
            ),
          );
        }
        return;
      }

      final recordConfig = await _buildSafeRecordConfig();
      final String filePath;
      if (kIsWeb) {
        filePath = '';
      } else {
        final tempDir = await getTemporaryDirectory();
        filePath =
            '${tempDir.path}/chatbot_voice_${DateTime.now().millisecondsSinceEpoch}.${_extensionForEncoder(recordConfig.encoder)}';
      }

      await _audioRecorder.start(recordConfig, path: filePath);

      _recordingTimer?.cancel();
      _recordingDuration = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        }
      });

      _amplitudeTimer?.cancel();
      _currentAmplitude = 0.0;
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        try {
          if (_isRecording) {
            final amp = await _audioRecorder.getAmplitude();
            double db = amp.current;
            double normalized = 0.0;
            // Silence starts at -50dB or lower, and peak volume around -5dB or higher.
            const double minDb = -50.0;
            const double maxDb = -5.0;
            if (db > minDb) {
              normalized = (db - minDb) / (maxDb - minDb);
              if (normalized > 1.0) normalized = 1.0;
              if (normalized < 0.0) normalized = 0.0;
            }
            if (mounted) {
              setState(() {
                _currentAmplitude = normalized;
              });
            }
          }
        } catch (e) {
          debugPrint('Error getting amplitude: $e');
        }
      });

      _recordingGlowController.repeat(reverse: true);

      if (mounted) {
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] Voice recording start failed: $e');
      _recordingGlowController.stop();
      _amplitudeTimer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(
              'Unable to start recording. Please try again.',
              'Hindi masimulan ang recording. Pakisubukan muli.',
            )),
          ),
        );
      }
    }
  }

  Future<RecordConfig> _buildSafeRecordConfig() async {
    if (kIsWeb) {
      return const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        bitRate: 128000,
        numChannels: 1,
      );
    }

    final candidateEncoders = [
      AudioEncoder.aacLc,
      AudioEncoder.wav,
      AudioEncoder.pcm16bits,
      AudioEncoder.opus,
    ];

    for (final encoder in candidateEncoders) {
      try {
        if (await _audioRecorder.isEncoderSupported(encoder)) {
          return RecordConfig(
            encoder: encoder,
            sampleRate: 16000,
            bitRate: 128000,
            numChannels: 1,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Encoder support check failed for $encoder: $e');
      }
    }

    return const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      bitRate: 128000,
      numChannels: 1,
    );
  }

  String _extensionForEncoder(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
        return '3gp';
      case AudioEncoder.opus:
        return 'opus';
      case AudioEncoder.flac:
        return 'flac';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.pcm16bits:
        return 'pcm';
    }
  }

  Future<void> _stopVoiceRecording() async {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingGlowController.stop();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      debugPrint('[MotherChatbotPage] Voice recording stop failed: $e');
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
        _currentAmplitude = 0.0;
        _isTranscribing = true;
      });
    }

    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
        });
      }
      return;
    }

    try {
      final Uint8List audioBytes;
      final String fileName;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        audioBytes = response.bodyBytes;
        fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        audioBytes = await File(path).readAsBytes();
        fileName = path.split(RegExp(r'[/\\]')).last;
      }

      final transcript = await _groqService.transcribeAudio(
        audioBytes: audioBytes,
        fileName: fileName,
      );

      if (transcript.isNotEmpty) {
        _inputController.text = transcript;
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] STT failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(
              'Unable to transcribe audio. Please try again.',
              'Hindi ma-transcribe ang audio. Pakisubukan muli.',
            )),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingGlowController.stop();
    try {
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('[MotherChatbotPage] Voice recording cancel failed: $e');
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
        _currentAmplitude = 0.0;
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  Future<void> _loadMotherMedicalInfo() async {
    try {
      final motherId = await AuthStorage.getMotherId();
      if (motherId == null) return;

      final client = Supabase.instance.client;

      // Fetch allergies
      final allergyRows = await client
          .from('allergies')
          .select('allergen, status')
          .eq('mother_id', motherId);

      final activeAllergiesList = (allergyRows as List)
          .where((row) =>
              (row['status'] ?? '').toString().toLowerCase() == 'active')
          .map((row) => (row['allergen'] ?? '').toString().trim())
          .where((allergen) => allergen.isNotEmpty)
          .toList();

      // Fetch medical conditions
      final conditionRows = await client
          .from('medical_conditions')
          .select('condition_name, status')
          .eq('mother_id', motherId);

      final activeConditionsList = (conditionRows as List)
          .where((row) =>
              (row['status'] ?? '').toString().toLowerCase() == 'active')
          .map((row) => (row['condition_name'] ?? '').toString().trim())
          .where((cond) => cond.isNotEmpty)
          .toList();

      // Fetch AI Privacy settings from secure storage
      final hidePregnancy = await AuthStorage.getHiddenPregnancyInfo();
      final hiddenAllergiesList = await AuthStorage.getHiddenAllergies();
      final hiddenConditionsList =
          await AuthStorage.getHiddenMedicalConditions();

      if (mounted) {
        setState(() {
          _activeAllergies = activeAllergiesList;
          _activeMedicalConditions = activeConditionsList;
          _hidePregnancyInfo = hidePregnancy;
          _hiddenAllergies = hiddenAllergiesList;
          _hiddenMedicalConditions = hiddenConditionsList;
        });
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] Error loading mother medical info: $e');
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recordingGlowController.dispose();
    _audioPlayer.dispose();
    _deviceTts?.stop();
    _audioRecorder.dispose();
    _drawerSearchController.dispose();
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _loadingSessions = true;
    });

    try {
      final sessions = await ChatbotService.fetchSessions();
      setState(() {
        _sessions = sessions;
      });

      if (_sessions.isNotEmpty) {
        // Load the most recent session
        await _loadSession(_sessions.first);
      } else {
        // Create an initial new session
        await _createNewSession();
      }
    } catch (e) {
      // If error occurs (e.g. Supabase connection issue before fallback establishes)
      // trigger local session creation
      await _createNewSession();
    } finally {
      setState(() {
        _loadingSessions = false;
      });
    }
  }

  Future<void> _loadSession(ChatSession session) async {
    setState(() {
      _currentSession = session;
      _loadingMessages = true;
      _messages = [];
    });

    try {
      final messages = await ChatbotService.fetchMessages(session.sessionId);
      setState(() {
        _messages = messages;
      });

      // If session is empty, insert initial welcome greeting
      if (_messages.isEmpty) {
        await _sendInitialGreeting(session.sessionId);
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] Error loading messages: $e');
    } finally {
      setState(() {
        _loadingMessages = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _createNewSession() async {
    setState(() {
      _loadingMessages = true;
    });

    try {
      final title =
          '${_t('Chat w/ Ate', 'Kausap si Ate')} - ${DateFormat('MMM dd').format(DateTime.now())}';
      final newSession = await ChatbotService.createSession(title);

      setState(() {
        if (!_sessions.any((s) => s.sessionId == newSession.sessionId)) {
          _sessions.insert(0, newSession);
        }
        _currentSession = newSession;
        _messages = [];
      });

      await _sendInitialGreeting(newSession.sessionId);
    } catch (e) {
      debugPrint('[MotherChatbotPage] Error creating session: $e');
    } finally {
      setState(() {
        _loadingMessages = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendInitialGreeting(int sessionId) async {
    String greeting;
    if (widget.hasPregnancy) {
      if (widget.week > 0) {
        greeting = _t(
          "Hi $_onlyFirstName! I'm Ate Assistant, your digital midwife guide. You're currently in Week ${widget.week} of your pregnancy (${_tTrimester(widget.trimester)}). How can I help you today? 🌸",
          "Kumusta, $_onlyFirstName! Ako si Ate Assistant, ang iyong gabay sa pagbubuntis. Nasa Week ${widget.week} ka na ngayon (${_tTrimester(widget.trimester)}). Paano kita matutulungan ngayong araw? 🌸",
        );
      } else {
        greeting = _t(
          "Hi $_onlyFirstName! I'm Ate Assistant, your digital midwife guide. How are you and your baby doing today? 🌸",
          "Kumusta, $_onlyFirstName! Ako si Ate Assistant, ang iyong gabay sa pagbubuntis. Kumusta ang lagay mo at ng iyong baby ngayon? 🌸",
        );
      }
    } else {
      greeting = _t(
        "Hi $_onlyFirstName! I'm Ate Assistant, your digital midwife guide. How can I help you today? 🌸",
        "Kumusta, $_onlyFirstName! Ako si Ate Assistant, ang iyong gabay. Ano ang maitutulong ko sa iyo ngayon? 🌸",
      );
    }

    final welcomeMessage = await ChatbotService.saveMessage(
      sessionId: sessionId,
      content: greeting,
      isUser: false,
    );

    setState(() {
      _messages.add(welcomeMessage);
    });
    _scrollToBottom();
  }

  String _tTrimester(String trim) {
    if (trim.contains('First') || trim.contains('Unang')) {
      return _t('First Trimester', 'Unang Trimester');
    }
    if (trim.contains('Second') || trim.contains('Ikalawang')) {
      return _t('Second Trimester', 'Ikalawang Trimester');
    }
    if (trim.contains('Third') || trim.contains('Ikatlong')) {
      return _t('Third Trimester', 'Ikatlong Trimester');
    }
    return trim;
  }

  String _tRiskLevel(String risk) {
    switch (risk.toLowerCase().trim()) {
      case 'low':
      case 'mababa':
        return _t('Low', 'Mababa');
      case 'medium':
      case 'katamtaman':
        return _t('Medium', 'Katamtaman');
      case 'high':
      case 'mataas':
        return _t('High', 'Mataas');
      default:
        return risk;
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _currentSession == null || _isTyping) return;

    final userContent = text.trim();
    _inputController.clear();

    setState(() {
      _isTyping = true;
    });

    try {
      // 1. Save and display User message
      final userMessage = await ChatbotService.saveMessage(
        sessionId: _currentSession!.sessionId,
        content: userContent,
        isUser: true,
      );

      setState(() {
        _messages.add(userMessage);
      });
      _scrollToBottom();

      // Refresh mother's medical details right before generating the system prompt
      await _loadMotherMedicalInfo();

      // 2. Prepare conversation history with system instructions
      final List<Map<String, dynamic>> apiHistory = [
        {
          'role': 'system',
          'content': _buildSystemPrompt(),
        }
      ];

      // Add recent messages to history context
      final recentMessages = _messages.length > 16
          ? _messages.sublist(_messages.length - 16)
          : _messages;

      for (final msg in recentMessages) {
        apiHistory.add({
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.content,
        });
      }

      // 3. Request LLM response from Groq
      final aiResponseText =
          await _groqService.getChatResponse(chatHistory: apiHistory);

      // 4. Save and display AI response
      final aiMessage = await ChatbotService.saveMessage(
        sessionId: _currentSession!.sessionId,
        content: aiResponseText,
        isUser: false,
      );

      setState(() {
        _messages.add(aiMessage);
      });
    } catch (e) {
      debugPrint('[MotherChatbotPage] Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Connection error. Please try again.',
                'May problema sa koneksyon. Pakisubukan muli.')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  String _buildSystemPrompt() {
    final visibleAllergies =
        _activeAllergies.where((a) => !_hiddenAllergies.contains(a)).toList();
    final visibleConditions = _activeMedicalConditions
        .where((c) => !_hiddenMedicalConditions.contains(c))
        .toList();

    final isFilipino = LanguageService.isFilipino;

    final allergiesStr = visibleAllergies.isEmpty
        ? (isFilipino ? 'Wala (o walang ibinahagi ang ina)' : 'None (or none shared by the mother)')
        : visibleAllergies.join(', ');
    final medicalConditionsStr = visibleConditions.isEmpty
        ? (isFilipino ? 'Wala (o walang ibinahagi ang ina)' : 'None (or none shared by the mother)')
        : visibleConditions.join(', ');

    final includePregnancy = widget.hasPregnancy && !_hidePregnancyInfo;

    final contextString = isFilipino
        ? (includePregnancy
            ? "Pangalan ng Buntis: $_onlyFirstName\n"
                "Linggo ng Pagbubuntis: Linggo ${widget.week} (${_tTrimester(widget.trimester)})\n"
                "Antas ng Panganib: ${_tRiskLevel(widget.riskLevel)}\n"
                "Mga Risk Factors: ${widget.riskFactors?.join(', ') ?? 'Wala'}\n"
                "Mga Rekomendadong Aksyon: ${widget.suggestedActions?.join(', ') ?? 'Wala'}\n"
                "Mga Aktibong Alerdye (Allergies) na ibinahagi: $allergiesStr\n"
                "Mga Kasalukuyang Kondisyong Medikal (Medical Conditions) na ibinahagi: $medicalConditionsStr"
            : "Pangalan ng Ina: $_onlyFirstName\n"
                "Pregnancy Status: Walang aktibong pagbubuntis na rehistrado o tinago ng ina ang detalye.\n"
                "Mga Aktibong Alerdye (Allergies) na ibinahagi: $allergiesStr\n"
                "Mga Kasalukuyang Kondisyong Medikal (Medical Conditions) na ibinahagi: $medicalConditionsStr")
        : (includePregnancy
            ? "Mother's Name: $_onlyFirstName\n"
                "Pregnancy Week: Week ${widget.week} (${_tTrimester(widget.trimester)})\n"
                "Risk Level: ${_tRiskLevel(widget.riskLevel)}\n"
                "Risk Factors: ${widget.riskFactors?.join(', ') ?? 'None'}\n"
                "Suggested Actions: ${widget.suggestedActions?.join(', ') ?? 'None'}\n"
                "Shared Active Allergies: $allergiesStr\n"
                "Shared Active Medical Conditions: $medicalConditionsStr"
            : "Mother's Name: $_onlyFirstName\n"
                "Pregnancy Status: No active pregnancy registered or pregnancy details hidden by the mother.\n"
                "Shared Active Allergies: $allergiesStr\n"
                "Shared Active Medical Conditions: $medicalConditionsStr");

    final disclaimerText = isFilipino
        ? "Tandaan: Ang payo na ito ay gabay lamang at hindi kapalit ng pagkonsulta sa iyong midwife o doktor."
        : "Remember: This advice is a guide only and not a substitute for consulting your midwife or doctor.";

    final declineText = isFilipino
        ? "Pasensya na, mama, ako ay ginawa lamang para sa mga usaping pagbubuntis at pangangalaga sa inyong baby..."
        : "I am sorry, mama, I am only designed to assist with pregnancy, motherhood, and baby care topics...";

    final personaPrompt = isFilipino
        ? "You are a caring, knowledgeable midwife assistant in the Philippines who genuinely cares about every mother and child. "
            "Write as if you are a trusted ate (older sister) sitting beside the mother, gently explaining things. "
            "Celebrate good news warmly. When something needs attention, be honest but gentle and always offer practical next steps. "
            "Use simple Filipino-context language (English/Tagalog/Taglish). Explain medical terms by what they mean for the mother and baby. "
            "Give culturally relevant advice (e.g., local foods like malunggay, kangkong, dilis for nutrition). "
            "Never be cold or clinical. Always end with encouragement."
        : "You are a caring, knowledgeable midwife assistant in the Philippines who genuinely cares about every mother and child. "
            "Write as if you are a trusted ate (older sister) sitting beside the mother, gently explaining things. "
            "Celebrate good news warmly. When something needs attention, be honest but gentle and always offer practical next steps. "
            "Respond in warm, supportive, clear English. Explain medical terms by what they mean for the mother and baby. "
            "Give culturally relevant advice (e.g., local foods like malunggay, kangkong, dilis for nutrition). "
            "Never be cold or clinical. Always end with encouragement.";

    return "$personaPrompt\n\n"
        "Here is the context about the mother you are talking to:\n"
        "$contextString\n\n"
        "Rules:\n"
        "1. Limit your responses to 2-3 brief paragraphs so they are easy to read on a mobile phone screen.\n"
        "2. STRICT LANGUAGE MATCHING: You must detect and mirror the language or dialect style the mother uses. If she asks in Tagalog, respond in warm, conversational Tagalog. If she asks in Taglish, respond in natural Taglish. If she asks in English, respond in clear English. Sound warm, natural, and never use rigid clinical translations.\n"
        "3. Every message you send MUST end with a caring tag and a soft disclaimer: "
        "\"$disclaimerText\"\n"
        "4. Address the mother by name ($_onlyFirstName) naturally occasionally.\n"
        "5. CRITICAL: You are STRICTLY a maternal health, pregnancy, and baby care assistant. Do NOT write computer code, programming instructions, web scripts, or answer any questions unrelated to pregnancy, motherhood, maternal/infant nutrition, or parenting. If asked about programming, code, web projects, or other unrelated subjects, politely and warmly decline (e.g., '$declineText').\n"
        "6. CRITICAL SAFETY RULE: You must ALWAYS cross-reference the mother's list of active allergies and medical conditions when she asks about food, diet, nutrition, home remedies, medications, activities, or exercises. If she asks if she can eat or do something that matches or is related to her active allergies or medical conditions (e.g. asking to eat fish when allergic to fish, or do heavy tasks with high risk), you MUST strongly advise against it, state the reason clearly by referring to her allergy or condition, and provide safe, healthy local alternatives in your warm Filipino midwife ('Ate') persona.\n"
        "7. EMERGENCY HOTLINES: If the mother mentions or describes any pregnancy danger signs (such as vaginal bleeding, severe abdominal pain, high fever, blurred vision, severe headache, swelling/edema of face or hands, or sudden decrease in baby movement), or if she is experiencing a mental health crisis, you MUST suggest that she seek immediate medical help or contact emergency services. In these cases, append `[CALL_HOTLINE: <number>]` on a new line at the very end of your response, where `<number>` is:\n"
        "  - `911` for severe/life-threatening medical emergencies or general emergencies.\n"
        "  - `1555` for DOH health advice/consultation.\n"
        "  - `143` for Philippine Red Cross ambulance/medical aid.\n"
        "  - `1553` if she describes feelings of depression, severe anxiety, or mental health crisis.\n"
        "  - `117` for police emergency.\n"
        "  Do not output the bracketed tag unless there is an actual emergency, danger sign, or crisis mentioned by the mother.\n"
        "8. QUICK-REPLY SUGGESTIONS: At the very end of your response, on new lines, you can recommend 2-3 short, relevant follow-up questions that the mother might want to ask next based on the conversation context. Format each suggestion inside square brackets like `[SUGGEST: question_text]`. The suggestions MUST be in the same matching language/style as your main response (conversational Tagalog, Taglish, or English). Do not use this if there is an active emergency/danger sign.\n"
        "9. APP NAVIGATION ACTION: If the mother asks about tracking her mood, writing in her diary/journal, viewing medical checkup history/prescriptions, checking child growth charts/immunizations, or managing AI privacy options, you can suggest opening the relevant app screen. Append `[NAVIGATE: screen_key]` on a new line at the very end of your response, where `<screen_key>` is:\n"
        "  - `journal` to open the Mother's Journal/Diary screen.\n"
        "  - `records` to open the Medical Records/Consultations screen.\n"
        "  - `children` to open the Child Growth & Vaccine tracker screen.\n"
        "  - `privacy` to open the AI Privacy Settings sheet.\n"
        "10. FOLK MEDICINE & TRADITIONAL REMEDIES SAFEGUARD: You must never recommend, approve, or encourage traditional, unverified, or unsafe folk practices. Specifically, explicitly forbid: (a) traditional abdominal belly massages (hilot) for abdominal pain, as this can cause placental abruption; (b) traditional herbal concoctions/brews (halamang gamot) like makabuhay, pampalaglag, or unspecified herbal teas which can be abortifacients or toxic; (c) self-medication. You may only suggest safe, standard, clinically accepted nutrition (e.g., malunggay, kangkong, dilis, eggs, iron-rich local foods) or doctor-approved remedies, and must tell the mother to consult her midwife or doctor for any physical/herbal therapy.";
  }

  String _cleanMessageContent(String text) {
    String cleaned = text.replaceAll(RegExp(r'\[CALL_HOTLINE:\s*\d+\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[SUGGEST:\s*(.*?)\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[NAVIGATE:\s*[a-zA-Z_]+\]'), '');
    return cleaned.trim();
  }

  Map<String, String> _splitMessageDisclaimer(String text) {
    final RegExp disclaimerRegex = RegExp(
      r'((?:Tandaan|Disclaimer|Reminder|Patalastas):\s*(?:Ang payo na ito ay gabay lamang at hindi kapalit ng pagkonsulta sa iyong midwife o doktor|This advice is a guide only and not a substitute for consulting your midwife or doctor)\.?|'
      r'(?:Tandaan|Disclaimer|Reminder):\s*(?:Ang payo na ito|This advice).*?(?:midwife o doktor|midwife or doctor)\.?)',
      caseSensitive: false,
    );

    final match = disclaimerRegex.firstMatch(text);
    if (match != null) {
      final disclaimerText = match.group(0)!;
      String mainContent = text.replaceFirst(disclaimerText, '').trim();
      return {
        'content': mainContent,
        'disclaimer': disclaimerText,
      };
    }

    final lines = text.split('\n');
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.toLowerCase().startsWith('tandaan:') ||
          line.toLowerCase().startsWith('disclaimer:') ||
          line.toLowerCase().startsWith('reminder:')) {
        final lower = line.toLowerCase();
        if (lower.contains('midwife') ||
            lower.contains('doktor') ||
            lower.contains('doctor') ||
            lower.contains('pagkonsulta') ||
            lower.contains('consult')) {
          final disclaimerText = line;
          lines.removeAt(i);
          return {
            'content': lines.join('\n').trim(),
            'disclaimer': disclaimerText,
          };
        }
      }
    }

    return {
      'content': text,
      'disclaimer': '',
    };
  }

  String? _checkForEmergencyKeywords(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('bleeding') ||
        lower.contains('pagdurugo') ||
        lower.contains('dinudugo') ||
        lower.contains('abdominal pain') ||
        lower.contains('matinding sakit ng tiyan') ||
        lower.contains('sumasakit ang tiyan') ||
        lower.contains('blurred vision') ||
        lower.contains('panlalabo ng paningin') ||
        lower.contains('lumalabo ang mata') ||
        lower.contains('severe headache') ||
        lower.contains('matinding sakit ng ulo') ||
        lower.contains('sumasakit ang ulo') ||
        lower.contains('hindi gumagalaw ang baby') ||
        lower.contains('bawas ang galaw ng baby') ||
        lower.contains('baby not moving') ||
        lower.contains('decreased fetal movement') ||
        lower.contains('tubig na lumabas') ||
        lower.contains('panubigan') ||
        lower.contains('water broke')) {
      return '911';
    }
    if (lower.contains('magpakamatay') ||
        lower.contains('suicide') ||
        lower.contains('gusto ko nang mamatay') ||
        lower.contains('ayoko na mabuhay') ||
        lower.contains('self-harm') ||
        lower.contains('laslas') ||
        lower.contains('kitilin') ||
        lower.contains('depression') ||
        lower.contains('depress')) {
      return '1553';
    }
    return null;
  }

  List<String> _extractHotlineNumbers(ChatMessage message) {
    final regex = RegExp(r'\[CALL_HOTLINE:\s*(\d+)\]');
    final extracted =
        regex.allMatches(message.content).map((m) => m.group(1)!).toList();

    if (extracted.isEmpty && !message.isUser) {
      final index = _messages.indexOf(message);
      if (index > 0) {
        final prevMessage = _messages[index - 1];
        if (prevMessage.isUser) {
          final keywordHotline =
              _checkForEmergencyKeywords(prevMessage.content);
          if (keywordHotline != null) {
            extracted.add(keywordHotline);
          }
        }
      }
      final aiKeywordHotline = _checkForEmergencyKeywords(message.content);
      if (aiKeywordHotline != null && !extracted.contains(aiKeywordHotline)) {
        extracted.add(aiKeywordHotline);
      }
    }
    return extracted.toSet().toList();
  }

  List<String> _extractSuggestions(String text) {
    final regex = RegExp(r'\[SUGGEST:\s*(.*?)\]');
    return regex.allMatches(text).map((m) => m.group(1)!.trim()).toList();
  }

  List<String> _extractNavigationActions(String text) {
    final regex = RegExp(r'\[NAVIGATE:\s*([a-zA-Z_]+)\]');
    return regex
        .allMatches(text)
        .map((m) => m.group(1)!.trim().toLowerCase())
        .toList();
  }

  Future<void> _callNumber(String number) async {
    try {
      final uri = Uri.parse('tel:$number');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  _t('Could not call $number', 'Hindi matawagan ang $number')),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[MotherChatbotPage] Error launching dialer: $e');
    }
  }

  Widget _buildHotlineButton(String number) {
    String label;
    IconData icon;
    Color color;

    switch (number) {
      case '911':
        label = _t('Call 911 Emergency', 'Tawagan ang 911 Emergency');
        icon = Icons.local_hospital_rounded;
        color = AppColors.error;
        break;
      case '1555':
        label = _t('Call DOH Health (1555)', 'Tawagan ang DOH Health (1555)');
        icon = Icons.phone_in_talk_rounded;
        color = AppColors.brandPrimaryOf(context);
        break;
      case '143':
        label = _t('Call Red Cross (143)', 'Tawagan ang Red Cross (143)');
        icon = Icons.health_and_safety_rounded;
        color = const Color(0xFFD32F2F);
        break;
      case '1553':
        label = _t('Call Mental Health Crisis (1553)',
            'Tawagan ang Mental Health Crisis (1553)');
        icon = Icons.psychology_rounded;
        color = const Color(0xFF7B1FA2);
        break;
      case '117':
        label =
            _t('Call PNP Emergency (117)', 'Tawagan ang PNP Emergency (117)');
        icon = Icons.shield_rounded;
        color = const Color(0xFF1565C0);
        break;
      case '160':
        label = _t(
            'Call Fire Department (160)', 'Tawagan ang Bureau of Fire (160)');
        icon = Icons.local_fire_department_rounded;
        color = const Color(0xFFE65100);
        break;
      default:
        label = '${_t('Call Hotline', 'Tawagan ang')} $number';
        icon = Icons.call;
        color = AppColors.brandPrimaryOf(context);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _callNumber(number),
          icon: Icon(icon, size: 16, color: Colors.white),
          label: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton(String screenKey) {
    String label;
    IconData icon;
    Widget Function(BuildContext)? routeBuilder;
    VoidCallback? customAction;

    switch (screenKey) {
      case 'journal':
        label = _t('Open Journal / Diary', 'Buksan ang Journal / Talaarawan');
        icon = Icons.book_rounded;
        routeBuilder = (_) => const MotherJournalScreen();
        break;
      case 'records':
        label = _t('Open Medical Records', 'Tingnan ang Medical Records');
        icon = Icons.assignment_rounded;
        routeBuilder = (_) => const RecordsScreen();
        break;
      case 'children':
        label = _t('Open Child Tracker', 'Buksan ang Tracker ng Sanggol');
        icon = Icons.child_care_rounded;
        routeBuilder = (_) => const MotherChildrenScreen();
        break;
      case 'privacy':
        label =
            _t('Open AI Privacy Settings', 'Buksan ang AI Privacy Settings');
        icon = Icons.shield_outlined;
        customAction = _showPrivacySettingsSheet;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            if (customAction != null) {
              customAction();
            } else if (routeBuilder != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: routeBuilder),
              );
            }
          },
          icon: Icon(icon, size: 16, color: Colors.white),
          label: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandPrimaryOf(context),
            foregroundColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsContainer() {
    if (_isTyping || _messages.isEmpty) return const SizedBox.shrink();

    final lastMessage = _messages.last;
    if (lastMessage.isUser) return const SizedBox.shrink();

    final suggestions = _extractSuggestions(lastMessage.content);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ActionChip(
                backgroundColor: AppColors.cardColorOf(context),
                side: BorderSide(
                  color:
                      AppColors.brandPrimaryOf(context).withValues(alpha: 0.2),
                  width: 1,
                ),
                elevation: 1,
                shadowColor: Colors.black.withValues(alpha: 0.05),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                label: Text(
                  suggestion,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.brandPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => _sendMessage(suggestion),
              ),
            );
          },
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleClearAllConversations() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardColorOf(context),
        title: Text(
          _t('Clear History?', 'I-clear ang History?'),
          style: TextStyle(color: AppColors.headingSoft),
        ),
        content: Text(
          _t('Are you sure you want to delete all chat history? This cannot be undone.',
              'Sigurado ka bang nais mong burahin ang lahat ng chat history? Hindi na ito maibabalik.'),
          style: TextStyle(color: AppColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'Kanselahin')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _t('Delete', 'Burahin'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _loadingMessages = true;
      });
      await ChatbotService.clearAllConversations();
      await _initializeChat();
    }
  }

  void _askFAQInChat(FAQItem faq) {
    _tabController.animateTo(0);
    final questionText = _t(faq.questionEn, faq.questionTl);
    _sendMessage(questionText);
  }

  void _showPrivacySettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: AppColors.cardColorOf(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: AppColors.brandPrimary),
                        const SizedBox(width: 8),
                        Text(
                          // Named for what she decides here, not for the
                          // settings screen it technically is.
                          _t('What Ate can see',
                              'Ano ang nakikita ni Ate'),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.headingSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24, thickness: 1, color: Color(0xFFF5E4EC)),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimaryOf(context)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.brandPrimaryOf(context)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: AppColors.brandPrimary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _t('Your privacy is respected. The settings below control what information is shared with Ate Assistant to tailor her advice. Toggling off an item will exclude it from the AI context.',
                                      'Pinahahalagahan namin ang inyong privacy. Ang mga setting sa ibaba ay kumokontrol sa impormasyong ibinabahagi kay Ate Assistant. Ang pag-toggle off ay magtatanggal nito sa konteksto ng AI.'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.brandPrimaryOf(context),
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (widget.hasPregnancy) ...[
                          _buildPrivacyHeader(_t(
                              'Pregnancy Profile', 'Profile ng Pagbubuntis')),
                          SwitchListTile(
                            activeThumbColor: AppColors.brandPrimary,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _t('Share Pregnancy Details',
                                  'Ibahagi ang Detalye ng Pagbubuntis'),
                              style: TextStyle(
                                  color: AppColors.headingSoft,
                                  fontSize: 14),
                            ),
                            subtitle: Text(
                              _t(
                                'Week ${widget.week}, ${_tTrimester(widget.trimester)}, Risk Level: ${_tRiskLevel(widget.riskLevel)}',
                                'Linggo ${widget.week}, ${_tTrimester(widget.trimester)}, Antas ng Panganib: ${_tRiskLevel(widget.riskLevel)}',
                              ),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                            value: !_hidePregnancyInfo,
                            onChanged: (val) async {
                              final newHide = !val;
                              await AuthStorage.saveHiddenPregnancyInfo(
                                  newHide);
                              setSheetState(() {
                                _hidePregnancyInfo = newHide;
                              });
                              setState(() {
                                _hidePregnancyInfo = newHide;
                              });
                            },
                          ),
                          const Divider(height: 24, thickness: 1, color: Color(0xFFF5E4EC)),
                        ],
                        _buildPrivacyHeader(_t('Allergies', 'Mga Allergy')),
                        if (_activeAllergies.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              _t('No active allergies recorded.',
                                  'Walang nakatalang alerdye.'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          ..._activeAllergies.map((allergen) {
                            final isVisible =
                                !_hiddenAllergies.contains(allergen);
                            return SwitchListTile(
                              activeThumbColor: AppColors.brandPrimary,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                allergen,
                                style: TextStyle(
                                    color: AppColors.headingSoft,
                                    fontSize: 14),
                              ),
                              value: isVisible,
                              onChanged: (val) async {
                                final updatedList =
                                    List<String>.from(_hiddenAllergies);
                                if (val) {
                                  updatedList.remove(allergen);
                                } else {
                                  if (!updatedList.contains(allergen)) {
                                    updatedList.add(allergen);
                                  }
                                }
                                await AuthStorage.saveHiddenAllergies(
                                    updatedList);
                                setSheetState(() {
                                  _hiddenAllergies = updatedList;
                                });
                                setState(() {
                                  _hiddenAllergies = updatedList;
                                });
                              },
                            );
                          }),
                        const Divider(height: 24, thickness: 1, color: Color(0xFFF5E4EC)),
                        _buildPrivacyHeader(_t(
                            'Medical Conditions', 'Mga Medikal na Kondisyon')),
                        if (_activeMedicalConditions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              _t('No active medical conditions recorded.',
                                  'Walang nakatalang medikal na kondisyon.'),
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          ..._activeMedicalConditions.map((cond) {
                            final isVisible =
                                !_hiddenMedicalConditions.contains(cond);
                            return SwitchListTile(
                              activeThumbColor: AppColors.brandPrimary,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                cond,
                                style: TextStyle(
                                    color: AppColors.headingSoft,
                                    fontSize: 14),
                              ),
                              value: isVisible,
                              onChanged: (val) async {
                                final updatedList =
                                    List<String>.from(_hiddenMedicalConditions);
                                if (val) {
                                  updatedList.remove(cond);
                                } else {
                                  if (!updatedList.contains(cond)) {
                                    updatedList.add(cond);
                                  }
                                }
                                await AuthStorage.saveHiddenMedicalConditions(
                                    updatedList);
                                setSheetState(() {
                                  _hiddenMedicalConditions = updatedList;
                                });
                                setState(() {
                                  _hiddenMedicalConditions = updatedList;
                                });
                              },
                            );
                          }),
                        const Divider(height: 24, thickness: 1, color: Color(0xFFF5E4EC)),
                        const SizedBox(height: 8),
                        _buildPrivacyHeader(_t('AI Ethical Code & Safe Use',
                            'Etika at Ligtas na Paggamit ng AI')),
                        const SizedBox(height: 8),
                        _buildEthicalCard(
                          context,
                          icon: Icons.psychology_alt_rounded,
                          title: _t('Informational Support Only',
                              'Impormasyon Lamang ang Layunin'),
                          description: _t(
                              'Ate Assistant is an AI helper, not a doctor or midwife. It cannot provide clinical diagnoses or prescriptions. Always consult your midwife or OB-GYN.',
                              'Si Ate Assistant ay AI na katulong at hindi doktor o midwife. Hindi ito maaaring magbigay ng medikal na diagnosis o reseta. Kumonsulta palagi sa inyong midwife o doktor.'),
                        ),
                        const SizedBox(height: 10),
                        _buildEthicalCard(
                          context,
                          icon: Icons.lock_outline,
                          title: _t('Secure Data Processing',
                              'Ligtas na Pagproseso ng Data'),
                          description: _t(
                              'Your shared health context is only processed to personalize recommendations and is never stored for model training or shared with third parties.',
                              'Ang iyong ibinabahaging detalye ay ginagamit lamang para sa iyong rekomendasyon. Hindi ito ginagamit para sa pagsasanay ng AI o ibinabahagi sa iba.'),
                        ),
                        const SizedBox(height: 10),
                        _buildEthicalCard(
                          context,
                          icon: Icons.chat_bubble_outline_rounded,
                          title: _t('Inclusive & Respectful AI',
                              'Madaling Maunawaan at May Kagalangang AI'),
                          description: _t(
                              'Ate Assistant is designed to be culturally respectful and to converse in your preferred language style (English, Tagalog, or Taglish).',
                              'Si Ate Assistant ay idinisenyo upang maging magalang sa kultura at makipag-usap sa iyong ginustong wika (English, Tagalog, o Taglish).'),
                        ),
                        const SizedBox(height: 10),
                        _buildEthicalCard(
                          context,
                          icon: Icons.local_hospital_outlined,
                          title: _t('Emergency Redirection',
                              'Pang-emerhensiyang Direksyon'),
                          description: _t(
                              'Critical symptoms automatically trigger local hotline suggestions. The AI will never attempt to diagnose severe warning signs.',
                              'Ang mga malulubhang sintomas ay awtomatikong nagpapakita ng hotline. Hindi susubukang suriin ng AI ang mga pang-emerhensiyang senyales.'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// The same small uppercase heading ProfileCardSection uses, so the sheet
  /// reads like the rest of the app's grouped settings rather than a stack of
  /// pink labels.
  Widget _buildPrivacyHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 6.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEthicalCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondaryOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.brandPrimaryOf(context), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.headingSoft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.selectedLanguage,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.bgPrimaryOf(context),
          appBar: AppBar(
            backgroundColor: AppColors.cardColorOf(context),
            elevation: 0,
            centerTitle: true,
            // Pink title, like every other pushed page in the mother's app.
            // "Ate Assistant Chatbot" in near-black was the one screen whose
            // header looked like a different application — and "Chatbot" is
            // the developer's word for her; she calls it Ate.
            title: Text(
              _t('Ate', 'Ate'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.brandPrimary,
              ),
            ),
            // Soft grey, not near-black. These two are secondary to the pink
            // shield and the title — history and close are ways out of the
            // screen, not the reason she is on it.
            leading: Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.history_rounded, size: 22),
                  color: AppColors.textSecondary,
                  tooltip: _t('Past chats', 'Mga dating usapan'),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                );
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.shield_outlined, size: 22),
                color: AppColors.brandPrimaryOf(context),
                tooltip:
                    _t('AI Privacy Settings', 'Mga Setting ng Privacy sa AI'),
                onPressed: _showPrivacySettingsSheet,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                color: AppColors.textSecondary,
                tooltip: _t('Close', 'Isara'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.brandPrimary,
              indicatorWeight: 3,
              // The line under the tabs.
              //
              // Material draws this itself, and left alone it takes the
              // theme's outline colour — which is what put a hard rule the
              // full width of the header. Named explicitly so it matches the
              // soft rules used everywhere else in the app.
              dividerColor: const Color(0xFFF5E4EC),
              dividerHeight: 1,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              tabs: [
                Tab(text: _t('Chat with Ate', 'Chat kay Ate')),
                Tab(text: _t('FAQs', 'Mga Tanong')),
              ],
            ),
          ),
          drawer: _buildHistoryDrawer(),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildChatTab(),
              _buildFAQTab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: AppColors.bgPrimaryOf(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _t('Chat History', 'Mga Chat'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.headingSoft,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined,
                        color: AppColors.error),
                    tooltip: _t('Delete All', 'Burahin Lahat'),
                    onPressed: _handleClearAllConversations,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF5E4EC)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  _drawerSearchController.clear();
                  setState(() {
                    _drawerSearchQuery = '';
                  });
                  Navigator.pop(context); // Close Drawer
                  _createNewSession();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(_t('New Conversation', 'Bagong Chat')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPrimaryOf(context),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSecondaryOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.borderOf(context),
                  ),
                ),
                child: TextField(
                  controller: _drawerSearchController,
                  onChanged: (value) {
                    setState(() {
                      _drawerSearchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: _t('Search chat...', 'Maghanap ng chat...'),
                    hintStyle: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.textSecondaryOf(context),
                      size: 20,
                    ),
                    suffixIcon: _drawerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: AppColors.textSecondaryOf(context),
                              size: 18,
                            ),
                            onPressed: () {
                              _drawerSearchController.clear();
                              setState(() {
                                _drawerSearchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: TextStyle(
                    color: AppColors.headingSoft,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loadingSessions
                  ? const Center(child: CircularProgressIndicator())
                  : () {
                      final filteredSessions = _sessions.where((session) {
                        return session.title
                            .toLowerCase()
                            .contains(_drawerSearchQuery.toLowerCase());
                      }).toList();

                      if (filteredSessions.isEmpty) {
                        return Center(
                          child: Text(
                            _drawerSearchQuery.isEmpty
                                ? _t('No chat history', 'Walang nakaraang chat')
                                : _t('No matching history found',
                                    'Walang nahanap na tugmang chat'),
                            style: TextStyle(
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredSessions.length,
                        itemBuilder: (context, index) {
                          final session = filteredSessions[index];
                          final isSelected =
                              _currentSession?.sessionId == session.sessionId;
                          return ListTile(
                            leading: Icon(
                              Icons.chat_bubble_outline,
                              color: isSelected
                                  ? AppColors.brandPrimaryOf(context)
                                  : AppColors.textSecondaryOf(context),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? AppColors.brandPrimaryOf(context)
                                    : AppColors.headingSoft,
                              ),
                            ),
                            subtitle: Text(
                              DateFormat('MMM dd, yyyy')
                                  .format(session.createdAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                            selected: isSelected,
                            onTap: () {
                              _drawerSearchController.clear();
                              setState(() {
                                _drawerSearchQuery = '';
                              });
                              Navigator.pop(context); // Close Drawer
                              _loadSession(session);
                            },
                          );
                        },
                      );
                    }(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_hidePregnancyInfo ||
            _hiddenAllergies.isNotEmpty ||
            _hiddenMedicalConditions.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(
                      'Warning: Some medical history is hidden. AI advice may not be fully safe or customized for your safety.',
                      'Babala: May mga tinagong detalye sa iyong medical history. Maaaring hindi maging ganap na ligtas ang payo ng AI.',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_showPrivacyBanner)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    AppColors.brandPrimaryOf(context).withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: AppColors.brandPrimaryOf(context),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _t(
                      'Note: Ate Assistant uses your health info for safe advice. Tap the shield icon at the top to manage your privacy.',
                      'Tandaan: Gagamitin ni Ate Assistant ang inyong health details para sa ligtas na payo. I-tap ang shield icon sa itaas upang pamahalaan ang privacy.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.headingSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textSecondaryOf(context),
                  onPressed: () {
                    setState(() {
                      _showPrivacyBanner = false;
                    });
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? _buildWelcomeView()
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return _buildTypingIndicatorBubble();
                    }

                    final message = _messages[index];
                    return _buildMessageBubble(message);
                  },
                ),
        ),
        _buildSuggestionsContainer(),
        _buildInputContainer(),
      ],
    );
  }

  Widget _buildWelcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular Avatar for Ate Assistant
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: Image.asset(
                'assets/images/chatbot_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Greeting Title
          Text(
            _t('Meet Ate Assistant', 'Kausapin si Ate Assistant'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.headingSoft,
            ),
          ),
          const SizedBox(height: 6),
          // Subtitle
          Text(
            _t('Your personal AI guide for a safe and healthy pregnancy. Ask me anything about nutrition, symptoms, or baby updates!',
                'Ang iyong personal na AI guide para sa ligtas at malusog na pagbubuntis. Magtanong tungkol sa pagkain, mga sintomas, o paglaki ng bata!'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Prompt suggestions section header
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _t('Try Asking (Subukang Itanong):', 'Subukang Itanong:'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.brandPrimaryOf(context),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Grid/List of starter prompts
          _buildStarterPromptTile(
            title: _t('Foods to Avoid', 'Mga Pagkaing Dapat Iwasan'),
            subtitle: _t('What foods should I stay away from?',
                'Ano ang mga pagkaing hindi ligtas?'),
            query: _t('What foods should I avoid during pregnancy?',
                'Ano ang mga pagkaing dapat kong iwasan habang buntis?'),
            icon: Icons.no_food_outlined,
          ),
          const SizedBox(height: 8),
          _buildStarterPromptTile(
            title: _t('Relieving Back Pain', 'Sakit sa Likod'),
            subtitle: _t('Safe ways to ease pregnancy back aches.',
                'Paano maibsan ang pananakit ng likod?'),
            query: _t('How can I relieve back pain safely during pregnancy?',
                'Paano maibsan ang pananakit ng likod nang ligtas habang buntis?'),
            icon: Icons.health_and_safety_outlined,
          ),
          const SizedBox(height: 8),
          _buildStarterPromptTile(
            title: _t('Exercises per Trimester', 'Mga Ehersisyo'),
            subtitle: _t('Learn about safe physical activities.',
                'Anong mga ehersisyo ang ligtas sa akin?'),
            query: _t('What are safe exercises for my trimester?',
                'Anong mga ehersisyo ang ligtas para sa aking trimester?'),
            icon: Icons.fitness_center_outlined,
          ),
          const SizedBox(height: 8),
          _buildStarterPromptTile(
            title: _t('Coffee & Caffeine', 'Uminom ng Kape'),
            subtitle: _t('Is it safe to consume caffeine?',
                'Ligtas ba ang uminom ng kape?'),
            query: _t('Is coffee safe for pregnant mothers?',
                'Ligtas ba ang uminom ng kape kapag buntis?'),
            icon: Icons.coffee_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStarterPromptTile({
    required String title,
    required String subtitle,
    required String query,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.bgSecondaryOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.15)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _sendMessage(query),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:
                      AppColors.brandPrimaryOf(context).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: AppColors.brandPrimaryOf(context), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.headingSoft,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.6),
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final cleanText = _cleanMessageContent(message.content);
    final splitText = !isUser
        ? _splitMessageDisclaimer(cleanText)
        : {'content': cleanText, 'disclaimer': ''};
    final mainContent = splitText['content'] ?? cleanText;
    final disclaimer = splitText['disclaimer'] ?? '';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.brandPrimaryOf(context)
              : AppColors.cardColorOf(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.face_retouching_natural_rounded,
                    size: 14,
                    color: AppColors.brandPrimaryOf(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _t('Ate Assistant', 'Ate Assistant'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            _buildFormattedText(mainContent, context, isUser),
            if (!isUser && disclaimer.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.borderOf(context),
              ),
              const SizedBox(height: 6),
              Text(
                disclaimer,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.3,
                ),
              ),
            ],
            if (!isUser) ...[
              ..._extractHotlineNumbers(message)
                  .map((hotlineNum) => _buildHotlineButton(hotlineNum)),
              ..._extractNavigationActions(message.content)
                  .map((screenKey) => _buildNavigationButton(screenKey)),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isUser)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTtsActionButton(
                          message.messageId?.toString() ??
                              message.hashCode.toString(),
                          mainContent),
                      _buildCopyActionButton(mainContent),
                      _buildShareActionButton(mainContent),
                    ],
                  )
                else
                  _buildCopyActionButton(mainContent, isUser: true),
                Text(
                  DateFormat('hh:mm a').format(message.createdAt),
                  style: TextStyle(
                    fontSize: 9,
                    color: isUser
                        ? Colors.white70
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTtsActionButton(String messageId, String text) {
    final isLoading = _loadingTtsMessageId == messageId;
    final isPlaying = _currentlyReadingMessageId == messageId;
    return GestureDetector(
      onTap: () => _toggleTts(messageId, text),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: isLoading
              ? CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.brandPrimaryOf(context),
                  ),
                )
              : Icon(
                  isPlaying
                      ? Icons.stop_circle_outlined
                      : Icons.volume_up_rounded,
                  size: 16,
                  color: isPlaying
                      ? AppColors.brandPrimaryOf(context)
                      : AppColors.textSecondaryOf(context),
                ),
        ),
      ),
    );
  }

  Widget _buildCopyActionButton(String text, {bool isUser = false}) {
    return GestureDetector(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final snackColor = AppColors.brandPrimaryOf(context);
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(
          SnackBar(
            content: Text(_t('Copied to clipboard!', 'Kopya sa clipboard!')),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: snackColor,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Icon(
          Icons.copy_all_rounded,
          size: 14,
          color: isUser ? Colors.white70 : AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }

  Widget _buildShareActionButton(String text) {
    return GestureDetector(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final snackColor = AppColors.brandPrimaryOf(context);
        await Clipboard.setData(ClipboardData(text: text));
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Ready to share! Copied message to clipboard.',
                'Handa nang ibahagi! Nakopya ang chat sa clipboard.',
              ),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: snackColor,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Icon(
          Icons.share_outlined,
          size: 14,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }

  Future<void> _toggleTts(String messageId, String text) async {
    // If already playing this message → stop
    if (_currentlyReadingMessageId == messageId) {
      // Both engines: either one could be the one talking, and stopping only
      // the player would leave the device voice reading on.
      await _audioPlayer.stop();
      await _deviceTts?.stop();
      if (mounted) {
        setState(() {
          _currentlyReadingMessageId = null;
        });
      }
      return;
    }

    // Stop whatever is currently playing, from either engine.
    await _audioPlayer.stop();
    await _deviceTts?.stop();
    if (mounted) {
      setState(() {
        _currentlyReadingMessageId = null;
        _loadingTtsMessageId = messageId;
      });
    }

    // Filipino goes straight to the device voice.
    //
    // Orpheus is `orpheus-v1-english` — an English-only model. Asked to read a
    // Tagalog reply it pronounces it as English, which is worse than not
    // reading it at all for the mother who chose Filipino. The phone's own
    // engine has a fil-PH voice on most Android builds.
    // If the device voice fails, this falls through to Groq below rather than
    // returning — an English-accented reading is worse than a Filipino one,
    // but both are better than a mother tapping the speaker and getting
    // nothing. On web the device path fails often, which is what the
    // SpeechSynthesisErrorEvent in the log was.
    if (LanguageService.isFilipino) {
      final spoken = await _speakOnDevice(text, messageId);
      if (spoken) return;
      debugPrint('[MotherChatbotPage] device voice failed; trying Groq');
    }

    try {
      final wavBytes = await _groqService.speakWithGroqTts(text);

      if (!mounted) return;
      setState(() {
        _loadingTtsMessageId = null;
        _currentlyReadingMessageId = messageId;
      });

      // Write bytes to a temporary file to guarantee compatibility across all Android devices/emulators
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_tts_$messageId.wav');
      await tempFile.writeAsBytes(wavBytes, flush: true);

      // Play from the temporary file source
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('[MotherChatbotPage] Groq TTS error: $e');

      // The phone can read it even when the service will not.
      //
      // Groq's TTS is a hosted, gated, English-only model behind an API key —
      // four ways for it to be unavailable to a mother who just wants the
      // message read to her. The device engine needs no key, no terms, and no
      // signal. Tried before giving up, so the feature degrades instead of
      // failing.
      if (await _speakOnDevice(text, messageId)) return;
      if (mounted) {
        setState(() {
          _loadingTtsMessageId = null;
          _currentlyReadingMessageId = null;
        });
        // What she sees is one plain sentence.
        //
        // This printed the provider's raw reply — a mother tapping the speaker
        // met "Groq TTS Error (400): The model `canopylabs/orpheus-v1-english`
        // requires terms acceptance. Please have the org admin accept the
        // terms at console.groq.com..." in a red box. That is a message for
        // whoever owns the API key, and it is already in the debug log above,
        // where they will see it.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(
              'Reading aloud is not available right now. You can still read '
                  'the message.',
              'Hindi available ngayon ang pagbasa nang malakas. Mababasa mo pa '
                  'rin ang mensahe.',
            )),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: AppColors.headingSoft,
          ),
        );
      }
    }
  }

  Widget _buildTypingIndicatorBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardColorOf(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.brandPrimary),
            ),
            const SizedBox(width: 8),
            Text(
              _t('Ate is typing...', 'Sumusulat si Ate...'),
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattedText(String text, BuildContext context, bool isUser) {
    final textColor = isUser ? Colors.white : AppColors.headingSoft;
    final List<TextSpan> spans = [];
    final RegExp regex = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          height: 1.4,
        ),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildInputContainer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardColorOf(context),
        border: Border(
          top: BorderSide(color: AppColors.borderOf(context), width: 1),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_isTranscribing)
              Expanded(
                child: ShimmerTranscribingLoader(
                  text: _t('Converting speech to text...', 'Isinasalin ang boses sa teksto...'),
                ),
              )
            else if (_isRecording)
              Expanded(
                child: AnimatedBuilder(
                  animation: _recordingGlowController,
                  builder: (context, child) {
                    final glowVal = _recordingGlowController.value;
                    return Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.bgPrimaryOf(context),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.2 + 0.3 * glowVal),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.05 + 0.15 * glowVal),
                            blurRadius: 8.0,
                            spreadRadius: 1.0,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _recordingGlowController,
                        builder: (context, _) {
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.4 + 0.6 * _recordingGlowController.value),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(alpha: 0.4 * _recordingGlowController.value),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_t("Recording", "Nagre-record")}... ${_formatDuration(_recordingDuration)}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      SoundwaveVisualizer(volume: _currentAmplitude),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        onPressed: () {
                          try {
                            HapticFeedback.mediumImpact();
                          } catch (e) {
                            debugPrint('HapticFeedback failed: $e');
                          }
                          _cancelVoiceRecording();
                        },
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        tooltip: _t('Cancel recording', 'Kanselahin ang recording'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                // The white, softly-shadowed field the rest of the app uses,
                // rather than a flat grey pill on a grey bar.
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFFF5E4EC)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _inputController,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        color: AppColors.inputText, fontSize: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      hintText: _t('Ask Ate anything…',
                          'Magtanong ka lang kay Ate…'),
                      hintStyle: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14.5),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            PulsingMicButton(
              isRecording: _isRecording,
              onPressed: (_isTyping || _isTranscribing) ? () {} : _toggleVoiceInput,
            ),
            const SizedBox(width: 8),
            // A filled circle, matching the send affordance elsewhere. A bare
            // pink glyph beside a filled mic button read as the lesser of the
            // two, when sending is the main action.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: (_isTyping || _isTranscribing || _isRecording)
                    ? const Color(0xFFFFD5E5)
                    : AppColors.brandPrimary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                tooltip: _t('Send', 'Ipadala'),
                onPressed: (_isTyping || _isTranscribing || _isRecording)
                    ? null
                    : () => _sendMessage(_inputController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: faqsList.length,
      itemBuilder: (context, index) {
        final faq = faqsList[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF5E4EC)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            // The default ExpansionTile draws a rule above and below itself
            // when open — two more hard lines on a page that had several.
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
            title: Text(
              _t(faq.questionEn, faq.questionTl),
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: AppColors.headingSoft,
              ),
            ),
            // A pill that fits its words.
            //
            // The category sat in a full-width block under every question, so
            // "Nutrition" arrived as a pink bar the width of the card and read
            // as a progress meter rather than a label.
            subtitle: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _tCategory(faq.category),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandText,
                  ),
                ),
              ),
            ),
            iconColor: AppColors.brandPrimary,
            collapsedIconColor: AppColors.brandPrimary,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedAlignment: Alignment.topLeft,
            children: [
              Text(
                _t(faq.answerEn, faq.answerTl),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppColors.inputText,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _askFAQInChat(faq),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: Text(_t('Ask Ate in Chat', 'Itanong kay Ate sa Chat')),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.brandPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}

class FAQItem {
  final String questionEn;
  final String questionTl;
  final String answerEn;
  final String answerTl;
  final String category;

  FAQItem({
    required this.questionEn,
    required this.questionTl,
    required this.answerEn,
    required this.answerTl,
    required this.category,
  });
}

final List<FAQItem> faqsList = [
  FAQItem(
    category: 'Nutrisyon / Nutrition',
    questionEn: 'What foods should I avoid during pregnancy?',
    questionTl: 'Ano ang mga pagkaing dapat iwasan kapag buntis?',
    answerEn:
        'Avoid raw or undercooked foods (like raw eggs, sashimi, kilawin) to prevent bacterial infections. Limit salty or sugary foods, and fish high in mercury (like tuna). Limit caffeine intake.',
    answerTl:
        'Iwasan ang mga hilaw o hindi gaanong lutong pagkain (gaya ng hilaw na itlog, sashimi, o kilawin) upang maiwasan ang impeksyon. Bawasan ang maaalat, matatamis, at isdang mataas sa mercury tulad ng tuna. Limitahan din ang kape o caffeine.',
  ),
  FAQItem(
    category: 'Prenatal Care / Pagpapasuri',
    questionEn: 'How often should I get a prenatal checkup?',
    questionTl: 'Gaano kadalas dapat magpa-prenatal checkup?',
    answerEn:
        'It is recommended to have at least 4 prenatal checkups: 1 in the 1st trimester (before 12 weeks), 1 in the 2nd trimester (12-26 weeks), and 2 in the 3rd trimester (27 weeks onwards). More frequent checkups are highly encouraged if recommended by your midwife.',
    answerTl:
        'Inirerekomenda ang hindi bababa sa 4 na prenatal checkup: 1 sa 1st trimester (bago mag-12 weeks), 1 sa 2nd trimester (12-26 weeks), at 2 sa 3rd trimester (27 weeks pataas). Mas mabuti kung mas madalas, lalo na kung nireseta ng iyong midwife.',
  ),
  FAQItem(
    category: 'Mga Babala / Danger Signs',
    questionEn:
        'What are the pregnancy danger signs that require immediate care?',
    questionTl:
        'Ano ang mga danger signs sa pagbubuntis na kailangang ipatingin agad?',
    answerEn:
        'Seek emergency medical attention if you experience: vaginal bleeding, severe abdominal pain, high fever, severe headaches with blurred vision, swelling of the face or hands, or sudden reduction of baby movements.',
    answerTl:
        'Magpatingin agad sa doktor o midwife kapag nakaranas ng: pagdurugo sa puwerta, matinding pananakit ng tiyan, mataas na lagnat, matinding sakit ng ulo na may kasamang panlalabo ng paningin, pamamanas ng mukha o kamay, o biglang paghinto/pagbawas ng galaw ng sanggol.',
  ),
  FAQItem(
    category: 'Pamamanas / Swelling',
    questionEn: 'Is foot swelling normal during pregnancy?',
    questionTl: 'Normal ba ang pamamanas ng paa habang buntis?',
    answerEn:
        'Yes, mild swelling of the feet is common in late pregnancy. Elevate your feet when resting, avoid long periods of sitting/standing, and wear comfortable shoes. However, if swelling affects your face/hands or is accompanied by headaches, check with your midwife immediately as it may indicate preeclampsia.',
    answerTl:
        'Oo, karaniwan ang banayad na pamamanas ng paa lalo na sa huling bahagi ng pagbubuntis. Itaas ang paa kapag nagpapahinga, iwasan ang matagal na pagtayo/pag-upo, at gumamit ng malambot na sapatos. Ngunit kung mamamaga ang mukha/kamay o sasakit ang ulo, magpatingin agad dahil maaari itong preeclampsia.',
  ),
  FAQItem(
    category: 'Morning Sickness / Pagduduwal',
    questionEn: 'How can I manage severe morning sickness?',
    questionTl: 'Paano maiiwasan ang matinding morning sickness o pagduduwal?',
    answerEn:
        'Eat small, frequent meals instead of large ones. Avoid greasy, spicy, or strong-smelling foods. Keep simple crackers by your bed to eat before standing up in the morning, and drink water in between meals to stay hydrated.',
    answerTl:
        'Kumain ng maliliit at madalas na bahagi (small, frequent meals). Iwasan ang mamantika, maanghang, o mabahong pagkain. Magtabi ng crackers o biskwit sa tabi ng higaan para kainin bago bumangon sa umaga. Uminom ng tubig sa pagitan ng pagkain.',
  ),
];

// ── Voice Recording UI Components ──────────────────────────────────────────

class ShimmerTranscribingLoader extends StatefulWidget {
  final String text;
  const ShimmerTranscribingLoader({super.key, required this.text});

  @override
  State<ShimmerTranscribingLoader> createState() => _ShimmerTranscribingLoaderState();
}

class _ShimmerTranscribingLoaderState extends State<ShimmerTranscribingLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgPrimaryOf(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _controller,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.brandPrimaryOf(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [
                        AppColors.textSecondaryOf(context),
                        AppColors.brandPrimaryOf(context),
                        AppColors.textSecondaryOf(context),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      begin: Alignment(-2.0 + 4.0 * _controller.value, 0.0),
                      end: Alignment(-1.0 + 4.0 * _controller.value, 0.0),
                    ).createShader(bounds);
                  },
                  child: Text(
                    widget.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SoundwaveVisualizer extends StatefulWidget {
  final double volume;
  const SoundwaveVisualizer({super.key, required this.volume});

  @override
  State<SoundwaveVisualizer> createState() => _SoundwaveVisualizerState();
}

class _SoundwaveVisualizerState extends State<SoundwaveVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _baseHeights = [8.0, 16.0, 24.0, 12.0, 32.0, 20.0, 28.0, 16.0, 22.0, 10.0, 6.0];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_baseHeights.length, (index) {
            final value = _controller.value;
            final phase = (index * 0.15) % 1.0;
            final sine = (value + phase) % 1.0;
            final factor = sine < 0.5 ? sine * 2 : (1.0 - sine) * 2;
            
            const double idleLevel = 0.15;
            final double scalingFactor = idleLevel + (1.0 - idleLevel) * widget.volume;
            
            const double minHeight = 4.0;
            final double height = minHeight + (_baseHeights[index] - minHeight) * factor * scalingFactor;

            return Container(
              width: 3.0,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.brandPrimaryOf(context),
                    Colors.redAccent,
                  ],
                ),
                borderRadius: BorderRadius.circular(1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.3 * scalingFactor),
                    blurRadius: 2.0,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class PulsingMicButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isRecording;
  const PulsingMicButton({
    super.key,
    required this.onPressed,
    required this.isRecording,
  });

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isRecording) {
      _pulseController.repeat(reverse: false);
    }
  }

  @override
  void didUpdateWidget(PulsingMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: false);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRecording) {
      return InkWell(
        onTap: () {
          try {
            HapticFeedback.lightImpact();
          } catch (e) {
            debugPrint('HapticFeedback failed: $e');
          }
          widget.onPressed();
        },
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandPrimaryOf(context),
                Colors.pinkAccent.shade100,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.brandPrimaryOf(context).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.mic_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseVal = _pulseController.value;
          final size1 = 48.0 + (24.0 * pulseVal);
          final size2 = 48.0 + (12.0 * pulseVal);
          
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                width: size1,
                height: size1,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(
                      alpha: 0.25 * (1.0 - pulseVal),
                    ),
                  ),
                ),
              ),
              Positioned(
                width: size2,
                height: size2,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withValues(
                      alpha: 0.4 * (1.0 - pulseVal),
                    ),
                  ),
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.stop_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    try {
                      HapticFeedback.mediumImpact();
                    } catch (e) {
                      debugPrint('HapticFeedback failed: $e');
                    }
                    widget.onPressed();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
