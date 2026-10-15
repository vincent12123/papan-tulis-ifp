import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/ai/ai_dialog.dart';
import 'package:whiteboard_ifp/ai/graph_builder.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/graph/graph_painter.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/memory_repository.dart';

/// The app with Pengaturan already set up and a fake school server.
Future<FakeServer> _pumpWithAi(
  WidgetTester tester, {
  bool configured = true,
}) async {
  final server = FakeServer();
  final settings = MemorySettingsStore(
    configured
        ? const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915')
        : const ServerSettings(),
  );
  await pumpApp(
    tester,
    repo: MemoryBoardRepository(),
    settingsFor: (_) => settings,
    clientFor: server.clientFor,
  );
  return server;
}

/// Writes something, then circles it with Pilih.
Future<void> _writeAndCircle(WidgetTester tester) async {
  await drag(tester, const Offset(300, 300), const Offset(150, 40));
  await tester.tap(find.text('Pilih'));
  await tester.pump();
  await drag(tester, const Offset(260, 260), const Offset(260, 120));
  // The menu pintar recognizes the circle at once; let it finish so its
  // spinner does not keep pumpAndSettle busy.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    if (find.text(SmartAreaBar.reading).evaluate().isEmpty) break;
  }
}

/// Taps an AI action and lets the real async work (PNG capture) finish.
Future<void> _runAction(WidgetTester tester, String label) async {
  // .last: the dialog's button, above the bar under the area.
  await tester.tap(find.text(label).last);
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.text('Tempel ke papan').evaluate().isNotEmpty ||
        find.textContaining('Coba lagi').evaluate().isNotEmpty ||
        find.textContaining('Lingkari').evaluate().isNotEmpty) {
      break;
    }
  }
}

