import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/board/board_screen.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/lesson/lesson_session.dart';
import 'package:whiteboard_ifp/lesson/lesson_widgets.dart';
import 'package:whiteboard_ifp/server/server_client.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/ui/notices.dart';

import 'support/app_harness.dart';
import 'support/fake_server.dart';
import 'support/memory_repository.dart';

/// Writes a small file where the panel would record.
class FakeRecorder implements LessonRecorder {
  FakeRecorder({this.allowed = true, this.broken = false});
  bool allowed, broken;
  String? path;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<void> start(String p) async {
    if (broken) throw Exception('tidak ada mikrofon');
    path = p;
  }

  @override
  Future<String?> stop() async {
    final p = path;
    if (p == null) return null;
    File(p).writeAsBytesSync(List.filled(64, 7));
    return p;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeApi implements LessonApi {
  final uploads = <(List<int>, List<String>)>[];
  ServerFailure? uploadFailure;
  LessonStatus next = const LessonStatus('mentranskrip');

  @override
  Future<String> upload(audio, formulas) async {
    final f = uploadFailure;
    if (f != null) throw f;
    uploads.add((audio, formulas));
    return 'job';
  }

  @override
  Future<LessonStatus> status(String id) async => next;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pelajaran'));
  tearDown(() {
    Notices.hide();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  LessonSession session(FakeApi api, FakeRecorder mic) => LessonSession(
    api: api,
    recorder: () => mic,
    tempPath: () async => '${tmp.path}/rekaman.m4a',
    pollEvery: const Duration(milliseconds: 10),
  );

  Future<void> until(LessonSession s, LessonPhase phase) async {
    for (var i = 0; i < 200 && s.phase != phase; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(s.phase, phase);
  }

  group('AC-130 LessonSession', () {
    test('record → send with formulas → processing → ready', () async {
      final api = FakeApi();
      final s = session(api, FakeRecorder());
      expect(await s.start(), isNull);
      expect(s.phase, LessonPhase.recording);
      s.noteFormulas(['y = x^{2} - 3', 'y = x^{2} - 3']);
      await s.stop();
      expect(api.uploads.single.$2, ['y = x^{2} - 3']);
      expect(
        File('${tmp.path}/rekaman.m4a').existsSync(),
        isFalse,
        reason: 'deleted from the panel once sent',
      );
      expect(s.phase, LessonPhase.processing);
      api.next = const LessonStatus('selesai', summary: 'Ringkasan');
      await until(s, LessonPhase.ready);
      expect(s.summary, 'Ringkasan');
      s.dispose();
    });

    test('no permission or no microphone: a clear message', () async {
      final s = session(FakeApi(), FakeRecorder(allowed: false));
      expect(await s.start(), LessonSession.noPermission);
      expect(s.phase, LessonPhase.idle);
      final t = session(FakeApi(), FakeRecorder(broken: true));
      expect(await t.start(), LessonSession.noMicrophone);
      s.dispose();
      t.dispose();
    });

    test('offline: the recording is kept and Coba lagi sends it', () async {
      final api = FakeApi()..uploadFailure = const ServerUnreachable();
      final s = session(api, FakeRecorder());
      await s.start();
      await s.stop();
      expect(s.phase, LessonPhase.failed);
      expect(s.error, LessonSession.offline);
      expect(s.canRetry, isTrue);
      expect(File('${tmp.path}/rekaman.m4a').existsSync(), isTrue);
      api.uploadFailure = null;
      await s.retry();
      expect(api.uploads, hasLength(1));
      expect(s.phase, LessonPhase.processing);
      s.dispose();
    });

    test('silence and AI down are reported', () async {
      final api = FakeApi();
      final s = session(api, FakeRecorder());
      await s.start();
      await s.stop();
      api.next = const LessonStatus('gagal', code: 'tanpa_suara');
      await until(s, LessonPhase.failed);
      expect(s.error, LessonSession.silent);
      expect(s.canRetry, isFalse);
      await s.reset();
      await s.start();
      await s.stop();
      api.next = const LessonStatus('gagal', code: 'ai_tidak_tersedia');
      await until(s, LessonPhase.failed);
      expect(s.error, LessonSession.aiDown);
      s.dispose();
    });

    test('stops by itself after the time limit', () async {
      final api = FakeApi();
      var now = DateTime(2026, 10, 15, 8);
      final s = LessonSession(
        api: api,
        recorder: FakeRecorder.new,
        tempPath: () async => '${tmp.path}/rekaman.m4a',
        maxLength: const Duration(minutes: 90),
        clock: () => now,
      );
      await s.start();
      now = now.add(const Duration(minutes: 91));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(s.autoStopped, isTrue);
      expect(api.uploads, hasLength(1));
      s.dispose();
    });
  });

  group('AC-131 on the board', () {
    Future<FakeServer> pump(WidgetTester tester) async {
      final server = FakeServer();
      await pumpApp(
        tester,
        repo: MemoryBoardRepository(),
        settingsFor: (_) => MemorySettingsStore(
          const ServerSettings(
            serverUrl: 'https://papan.contoh',
            pin: '482915',
          ),
        ),
        clientFor: server.clientFor,
        recorder: FakeRecorder.new,
        lessonPath: () async => '${tmp.path}/rekaman.m4a',
      );
      return server;
    }

    testWidgets('asks first; Batal records nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text(LessonTexts.record));
      await tester.pumpAndSettle();
      expect(find.text(LessonTexts.consentBody), findsOneWidget);
      await tester.tap(find.text(LessonTexts.cancel));
      await tester.pumpAndSettle();
      expect(find.text(LessonTexts.record), findsOneWidget);
    });

    testWidgets('record, summary ready, Tempel ke papan on a new page', (
      tester,
    ) async {
      final server = await pump(tester);
      await tester.tap(find.text(LessonTexts.record));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LessonTexts.start));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.textContaining('Merekam 00:00'), findsOneWidget);

      await tester.tap(find.textContaining('Merekam'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(server.lessonUploads, hasLength(1));
      expect(find.text(LessonTexts.processing), findsOneWidget);
      expect(inkOf(tester).items, isEmpty, reason: 'writing still works');

      server.lessonStatus = 'selesai';
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
      await tester.tap(find.text(LessonTexts.ready));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fungsi kuadrat'), findsOneWidget);
      await tester.tap(find.text(LessonTexts.paste));
      await tester.pumpAndSettle();
      expect(find.text(BoardScreen.summaryPasted(2)), findsOneWidget);
      final text = inkOf(tester).items.whereType<TextItem>().single;
      expect(text.text, contains('parabola'));
      expect(find.text(LessonTexts.record), findsOneWidget);
    });

    testWidgets('no Rekam button without server settings', (tester) async {
      await pumpApp(tester);
      expect(find.text(LessonTexts.record), findsNothing);
      expect(find.byType(LessonButton), findsNothing);
    });
  });
}
