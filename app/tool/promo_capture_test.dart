// Records the real app frame by frame (30 fps, 1920×1080) for the promo
// video in D:/Codingan/OpenMontage/projects/papan-tulis-ifp-promo.
// Not part of the test suite and not in the APK. Run one scene:
//   flutter test tool/promo_capture_test.dart --plain-name grafik \
//     --dart-define=PROMO=build/promo
// then turn build/promo/<scene>/f_%05d.png into MP4 with ffmpeg.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_document.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/canvas/media_images.dart';
import 'package:whiteboard_ifp/graph/graph_painter.dart';
import 'package:whiteboard_ifp/lesson/lesson_session.dart';
import 'package:whiteboard_ifp/lesson/lesson_widgets.dart';
import 'package:whiteboard_ifp/mandarin/mandarin_voice.dart';
import 'package:whiteboard_ifp/peraga/peraga_painter.dart';
import 'package:whiteboard_ifp/peraga/quiz_editor.dart';
import 'package:whiteboard_ifp/peraga/quiz_painter.dart';
import 'package:whiteboard_ifp/solid/solid_painter.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';

import '../test/support/app_harness.dart';
import '../test/support/fake_server.dart';
import '../test/support/media_fakes.dart';
import '../test/support/memory_repository.dart';

const _out = String.fromEnvironment('PROMO', defaultValue: 'build/promo');
const _fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ _fps);

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  for (final family in ['Roboto', 'FlutterTest']) {
    final loader = FontLoader(family)
      ..addFont(read('roboto-regular.ttf'))
      ..addFont(read('roboto-medium.ttf'))
      ..addFont(read('roboto-bold.ttf'));
    await loader.load();
  }
  final cjk = File('C:/Windows/Fonts/msyh.ttc');
  if (cjk.existsSync()) {
    await (FontLoader('Noto Sans CJK SC')
          ..addFont(Future.value(ByteData.sublistView(cjk.readAsBytesSync()))))
        .load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('materialicons-regular.otf'))).load();
}

/// Streams every frame of one scene into ffmpeg (raw RGBA in, H.264 out;
/// encoding a PNG per frame made flutter_tester crash).
///
/// flutter_tester still crashes at random on this machine, so recording is
/// resumable: scenes are deterministic, and after a crash the next run only
/// pumps the frames already recorded (`done.txt`) and records the rest into
/// a new segment. [finish] joins the segments into `$_out/<scene>.mp4`.
class Recorder {
  Recorder._(this.tester, this.scene, this._skip);

  static Future<Recorder> start(WidgetTester tester, String scene) async {
    final dir = Directory('$_out/$scene')..createSync(recursive: true);
    final done = File('${dir.path}/done.txt');
    final skip = done.existsSync() ? int.parse(done.readAsStringSync()) : 0;
    return Recorder._(tester, scene, skip);
  }

  final WidgetTester tester;
  final String scene;
  final int _skip;
  Process? _ffmpeg;
  int frames = 0;

  String get _dir => '$_out/$scene';

  double get seconds => frames / _fps;

  Future<Process> _segment() async {
    final size = tester.binding.renderViews.first.size;
    return (await tester.runAsync(
      () => Process.start('ffmpeg', [
        '-y',
        '-v',
        'error',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgba',
        '-s',
        '${size.width.round()}x${size.height.round()}',
        '-r',
        '$_fps',
        '-i',
        '-',
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-crf',
        '14',
        '-pix_fmt',
        'yuv420p',
        '$_dir/seg_${frames.toString().padLeft(5, '0')}.mp4',
      ]),
    ))!;
  }

  /// Ends the scene and joins its segments into one MP4.
  Future<void> finish() async {
    await tester.runAsync(() async {
      final ffmpeg = _ffmpeg;
      if (ffmpeg != null) {
        await ffmpeg.stdin.close();
        if (await ffmpeg.exitCode != 0) throw StateError('ffmpeg gagal');
      }
      final segments =
          Directory(_dir)
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((name) => name.endsWith('.mp4'))
              .toList()
            ..sort();
      File('$_dir/list.txt')
          .writeAsStringSync(segments.map((name) => "file '$name'\n").join());
      final r = await Process.run('ffmpeg', [
        '-y',
        '-v',
        'error',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        '$_dir/list.txt',
        '-c',
        'copy',
        '$_out/$scene.mp4',
      ]);
      if (r.exitCode != 0) throw StateError('concat: ${r.stderr}');
      File('$_dir/complete').writeAsStringSync('$frames');
    });
  }

