import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/ai/ai_dialog.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/media_fakes.dart';
import 'support/memory_repository.dart';

/// Menu pintar (SPEC 1.9 REQ-22, ux-flow 1.5): circling an area recognizes
/// it at once; the bar under it offers only the actions that fit.
Future<(FakeServer, MemoryMediaStore)> _pump(
  WidgetTester tester, {
  bool configured = true,
  void Function(FakeServer)? setUp,
}) async {
  final server = FakeServer();
  setUp?.call(server);
  final media = MemoryMediaStore();
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
    media: media,
  );
  return (server, media);
}

/// Lets real async work (PNG capture, decoding) finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    if (find.text(SmartAreaBar.reading).evaluate().isEmpty) break;
  }
  await tester.pump();
}

/// Writes two strokes (one blue), then circles them with Pilih.
Future<void> _writeAndCircle(WidgetTester tester) async {
  await drag(tester, const Offset(300, 300), const Offset(150, 40));
  await drag(tester, const Offset(300, 360), const Offset(120, 0));
  await tester.tap(find.text('Pilih'));
  await tester.pump();
  await drag(tester, const Offset(260, 260), const Offset(260, 160));
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  tearDown(Notices.hide);

  testWidgets('AC-100 circling starts recognition at once, under the area', (
    tester,
  ) async {
    final (server, _) = await _pump(tester);
    await _writeAndCircle(tester);
    expect(find.text(SmartAreaBar.reading), findsOneWidget);
    final area = inkOf(tester).area.value!;
    expect(
      tester.getRect(find.text(SmartAreaBar.reading)).top,
      greaterThan(area.bottom),
    );
    await _settle(tester);
    expect(server.requests.last.url.path, '/rumus/kenali');
    expect(server.lastColor, '#111827', reason: 'ink color of the writing');
    expect(find.byType(AiDialog), findsNothing);
  });

  testWidgets('AC-101 a function offers Jadikan grafik and Rapikan rumus', (
    tester,
  ) async {
    await _pump(tester);
    await _writeAndCircle(tester);
    await _settle(tester);
    expect(find.text(SmartAreaBar.graph), findsOneWidget);
    expect(find.text(SmartAreaBar.tidy), findsOneWidget);
    expect(find.text(SmartAreaBar.solve), findsNothing);
  });

  testWidgets('AC-101 an equation offers Rapikan rumus and Selesaikan', (
    tester,
  ) async {
    await _pump(tester, setUp: (s) => s.insightKind = 'persamaan');
    await _writeAndCircle(tester);
    await _settle(tester);
    expect(find.text(SmartAreaBar.graph), findsNothing);
    expect(find.text(SmartAreaBar.tidy), findsOneWidget);
    expect(find.text(SmartAreaBar.solve), findsOneWidget);
  });

  testWidgets('AC-83 Jadikan grafik pastes at once and Undo removes it', (
    tester,
  ) async {
    final (server, _) = await _pump(tester);
    await _writeAndCircle(tester);
    await _settle(tester);
    final requests = server.requests.length;
    await _tap(tester, SmartAreaBar.graph);

    expect(server.requests.length, requests, reason: 'no second request');
    final ink = inkOf(tester);
    final graph = ink.items.whereType<GraphItem>().single;
    expect(graph.params.map((p) => p.name), ['A', 'B']);
    expect(ink.selected.value, graph.id);
    expect(ink.area.value, isNull);
    expect(find.text(BoardScreen.graphPasted), findsOneWidget);
    ink.undo();
    expect(ink.items.whereType<GraphItem>(), isEmpty);
  });

  testWidgets(
    'AC-102 Rapikan rumus replaces the handwriting in place; Undo brings it back',
    (tester) async {
      final (_, media) = await _pump(tester);
      await _writeAndCircle(tester);
      await _settle(tester);
      final ink = inkOf(tester);
      final strokes = ink.items.whereType<Stroke>().toList();
      final written = strokes
          .map((s) => s.bounds)
          .reduce((a, b) => a.expandToInclude(b));
      await _tap(tester, SmartAreaBar.tidy);

      expect(ink.items.whereType<Stroke>(), isEmpty);
      final tidy = ink.items.whereType<ImageItem>().single;
      expect(media.files.keys, [tidy.file], reason: 'saved with the board');
      expect(tidy.rect.left, closeTo(written.left, 0.01));
      expect(tidy.rect.width, lessThanOrEqualTo(written.width + 0.01));
      expect(tidy.rect.height, lessThanOrEqualTo(written.height + 0.01));
      expect(tidy.rect.width / tidy.rect.height, closeTo(4, 0.01));
      expect(find.text(BoardScreen.tidyDone), findsOneWidget);

      ink.undo();
      expect(ink.items.whereType<ImageItem>(), isEmpty);
      expect(ink.items.whereType<Stroke>().length, strokes.length);
      ink.redo();
      expect(ink.items.whereType<Stroke>(), isEmpty);
    },
  );

  testWidgets('AC-103 Selesaikan puts the solution beside the equation', (
    tester,
  ) async {
    await _pump(tester, setUp: (s) => s.insightKind = 'persamaan');
    await _writeAndCircle(tester);
    await _settle(tester);
    final area = inkOf(tester).area.value!;
    await _tap(tester, SmartAreaBar.solve);

    final ink = inkOf(tester);
    expect(ink.items.whereType<Stroke>().length, 2, reason: 'writing stays');
    final solution = ink.items.whereType<ImageItem>().single;
    expect(solution.rect.left, greaterThan(area.right));
    expect(find.text(BoardScreen.solveDone), findsOneWidget);
  });

  testWidgets('a new circle replaces the old answer', (tester) async {
    final (server, _) = await _pump(tester);
    await _writeAndCircle(tester);
    await _settle(tester);
    server.insightKind = 'persamaan';
    await drag(tester, const Offset(250, 250), const Offset(280, 170));
    expect(find.text(SmartAreaBar.reading), findsOneWidget);
    await _settle(tester);
    expect(find.text(SmartAreaBar.solve), findsOneWidget);
    expect(find.text(SmartAreaBar.graph), findsNothing);
  });

  group('AC-104 failures leave the board as it was', () {
    Future<void> failWith(
      WidgetTester tester,
      void Function(FakeServer) setUp,
      String message, {
      bool configured = true,
      bool retry = true,
    }) async {
      await _pump(tester, configured: configured, setUp: setUp);
      await _writeAndCircle(tester);
      final ink = inkOf(tester);
      final before = ink.items.length;
      await _settle(tester);
      expect(find.text(message), findsOneWidget);
      expect(
        find.text(SmartAreaBar.retry),
        retry ? findsOneWidget : findsNothing,
      );
      expect(ink.items.length, before);
      expect(ink.area.value, isNotNull);
    }

    testWidgets('nothing recognized', (tester) async {
      await failWith(
        tester,
        (s) => s.insightKind = null,
        SmartAreaBar.noFormula,
        retry: false,
      );
    });

    testWidgets('offline, then Coba lagi works', (tester) async {
      late FakeServer server;
      await failWith(tester, (s) {
        server = s;
        s.reachable = false;
      }, SmartAreaBar.offline);
      server.reachable = true;
      await _tap(tester, SmartAreaBar.retry);
      expect(find.text(SmartAreaBar.graph), findsOneWidget);
    });

    testWidgets('recognizer unavailable', (tester) async {
      await failWith(
        tester,
        (s) => s.insightFailure = (503, 'ai_tidak_tersedia'),
        SmartAreaBar.unavailable,
      );
    });

    testWidgets('Pengaturan not set up', (tester) async {
      await failWith(
        tester,
        (_) {},
        SmartAreaBar.notAllowed,
        configured: false,
      );
    });
  });

  testWidgets('no bar without server settings', (tester) async {
    await pumpApp(tester);
    await _writeAndCircle(tester);
    expect(find.text(SmartAreaBar.reading), findsNothing);
    expect(find.byType(SmartAreaBar), findsNothing);
  });

  testWidgets('clearing the circle hides the bar', (tester) async {
    await _pump(tester);
    await _writeAndCircle(tester);
    await _settle(tester);
    inkOf(tester).clearArea();
    await tester.pump();
    expect(find.text(SmartAreaBar.tidy), findsNothing);
    expect(find.byType(Wrap), findsNothing);
  });
}
