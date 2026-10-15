import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/mandarin/mandarin_painter.dart';
import 'package:whiteboard_ifp/mandarin/mandarin_voice.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/memory_repository.dart';

/// Pinyin & arti (REQ-30, AC-190 to AC-194).
class _FakeVoice implements MandarinVoice {
  _FakeVoice(this.ok);
  final bool ok;
  final spoken = <(String, bool)>[];

  @override
  Future<bool> init() async => ok;

  @override
  Future<void> speak(String text, {bool slow = false}) async =>
      spoken.add((text, slow));
}

Future<FakeServer> _pump(
  WidgetTester tester, {
  _FakeVoice? voice,
  MemoryBoardRepository? repo,
  String kind = 'mandarin',
}) async {
  final server = FakeServer()..insightKind = kind;
  await pumpApp(
    tester,
    repo: repo ?? MemoryBoardRepository(),
    settingsFor: (_) => MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    ),
    clientFor: server.clientFor,
    voice: () => voice ?? _FakeVoice(false),
  );
  return server;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

Future<void> _writeAndCircle(WidgetTester tester) async {
  await drag(tester, const Offset(300, 300), const Offset(150, 40));
  await drag(tester, const Offset(300, 360), const Offset(120, 0));
  await tester.tap(find.text('Pilih'));
  await tester.pump();
  await drag(tester, const Offset(260, 260), const Offset(260, 160));
  await _settle(tester);
}

Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

Future<MandarinItem> _makeCard(WidgetTester tester) async {
  await _writeAndCircle(tester);
  await tester.tap(find.text(SmartAreaBar.mandarin));
  await _settle(tester);
  return inkOf(tester).items.whereType<MandarinItem>().single;
}