  /// Advances the app one frame and records it (frames recorded by an
  /// earlier, crashed run are only pumped).
  Future<void> frame() async {
    await tester.pump(_frame);
    if (frames < _skip) {
      frames++;
      return;
    }
    final ffmpeg = _ffmpeg ??= await _segment();
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = layer.toImageSync(Offset.zero & view.size);
    await tester.runAsync(() async {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      ffmpeg.stdin.add(bytes!.buffer.asUint8List());
      await ffmpeg.stdin.flush();
    });
    image.dispose();
    frames++;
    File('$_dir/done.txt').writeAsStringSync('$frames');
  }

  Future<void> hold(double seconds) async {
    for (var i = 0; i < (seconds * _fps).round(); i++) {
      await frame();
    }
  }

  /// Lets real async work (PNG capture of the area, server answer) finish
  /// while frames keep coming.
  Future<void> settle(double seconds) async {
    for (var i = 0; i < (seconds * _fps).round(); i++) {
      await tester.runAsync(() => Future<void>.delayed(_frame));
      await frame();
    }
  }

  /// Draws one stroke through [points] (screen) at [speed] px/s, a few
  /// pointer moves per frame so the ink is smooth.
  Future<void> stroke(List<Offset> points, {double speed = 900}) async {
    final g = await tester.startGesture(points.first);
    final path = <Offset>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final n = ((b - a).distance / 6).ceil().clamp(1, 1000);
      for (var k = 1; k <= n; k++) {
        path.add(Offset.lerp(a, b, k / n)!);
      }
    }
    var length = 0.0;
    var due = 0.0;
    for (var i = 0; i < path.length; i++) {
      await g.moveTo(path[i]);
      if (i > 0) length += (path[i] - path[i - 1]).distance;
      if (length >= due) {
        due += speed / _fps;
        await frame();
      }
    }
    await g.up();
    await frame();
  }

  /// Writes [text] with the simple handwriting glyphs below, [h] px tall,
  /// starting at [origin] (top-left, screen).
  Future<void> write(String text, Offset origin, double h) async {
    var x = origin.dx;
    for (final ch in text.split('')) {
      if (ch == '₂') {
        // Subscript: a small 2 sitting low.
        for (final s in _glyphs['2']!.strokes) {
          await stroke([
            for (final p in s)
              Offset(x + p.dx * h * 0.5, origin.dy + h * 0.6 + p.dy * h * 0.5),
          ]);
        }
        x += _glyphs['2']!.width * h * 0.5 + h * 0.12;
        continue;
      }
      final glyph = _glyphs[ch];
      if (glyph == null) {
        x += h * 0.45;
        continue;
      }
      for (final s in glyph.strokes) {
        await stroke([
          for (final p in s) Offset(x + p.dx * h, origin.dy + p.dy * h),
        ]);
      }
      x += glyph.width * h + h * 0.18;
    }
  }
}

/// Single-line handwriting glyphs in a box 1 unit tall (y down); points
/// wobble a little so the ink looks written, not typeset.
class _Glyph {
  const _Glyph(this.width, this.strokes);
  final double width;
  final List<List<Offset>> strokes;
}

List<Offset> _arc(
  double cx,
  double cy,
  double rx,
  double ry,
  double from,
  double to, {
  int n = 14,
}) => [
  for (var i = 0; i <= n; i++)
    Offset(
      cx + rx * math.cos((from + (to - from) * i / n) * math.pi / 180),
      cy + ry * math.sin((from + (to - from) * i / n) * math.pi / 180),
    ),
];

