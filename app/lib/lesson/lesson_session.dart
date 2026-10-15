import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../server/server_client.dart';

/// The microphone (REQ-25). Tests use a fake.
abstract interface class LessonRecorder {
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// Path of the finished recording, or null when nothing was recorded.
  Future<String?> stop();
  Future<void> dispose();
}

/// AAC in an M4A file, mono 16 kHz at 48 kbit/s: speech stays clear and a
/// 45-minute lesson is about 16 MB.
class MicRecorder implements LessonRecorder {
  final AudioRecorder _mic = AudioRecorder();

  @override
  Future<bool> hasPermission() => _mic.hasPermission();

  @override
  Future<void> start(String path) => _mic.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 48000,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _mic.stop();

  @override
  Future<void> dispose() => _mic.dispose();
}

/// The school server's side of Rekam kelas.
abstract interface class LessonApi {
  /// Uploads the recording; returns the job id.
  Future<String> upload(Uint8List audio, List<String> formulas);
  Future<LessonStatus> status(String id);
}

enum LessonPhase { idle, recording, sending, processing, ready, failed }

/// Rekam kelas (SPEC 1.9, REQ-25): record → send → the server transcribes
/// and summarizes while the teacher keeps teaching → "Ringkasan siap".
class LessonSession extends ChangeNotifier {
  LessonSession({
    required this.api,
    required LessonRecorder Function() recorder,
    Future<String> Function()? tempPath,
    this.pollEvery = const Duration(seconds: 10),
    this.maxLength = const Duration(minutes: 90),
    DateTime Function()? clock,
  }) : _newRecorder = recorder,
       _tempPath = tempPath ?? _defaultPath,
       _clock = clock ?? DateTime.now;

  final LessonApi api;

  /// The microphone is opened only when recording starts.
  final LessonRecorder Function() _newRecorder;
  LessonRecorder? _recorder;
  LessonRecorder get recorder => _recorder ??= _newRecorder();
  final Duration pollEvery;
  final Duration maxLength;
  final Future<String> Function() _tempPath;
  final DateTime Function() _clock;

  static const noPermission =
      'Aplikasi belum diizinkan memakai mikrofon. Izinkan di Pengaturan '
      'Android, lalu coba lagi.';
  static const noMicrophone =
      'Mikrofon panel tidak bisa dipakai. Periksa mikrofon, lalu coba lagi.';
  static const offline =
      'Rekaman belum terkirim karena panel tidak terhubung ke server '
      'sekolah. Tekan Coba lagi.';
  static const silent = 'Tidak ada suara pelajaran yang terdengar di rekaman.';
  static const aiDown =
      'Ringkasan belum bisa dibuat. Coba lagi beberapa menit lagi.';
  static const failedGeneric =
      'Ringkasan gagal dibuat di server sekolah. Tekan Coba lagi.';
  static const autoStoppedText =
      'Rekaman berhenti otomatis setelah 90 menit dan sedang diringkas.';

  LessonPhase phase = LessonPhase.idle;
  DateTime? _startedAt;
  String? _audio;
  String? _job;
  String? summary;
  String? error;

  /// Whether Coba lagi makes sense (the recording is still here).
  bool get canRetry => _audio != null;

  /// Formulas recognized on the board while recording (menu pintar).
  final List<String> formulas = [];
  Timer? _ticker;
  Timer? _poll;

  Duration get elapsed =>
      _startedAt == null ? Duration.zero : _clock().difference(_startedAt!);

  static Future<String> _defaultPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/pelajaran-${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  /// Returns an error text, or null once recording runs.
  Future<String?> start() async {
    if (phase != LessonPhase.idle) return null;
    if (!await recorder.hasPermission()) return noPermission;
    try {
      await recorder.start(await _tempPath());
    } on Exception {
      return noMicrophone;
    }
    formulas.clear();
    _startedAt = _clock();
    phase = LessonPhase.recording;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (elapsed >= maxLength) {
        stop(auto: true);
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
    return null;
  }

  /// Notes a formula seen on the board while recording.
  void noteFormulas(List<String> latex) {
    if (phase != LessonPhase.recording) return;
    for (final f in latex) {
      if (!formulas.contains(f) && formulas.length < 20) formulas.add(f);
    }
  }

  bool autoStopped = false;

  Future<void> stop({bool auto = false}) async {
    if (phase != LessonPhase.recording) return;
    _ticker?.cancel();
    autoStopped = auto;
    final path = await recorder.stop();
    _startedAt = null;
    if (path == null) {
      _fail(silent, keepAudio: false);
      return;
    }
    _audio = path;
    await _send();
  }

  Future<void> retry() async {
    if (phase != LessonPhase.failed) return;
    if (_job != null && _audio == null) {
      // Sent already: only the summary failed; ask the server again later.
      _fail(error ?? failedGeneric, keepAudio: false);
      return;
    }
    await _send();
  }

  Future<void> _send() async {
    final path = _audio;
    if (path == null) return;
    phase = LessonPhase.sending;
    error = null;
    notifyListeners();
    try {
      final bytes = await File(path).readAsBytes();
      _job = await api.upload(bytes, List.of(formulas));
    } on ServerFailure catch (f) {
      _fail(f is ServerUnreachable ? offline : failedGeneric, keepAudio: true);
      return;
    } on FileSystemException {
      _fail(noMicrophone, keepAudio: false);
      return;
    }
    // Sent: the recording on the panel is not needed any more.
    await _deleteAudio();
    phase = LessonPhase.processing;
    notifyListeners();
    _poll = Timer.periodic(pollEvery, (_) => _check());
  }

  bool _checking = false;

  Future<void> _check() async {
    final job = _job;
    if (job == null || _checking) return;
    _checking = true;
    try {
      final s = await api.status(job);
      switch (s.status) {
        case 'selesai':
          _poll?.cancel();
          summary = s.summary;
          phase = LessonPhase.ready;
          notifyListeners();
        case 'gagal':
          _poll?.cancel();
          _fail(switch (s.code) {
            'tanpa_suara' => silent,
            'ai_tidak_tersedia' => aiDown,
            _ => failedGeneric,
          }, keepAudio: false);
      }
    } on ServerFailure {
      // Keep polling: the panel may be offline for a moment.
    } finally {
      _checking = false;
    }
  }

  void _fail(String message, {required bool keepAudio}) {
    error = message;
    phase = LessonPhase.failed;
    if (!keepAudio) _deleteAudio();
    notifyListeners();
  }

  Future<void> _deleteAudio() async {
    final path = _audio;
    _audio = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Buang / after Tempel: back to idle.
  Future<void> reset() async {
    _poll?.cancel();
    _ticker?.cancel();
    await _deleteAudio();
    phase = LessonPhase.idle;
    summary = null;
    error = null;
    _job = null;
    autoStopped = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ticker?.cancel();
    final mic = _recorder;
    if (mic != null) {
      if (phase == LessonPhase.recording) mic.stop();
      mic.dispose();
    }
    _deleteAudio();
    super.dispose();
  }
}
