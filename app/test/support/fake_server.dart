import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whiteboard_ifp/server/server_client.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';

/// A tiny stand-in for the FastAPI server with the same answers.
class FakeServer {
  FakeServer({this.pin = '482915'});

  String pin;
  bool reachable = true;
  bool locked = false;
  List<Map<String, Object?>> providers = [
    {
      'id': 'ollama',
      'nama': 'Ollama cloud',
      'model_bawaan': 'gpt-oss:120b',
      'model': [
        {'nama': 'gpt-oss:120b', 'dukung_gambar': false},
      ],
    },
    {
      'id': 'claude',
      'nama': 'Claude (Anthropic)',
      'model_bawaan': 'claude-sonnet-5-5',
      'model': [
        {'nama': 'claude-sonnet-5-5', 'dukung_gambar': true},
      ],
    },
  ];

  /// Graph the AI "reads" from the picture (the formulas in the video).
  Map<String, Object?>? graphAnswer = {
    'fungsi': ['y = x^2 - 3', 'y = A*sin(x) + B'],
    'parameter': [
      {'nama': 'A', 'min': -5, 'maks': 5, 'nilai': 1},
      {'nama': 'B', 'min': -5, 'maks': 5, 'nilai': 0},
    ],
    'sumbu': {'x_min': -6.28, 'x_maks': 6.28, 'y_min': -5, 'y_maks': 5},
  };
  String textAnswer = '1. Pindahkan 3 ke ruas kanan.\n2. x = 2';

  /// A 40×10 PNG standing in for the server's typeset formulas.
  static const typesetPng =
      'iVBORw0KGgoAAAANSUhEUgAAACgAAAAKCAYAAADGmhxQAAAAL0lEQVR4nM3OQQEAEADAwFkQfxn0z0UET7sEN+bahzCJkziJkziJkziJkzh/B14uteIBlf+HSU4AAAAASUVORK5CYII=';

  /// Typeset picture returned by /rumus/kenali (base64 PNG and its size).
  String typesetImage = typesetPng;
  int typesetWidth = 40, typesetHeight = 10;

  /// What /rumus/kenali recognizes: `fungsi` (the video's formulas),
  /// `persamaan` (x² = 4), `ekspresi`, or null for nothing (tanpa_rumus).
  String? insightKind = 'fungsi';

  /// Catalog videos /rumus/kenali lists for `kimia`.
  List<Map<String, String>> videos = [
    {'id': 'natrium-klorin', 'judul': 'Reaksi natrium dengan gas klorin'},
  ];

  /// When set, /rumus/kenali answers with this status and code.
  (int, String)? insightFailure;

  /// Ink color the panel sent with the last /rumus/kenali.
  String? lastColor;

  /// Rekam kelas: uploaded recordings and the job's state.
  final List<List<int>> lessonUploads = [];
  String lessonStatus = 'mentranskrip';
  String lessonSummary =
      'Judul: Fungsi kuadrat\n- Grafik y = x^2 - 3 adalah parabola.';
  String lessonCode = 'tanpa_suara';

  /// Pairs the AI suggests for a quiz.
  List<Map<String, String>> quizAnswer = [
    {'kiri': 'y = x^2 - 3', 'kanan': 'Parabola'},
    {'kiri': 'T = 2π√(L/g)', 'kanan': 'Periode bandul'},
    {'kiri': 'H2O', 'kanan': 'Air'},
  ];

  /// When set, /ai/jalankan answers with this status and code.
  (int, String)? aiFailure;

  /// Fallback info returned with every AI answer.
  String? fallbackFromName;

  /// Provider id → failure reason for Tes AI.
  final Map<String, String> aiFailures = {};
  final List<http.Request> requests = [];

