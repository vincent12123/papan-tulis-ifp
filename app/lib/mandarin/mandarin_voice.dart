import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks Mandarin with the panel's own text-to-speech engine (REQ-30): no
/// internet needed, but only if a Mandarin (zh-CN) voice is installed.
abstract class MandarinVoice {
  /// Whether a Mandarin voice can be used on this panel.
  Future<bool> init();

  Future<void> speak(String text, {bool slow = false});
}

/// Whether the panel can speak Mandarin; cards show their speak buttons only
/// when true (otherwise a hint how to install the voice).
abstract final class MandarinVoiceStatus {
  static final available = ValueNotifier<bool>(false);
}

class TtsMandarinVoice implements MandarinVoice {
  FlutterTts? _tts;

  /// Android speech rate: 0.5 is normal speed.
  static const normalRate = 0.45, slowRate = 0.25;

  @override
  Future<bool> init() async {
    try {
      final tts = FlutterTts();
      final ok = await tts.isLanguageAvailable('zh-CN');
      if (ok != true) return false;
      await tts.setLanguage('zh-CN');
      await tts.awaitSpeakCompletion(false);
      _tts = tts;
      return true;
    } catch (_) {
      // No TTS engine, or no plugin (widget tests): no voice.
      return false;
    }
  }

  @override
  Future<void> speak(String text, {bool slow = false}) async {
    final tts = _tts;
    if (tts == null || text.trim().isEmpty) return;
    try {
      await tts.stop();
      await tts.setSpeechRate(slow ? slowRate : normalRate);
      await tts.speak(text);
    } catch (_) {
      // Speaking is a help, never a reason to disturb the lesson.
    }
  }
}
