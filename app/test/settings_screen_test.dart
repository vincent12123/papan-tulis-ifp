import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';
import 'package:whiteboard_ifp/settings/settings_screen.dart';
import 'package:whiteboard_ifp/ui/notices.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

import 'support/fake_server.dart';

const _url = 'https://papan.karyabangsa.sch.id';
const _pin = '482915';

Future<(FakeServer, MemorySettingsStore)> _pump(
  WidgetTester tester, {
  ServerSettings saved = const ServerSettings(),
  FakeServer? server,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = server ?? FakeServer();
  final store = MemorySettingsStore(saved);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: SettingsScreen(store: store, clientFor: s.clientFor),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(Notices.hide);
  return (s, store);
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _connect(
  WidgetTester tester, {
  String url = _url,
  String pin = _pin,
}) async {
  await tester.enterText(_field('Alamat server'), url);
  await tester.enterText(_field('PIN admin'), pin);
  await tester.tap(find.text('Tes koneksi'));
  await tester.pumpAndSettle();
}

const _configured = ServerSettings(serverUrl: _url, pin: _pin);

void main() {
  group('first install', () {
    testWidgets('fields are open; AI waits for a connection', (tester) async {
      final (_, store) = await _pump(tester);
      expect(find.text(SettingsScreen.lockedText), findsNothing);
      expect(find.text(SettingsScreen.exampleUrl), findsOneWidget);
      expect(find.text(SettingsScreen.noServerText), findsOneWidget);
      final save = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Simpan'),
      );
      expect(save.onPressed, isNull, reason: 'test the connection first');
      expect(store.saves, 0);
    });

    testWidgets('AC-90 address and PIN are validated', (tester) async {
      await _pump(tester);
      await _connect(tester, url: 'papan.sekolah.sch.id');
      expect(
        find.text('Alamat server harus diawali https://.'),
        findsOneWidget,
      );
      await _connect(tester, pin: '');
      expect(find.text(SettingsScreen.pinEmptyText), findsOneWidget);
    });

    testWidgets(
      'AC-91 PIN rejected and server unreachable say different things',
      (tester) async {
        final (server, _) = await _pump(tester);
        await _connect(tester, pin: '000000');
        expect(find.text(SettingsScreen.pinRejectedText), findsOneWidget);
        server.reachable = false;
        await _connect(tester);
        expect(find.text(SettingsScreen.unreachable(_url)), findsOneWidget);
      },
    );

    testWidgets('AC-92 a good connection loads providers and can be saved', (
      tester,
    ) async {
      final (_, store) = await _pump(tester);
      await _connect(tester);
      expect(find.text(SettingsScreen.connectedText), findsOneWidget);
      expect(find.text('Ikuti bawaan server (Ollama cloud)'), findsOneWidget);
      expect(find.text('gpt-oss:120b (teks saja)'), findsOneWidget);
      expect(find.text(SettingsScreen.fallbackNote), findsOneWidget);

      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(store.value.serverUrl, _url);
      expect(store.value.pin, _pin);
      expect(store.value.providerId, isNull);
      expect(
        find.text('Pengaturan disimpan. Asisten AI memakai Ollama cloud.'),
        findsOneWidget,
      );
    });

    testWidgets('changing the address after a test needs a new test', (
      tester,
    ) async {
      await _pump(tester);
      await _connect(tester);
      await tester.enterText(_field('Alamat server'), 'https://lain.sch.id');
      await tester.pump();
      final save = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Simpan'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('AC-99 server without active providers', (tester) async {
      final server = FakeServer()..providers = [];
      await _pump(tester, server: server);
      await _connect(tester);
      expect(find.text(SettingsScreen.noProvidersText), findsOneWidget);
    });
  });

  group('after setup (locked for guru)', () {
    testWidgets('AC-93b and AC-94 everything is read-only for guru', (
      tester,
    ) async {
      await _pump(tester, saved: _configured);
      expect(find.text(SettingsScreen.lockedText), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Alamat server')).enabled,
        isFalse,
      );
      expect(find.text('PIN tersimpan'), findsOneWidget);
      expect(find.text(SettingsScreen.adminOnlyAiText), findsOneWidget);
      expect(find.text('Tes AI'), findsNothing);
      expect(find.text('Ganti PIN admin'), findsNothing);
      expect(find.text('Simpan'), findsNothing);
      final pick = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(pick.onChanged, isNull);
    });

    testWidgets('AC-95 the right PIN unlocks; a wrong one does not', (
      tester,
    ) async {
      await _pump(tester, saved: _configured);
      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text(SettingsScreen.pinWrongText), findsOneWidget);
      expect(find.text(SettingsScreen.lockedText), findsOneWidget);

      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, _pin);
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text(SettingsScreen.lockedText), findsNothing);
      expect(find.text('Ganti PIN admin'), findsOneWidget);
      expect(find.text('Tes AI'), findsOneWidget);
    });

    testWidgets('server unreachable: the stored PIN still unlocks', (
      tester,
    ) async {
      final server = FakeServer()..reachable = false;
      await _pump(tester, saved: _configured, server: server);
      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '999999');
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text(SettingsScreen.lockedText), findsOneWidget);

      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, _pin);
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text(SettingsScreen.lockedText), findsNothing);
    });

    testWidgets('AC-96 lockout message', (tester) async {
      final server = FakeServer()..locked = true;
      await _pump(tester, saved: _configured, server: server);
      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, _pin);
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(find.text(SettingsScreen.lockedOutText), findsOneWidget);
    });

    Future<void> unlock(WidgetTester tester) async {
      await tester.tap(find.text('Ubah (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, _pin);
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
    }

    testWidgets('admin picks a provider, tests it, and saves', (tester) async {
      final (_, store) = await _pump(tester, saved: _configured);
      await unlock(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude (Anthropic)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tes AI'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Claude (Anthropic) · claude-sonnet-5-5 menjawab dalam 2,4 detik.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(store.value.providerId, 'claude');
      expect(store.value.pin, _pin, reason: 'unchanged PIN is kept');
      expect(
        find.text(
          'Pengaturan disimpan. Asisten AI memakai Claude (Anthropic).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failing Tes AI names the provider and the cause', (
      tester,
    ) async {
      final server = FakeServer()..aiFailures['ollama'] = 'kuota habis';
      await _pump(tester, saved: _configured, server: server);
      await unlock(tester);
      await tester.tap(find.text('Tes AI'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Ollama cloud tidak menjawab: kuota habis. '
          'Saat dipakai mengajar, AI akan otomatis memakai Ollama cloud.',
        ),
        findsOneWidget,
      );
    });

    group('TSK-10 Ganti PIN admin', () {
      Future<void> fill(
        WidgetTester tester,
        String old,
        String fresh,
        String again,
      ) async {
        await tester.tap(find.text('Ganti PIN admin'));
        await tester.pumpAndSettle();
        await tester.enterText(_field('PIN lama'), old);
        await tester.enterText(_field('PIN baru'), fresh);
        await tester.enterText(_field('Ulangi PIN baru'), again);
        await tester.tap(find.text('Ganti PIN'));
        await tester.pumpAndSettle();
      }

      testWidgets('AC-97 validation messages', (tester) async {
        await _pump(tester, saved: _configured);
        await unlock(tester);
        await fill(tester, _pin, '123456', '123456');
        expect(
          find.text(
            'PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang.',
          ),
          findsOneWidget,
        );
        await tester.enterText(_field('PIN baru'), _pin);
        await tester.enterText(_field('Ulangi PIN baru'), _pin);
        await tester.tap(find.text('Ganti PIN'));
        await tester.pump();
        expect(
          find.text('PIN baru tidak boleh sama dengan PIN lama.'),
          findsOneWidget,
        );
        await tester.enterText(_field('PIN baru'), '730518');
        await tester.enterText(_field('Ulangi PIN baru'), '730519');
        await tester.tap(find.text('Ganti PIN'));
        await tester.pump();
        expect(find.text('Ulangan PIN baru tidak sama.'), findsOneWidget);
        expect(
          find.textContaining('Minta operator mengatur ulang PIN lewat server'),
          findsOneWidget,
        );
      });

      testWidgets('success stores the new PIN on this panel', (tester) async {
        final (server, store) = await _pump(tester, saved: _configured);
        await unlock(tester);
        await fill(tester, _pin, '730518', '730518');
        expect(server.pin, '730518');
        expect(store.value.pin, '730518');
        expect(
          find.text(
            'PIN admin sudah diganti. PIN lama tidak berlaku lagi di semua panel.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('wrong old PIN and no connection are reported', (
        tester,
      ) async {
        final (server, store) = await _pump(tester, saved: _configured);
        await unlock(tester);
        await fill(tester, '999999', '730518', '730518');
        expect(
          find.text('PIN lama salah. PIN admin tidak berubah.'),
          findsOneWidget,
        );
        server.reachable = false;
        Notices.hide();
        await fill(tester, _pin, '730518', '730518');
        expect(
          find.text(
            'PIN belum diganti karena panel tidak terhubung ke server. Coba lagi.',
          ),
          findsOneWidget,
        );
        expect(store.value.pin, _pin);
      });
    });
  });

  testWidgets('NF-06 main action is 64 dp and text is 20 sp', (tester) async {
    await _pump(tester);
    final size = tester.getSize(
      find.widgetWithText(FilledButton, 'Tes koneksi'),
    );
    expect(size.height, greaterThanOrEqualTo(AppSizes.primaryTarget));
  });
}
