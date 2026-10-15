import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/board/smart_suggest.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/peraga/peraga_specs.dart';
import 'package:whiteboard_ifp/peraga/quiz_editor.dart';
import 'package:whiteboard_ifp/peraga/quiz_painter.dart';
import 'package:whiteboard_ifp/server/server_client.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/solid/solid_geometry.dart';
import 'package:whiteboard_ifp/ui/notices.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/memory_repository.dart';

/// Kuis (REQ-27), sketch → solid (REQ-23), menu pintar suggestions
/// (REQ-26, REQ-28), and chalk + board color (REQ-29).
Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

Future<FakeServer> _withServer(
  WidgetTester tester, {
  MemoryBoardRepository? repo,
}) async {
  final server = FakeServer();
  await pumpApp(
    tester,
    repo: repo ?? MemoryBoardRepository(),
    settingsFor: (_) => MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    ),
    clientFor: server.clientFor,
  );
  return server;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

FormulaInsight _insight(String kind, List<String> formulas) => FormulaInsight(
  kind: kind,
  tidy: TypesetImage(Uint8List(0), const Size(1, 1)),
  formulas: formulas,
);

void main() {
  tearDown(Notices.hide);

  group('REQ-26/28 menu pintar suggestions', () {
    test('period formulas suggest the pendulum or the spring', () {
      expect(
        peragaFor(_insight('persamaan', [r'T = 2 \pi \sqrt{\frac{L}{g}}'])),
        [PeragaKind.bandul],
      );
      expect(
        peragaFor(_insight('persamaan', [r'T = 2 \pi \sqrt{\frac{m}{k}}'])),
        [PeragaKind.pegas],
      );
      expect(peragaFor(_insight('fungsi', ['y = x^{2} - 3'])), isEmpty);
    });

    test('reactions suggest the matching lab', () {
      expect(
        labsFor(
          r'\mathrm{Mg} + 2\,\mathrm{H}\mathrm{Cl} \rightarrow '
          r'\mathrm{Mg}\mathrm{Cl}_{2} + \mathrm{H}_{2}',
        ),
        [PeragaKind.logamAsam, PeragaKind.indikator],
      );
      expect(
        labsFor(
          r'\mathrm{C}\mathrm{H}_{4} + 2\,\mathrm{O}_{2} \rightarrow '
          r'\mathrm{C}\mathrm{O}_{2} + 2\,\mathrm{H}_{2}\mathrm{O}',
        ),
        [PeragaKind.pembakaran],
      );
      expect(labsFor(r'\mathrm{Na}\mathrm{Cl}'), isEmpty);
    });
  });

  group('AC-160 Kuis', () {
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.text('Peraga'));
      await tester.pump();
      await tester.tap(find.text('Kuis'));
      await tester.pumpAndSettle();
    }

    testWidgets('teacher writes pairs; students match; wrong shows red', (
      tester,
    ) async {
      await pumpApp(tester);
      await openEditor(tester);
      await tester.tap(find.text(QuizEditor.create));
      await tester.pump();
      expect(find.text(QuizEditor.tooFew), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), 'H2O');
      await tester.enterText(fields.at(2), 'Air');
      await tester.enterText(fields.at(3), 'NaCl');
      await tester.enterText(fields.at(4), 'Garam dapur');
      await tester.tap(find.text(QuizEditor.create));
      await tester.pumpAndSettle();
      expect(find.text(BoardScreen.quizPlaced), findsOneWidget);

      final ink = inkOf(tester);
      final quiz = ink.items.whereType<QuizItem>().single;
      expect(quiz.pairs, [('H2O', 'Air'), ('NaCl', 'Garam dapur')]);
      final layout = QuizLayout(quiz);
      final state = ink.quizState(quiz);
      final rowOfAir = state.order.indexOf(0);
      final rowOfSalt = state.order.indexOf(1);

      await tester.tapAt(_screen(tester, layout.left[0].center));
      await tester.tapAt(_screen(tester, layout.right[rowOfSalt].center));
      await tester.pump();
      expect(state.wrong, (0, rowOfSalt));
      expect(state.matched, isEmpty);

      await tester.tapAt(_screen(tester, layout.left[0].center));
      await tester.tapAt(_screen(tester, layout.right[rowOfAir].center));
      await tester.pump();
      expect(ink.quizState(quiz).matched, {0});
      expect(ink.strokes, isEmpty, reason: 'taps are answers, not ink');

      await tester.tapAt(_screen(tester, layout.shuffle.center));
      await tester.pump();
      expect(ink.quizState(quiz).matched, isEmpty, reason: 'Acak ulang');
    });

    testWidgets('the AI can suggest pairs from the page', (tester) async {
      await _withServer(tester);
      await openEditor(tester);
      await tester.tap(find.text(QuizEditor.suggestButton));
      await _settle(tester);
      expect(find.text('Periode bandul'), findsOneWidget);
      await tester.tap(find.text(QuizEditor.create));
      await tester.pumpAndSettle();
      expect(
        inkOf(tester).items.whereType<QuizItem>().single.pairs,
        hasLength(3),
      );
    });

    test('quizzes are saved and read back; damaged data is refused', () {
      final quiz = QuizItem(
        id: 'q',
        rect: const Rect.fromLTWH(0, 0, 500, 400),
        title: 'Kimia',
        pairs: const [('H2O', 'Air'), ('O2', 'Oksigen')],
      );
      final back =
          ItemCodec.decode(
                kind: ObjectKind.quiz,
                id: 'q',
                z: 0,
                data: ItemCodec.encode(quiz),
              )!
              as QuizItem;
      expect(back.title, 'Kimia');
      expect(back.pairs, quiz.pairs);
      expect(
        () => ItemCodec.decode(
          kind: ObjectKind.quiz,
          id: 'q',
          z: 0,
          data: '{"v":1,"judul":"x","x":0,"y":0,"w":1,"h":1,"pasangan":[]}',
        ),
        throwsFormatException,
      );
    });
  });

  testWidgets('AC-161 a sketched square becomes a cube; Undo brings it back', (
    tester,
  ) async {
    final server = await _withServer(tester);
    server.insightKind = null; // the server sees no formula in a sketch
    // A square drawn in one stroke.
    final g = await tester.startGesture(const Offset(400, 300));
    var from = const Offset(400, 300);
    for (final to in const [
      Offset(600, 300),
      Offset(600, 500),
      Offset(400, 500),
      Offset(400, 302),
    ]) {
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 6)!);
      }
      from = to;
    }
    await g.up();
    await tester.pump();
    final sketch = inkOf(tester).strokes.single;
    await tester.tap(find.text('Pilih'));
    await tester.pump();
    await drag(tester, const Offset(350, 250), const Offset(320, 320));
    await _settle(tester);
    expect(find.text(SmartAreaBar.noFormula), findsNothing);
    await tester.tap(find.text(SmartAreaBar.makeSolid('Kubus')));
    await tester.pump();

    final ink = inkOf(tester);
    final solid = ink.items.whereType<SolidItem>().single;
    expect(solid.kind, SolidKind.kubus);
    expect(ink.strokes, isEmpty);
    expect(solid.rect.center.dx, closeTo(sketch.bounds.center.dx, 1));
    ink.undo();
    expect(ink.strokes.single.id, sketch.id);
    expect(ink.items.whereType<SolidItem>(), isEmpty);
  });

  testWidgets('AC-170 chalk and board color: saved per board, pen follows', (
    tester,
  ) async {
    final repo = MemoryBoardRepository();
    await pumpApp(tester, repo: repo);
    await tester.tap(find.byTooltip('Warna'));
    await tester.pump();
    await tester.tap(find.text('Kapur'));
    await tester.tap(find.text('Papan hijau kapur'));
    await tester.pumpAndSettle();
    final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
    expect(canvas.color, BoardTheme.hijau.color);
    final ink = inkOf(tester);
    expect(ink.color, PenColors.white, reason: 'black would be invisible');
    expect(ink.chalk, isTrue);
    await drag(tester, const Offset(600, 400), const Offset(200, 50));
    final stroke = ink.strokes.single;
    expect(stroke.chalk, isTrue);
    final back = StrokeCodec.decode(
      id: 's',
      z: 0,
      data: ItemCodec.encode(stroke),
    );
    expect(back.chalk, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    final key = repo.state.keys.firstWhere((k) => k.startsWith('tema:'));
    expect(repo.state[key], 'hijau');
  });

  test('strokes saved before chalk existed read as plain ink', () {
    final old = StrokeCodec.decode(
      id: 's',
      z: 0,
      data: '{"v":1,"c":4279308561,"w":6,"p":false,"pts":[1,2,3,4]}',
    );
    expect(old.chalk, isFalse);
  });
}