void main() {
  tearDown(() {
    Notices.hide();
    MandarinVoiceStatus.available.value = false;
  });

  testWidgets('AC-190 Chinese writing offers only Pinyin & arti', (
    tester,
  ) async {
    await _pump(tester);
    await _writeAndCircle(tester);
    expect(find.text(SmartAreaBar.mandarin), findsOneWidget);
    expect(find.text(SmartAreaBar.tidy), findsNothing);
    expect(find.text(SmartAreaBar.graph), findsNothing);
  });

  testWidgets('AC-190 formulas do not offer Pinyin & arti', (tester) async {
    await _pump(tester, kind: 'fungsi');
    await _writeAndCircle(tester);
    expect(find.text(SmartAreaBar.graph), findsOneWidget);
    expect(find.text(SmartAreaBar.mandarin), findsNothing);
  });

  testWidgets(
    'AC-191/193 the card shows the server reading beside the writing',
    (tester) async {
      final server = await _pump(tester);
      final card = await _makeCard(tester);
      final sent = server.requests.lastWhere(
        (r) => r.url.path == '/mandarin/arti',
      );
      expect(jsonDecode(sent.body)['teks'], '学习');
      expect(
        (card.hanzi, card.pinyin, card.translation),
        ('学习', 'xué xí', 'Belajar'),
      );
      expect(card.words.map((w) => (w.hanzi, w.meaning, w.source)), [
        ('学', 'belajar', 'kamus'),
        ('习', 'to practice', 'inggris'),
      ]);
      expect(find.text(BoardScreen.mandarinPlaced), findsOneWidget);
      final ink = inkOf(tester);
      expect(ink.area.value, isNull, reason: 'circle cleared');
      expect(
        ink.items.whereType<Stroke>().every(
          (s) => !s.bounds.overlaps(card.rect),
        ),
        isTrue,
        reason: 'beside the writing, not over it',
      );
      ink.undo();
      await tester.pump();
      expect(ink.items.whereType<MandarinItem>(), isEmpty);
    },
  );

  testWidgets('AC-192 server or AI trouble: message, board unchanged', (
    tester,
  ) async {
    final server = await _pump(tester);
    server.mandarinFailure = (503, 'kamus_tidak_tersedia');
    await _writeAndCircle(tester);
    final before = inkOf(tester).items.length;
    await tester.tap(find.text(SmartAreaBar.mandarin));
    await _settle(tester);
    expect(find.text(BoardScreen.mandarinUnavailable), findsOneWidget);
    expect(inkOf(tester).items.length, before);

    Notices.hide();
    server.mandarinFailure = (422, 'tanpa_hanzi');
    await tester.tap(find.text(SmartAreaBar.mandarin));
    await _settle(tester);
    expect(find.text(BoardScreen.noHanzi), findsOneWidget);

    Notices.hide();
    server
      ..mandarinFailure = null
      ..mandarinAnswer = {...server.mandarinAnswer, 'terjemahan': null};
    await tester.tap(find.text(SmartAreaBar.mandarin));
    await _settle(tester);
    final card = inkOf(tester).items.whereType<MandarinItem>().single;
    expect(card.translation, isNull, reason: 'no made-up translation');
  });

  testWidgets('AC-194 tapping words and buttons speaks; no ink on the card', (
    tester,
  ) async {
    final voice = _FakeVoice(true);
    await _pump(tester, voice: voice);
    await _settle(tester);
    expect(MandarinVoiceStatus.available.value, isTrue);
    final card = await _makeCard(tester);
    await tester.tap(find.text('Pena'));
    await tester.pump();
    final layout = MandarinLayout(card, voice: true);
    final strokes = inkOf(tester).items.whereType<Stroke>().length;
    await tester.tapAt(_screen(tester, layout.words[1].center));
    await tester.tapAt(_screen(tester, layout.slow.center));
    await tester.tapAt(_screen(tester, layout.listen.center));
    await tester.pump();
    expect(voice.spoken, [('习', false), ('学习', true), ('学习', false)]);
    await drag(
      tester,
      _screen(tester, layout.hanzi.center),
      const Offset(60, 10),
    );
    expect(inkOf(tester).items.whereType<Stroke>().length, strokes);
  });

  test('AC-194 without a Mandarin voice there is nothing to tap', () {
    final card = MandarinItem(
      id: 'm',
      rect: const Rect.fromLTWH(0, 0, 700, 600),
      hanzi: '你好',
      pinyin: 'nǐ hǎo',
      words: const [
        (hanzi: '你好', pinyin: 'nǐ hǎo', meaning: 'halo', source: 'kamus'),
      ],
    );
    final layout = MandarinLayout(card, voice: false);
    expect(layout.targetAt(layout.listen.center), isNull);
    expect(layout.targetAt(layout.words.single.center), isNull);
    final voiced = MandarinLayout(card, voice: true);
    expect(voiced.targetAt(voiced.words.single.center)?.text, '你好');
    expect(
      MandarinLayout.heightFor(card, 700) <= 600 + 0.01,
      isTrue,
      reason: 'fits the frame it was given',
    );
  });

  test('AC-193 cards are saved and read back; damage is refused', () {
    final card = MandarinItem(
      id: 'm',
      rect: const Rect.fromLTWH(10, 20, 700, 500),
      hanzi: '好好学习，天天向上',
      pinyin: 'hǎo hǎo xué xí tiān tiān xiàng shàng',
      translation: 'Belajarlah dengan giat.',
      words: const [
        (
          hanzi: '好好',
          pinyin: 'hǎo hǎo',
          meaning: 'dengan baik',
          source: 'kamus',
        ),
        (hanzi: '向上', pinyin: 'xiàng shàng', meaning: 'up', source: 'inggris'),
      ],
    );
    final back =
        ItemCodec.decode(
              kind: ObjectKind.of(card),
              id: 'm',
              z: 2,
              data: ItemCodec.encode(card),
            )!
            as MandarinItem;
    expect(
      (back.hanzi, back.pinyin, back.translation, back.rect),
      (card.hanzi, card.pinyin, card.translation, card.rect),
    );
    expect(back.words, card.words);
    for (final bad in [
      '{"v":1,"x":0,"y":0,"w":1,"h":1,"pinyin":"a","kata":[]}',
      '{"v":1,"x":0,"y":0,"w":1,"h":1,"hanzi":"a","pinyin":"a","kata":[["a"]]}',
      '{"v":1,"x":0,"y":0,"w":1,"h":1,"hanzi":"a","pinyin":"a","kata":[],"terjemahan":3}',
    ]) {
      expect(
        () => ItemCodec.decode(
          kind: ObjectKind.mandarin,
          id: 'x',
          z: 0,
          data: bad,
        ),
        throwsFormatException,
        reason: bad,
      );
    }
  });
}
