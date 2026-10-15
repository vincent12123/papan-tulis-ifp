import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:http/http.dart' as http;

/// Why a call to the school server failed, in the terms SCR-06 shows.
sealed class ServerFailure implements Exception {
  const ServerFailure();
}

/// No answer: wrong address, server down, or the panel is offline.
class ServerUnreachable extends ServerFailure {
  const ServerUnreachable();
}

/// The server refused the stored or typed admin PIN.
class PinRejected extends ServerFailure {
  const PinRejected({this.oldPinWrong = false});

  /// True when changing the PIN and the old PIN was wrong.
  final bool oldPinWrong;
}

/// Too many wrong PINs from this panel: locked for a while.
class PinLocked extends ServerFailure {
  const PinLocked(this.seconds);
  final int seconds;
}

/// The operator has not set a PIN on the server yet.
class PinNotSetOnServer extends ServerFailure {
  const PinNotSetOnServer();
}

/// The server rejected input with a message meant for the user.
class ServerValidation extends ServerFailure {
  const ServerValidation(this.message);
  final String message;
}

/// A provider test failed; [reason] is a short Indonesian cause.
class ProviderFailed extends ServerFailure {
  const ProviderFailed(this.reason);
  final String reason;
}

/// Anything else the server answered that the app does not understand.
/// Neither the chosen AI provider nor Ollama cloud answered.
class AiUnavailable extends ServerFailure {
  const AiUnavailable();
}

/// The AI did not answer within the time limit (NFR-33).
class AiTimedOut extends ServerFailure {
  const AiTimedOut();
}

/// "Jadikan grafik" found no function formula in the area.
class NoFormulaFound extends ServerFailure {
  const NoFormulaFound();
}

class ServerError extends ServerFailure {
  const ServerError();
}

class AiModel {
  const AiModel(this.name, {required this.supportsImages});
  final String name;
  final bool supportsImages;
}

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.defaultModel,
    required this.models,
  });

  final String id;
  final String name;
  final String defaultModel;
  final List<AiModel> models;
}

class ProviderList {
  const ProviderList({required this.defaultId, required this.providers});
  final String defaultId;
  final List<AiProvider> providers;