final _glyphs = <String, _Glyph>{
  '2': _Glyph(0.48, [
    [
      ..._arc(0.24, 0.3, 0.22, 0.22, 200, 380, n: 10),
      const Offset(0.02, 0.98),
      const Offset(0.5, 0.97),
    ],
  ]),
  '4': const _Glyph(0.5, [
    [Offset(0.34, 0.04), Offset(0.02, 0.68), Offset(0.52, 0.67)],
    [Offset(0.38, 0.3), Offset(0.37, 1.0)],
  ]),
  '7': const _Glyph(0.48, [
    [Offset(0.02, 0.06), Offset(0.48, 0.05), Offset(0.2, 1.0)],
  ]),
  'H': const _Glyph(0.55, [
    [Offset(0.03, 0.04), Offset(0.02, 1.0)],
    [Offset(0.54, 0.03), Offset(0.55, 1.0)],
    [Offset(0.02, 0.52), Offset(0.55, 0.5)],
  ]),
  'O': _Glyph(0.62, [_arc(0.31, 0.52, 0.31, 0.48, 250, 615, n: 24)]),
  '+': const _Glyph(0.5, [
    [Offset(0.0, 0.6), Offset(0.5, 0.59)],
    [Offset(0.25, 0.34), Offset(0.26, 0.86)],
  ]),
  '>': const _Glyph(0.75, [
    [Offset(0.0, 0.6), Offset(0.74, 0.6)],
    [Offset(0.54, 0.42), Offset(0.75, 0.6), Offset(0.54, 0.78)],
  ]),
  'y': const _Glyph(0.55, [
    [Offset(0.02, 0.35), Offset(0.14, 0.58), Offset(0.27, 0.72)],
    [
      Offset(0.55, 0.33),
      Offset(0.42, 0.6),
      Offset(0.27, 0.9),
      Offset(0.12, 1.12),
    ],
  ]),
  'x': const _Glyph(0.5, [
    [Offset(0.02, 0.36), Offset(0.25, 0.62), Offset(0.5, 0.96)],
    [Offset(0.48, 0.34), Offset(0.26, 0.64), Offset(0.03, 0.98)],
  ]),
  '=': const _Glyph(0.55, [
    [Offset(0.0, 0.5), Offset(0.55, 0.49)],
    [Offset(0.02, 0.72), Offset(0.56, 0.7)],
  ]),
  '-': const _Glyph(0.45, [
    [Offset(0.0, 0.62), Offset(0.46, 0.6)],
  ]),
  '²': _Glyph(0.32, [
    [
      ..._arc(0.16, 0.12, 0.13, 0.11, 200, 380, n: 8),
      const Offset(0.02, 0.4),
      const Offset(0.32, 0.39),
    ],
  ]),
  '3': _Glyph(0.48, [
    [
      ..._arc(0.22, 0.27, 0.22, 0.22, 200, 420, n: 10),
      ..._arc(0.22, 0.75, 0.26, 0.26, 280, 520, n: 12),
    ],
  ]),
};

Future<FakeServer> _app(WidgetTester tester) async {
  await tester.runAsync(_loadFonts);
  final server = FakeServer();
  await pumpApp(
    tester,
    repo: MemoryBoardRepository(),
    settingsFor: (_) => MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    ),
    clientFor: server.clientFor,
  );
  return server;
}

Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

void main() {
  _scenes();

  testWidgets('grafik', (tester) async {
    final server = await _app(tester);
    server.graphAnswer = {
      'fungsi': ['y = A*x^2 - 3'],
      'parameter': [
        {'nama': 'A', 'min': -3, 'maks': 3, 'nilai': 1},
      ],
      'sumbu': {'x_min': -5, 'x_maks': 5, 'y_min': -6, 'y_maks': 8},
    };
    final rec = await Recorder.start(tester, 'grafik');
    await rec.hold(0.3);
    await rec.write('y = x² - 3', const Offset(260, 330), 120);
    await rec.hold(0.3);
    await tester.tap(find.text('Pilih'));
    await rec.frame();
    // Circle the formula like a teacher would: one loose loop.
    await rec.stroke(_arc(560, 395, 380, 130, 200, 560, n: 40), speed: 1800);
    await rec.settle(1.4);
    expect(find.text(SmartAreaBar.graph), findsOneWidget);
    await rec.hold(0.4);
    await tester.tap(find.text(SmartAreaBar.graph));
    await rec.settle(1.0);
    final graph = inkOf(tester).items.whereType<GraphItem>().single;
    final layout = GraphLayout(graph);
    final slider = layout.sliders.first;
    final from = _screen(tester, slider.center);
    await rec.hold(0.5);
    await rec.stroke([
      from,
      _screen(tester, slider.centerRight - Offset(slider.width * 0.1, 0)),
      _screen(tester, slider.centerLeft + Offset(slider.width * 0.15, 0)),
      _screen(tester, slider.center + Offset(slider.width * 0.18, 0)),
    ], speed: 500);
    await rec.hold(1.0);
    await rec.finish();
    // ignore: avoid_print
    print('grafik: ${rec.frames} frames, ${rec.seconds.toStringAsFixed(1)} s');
  });
}

