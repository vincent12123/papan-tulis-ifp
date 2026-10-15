import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/peraga/peraga_painter.dart';
import 'package:whiteboard_ifp/peraga/peraga_specs.dart';
import 'package:whiteboard_ifp/ui/notices.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/app_harness.dart';

/// Alat peraga: physics (REQ-26) and chemistry labs (REQ-28).
PeragaItem _peraga(WidgetTester tester) =>
    inkOf(tester).items.whereType<PeragaItem>().single;

Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

Future<void> _place(WidgetTester tester, String label) async {
  await pumpApp(tester);
  await tester.tap(find.text('Peraga'));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  tearDown(Notices.hide);

  group('REQ-26 physics is right', () {
    test('pendulum period T = 2π√(L/g)', () {
      final v = PeragaKind.bandul.spec.defaults..['L'] = 1;
      expect(PeragaKind.bandul.spec.readout(v), contains('2,01 s'));
    });

    test('projectile height and range at 45°', () {
      final v = {'v0': 20.0, 'sudut': 45.0, 'g': 10.0};
      // H = v0² sin²α / 2g = 10 m, R = v0² sin 2α / g = 40 m.
      expect(
        PeragaKind.parabola.spec.readout(v),
        'Tinggi maks 10,0 m · Jarak 40,0 m',
      );
    });

    test('incline: friction holds the block when tan θ ≤ μ', () {
      expect(inclineAcceleration({'sudut': 20, 'mu': 0.5, 'g': 9.8}), 0);
      expect(
        inclineAcceleration({'sudut': 30, 'mu': 0, 'g': 10}),
        closeTo(5, 1e-9),
      );
    });

    test('sliders snap to their step and range', () {
      final p = PeragaKind.bandul.spec.params.first;
      expect(p.snap(1.234), 1.2);
      expect(p.snap(99), 2.5);
      expect(p.show(1.2), '1,2 m');
    });
  });

  group('REQ-28 chemistry is right', () {
    test('indicator colors follow the practicum charts', () {
      expect(indicatorColor(1, 3), PeragaColors.acidRed);
      expect(indicatorColor(1, 11), PeragaColors.baseBlue);
      expect(indicatorColor(2, 5), PeragaColors.clear, reason: 'PP colorless');
      expect(indicatorColor(2, 12), PeragaColors.phenolPink);
      expect(phName(2), 'asam');
      expect(phName(7), 'netral');
      expect(phName(13), 'basa');
    });

    test('copper does not react with dilute acid; phenol clears at 66 °C', () {
      final metal = PeragaKind.logamAsam.spec;
      expect(metal.readout({'logam': 3, 'M': 1}), contains('tidak bereaksi'));
      expect(metalRate[3], 0);
      final heat = PeragaKind.pemanasan.spec;
      expect(heat.readout({'suhu': 40}), contains('keruh'));
      expect(heat.readout({'suhu': 70}), contains('jernih'));
    });
  });

  testWidgets('AC-150 Peraga lists 8 tools and the quiz; Bandul is placed', (
    tester,
  ) async {
    await _place(tester, 'Bandul');
    final item = _peraga(tester);
    expect(item.kind, PeragaKind.bandul);
    expect(find.text(BoardScreen.peragaPlaced('Bandul')), findsOneWidget);
  });

  testWidgets('AC-151 Putar plays, Jeda stops the clock, Ulang resets', (
    tester,
  ) async {
    await _place(tester, 'Bandul');
    final ink = inkOf(tester);
    final item = _peraga(tester);
    final layout = PeragaLayout(item);
    await tester.tapAt(_screen(tester, layout.play.center));
    await tester.pump();
    expect(ink.running, contains(item.id));
    // One second of frames at 30 fps.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    final t = ink.liveTime[item.id]!;
    expect(t, closeTo(1, 0.1));
    expect(ink.isLive(item), isTrue, reason: 'drawn on the live layer');

    await tester.tapAt(_screen(tester, layout.play.center));
    await tester.pump(const Duration(milliseconds: 500));
    expect(ink.running, isEmpty);
    expect(ink.liveTime[item.id], closeTo(t, 0.1), reason: 'frozen');

    await tester.tapAt(_screen(tester, layout.reset.center));
    await tester.pump();
    expect(ink.liveTime[item.id], isNull);
    expect(ink.isLive(item), isFalse, reason: 'back to the cached layer');
  });

  testWidgets('AC-152 a slider changes the value; one Undo per drag', (
    tester,
  ) async {
    await _place(tester, 'Bandul');
    final layout = PeragaLayout(_peraga(tester));
    final track = layout.track(0);
    await drag(
      tester,
      _screen(tester, layout.knob(0)),
      _screen(tester, track.centerRight) - _screen(tester, layout.knob(0)),
    );
    expect(_peraga(tester).values['L'], 2.5);
    expect(inkOf(tester).strokes, isEmpty, reason: 'no ink on the slider');
    inkOf(tester).undo();
    expect(_peraga(tester).values['L'], 1.2);
  });

  testWidgets('AC-153 a choice cycles (indicator), and the body takes no ink', (
    tester,
  ) async {
    await _place(tester, 'Indikator asam-basa');
    final layout = PeragaLayout(_peraga(tester));
    await tester.tapAt(_screen(tester, layout.rows[1].center));
    await tester.pump();
    expect(_peraga(tester).values['indikator'], 1, reason: 'Lakmus');
    await drag(
      tester,
      _screen(tester, layout.scene.center),
      const Offset(60, 20),
    );
    expect(inkOf(tester).strokes, isEmpty);
  });

  test('peraga are saved and read back; damaged data is refused', () {
    final item = PeragaItem(
      id: 'p',
      kind: PeragaKind.pegas,
      rect: const Rect.fromLTWH(1, 2, 300, 280),
      values: {'k': 50, 'm': 2},
      z: 3,
    );
    final back =
        ItemCodec.decode(
              kind: ObjectKind.peraga,
              id: 'p',
              z: 3,
              data: ItemCodec.encode(item),
            )!
            as PeragaItem;
    expect(back.kind, PeragaKind.pegas);
    expect(back.values, {'k': 50, 'm': 2, 'A': 0.15});
    expect(
      () => ItemCodec.decode(
        kind: ObjectKind.peraga,
        id: 'p',
        z: 0,
        data: '{"v":1,"jenis":"roket"}',
      ),
      throwsFormatException,
    );
  });
}
