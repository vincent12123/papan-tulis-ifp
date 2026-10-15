import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/solid/solid_geometry.dart';
import 'package:whiteboard_ifp/solid/solid_painter.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';

/// Bangun ruang on the board (SPEC 1.9 REQ-23).
Future<SolidItem> _placeCube(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.tap(find.text('Bentuk'));
  await tester.pump();
  await tester.tap(find.text('Kubus'));
  await tester.pump();
  return inkOf(tester).items.whereType<SolidItem>().single;
}

SolidItem _solid(WidgetTester tester) =>
    inkOf(tester).items.whereType<SolidItem>().single;

Offset _screen(WidgetTester tester, Offset canvasPoint) {
  final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
  return tester.getTopLeft(find.byType(InkCanvas)) +
      canvas.viewport!.toScreen(canvasPoint);
}

Future<void> _press(WidgetTester tester, SolidButton button) async {
  final rect = SolidLayout(_solid(tester)).buttons[button]!;
  await tester.tapAt(_screen(tester, rect.center));
  await tester.pump();
}

void main() {
  tearDown(Notices.hide);

  testWidgets('AC-110 Bentuk lists the seven solids; Kubus is placed', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Bentuk'));
    await tester.pump();
    for (final kind in SolidKind.values) {
      expect(find.text(kind.label), findsOneWidget);
    }
    await tester.tap(find.text('Kubus'));
    await tester.pump();
    final solid = _solid(tester);
    expect(solid.kind, SolidKind.kubus);
    expect(find.text(BoardScreen.solidPlaced('Kubus')), findsOneWidget);
    expect(find.text('Kubus'), findsNothing, reason: 'menu closed');
  });

  testWidgets('AC-111 a finger turns the solid with the pen; Undo turns back', (
    tester,
  ) async {
    final before = await _placeCube(tester);
    final center = _screen(tester, SolidLayout(before).view.center);
    await drag(tester, center, const Offset(120, -60));
    final after = _solid(tester);
    expect(after.yaw, greaterThan(before.yaw));
    expect(after.pitch, greaterThan(before.pitch));
    expect(inkOf(tester).strokes, isEmpty, reason: 'no ink on the solid');
    inkOf(tester).undo();
    expect(_solid(tester).yaw, before.yaw);
  });

  testWidgets('AC-112 Jaring-jaring opens the net with an animation', (
    tester,
  ) async {
    await _placeCube(tester);
    await _press(tester, SolidButton.net);
    await tester.pump(const Duration(milliseconds: 450));
    final half = inkOf(tester).transformPreview! as SolidItem;
    expect(half.unfold, inExclusiveRange(0, 1), reason: 'opening');
    await tester.pump(const Duration(milliseconds: 600));
    expect(_solid(tester).unfold, 1);
    expect(
      SolidLayout.labelOf(SolidButton.net, _solid(tester)),
      'Tutup jaring',
    );

    await _press(tester, SolidButton.net);
    await tester.pump(const Duration(seconds: 1));
    expect(_solid(tester).unfold, 0, reason: 'closes again');
    inkOf(tester).undo();
    expect(_solid(tester).unfold, 1, reason: 'one undo step per press');
  });

  testWidgets('AC-113 Bidang potong toggles the cut plane', (tester) async {
    await _placeCube(tester);
    await _press(tester, SolidButton.cut);
    expect(_solid(tester).cut, isTrue);
    await _press(tester, SolidButton.cut);
    expect(_solid(tester).cut, isFalse);
  });

  testWidgets('Pilih moves the solid instead of turning it', (tester) async {
    final before = await _placeCube(tester);
    await tester.tap(find.text('Pilih'));
    await tester.pump();
    final center = _screen(tester, SolidLayout(before).view.center);
    await tester.tapAt(center);
    await tester.pump();
    await drag(tester, center, const Offset(100, 0));
    final after = _solid(tester);
    expect(after.rect.left, closeTo(before.rect.left + 100, 1));
    expect(after.yaw, before.yaw);
  });

  testWidgets('Geser and Penghapus leave the solid alone', (tester) async {
    final before = await _placeCube(tester);
    final center = _screen(tester, SolidLayout(before).view.center);
    await tester.tap(find.text('Penghapus'));
    await tester.pump();
    await drag(tester, center, const Offset(80, 0));
    expect(_solid(tester).id, before.id, reason: 'not erased');
    await tester.tap(find.text('Geser'));
    await tester.pump();
    await drag(tester, center, const Offset(80, 0));
    expect(_solid(tester).yaw, closeTo(before.yaw + 0.8, 1e-9));
  });

  test('a sphere has no Jaring-jaring button', () {
    final ball = SolidItem(
      id: 'b',
      kind: SolidKind.bola,
      rect: const Rect.fromLTWH(0, 0, 400, 360),
    );
    expect(SolidLayout(ball).buttons.keys, [SolidButton.cut]);
  });

  test('solids are saved and read back; damaged data is refused', () {
    final solid = SolidItem(
      id: 's',
      kind: SolidKind.limas,
      rect: const Rect.fromLTWH(10, 20, 300, 270),
      yaw: 1.2,
      pitch: -0.3,
      unfold: 1,
      cut: true,
      z: 4,
    );
    final data = ItemCodec.encode(solid);
    final back =
        ItemCodec.decode(kind: ObjectKind.solid, id: 's', z: 4, data: data)!
            as SolidItem;
    expect(back.kind, SolidKind.limas);
    expect(back.rect, solid.rect);
    expect([back.yaw, back.pitch, back.unfold, back.cut], [1.2, -0.3, 1, true]);
    expect(
      () => ItemCodec.decode(
        kind: ObjectKind.solid,
        id: 's',
        z: 0,
        data: '{"v":1,"bentuk":"donat"}',
      ),
      throwsFormatException,
    );
  });
}