  AiProvider? byId(String? id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  AiProvider? get defaultProvider => byId(defaultId);
}

/// Talks to the school's FastAPI server with the admin PIN in every request
/// (SPEC §8, P-11).
class ServerClient {
  ServerClient({
    required this.baseUrl,
    required this.pin,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String pin;
  final http.Client _client;
  final Duration timeout;

  Uri _uri(String path) => Uri.parse(
    baseUrl.endsWith('/')
        ? '${baseUrl.substring(0, baseUrl.length - 1)}$path'
        : '$baseUrl$path',
  );

  Map<String, String> get _headers => {
    'X-PIN-Admin': pin,
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ServerUnreachable();
    } on SocketException {
      throw const ServerUnreachable();
    } on http.ClientException {
      throw const ServerUnreachable();
    } on HandshakeException {
      throw const ServerUnreachable();
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      // Not our server (e.g. a proxy error page).
      if (response.statusCode >= 400) throw const ServerError();
      throw const ServerError();
    }
    if (response.statusCode < 400) return body;
    final code = body['kode'];
    final message = body['pesan'];
    switch (response.statusCode) {
      case 401:
        throw PinRejected(oldPinWrong: code == 'pin_lama_salah');
      case 429 when code == 'terkunci':
        throw PinLocked((body['sisa_detik'] as num?)?.toInt() ?? 300);
      case 503 when code == 'pin_belum_diatur':
        throw const PinNotSetOnServer();
      case 422 when code == 'tanpa_rumus':
        throw const NoFormulaFound();
      case 503 when code == 'ai_tidak_tersedia':
        throw body['alasan'] == 'batas_waktu'
            ? const AiTimedOut()
            : const AiUnavailable();
      case 422 when message is String:
        throw ServerValidation(message);
      case 502 when message is String:
        throw ProviderFailed(message);
      default:
        throw const ServerError();
    }
  }

  /// Tes koneksi: checks the address and the PIN.
  Future<void> testConnection() =>
      _send(() => _client.get(_uri('/koneksi'), headers: _headers));

  Future<ProviderList> providers() async {
    final body = await _send(
      () => _client.get(_uri('/ai/penyedia'), headers: _headers),
    );
    try {
      return ProviderList(
        defaultId: body['bawaan'] as String,
        providers: [
          for (final p in body['penyedia'] as List)
            AiProvider(
              id: p['id'] as String,
              name: p['nama'] as String,
              defaultModel: p['model_bawaan'] as String,
              models: [
                for (final m in p['model'] as List)
                  AiModel(
                    m['nama'] as String,
                    supportsImages: m['dukung_gambar'] == true,
                  ),
              ],
            ),
        ],
      );
    } on TypeError {
      throw const ServerError();
    }
  }

  /// Tes AI: a short request to one provider, no fallback. Returns seconds.
  Future<double> testAi(String providerId, String model) async {
    final body = await _send(
      () => _client.post(
        _uri('/ai/tes'),
        headers: _headers,
        body: jsonEncode({'penyedia': providerId, 'model': model}),
      ),
      timeout: const Duration(seconds: 45),
    );
    return ((body['durasi_ms'] as num?) ?? 0) / 1000;
  }

  /// Runs one AI action on a PNG of the selected area (SPEC 5.7, P-03).
  /// [kind] is pecah_soal, soal_serupa, ringkas, or grafik.
  Future<AiAnswer> runAi({
    required String kind,
    required List<int> png,
    String? providerId,
    String? model,
  }) async {
    final Map<String, dynamic> body;
    try {
      body = await _send(
        () => _client.post(
          _uri('/ai/jalankan'),
          headers: _headers,
          body: jsonEncode({
            'jenis': kind,
            'gambar': base64Encode(png),
            'penyedia': ?providerId,
            'model': ?model,
          }),
        ),
        // The server gives up after 60 s (NFR-33); allow for the network.
        timeout: const Duration(seconds: 70),
      );
    } on ServerUnreachable {
      rethrow;
    }
    try {
      return AiAnswer(
        text: body['hasil'] as String?,
        graph: body['grafik'] as Map<String, dynamic>?,
        quiz: [
          for (final p in (body['kuis'] as List?) ?? const [])
            (
              (p as Map<String, dynamic>)['kiri'] as String,
              p['kanan'] as String,
            ),
        ],
        providerName: body['nama'] as String,
        model: body['model'] as String,
        fallbackFromName: body['cadangan_dari_nama'] as String?,
        fallbackReason: body['alasan_cadangan'] as String?,
      );
    } on TypeError {
      throw const ServerError();
    }
  }

  /// Pinyin & arti for [text] (REQ-30). The server answers even when its AI
  /// is down (no translation then).
  Future<MandarinReading> mandarin(
    String text, {
    String? providerId,
    String? model,
  }) async {
    final body = await _send(
      () => _client.post(
        _uri('/mandarin/arti'),
        headers: _headers,
        body: jsonEncode({
          'teks': text,
          'penyedia': ?providerId,
          'model': ?model,
        }),
      ),
      timeout: const Duration(seconds: 70),
    );
    try {
      return MandarinReading(
        hanzi: body['hanzi'] as String,
        pinyin: body['pinyin'] as String,
        translation: body['terjemahan'] as String?,
        words: [
          for (final w in body['kata'] as List)
            MandarinWord(
              hanzi: (w as Map<String, dynamic>)['hanzi'] as String,
              pinyin: w['pinyin'] as String,
              meaning: w['arti'] as String,
              source: w['sumber'] as String,
            ),
        ],
      );
    } on TypeError {
      throw const ServerError();
    }
  }

  /// Menu pintar (REQ-22): reads the circled area once; the answer holds
  /// everything its buttons need. [color] is the handwriting's ink color.
  Future<FormulaInsight> recognizeFormula({
    required List<int> png,
    required String color,
  }) async {
    final body = await _send(
      () => _client.post(
        _uri('/rumus/kenali'),
        headers: _headers,
        body: jsonEncode({'gambar': base64Encode(png), 'warna': color}),
      ),
      timeout: const Duration(seconds: 70),
    );
    try {
      final solution = body['penyelesaian'] as Map<String, dynamic>?;
      final tidy = body['rapi'] as Map<String, dynamic>?;
      return FormulaInsight(
        kind: body['jenis'] as String,
        hanzi: body['hanzi'] as String?,
        graph: body['grafik'] as Map<String, dynamic>?,
        // Mandarin areas (REQ-30) have no typeset formula.
        tidy: tidy == null ? TypesetImage.none : TypesetImage.fromJson(tidy),
        solution: solution == null ? null : TypesetImage.fromJson(solution),
        formulas: [
          for (final f in (body['rumus'] as List?) ?? const []) f as String,
        ],
        videos: [
          for (final v in (body['video'] as List?) ?? const [])
            VideoRef(
              (v as Map<String, dynamic>)['id'] as String,
              v['judul'] as String,
            ),
        ],
      );
    } on TypeError {
      throw const ServerError();
    } on FormatException {
      throw const ServerError();
    }
  }

  /// Rekam kelas (REQ-25): uploads the recording with the formulas seen on
  /// the board; returns the job id to poll.
  Future<String> uploadLesson(List<int> audio, List<String> formulas) async {
    final body = await _send(
      () => _client.post(
        _uri('/kelas/ringkas'),
        headers: {
          'X-PIN-Admin': pin,
          'Content-Type': 'audio/mp4',
          'X-Rumus': base64Encode(utf8.encode(jsonEncode(formulas))),
        },
        body: audio,
      ),
      // A long lesson over a slow school line.
      timeout: const Duration(minutes: 5),
    );
    final id = body['id'];
    if (id is! String) throw const ServerError();
    return id;
  }

  Future<LessonStatus> lessonStatus(String id) async {
    final body = await _send(
      () => _client.get(
        _uri('/kelas/ringkas/${Uri.encodeComponent(id)}'),
        headers: _headers,
      ),
    );
    final status = body['status'];
    if (status is! String) throw const ServerError();
    return LessonStatus(
      status,
      summary: body['ringkasan'] as String?,
      code: body['kode'] as String?,
    );
  }

  /// Where a catalog video streams from (REQ-24), with the PIN header.
  ({Uri uri, Map<String, String> headers}) videoAddress(String id) => (
    uri: _uri('/video/${Uri.encodeComponent(id)}'),
    headers: {'X-PIN-Admin': pin},
  );

  /// Ganti PIN admin (TSK-10). The old PIN is checked by the server.
  Future<void> changePin(String oldPin, String newPin) => _send(
    () => _client.post(
      _uri('/admin/pin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pin_lama': oldPin, 'pin_baru': newPin}),
    ),
  );

