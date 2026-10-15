import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whiteboard_ifp/data/app_database.dart';
import 'package:whiteboard_ifp/data/board_repository.dart';
import 'package:whiteboard_ifp/server/server_client.dart';
import 'package:whiteboard_ifp/server/settings_store.dart';

import 'support/fake_server.dart';

ServerClient _client(http.Response Function(http.Request) handler) =>
    ServerClient(
      baseUrl: 'https://papan.contoh/',
      pin: '482915',
      client: MockClient((r) async => handler(r)),
    );

http.Response _json(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status);

void main() {
  group('ServerClient', () {
    test('sends the PIN header to the right path', () async {
      final server = FakeServer();
      await server
          .clientFor('https://papan.contoh/', '482915')
          .testConnection();
      final r = server.requests.single;
      expect(r.url.toString(), 'https://papan.contoh/koneksi');
      expect(r.headers['X-PIN-Admin'], '482915');
    });

    test(
      'AC-91 a wrong PIN and an unreachable server are told apart',
      () async {
        final server = FakeServer();
        await expectLater(
          server.clientFor('https://a', '000000').testConnection(),
          throwsA(isA<PinRejected>()),
        );
        server.reachable = false;
        await expectLater(
          server.clientFor('https://a', '482915').testConnection(),
          throwsA(isA<ServerUnreachable>()),
        );
      },
    );

    test(
      'classifies lockout, missing PIN, validation, and provider errors',
      () async {
        Future<void> expectFailure(http.Response response, Matcher matcher) =>
            expectLater(
              _client((_) => response).testConnection(),
              throwsA(matcher),
            );
        await expectFailure(
          _json(429, {'kode': 'terkunci', 'sisa_detik': 120}),
          isA<PinLocked>().having((e) => e.seconds, 'seconds', 120),
        );
        await expectFailure(
          _json(503, {'kode': 'pin_belum_diatur'}),
          isA<PinNotSetOnServer>(),
        );
        await expectFailure(
          _json(422, {'kode': 'x', 'pesan': 'PIN baru minimal 6 angka.'}),
          isA<ServerValidation>().having(
            (e) => e.message,
            'm',
            'PIN baru minimal 6 angka.',
          ),
        );
        await expectFailure(
          _json(502, {'kode': 'penyedia_gagal', 'pesan': 'kuota habis'}),
          isA<ProviderFailed>().having((e) => e.reason, 'r', 'kuota habis'),
        );
        await expectFailure(
          http.Response('<html>Bad gateway</html>', 502),
          isA<ServerError>(),
        );
      },
    );

    test('parses the provider list', () async {
      final list = await FakeServer()
          .clientFor('https://a', '482915')
          .providers();
      expect(list.defaultId, 'ollama');
      expect(list.providers.map((p) => p.name), [
        'Ollama cloud',
        'Claude (Anthropic)',
      ]);
      expect(list.byId('claude')!.models.single.supportsImages, isTrue);
    });

    test(
      'changing the PIN sends the old PIN in the body, not a header',
      () async {
        final server = FakeServer();
        await server
            .clientFor('https://a', '482915')
            .changePin('482915', '730518');
        final r = server.requests.single;
        expect(r.headers.containsKey('X-PIN-Admin'), isFalse);
        expect(server.pin, '730518');
        await expectLater(
          server.clientFor('https://a', 'x').changePin('111111', '604728'),
          throwsA(
            isA<PinRejected>().having((e) => e.oldPinWrong, 'old', isTrue),
          ),
        );
      },
    );
  });

  group('AC-90 server address rules', () {
    for (final ok in [
      'https://papan.karyabangsa.sch.id',
      'http://192.168.1.20:8000',
      'http://10.0.0.5',
      'http://172.20.1.1',
      'http://localhost:8000',
    ]) {
      test('accepts $ok', () => expect(serverUrlProblem(ok), isNull));
    }
    for (final bad in [
      '',
      'papan.sekolah.sch.id',
      'http://papan.sekolah.sch.id',
      'http://8.8.8.8',
      'http://172.32.0.1',
      'ftp://192.168.1.2',
    ]) {
      test('rejects "$bad"', () {
        expect(serverUrlProblem(bad), 'Alamat server harus diawali https://.');
      });
    }
  });

  test('new PIN rules match the server', () {
    expect(newPinProblem('12345'), 'PIN baru minimal 6 angka.');
    expect(newPinProblem('12a456'), 'PIN baru minimal 6 angka.');
    expect(newPinProblem('123456'), contains('mudah ditebak'));
    expect(newPinProblem('987654'), contains('mudah ditebak'));
    expect(newPinProblem('000000'), contains('mudah ditebak'));
    expect(newPinProblem('730518'), isNull);
  });

  group('AC-93 PIN storage', () {
    sqfliteFfiInit();
    late Directory dir;
    late AppDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('papan_pin');
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        mainPath: p.join(dir.path, 'papan.db'),
        snapshotPath: p.join(dir.path, 'salinan.db'),
      );
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('the PIN goes to secure storage, never into the database', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      final repo = BoardRepository(db);
      final store = DeviceSettingsStore(repo);
      await store.save(
        const ServerSettings(
          serverUrl: 'https://papan.contoh',
          pin: '482915',
          providerId: 'claude',
          model: 'm',
        ),
      );
      final rows = await db.main.query('app_state');
      expect(rows.toString(), isNot(contains('482915')));
      expect(await repo.appState('server_url'), 'https://papan.contoh');

      final loaded = await store.load();
      expect(loaded.pin, '482915');
      expect(loaded.providerId, 'claude');
      expect(loaded.isConfigured, isTrue);

      // Following the server default removes the stored choice.
      await store.save(
        const ServerSettings(serverUrl: 'https://papan.contoh', pin: '482915'),
      );
      expect(await repo.appState('ai_penyedia'), isNull);
    });
  });
}
