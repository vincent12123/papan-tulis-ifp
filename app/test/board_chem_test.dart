import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/board/smart_menu.dart';
import 'package:whiteboard_ifp/board/video_dialog.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/server/server_client.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/media_fakes.dart';
import 'support/memory_repository.dart';

/// Kimia + video eksperimen (SPEC 1.9 REQ-24).
Future<FakeServer> _pump(WidgetTester tester) async {
  final server = FakeServer()..insightKind = 'kimia';
  await pumpApp(
    tester,
    repo: MemoryBoardRepository(),
    settingsFor: (_) => MemorySettingsStore(
      const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
    ),
    clientFor: server.clientFor,
    media: MemoryMediaStore(),
  );
  await drag(tester, const Offset(300, 300), const Offset(150, 40));
  await tester.tap(find.text('Pilih'));
  await tester.pump();
  await drag(tester, const Offset(260, 260), const Offset(260, 120));
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
  return server;
}

void main() {
  tearDown(Notices.hide);

  testWidgets('AC-120 a reaction offers Rapikan, Setarakan, and videos', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(SmartAreaBar.tidy), findsOneWidget);
    expect(find.text(SmartAreaBar.balance), findsOneWidget);
    expect(find.text(SmartAreaBar.solve), findsNothing);
    expect(find.text(SmartAreaBar.graph), findsNothing);
    expect(find.text(SmartAreaBar.videos(1)), findsOneWidget);
  });

  testWidgets('AC-120 Setarakan puts the balanced equation beside', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text(SmartAreaBar.balance));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    expect(inkOf(tester).items.whereType<ImageItem>(), hasLength(1));
    expect(inkOf(tester).items.whereType<Stroke>(), hasLength(1));
    expect(find.text(BoardScreen.balanceDone), findsOneWidget);
  });

  testWidgets('AC-121 Video eksperimen lists the school videos', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text(SmartAreaBar.videos(1)));
    await tester.pumpAndSettle();
    expect(find.text(VideoDialog.title), findsOneWidget);
    expect(find.text('Reaksi natrium dengan gas klorin'), findsOneWidget);
    await tester.tap(find.byTooltip(VideoDialog.close));
    await tester.pumpAndSettle();
    expect(find.byType(VideoDialog), findsNothing);
  });

  testWidgets('no video button when the catalog has nothing for it', (
    tester,
  ) async {
    final server = FakeServer()..insightKind = 'kimia';
    server.videos = [];
    await pumpApp(
      tester,
      settingsFor: (_) => MemorySettingsStore(
        const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
      ),
      clientFor: server.clientFor,
    );
    await drag(tester, const Offset(300, 300), const Offset(150, 40));
    await tester.tap(find.text('Pilih'));
    await tester.pump();
    await drag(tester, const Offset(260, 260), const Offset(260, 120));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    expect(find.text(SmartAreaBar.balance), findsOneWidget);
    expect(find.textContaining('Video eksperimen'), findsNothing);
  });

  group('VideoDialog', () {
    const video = VideoRef('v1', 'Elektrolisis air');

    testWidgets('plays the chosen video from the school server', (
      tester,
    ) async {
      VideoAddress? played;
      await tester.pumpWidget(
        MaterialApp(
          home: VideoDialog(
            videos: const [video],
            source: (id) async => (
              uri: Uri.parse('https://papan.contoh/video/$id'),
              headers: const {'X-PIN-Admin': '482915'},
            ),
            player: (address) {
              played = address;
              return const Text('pemutar');
            },
          ),
        ),
      );
      await tester.tap(find.text('Elektrolisis air'));
      await tester.pumpAndSettle();
      expect(find.text('pemutar'), findsOneWidget);
      expect(played!.uri.path, '/video/v1');
      expect(played!.headers['X-PIN-Admin'], '482915');
      await tester.tap(find.text(VideoDialog.back));
      await tester.pumpAndSettle();
      expect(find.text('Elektrolisis air'), findsOneWidget);
    });

    testWidgets('a server failure says what to do', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VideoDialog(
            videos: const [video],
            source: (_) async => throw const ServerUnreachable(),
          ),
        ),
      );
      await tester.tap(find.text('Elektrolisis air'));
      await tester.pumpAndSettle();
      expect(find.text(VideoDialog.failed), findsOneWidget);
    });
  });
}
