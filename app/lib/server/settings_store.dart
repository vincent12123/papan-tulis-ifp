import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/board_repository.dart';

/// What the panel remembers about the server (SPEC 5.8, §4.5b).
class ServerSettings {
  const ServerSettings({this.serverUrl, this.pin, this.providerId, this.model});

  final String? serverUrl;

  /// Admin PIN; only ever kept in Android's secure storage.
  final String? pin;

  /// Panel's AI choice; null = follow the server default (Ollama cloud).
  final String? providerId;
  final String? model;

  /// Settings were saved once, so the screen opens locked.
  bool get isConfigured => serverUrl != null && pin != null;
}

abstract interface class SettingsStore {
  Future<ServerSettings> load();
  Future<void> save(ServerSettings settings);
}

/// URL and AI choice in the app database; the PIN in Android Keystore
/// via flutter_secure_storage (AC-93).
class DeviceSettingsStore implements SettingsStore {
  DeviceSettingsStore(this.repo, [FlutterSecureStorage? secure])
    : _secure = secure ?? const FlutterSecureStorage();

  final BoardRepository repo;
  final FlutterSecureStorage _secure;

  static const _pinKey = 'pin_admin';

  @override
  Future<ServerSettings> load() async => ServerSettings(
    serverUrl: await repo.appState('server_url'),
    pin: await _secure.read(key: _pinKey),
    providerId: await repo.appState('ai_penyedia'),
    model: await repo.appState('ai_model'),
  );

  @override
  Future<void> save(ServerSettings s) async {
    if (s.pin != null) await _secure.write(key: _pinKey, value: s.pin);
    await repo.setAppState('server_url', s.serverUrl);
    await repo.setAppState('ai_penyedia', s.providerId);
    await repo.setAppState('ai_model', s.model);
  }
}