  void close() => _client.close();
}

/// SPEC 5.8: https always; http only for the school's local network.
/// Returns an error message, or null when the address is acceptable.
String? serverUrlProblem(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (text.isEmpty || uri == null || uri.host.isEmpty) {
    return 'Alamat server harus diawali https://.';
  }
  if (uri.scheme == 'https') return null;
  if (uri.scheme == 'http' && isLocalHost(uri.host)) return null;
  return 'Alamat server harus diawali https://.';
}

bool isLocalHost(String host) {
  if (host == 'localhost') return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final n = parts.map(int.tryParse).toList();
  if (n.any((v) => v == null || v < 0 || v > 255)) return false;
  return n[0] == 127 ||
      n[0] == 10 ||
      (n[0] == 172 && n[1]! >= 16 && n[1]! <= 31) ||
      (n[0] == 192 && n[1] == 168);
}

/// Same rules as the server, checked before sending (SPEC 5.8).
String? newPinProblem(String pin) {
  if (pin.length < 6 ||
      int.tryParse(pin) == null ||
      pin.contains(RegExp(r'\D'))) {
    return 'PIN baru minimal 6 angka.';
  }
  final digits = pin.split('').map(int.parse).toList();
  final steps = {
    for (var i = 1; i < digits.length; i++) digits[i] - digits[i - 1],
  };
  if (steps.every((s) => s == 0) ||
      (steps.length == 1 && (steps.first == 1 || steps.first == -1))) {
    return 'PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang.';
  }
  return null;
}

/// What the AI answered: text, or a graph description (REQ-20).
/// What the server recognized in a circled area (REQ-22).
class FormulaInsight {
  const FormulaInsight({
    required this.kind,
    required this.tidy,
    this.hanzi,
    this.graph,
    this.solution,
    this.videos = const [],
    this.formulas = const [],
  });