// ---------------------------------------------------------------------------
// Scene helpers

final _assets = '$_out/assets';

Map<String, dynamic> _typeset(String key) =>
    (jsonDecode(File('$_assets/typeset.json').readAsStringSync())
            as Map<String, dynamic>)[key]
        as Map<String, dynamic>;

class _FakeVoice implements MandarinVoice {
  @override
  Future<bool> init() async => true;

  @override
  Future<void> speak(String text, {bool slow = false}) async {}
}

class _FakeRecorder implements LessonRecorder {
  String? path;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String p) async => path = p;

  @override
  Future<String?> stop() async {
    final p = path;
    if (p == null) return null;
    File(p).writeAsBytesSync(List.filled(64, 7));
    return p;
  }

  @override
  Future<void> dispose() async {}
}

Future<(FakeServer, MemoryMediaStore)> _board(
  WidgetTester tester, {
  void Function(FakeServer)? setUp,
}) async {
  await tester.runAsync(_loadFonts);
  final server = FakeServer();
  setUp?.call(server);
  final media = MemoryMediaStore();
  final tmp = Directory.systemTemp.createTempSync('promo');
  await pumpApp(
    tester,
    repo: MemoryBoardRepository(),
    settingsFor: (_) => MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    ),
    clientFor: server.clientFor,
    media: media,
    voice: _FakeVoice.new,
    recorder: _FakeRecorder.new,
    lessonPath: () async => '${tmp.path}/rekaman.m4a',
  );
  return (server, media);
}

BoardDocument _doc(WidgetTester tester) =>
    tester.widget<BoardScreen>(find.byType(BoardScreen)).doc;

extension on Recorder {
  Future<void> tap(Finder f) async {
    await tester.tap(f);
    await frame();
  }

  Future<void> tapAt(Offset at) async {
    await tester.tapAt(at);
    await frame();
  }

  /// Several fingers drawing at once (REQ-03): each path advances together.
  Future<void> together(List<List<Offset>> paths, {double seconds = 2}) async {
    final gestures = <TestGesture>[];
    for (var i = 0; i < paths.length; i++) {
      gestures.add(await tester.startGesture(paths[i].first, pointer: 40 + i));
    }
    final steps = (seconds * _fps).round();
    for (var s = 1; s <= steps; s++) {
      for (var i = 0; i < paths.length; i++) {
        final p = paths[i];
        final at = (p.length - 1) * s / steps;
        final k = at.floor().clamp(0, p.length - 2);
        await gestures[i].moveTo(Offset.lerp(p[k], p[k + 1], at - k)!);
      }
      await frame();
    }
    for (final g in gestures) {
      await g.up();
    }
    await frame();
  }

  /// Circles the area (Pilih must be active) with one loose loop.
  Future<void> circle(Rect r) => stroke(
    _arc(r.center.dx, r.center.dy, r.width / 2, r.height / 2, 200, 560, n: 40),
    speed: 1800,
  );

