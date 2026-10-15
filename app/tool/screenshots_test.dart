// Screenshots of the real screens at panel size, for UI review (AGENTS §4A).
// Not part of the test suite. Run:
//   flutter test tool/screenshots_test.dart --dart-define=SHOTS=<folder>
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/peraga/peraga_specs.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/solid/solid_geometry.dart';

import '../test/support/app_harness.dart';
import '../test/support/fake_server.dart';
import '../test/support/media_fakes.dart';
import '../test/support/memory_repository.dart';

const _out = String.fromEnvironment('SHOTS', defaultValue: 'build/shots');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? r'D:\dev\flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(read('roboto-regular.ttf'))
    ..addFont(read('roboto-medium.ttf'))
    ..addFont(read('roboto-bold.ttf'));
  await roboto.load();
  // Styles without a family use the test default font; on the panel that is
  // the system Roboto, so show Roboto here too.
  final fallback = FontLoader('FlutterTest')
    ..addFont(read('roboto-regular.ttf'))
    ..addFont(read('roboto-medium.ttf'))
    ..addFont(read('roboto-bold.ttf'));
  await fallback.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('materialicons-regular.otf'));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('board screens', (tester) async {
    await tester.runAsync(_loadFonts);
    final server = FakeServer();
    // A real typeset picture from the server, when given.
    const tidy = String.fromEnvironment('TIDY');
    if (tidy.isNotEmpty) {
      server
        ..typesetImage = base64Encode(File(tidy).readAsBytesSync())
        ..typesetWidth = 553
        ..typesetHeight = 238;
    }
    final settings = MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    );
    await pumpApp(
      tester,
      repo: MemoryBoardRepository(),
      settingsFor: (_) => settings,
      clientFor: server.clientFor,
      media: MemoryMediaStore(),
    );
    await _shot(tester, '1-papan-kosong');

    await drag(tester, const Offset(300, 300), const Offset(150, 40));
    await drag(tester, const Offset(300, 380), const Offset(200, -10));
    await tester.tap(find.text('Pilih'));
    await tester.pump();
    await drag(tester, const Offset(260, 260), const Offset(300, 180));
    await _shot(tester, '2-mengenali');
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, '3-menu-pintar-fungsi');
    await tester.tap(find.text('Rapikan rumus'));
    await _settle(tester);
    await _shot(tester, '4-rumus-dirapikan');
  });

  testWidgets('solids', (tester) async {
    await tester.runAsync(_loadFonts);
    await pumpApp(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    await _shot(tester, '5-menu-bangun-ruang');
    await tester.tap(find.text('Kubus'));
    await tester.pump();
    final ink = inkOf(tester);
    final cube = ink.items.whereType<SolidItem>().single;
    ink.beginLift(cube.id);
    ink.updateLifted((s) => (s as SolidItem).withCut(true));
    ink.endTransform();
    final visible = cube.rect;
    for (final (kind, dx, unfold) in [
      (SolidKind.balok, -1.15, 1.0),
      (SolidKind.limas, 1.15, 0.0),
      (SolidKind.kerucut, 2.3, 0.6),
    ]) {
      ink.addItem(
        SolidItem(
          id: ink.newId(),
          kind: kind,
          rect: visible.shift(Offset(visible.width * dx, 0)),
          unfold: unfold,
          pitch: unfold > 0 ? 1.0 : SolidItem.defaultPitch,
        ),
      );
    }
    await tester.pump(const Duration(seconds: 5));
    await _shot(tester, '6-bangun-ruang');
  });

  testWidgets('peraga', (tester) async {
    await tester.runAsync(_loadFonts);
    await pumpApp(tester);
    await tester.tap(find.text('Peraga'));
    await tester.pump();
    await _shot(tester, '7-menu-peraga');
    await tester.tap(find.text('Peraga'));
    await tester.pump();
    final ink = inkOf(tester);
    const w = 600.0, h = 470.0;
    final placed = <PeragaItem>[];
    for (final (kind, col, row) in [
      (PeragaKind.bandul, 0, 0),
      (PeragaKind.parabola, 1, 0),
      (PeragaKind.bidangMiring, 2, 0),
      (PeragaKind.indikator, 0, 1),
      (PeragaKind.logamAsam, 1, 1),
      (PeragaKind.pembakaran, 2, 1),
    ]) {
      final item = PeragaItem(
        id: ink.newId(),
        kind: kind,
        rect: Rect.fromLTWH(20 + col * (w + 20), 70 + row * (h + 10), w, h),
      );
      ink.addItem(item);
      placed.add(item);
    }
    for (final p in placed) {
      ink.togglePeraga(p.id);
    }
    ink.advance(0.7);
    await tester.pump();
    await _shot(tester, '8-peraga-berjalan');
    for (final p in placed) {
      ink.togglePeraga(p.id);
    }
  });

  testWidgets('kuis dan kapur', (tester) async {
    await tester.runAsync(_loadFonts);
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Warna'));
    await tester.pump();
    await tester.tap(find.text('Kapur'));
    await tester.tap(find.text('Papan hijau kapur'));
    await tester.pumpAndSettle();
    await drag(tester, const Offset(150, 200), const Offset(300, 60));
    await drag(tester, const Offset(150, 280), const Offset(260, -20));
    final ink = inkOf(tester);
    final quiz = QuizItem(
      id: ink.newId(),
      rect: const Rect.fromLTWH(700, 120, 640, 520),
      title: 'Pasangkan dengan benar',
      pairs: const [
        ('y = x² − 3', 'Parabola terbuka ke atas'),
        ('T = 2π√(L/g)', 'Periode bandul'),
        ('H₂O', 'Air'),
        ('NaCl', 'Garam dapur'),
      ],
    );
    ink.addItem(quiz);
    final s = ink.quizState(quiz);
    s.matched.add(0);
    s.selectedLeft = 2;
    await tester.pump();
    await _shot(tester, '9-kuis-kapur');
  });
}
