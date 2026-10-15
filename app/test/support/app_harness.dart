import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/app_shell.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';
import 'package:whiteboard_ifp/data/media_store.dart';
import 'package:whiteboard_ifp/lesson/lesson_session.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/settings/settings_screen.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/diagnostics/device_report.dart';
import 'package:whiteboard_ifp/ui/notices.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'memory_repository.dart';

Future<DeviceReport> fakeReport(FlutterView view) async => const DeviceReport(
  manufacturer: 'Hisense',
  model: 'Uji',
  androidVersion: '11',
  sdkInt: 30,
  screenPixels: Size(3840, 2160),
  devicePixelRatio: 2,
  multitouchFeature: '5 titik atau lebih',
  stylusFeature: false,
  hasPlayServices: false,
  hasPlayStore: null,
);

void panelSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Starts the real app shell on an in-memory repository.
Future<MemoryBoardRepository> pumpApp(
  WidgetTester tester, {
  MemoryBoardRepository? repo,
  SettingsStore Function(BoardRepository repo)? settingsFor,
  ClientFactory? clientFor,
  MediaStore? media,
  LessonRecorder Function()? recorder,
  Future<String> Function()? lessonPath,
}) async {
  panelSize(tester);
  final r = repo ?? MemoryBoardRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AppShell(
        repository: Future.value(r),
        clock: () => DateTime.utc(2026, 10, 14, 4, 30),
        settingsFor: settingsFor,
        clientFor: clientFor,
        media: media == null ? null : Future.value(media),
        recorder: recorder,
        lessonPath: lessonPath,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    Notices.hide();
    // Unmount so the open board cancels its timers.
    await tester.pumpWidget(const SizedBox());
  });
  return r;
}

InkController inkOf(WidgetTester tester) =>
    tester.widget<InkCanvas>(find.byType(InkCanvas)).controller;

Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
  final g = await tester.startGesture(from);
  for (var i = 0; i < 5; i++) {
    await g.moveBy(by / 5);
  }
  await g.up();
  await tester.pump();
}

int strokesStored(MemoryBoardRepository repo) => repo.boards.values
    .expand((b) => b.pages)
    .fold(0, (n, p) => n + p.strokes.length);

typedef CanvasViewSnapshot = (double, double);