  /// The formulas as LaTeX (for the lesson summary, REQ-25).
  final List<String> formulas;

  /// `fungsi`, `persamaan`, `ekspresi`, `kimia` (REQ-24), or `mandarin`
  /// (REQ-30).
  final String kind;

  /// Hanzi read in the area (mandarin only), for "Pinyin & arti".
  final String? hanzi;

  /// School videos matching the formulas (kimia only).
  final List<VideoRef> videos;

  /// Graph data for "Jadikan grafik" (functions only).
  final Map<String, dynamic>? graph;

  /// The formulas typeset, for "Rapikan rumus".
  final TypesetImage tidy;

  /// The solution typeset, for "Selesaikan" (for kimia: the balanced
  /// equation, for "Setarakan"); null when not offered.
  final TypesetImage? solution;
}

/// Where a lesson summary job stands (REQ-25).
class LessonStatus {
  const LessonStatus(this.status, {this.summary, this.code});

  /// antri, mentranskrip, meringkas, selesai, or gagal.
  final String status;
  final String? summary;

  /// Why it failed: tanpa_suara, ai_tidak_tersedia, gagal.
  final String? code;
}

/// A video in the school's catalog (REQ-24).
class VideoRef {
  const VideoRef(this.id, this.title);
  final String id;
  final String title;
}

/// A transparent PNG drawn by the server, with its pixel size.
class TypesetImage {
  const TypesetImage(this.png, this.size);

  factory TypesetImage.fromJson(Map<String, dynamic> json) => TypesetImage(
    base64Decode(json['gambar'] as String),
    Size((json['lebar'] as num).toDouble(), (json['tinggi'] as num).toDouble()),
  );

  final Uint8List png;
  final Size size;

  /// No picture (an area with nothing to typeset).
  static final none = TypesetImage(Uint8List(0), Size.zero);
}

/// One word of a Mandarin reading (REQ-30).
class MandarinWord {
  const MandarinWord({
    required this.hanzi,
    required this.pinyin,
    required this.meaning,
    required this.source,
  });

  final String hanzi;
  final String pinyin;

  /// Indonesian meaning, or the English one when [source] is `inggris`;
  /// empty when the dictionary does not know the word.
  final String meaning;

  /// `kamus`, `inggris`, or `tidak_ada`.
  final String source;
}

/// Pinyin & arti from the school server (REQ-30): pinyin and words from the
/// dictionary, [translation] from the AI (null when the AI failed).
class MandarinReading {
  const MandarinReading({
    required this.hanzi,
    required this.pinyin,
    required this.words,
    this.translation,
  });

  final String hanzi;
  final String pinyin;
  final List<MandarinWord> words;
  final String? translation;
}

class AiAnswer {
  const AiAnswer({
    required this.providerName,
    required this.model,
    this.text,
    this.graph,
    this.quiz = const [],
    this.fallbackFromName,
    this.fallbackReason,
  });

  final String? text;

  /// `{"fungsi": [...], "parameter": [...], "sumbu": {...}}` from the server.
  final Map<String, dynamic>? graph;

  /// Matching pairs for a quiz (jenis `kuis`, REQ-27).
  final List<(String, String)> quiz;
  final String providerName;
  final String model;

  /// The panel's provider that failed, when Ollama cloud answered instead.
  final String? fallbackFromName;

  /// `tidak_aktif` when the panel's choice is no longer enabled.
  final String? fallbackReason;
}