  /// Writes a Hanzi from hanzi-writer stroke medians, [size] px tall.
  Future<void> hanzi(String name, Offset origin, double size) async {
    final data = jsonDecode(
      File('$_assets/hanzi_$name.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final median in data['medians'] as List) {
      await stroke([
        for (final p in median as List)
          Offset(
            origin.dx + (p[0] as num) / 1024 * size,
            origin.dy + (900 - (p[1] as num)) / 1024 * size,
          ),
      ], speed: 1400);
    }
  }

  Future<void> holdUntil(double seconds) async {
    while (this.seconds < seconds) {
      await frame();
    }
  }
}

List<Offset> _wave(Offset from, double width, double amp, double turns) => [
  for (var i = 0; i <= 60; i++)
    Offset(
      from.dx + width * i / 60,
      from.dy + amp * math.sin(i / 60 * turns * 2 * math.pi),
    ),
];

List<Offset> _wobblyLoop(Offset c, double rx, double ry, {int n = 36}) => [
  for (var i = 0; i <= n; i++)
    Offset(
      c.dx +
          rx *
              (1 + 0.06 * math.sin(i * 1.7)) *
              math.cos(i / n * 2 * math.pi - 1.4),
      c.dy +
          ry *
              (1 + 0.05 * math.cos(i * 2.3)) *
              math.sin(i / n * 2 * math.pi - 1.4),
    ),
];

Future<void> _done(Recorder rec) async {
  await rec.finish();
  // ignore: avoid_print
  print(
    '${rec.scene}: ${rec.frames} frames, ${rec.seconds.toStringAsFixed(1)} s',
  );
}

void _scenes() {
  testWidgets('kosong', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'kosong');
    await rec.hold(1.0);
    await _done(rec);
  });

  testWidgets('menulis', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'menulis');
    await rec.hold(0.4);
    // Three students at the board at once.
    await rec.together([
      _wave(const Offset(140, 330), 420, 46, 3),
      _wave(const Offset(720, 470), 420, 60, 2.5),
      _wave(const Offset(1300, 330), 420, 46, 3.5),
    ], seconds: 2.2);
    await rec.together([
      _wobblyLoop(const Offset(350, 600), 110, 80),
      _wobblyLoop(const Offset(930, 700), 90, 90),
      _wobblyLoop(const Offset(1510, 600), 120, 75),
    ], seconds: 1.8);
    await rec.hold(0.8);
    await rec.tap(find.byTooltip('Halaman baru'));
    await rec.hold(0.6);
    await rec.write('y = x²', const Offset(700, 380), 120);
    await rec.hold(0.4);
    await rec.tap(find.byTooltip('Halaman sebelumnya'));
    await rec.holdUntil(10.4);
    await _done(rec);
  });

  testWidgets('bentuk', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'bentuk');
    await rec.hold(0.3);
    await rec.tap(find.text('Bentuk'));
    await rec.hold(0.3);
    await rec.tap(find.text('Otomatis'));
    await rec.stroke(
      _wobblyLoop(const Offset(420, 420), 170, 160),
      speed: 1100,
    );
    await rec.hold(0.4);
    await rec.stroke([
      const Offset(860, 610),
      const Offset(1010, 300),
      const Offset(1170, 612),
      const Offset(858, 606),
    ], speed: 1100);
    await rec.hold(0.4);
    await rec.stroke([
      const Offset(1330, 300),
      const Offset(1700, 302),
      const Offset(1698, 600),
      const Offset(1332, 598),
      const Offset(1330, 304),
    ], speed: 1200);
    await rec.holdUntil(7.2);
    await _done(rec);
  });

  testWidgets('pdf', (tester) async {
    final (_, media) = await _board(tester);
    final rec = await Recorder.start(tester, 'pdf');
    await rec.hold(0.5);
    final bytes = File('$_assets/modul_pdf_page.png').readAsBytesSync();
    final name = (await tester.runAsync(() => media.save(bytes, 'png')))!;
    final doc = _doc(tester);
    doc.setBackground(
      0,
      PageBackground(file: name, rect: const Rect.fromLTWH(560, 20, 560, 792)),
    );
    await rec.settle(0.6);
    await rec.tap(find.text('Pena'));
    // Page (1240×1754 px) sits at canvas (560, 20), 560 wide: underline the
    // title, then circle the worked answer — measured from the page itself.
    Offset page(double x, double y) =>
        _screen(tester, Offset(560 + x * 560 / 1240, 20 + y * 560 / 1240));
    await rec.stroke([page(80, 318), page(640, 314)], speed: 900);
    await rec.stroke(
      _wobblyLoop(page(560, 1322), 300 * 560 / 1240, 40 * 560 / 1240),
      speed: 1200,
    );
    await rec.holdUntil(7.2);
    await _done(rec);
  });

  testWidgets('rapikan', (tester) async {
    final (server, _) = await _board(
      tester,
      setUp: (s) {
        final tidy = _typeset('tidy_x2'), solve = _typeset('solve_x2');
        s
          ..insightKind = 'persamaan'
          ..typesetImage = tidy['gambar'] as String
          ..typesetWidth = tidy['lebar'] as int
          ..typesetHeight = tidy['tinggi'] as int
          ..solutionImage = solve['gambar'] as String
          ..solutionWidth = solve['lebar'] as int
          ..solutionHeight = solve['tinggi'] as int;
      },
    );
    final rec = await Recorder.start(tester, 'rapikan');
    await rec.hold(0.2);
    await rec.write('x² = 4', const Offset(560, 360), 150);
    await rec.tap(find.text('Pilih'));
    await rec.circle(const Rect.fromLTWH(480, 330, 720, 240));
    await rec.settle(1.0);
    await rec.tap(find.text(SmartAreaBar.tidy));
    await rec.settle(0.8);
    await rec.tapAt(const Offset(1700, 860)); // deselect
    await rec.circle(const Rect.fromLTWH(480, 330, 720, 240));
    await rec.settle(1.0);
    await rec.tap(find.text(SmartAreaBar.solve));
    await rec.settle(1.0);
    expect(server.requests, isNotEmpty);
    await rec.holdUntil(7.5);
    await _done(rec);
  });

  testWidgets('kimia', (tester) async {
    await _board(
      tester,
      setUp: (s) {
        final tidy = _typeset('tidy_chem'), bal = _typeset('balanced_chem');
        s
          ..insightKind = 'kimia'
          ..typesetImage = tidy['gambar'] as String
          ..typesetWidth = tidy['lebar'] as int
          ..typesetHeight = tidy['tinggi'] as int
          ..solutionImage = bal['gambar'] as String
          ..solutionWidth = bal['lebar'] as int
          ..solutionHeight = bal['tinggi'] as int
          ..videos = [
            {'id': 'air', 'judul': 'Pembakaran hidrogen menghasilkan air'},
          ];
      },
    );
    final rec = await Recorder.start(tester, 'kimia');
    await rec.hold(0.2);
    await rec.write('H₂ + O₂ > H₂O', const Offset(180, 300), 110);
    await rec.tap(find.text('Pilih'));
    await rec.circle(const Rect.fromLTWH(130, 270, 1060, 200));
    await rec.settle(1.0);
    await rec.hold(0.6);
    await rec.tap(find.text(SmartAreaBar.balance));
    await rec.settle(1.2);
    await rec.holdUntil(7.0);
    await _done(rec);
  });

  testWidgets('tigad', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'tigad');
    await rec.hold(0.2);
    await rec.tap(find.text('Bentuk'));
    await rec.hold(0.3);
    await rec.tap(find.text('Kubus'));
    await rec.settle(0.4);
    final solid = inkOf(tester).items.whereType<SolidItem>().single;
    final c = _screen(tester, SolidLayout(solid).view.center);
    await rec.tap(find.text('Pena'));
    await rec.stroke([
      c,
      c + const Offset(220, 40),
      c + const Offset(60, -30),
    ], speed: 400);
    final layout = SolidLayout(
      inkOf(tester).items.whereType<SolidItem>().single,
    );
    await rec.tapAt(_screen(tester, layout.buttons[SolidButton.net]!.center));
    await rec.hold(1.6);
    await rec.tapAt(_screen(tester, layout.buttons[SolidButton.net]!.center));
    await rec.hold(1.2);
    await rec.tapAt(_screen(tester, layout.buttons[SolidButton.cut]!.center));
    await rec.holdUntil(7.2);
    await _done(rec);
  });

  for (final (scene, label) in [
    ('bandul', 'Bandul'),
    ('parabola', 'Gerak parabola'),
    ('indikator', 'Indikator asam-basa'),
  ]) {
    testWidgets(scene, (tester) async {
      await _board(tester);
      final rec = await Recorder.start(tester, scene);
      await tester.tap(find.text('Peraga'));
      await tester.pump();
      await tester.tap(find.text(label));
      await rec.settle(0.3);
      final item = inkOf(tester).items.whereType<PeragaItem>().single;
      final layout = PeragaLayout(item);
      if (scene == 'indikator') {
        await rec.stroke([
          _screen(tester, layout.knob(0)),
          _screen(tester, layout.track(0).centerLeft),
          _screen(tester, layout.track(0).centerRight),
        ], speed: 260);
      } else {
        await rec.tapAt(_screen(tester, layout.play.center));
      }
      await rec.holdUntil(7.2);
      await _done(rec);
    });
  }

  testWidgets('kuis', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'kuis');
    await tester.tap(find.text('Peraga'));
    await tester.pump();
    await tester.tap(find.text('Kuis'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    const pairs = [
      ('y = x² − 3', 'Parabola terbuka ke atas'),
      ('NaCl', 'Garam dapur'),
      ('T = 2π√(L/g)', 'Periode bandul'),
    ];
    for (var i = 0; i < pairs.length; i++) {
      await tester.enterText(fields.at(1 + 2 * i), pairs[i].$1);
      await tester.enterText(fields.at(2 + 2 * i), pairs[i].$2);
    }
    await tester.tap(find.text(QuizEditor.create));
    await tester.pumpAndSettle();
    final ink = inkOf(tester);
    final quiz = ink.items.whereType<QuizItem>().single;
    final layout = QuizLayout(quiz);
    final state = ink.quizState(quiz);
    await rec.hold(0.6);
    for (final left in [0, 1, 2]) {
      await rec.tapAt(_screen(tester, layout.left[left].center));
      await rec.hold(0.35);
      final wrongRow = state.order.indexWhere((p) => p != left);
      if (left == 1 && wrongRow >= 0) {
        await rec.tapAt(_screen(tester, layout.right[wrongRow].center));
        await rec.hold(0.5);
        await rec.tapAt(_screen(tester, layout.left[left].center));
        await rec.hold(0.3);
      }
      final row = state.order.indexOf(left);
      await rec.tapAt(_screen(tester, layout.right[row].center));
      await rec.hold(0.5);
    }
    await rec.holdUntil(7.5);
    await _done(rec);
  });

  testWidgets('ai', (tester) async {
    await _board(
      tester,
      setUp: (s) => s.textAnswer =
          '1. Kurangi kedua ruas dengan 3: 2x = 4\n'
          '2. Bagi kedua ruas dengan 2: x = 2\n'
          'Jawaban: x = 2',
    );
    final rec = await Recorder.start(tester, 'ai');
    await rec.write('2x + 3 = 7', const Offset(300, 360), 120);
    await rec.tap(find.text('Pilih'));
    await rec.circle(const Rect.fromLTWH(240, 330, 980, 220));
    await rec.settle(0.8);
    await rec.tap(find.text('Asisten AI'));
    await rec.settle(0.8);
    await rec.tap(find.text('Pecah soal').last);
    await rec.settle(1.4);
    await rec.hold(1.2);
    await rec.tap(find.text('Tempel ke papan'));
    await rec.settle(0.6);
    await rec.holdUntil(8.0);
    await _done(rec);
  });

  testWidgets('rekam', (tester) async {
    await _board(
      tester,
      setUp: (s) => s
        ..lessonStatus = 'selesai'
        ..lessonSummary =
            'Ringkasan: Fungsi kuadrat\n'
            '- Bentuk umum y = ax² + bx + c\n'
            '- a > 0: parabola terbuka ke atas\n'
            '- Contoh: y = x² − 3 memotong sumbu y di −3',
    );
    final rec = await Recorder.start(tester, 'rekam');
    await rec.write('y = x² - 3', const Offset(260, 330), 110);
    await rec.tap(find.text(LessonTexts.record));
    await rec.settle(0.6);
    await rec.tap(find.text(LessonTexts.start));
    await rec.settle(2.2);
    await rec.tap(find.textContaining('Merekam'));
    await rec.settle(1.0); // upload; "Ringkasan diproses…" shows
    // The session asks the server every 10 s; skip that wait off-camera.
    await tester.pump(const Duration(seconds: 10));
    for (var i = 0; i < 60; i++) {
      await rec.settle(0.1);
      if (find.text(LessonTexts.ready).evaluate().isNotEmpty) break;
    }
    await rec.hold(0.4);
    await rec.tap(find.text(LessonTexts.ready));
    await rec.settle(0.8);
    await rec.tap(find.text(LessonTexts.paste));
    await rec.settle(1.0);
    await rec.holdUntil(9.0);
    await _done(rec);
  });

  testWidgets('kapur', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'kapur');
    await rec.write('y = x² - 3', const Offset(260, 330), 120);
    await rec.tap(find.byTooltip('Warna'));
    await rec.hold(0.4);
    await rec.tap(find.text('Kapur'));
    await rec.hold(0.2);
    await rec.tap(find.text('Papan hijau kapur'));
    await rec.hold(0.4);
    await rec.tap(find.text('Pena'));
    await rec.write('x² = 3', const Offset(260, 560), 120);
    await rec.holdUntil(6.5);
    await _done(rec);
  });

  testWidgets('tabel', (tester) async {
    await _board(tester);
    final rec = await Recorder.start(tester, 'tabel');
    final ink = inkOf(tester);
    var cells = [
      ['Minggu', 'Kelas A', 'Kelas B'],
      ['1', '72', '68'],
      ['2', '78', '74'],
      ['3', '85', '79'],
      ['4', '88', '86'],
    ];
    final table = TableItem(
      id: ink.newId(),
      rect: const Rect.fromLTWH(140, 230, 600, 320),
      cells: cells,
    );
    ink.addItem(table);
    ink.addItem(
      ChartItem(
        id: ink.newId(),
        rect: const Rect.fromLTWH(800, 150, 960, 640),
        kind: ChartKind.garis,
        tableId: table.id,
        cells: cells,
      ),
    );
    await rec.hold(0.8);
    for (final (r, c, v) in [
      (3, 2, '60'),
      (4, 2, '95'),
      (2, 1, '90'),
      (4, 1, '70'),
      (3, 2, '79'),
      (4, 2, '86'),
    ]) {
      cells = [
        for (final row in cells) [...row],
      ]..[r][c] = v;
      ink.updateTable(table.id, cells);
      await rec.hold(0.7);
    }
    await rec.holdUntil(6.0);
    await _done(rec);
  });

  testWidgets('mandarin', (tester) async {
    await _board(
      tester,
      setUp: (s) => s
        ..insightKind = 'mandarin'
        ..hanzi = '好好学习'
        ..mandarinAnswer = {
          'hanzi': '好好学习',
          'pinyin': 'hǎo hǎo xué xí',
          'kata': [
            {
              'hanzi': '好好',
              'pinyin': 'hǎo hǎo',
              'arti': 'dengan sungguh-sungguh',
              'sumber': 'kamus',
            },
            {
              'hanzi': '学习',
              'pinyin': 'xué xí',
              'arti': 'belajar',
              'sumber': 'kamus',
            },
          ],
          'terjemahan': 'Belajarlah dengan sungguh-sungguh.',
        },
    );
    final rec = await Recorder.start(tester, 'mandarin');
    await rec.settle(0.3);
    var x = 180.0;
    for (final ch in ['hao', 'hao', 'xue', 'xi']) {
      await rec.hanzi(ch, Offset(x, 260), 190);
      x += 200;
    }
    await rec.tap(find.text('Pilih'));
    await rec.circle(const Rect.fromLTWH(130, 230, 930, 260));
    await rec.settle(1.0);
    await rec.tap(find.text(SmartAreaBar.mandarin));
    await rec.settle(1.2);
    await rec.holdUntil(9.0);
    await _done(rec);
  });
}