  http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (!reachable) throw http.ClientException('tidak terjangkau');
    if (locked) {
      return _json(429, {
        'kode': 'terkunci',
        'pesan': 'PIN salah 5 kali. Coba lagi dalam 5 menit.',
        'sisa_detik': 300,
      });
    }
    if (r.url.path == '/admin/pin') {
      final body = jsonDecode(r.body) as Map;
      if (body['pin_lama'] != pin) {
        return _json(401, {'kode': 'pin_lama_salah', 'pesan': 'x'});
      }
      pin = body['pin_baru'] as String;
      return _json(200, {'status': 'ok'});
    }
    if (r.headers['X-PIN-Admin'] != pin) {
      return _json(401, {'kode': 'pin_salah', 'pesan': 'PIN admin salah.'});
    }
    switch (r.url.path) {
      case '/koneksi':
        return _json(200, {'status': 'ok', 'versi': '0.5.0'});
      case '/ai/penyedia':
        return _json(200, {'bawaan': 'ollama', 'penyedia': providers});
      case '/ai/jalankan':
        final failure = aiFailure;
        if (failure != null) {
          return _json(failure.$1, {'kode': failure.$2, 'pesan': 'x'});
        }
        final kind = (jsonDecode(r.body) as Map)['jenis'];
        if (kind == 'grafik' && graphAnswer == null) {
          return _json(422, {'kode': 'tanpa_rumus', 'pesan': 'x'});
        }
        if (kind == 'kuis') {
          return _json(200, {
            'hasil': null,
            'grafik': null,
            'kuis': quizAnswer,
            'penyedia': 'ollama',
            'nama': 'Ollama cloud',
            'model': 'gpt-oss:120b',
            'durasi_ms': 1500,
            'cadangan_dari': null,
            'cadangan_dari_nama': null,
            'alasan_cadangan': null,
          });
        }
        return _json(200, {
          'hasil': kind == 'grafik' ? null : textAnswer,
          'grafik': kind == 'grafik' ? graphAnswer : null,
          'penyedia': 'ollama',
          'nama': 'Ollama cloud',
          'model': 'model-vision',
          'durasi_ms': 1800,
          'cadangan_dari': fallbackFromName == null ? null : 'claude',
          'cadangan_dari_nama': fallbackFromName,
          'alasan_cadangan': fallbackFromName == null ? null : 'kuota_habis',
        });
      case '/rumus/kenali':
        lastColor = (jsonDecode(r.body) as Map)['warna'] as String?;
        final failure = insightFailure;
        if (failure != null) {
          return _json(failure.$1, {'kode': failure.$2, 'pesan': 'x'});
        }
        final kind = insightKind;
        if (kind == null) {
          return _json(422, {'kode': 'tanpa_rumus', 'pesan': 'x'});
        }
        final picture = {
          'gambar': typesetImage,
          'lebar': typesetWidth,
          'tinggi': typesetHeight,
        };
        return _json(200, {
          'jenis': kind,
          'rumus': ['x^{2} = 4'],
          'grafik': kind == 'fungsi' ? graphAnswer : null,
          'rapi': picture,
          'penyelesaian': kind == 'persamaan' || kind == 'kimia'
              ? {
                  ...picture,
                  'baris': ['x = -2', 'x = 2'],
                }
              : null,
          'video': kind == 'kimia' ? videos : const [],
          'durasi_ms': 900,
        });
      case '/kelas/ringkas':
        lessonUploads.add(r.bodyBytes);
        return _json(200, {'id': 'job-1', 'status': 'antri'});
      case '/kelas/ringkas/job-1':
        return _json(200, {
          'id': 'job-1',
          'status': lessonStatus,
          'ringkasan': lessonStatus == 'selesai' ? lessonSummary : null,
          'kode': lessonStatus == 'gagal' ? lessonCode : null,
        });
      case '/ai/tes':
        final id = (jsonDecode(r.body) as Map)['penyedia'] as String;
        final failure = aiFailures[id];
        if (failure != null) {
          return _json(502, {'kode': 'penyedia_gagal', 'pesan': failure});
        }
        return _json(200, {'durasi_ms': 2400});
    }
    return _json(404, {'kode': 'tidak_ada'});
  }

  ServerClient clientFor(String url, String pin) =>
      ServerClient(baseUrl: url, pin: pin, client: MockClient(handle));
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.value = const ServerSettings()]);

  ServerSettings value;
  int saves = 0;

  @override
  Future<ServerSettings> load() async => value;

  @override
  Future<void> save(ServerSettings settings) async {
    saves++;
    value = settings;
  }
}