void main() {
  tearDown(Notices.hide);

  testWidgets('Pilih on empty canvas circles an area with a quick AI button', (
    tester,
  ) async {
    await _pumpWithAi(tester);
    await _writeAndCircle(tester);
    final ink = inkOf(tester);
    expect(ink.area.value, isNotNull);
    expect(ink.area.value!.width, greaterThan(100));
    // Asisten AI stays in the top bar; the area gets the menu pintar.
    expect(find.text('Asisten AI'), findsOneWidget);
  });

  testWidgets(
    'AC-83 Jadikan grafik: preview, then paste a graph next to the area',
    (tester) async {
      final server = await _pumpWithAi(tester);
      await _writeAndCircle(tester);
      await tester.tap(find.text('Asisten AI'));
      await tester.pumpAndSettle();
      expect(find.text(AiDialog.privacy), findsOneWidget);

      await _runAction(tester, 'Jadikan grafik');
      expect(find.text('Memakai: Ollama cloud · model-vision'), findsOneWidget);
      expect(find.text(AiDialog.reminder), findsOneWidget);
      final sent = server.requests.lastWhere(
        (r) => r.url.path == '/ai/jalankan',
      );
      expect(sent.url.path, '/ai/jalankan');
      expect(sent.body, contains('"jenis":"grafik"'));
      expect(sent.body, contains('"gambar":"iVBOR'), reason: 'a PNG is sent');

      await tester.tap(find.text('Tempel ke papan'));
      await tester.pumpAndSettle();
      final ink = inkOf(tester);
      final graph = ink.items.whereType<GraphItem>().single;
      expect(graph.functions.length, 2);
      expect(graph.params.map((p) => p.name), ['A', 'B']);
      expect(ink.selected.value, graph.id, reason: 'ready to move with Pilih');
      expect(ink.area.value, isNull);
      expect(find.text(BoardScreen.pastedText), findsOneWidget);
    },
  );

  testWidgets(
    'AC-84 right after pasting (Pilih, graph selected) slider A can be dragged',
    (tester) async {
      await _pumpWithAi(tester);
      await _writeAndCircle(tester);
      await tester.tap(find.text('Asisten AI'));
      await tester.pumpAndSettle();
      await _runAction(tester, 'Jadikan grafik');
      await tester.tap(find.text('Tempel ke papan'));
      await tester.pumpAndSettle();

      final ink = inkOf(tester);
      final graph = ink.items.whereType<GraphItem>().single;
      final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
      final origin = tester.getTopLeft(find.byType(InkCanvas));
      Offset screen(Offset p) => origin + canvas.viewport!.toScreen(p);
      final layout = GraphLayout(graph);
      final g = await tester.startGesture(screen(layout.knob(0)));
      await tester.pump(const Duration(milliseconds: 80));
      await g.moveTo(screen(layout.sliders.first.centerRight));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      final moved = ink.items.whereType<GraphItem>().single;
      expect(moved.values['A'], moved.params.first.max);
      expect(moved.rect, graph.rect, reason: 'the graph itself did not move');
    },
  );

  testWidgets('text actions paste a text object', (tester) async {
    await _pumpWithAi(tester);
    await _writeAndCircle(tester);
    await tester.tap(find.text('Asisten AI'));
    await tester.pumpAndSettle();
    await _runAction(tester, 'Pecah soal');
    expect(find.textContaining('Pindahkan 3 ke ruas kanan'), findsOneWidget);
    await tester.tap(find.text('Tempel ke papan'));
    await tester.pumpAndSettle();
    final text = inkOf(tester).items.whereType<TextItem>().single;
    expect(text.text, contains('x = 2'));
  });

  testWidgets('Buang leaves the board unchanged', (tester) async {
    await _pumpWithAi(tester);
    await _writeAndCircle(tester);
    final before = inkOf(tester).items.length;
    await tester.tap(find.text('Asisten AI'));
    await tester.pumpAndSettle();
    await _runAction(tester, 'Jadikan grafik');
    await tester.tap(find.text('Buang'));
    await tester.pump();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(inkOf(tester).items.length, before);
  });

  testWidgets(
    'AC-73 without an area, Pecah soal and Jadikan grafik ask to circle',
    (tester) async {
      final server = await _pumpWithAi(tester);
      await tester.tap(find.text('Asisten AI'));
      await tester.pumpAndSettle();
      await _runAction(tester, 'Pecah soal');
      expect(find.text(AiDialog.noAreaSoal), findsOneWidget);
      await _runAction(tester, 'Jadikan grafik');
      expect(find.text(AiDialog.noAreaGrafik), findsOneWidget);
      expect(server.requests, isEmpty, reason: 'nothing sent to the AI');
    },
  );

  testWidgets('AC-72 Ringkas papan without an area uses the whole page', (
    tester,
  ) async {
    final server = await _pumpWithAi(tester);
    await drag(tester, const Offset(300, 300), const Offset(150, 40));
    await tester.tap(find.text('Asisten AI'));
    await tester.pumpAndSettle();
    await _runAction(tester, 'Ringkas papan');
    expect(
      server.requests.where((r) => r.url.path == '/ai/jalankan').single.body,
      contains('"jenis":"ringkas"'),
    );
    expect(find.text('Tempel ke papan'), findsOneWidget);
  });

  group('SCR-05 failures keep the board unchanged', () {
    Future<void> failWith(
      WidgetTester tester,
      void Function(FakeServer) setUp,
      String message, {
      bool configured = true,
    }) async {
      final server = await _pumpWithAi(tester, configured: configured);
      setUp(server);
      await _writeAndCircle(tester);
      final before = inkOf(tester).items.length;
      await tester.tap(find.text('Asisten AI'));
      await tester.pumpAndSettle();
      await _runAction(tester, 'Jadikan grafik');
      expect(find.text(message), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AiDialog),
          matching: find.text('Coba lagi'),
        ),
        findsOneWidget,
      );
      expect(inkOf(tester).items.length, before);
    }

    testWidgets('offline', (tester) async {
      await failWith(tester, (s) => s.reachable = false, AiDialog.offline);
    });

    testWidgets('AC-79 both providers failed', (tester) async {
      await failWith(
        tester,
        (s) => s.aiFailure = (503, 'ai_tidak_tersedia'),
        AiDialog.unavailable,
      );
    });

    testWidgets('AC-85 no formula found', (tester) async {
      await failWith(tester, (s) => s.graphAnswer = null, AiDialog.noFormula);
    });

    testWidgets('only unparsable formulas count as none found', (tester) async {
      await failWith(
        tester,
        (s) => s.graphAnswer = {
          'fungsi': ['import os', 'eval(x)'],
        },
        AiDialog.noFormula,
      );
    });

    testWidgets('Pengaturan not set up', (tester) async {
      await failWith(tester, (_) {}, AiDialog.notAllowed, configured: false);
    });
  });

  testWidgets('fallback answers say so', (tester) async {
    final server = await _pumpWithAi(tester);
    server.fallbackFromName = 'Claude (Anthropic)';
    await _writeAndCircle(tester);
    await tester.tap(find.text('Asisten AI'));
    await tester.pumpAndSettle();
    await _runAction(tester, 'Jadikan grafik');
    expect(find.text(AiDialog.fellBack('Claude (Anthropic)')), findsOneWidget);
  });

  test('placeResult goes right of the area, else left, else center', () {
    const visible = Rect.fromLTWH(0, 0, 1000, 600);
    const size = Size(300, 200);
    expect(
      placeResult(size, visible, const Rect.fromLTWH(50, 50, 100, 100)).left,
      174,
    );
    expect(
      placeResult(size, visible, const Rect.fromLTWH(800, 50, 100, 100)).right,
      776,
    );
    expect(placeResult(size, visible, null).center, visible.center);
  });

  test('buildGraph adds sliders for letters the AI forgot', () {
    final g = buildGraph(
      {
        'fungsi': ['y = k*x + c'],
        'parameter': [
          {'nama': 'k', 'min': -2, 'maks': 2, 'nilai': 9},
        ],
      },
      const Rect.fromLTWH(0, 0, 10, 10),
      'g',
    )!;
    expect(g.params.map((p) => p.name), ['k', 'c']);
    expect(g.params.first.value, 2, reason: 'clamped into its range');
    expect([g.xMin, g.xMax], [-10, 10], reason: 'default axes');
  });

  testWidgets('no AI button when the app has no server settings at all', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Asisten AI'), findsNothing);
    expect(find.byType(InkCanvas), findsOneWidget);
  });
}
