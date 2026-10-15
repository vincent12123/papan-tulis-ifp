import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../server/server_client.dart';
import '../server/settings_store.dart';
import '../ui/notices.dart';
import '../ui/theme.dart';

typedef ClientFactory = ServerClient Function(String url, String pin);

/// SCR-06 Pengaturan. Guru only see it; the admin unlocks it with the PIN
/// (SPEC 5.8, P-11). On first install it is open so the admin can set it up.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, this.clientFor});

  final SettingsStore store;
  final ClientFactory? clientFor;

  static const lockedText = 'Hanya admin yang bisa mengubah.';
  static const exampleUrl = 'Contoh: https://papan.sekolahanda.sch.id';
  static const noServerText =
      'Hubungkan ke server dulu untuk memilih penyedia AI.';
  static const noProvidersText =
      'Belum ada penyedia AI yang diaktifkan di server. Hubungi operator.';
  static const adminOnlyAiText = 'Hanya admin yang bisa mengganti penyedia AI.';
  static const fallbackNote =
      'Bila penyedia ini gagal, AI otomatis memakai Ollama cloud.';
  static const connectedText = 'Terhubung ke server sekolah.';
  static const pinRejectedText =
      'Server menolak PIN admin. Periksa PIN, atau minta admin memasukkan PIN terbaru.';
  static const pinWrongText = 'PIN admin salah.';
  static const lockedOutText = 'PIN salah 5 kali. Coba lagi dalam 5 menit.';
  static const pinNotSetText =
      'PIN admin belum diatur di server. Minta operator mengaturnya.';
  static const serverErrorText =
      'Server menjawab dengan cara yang tidak dikenali. Periksa alamat server.';
  static const pinEmptyText = 'PIN admin tidak boleh kosong.';
  static String unreachable(String url) =>
      'Tidak bisa terhubung ke $url. Periksa alamat dan Wi-Fi panel.';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _Status { idle, busy, ok, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _pin = TextEditingController();

  ServerSettings _saved = const ServerSettings();
  bool _loading = true;
  bool _unlocked = false;
  bool _showPin = false;

  _Status _connection = _Status.idle;
  String? _connectionText;

  /// URL and PIN that passed Tes koneksi; Simpan needs them to match.
  ({String url, String pin})? _verified;

  ProviderList? _providers;
  bool _loadingProviders = false;
  String? _providerId;
  String? _model;

  _Status _aiTest = _Status.idle;
  String? _aiTestText;

  bool get _editable => !_saved.isConfigured || _unlocked;

  ServerClient _client(String url, String pin) =>
      widget.clientFor?.call(url, pin) ??
      ServerClient(baseUrl: url, pin: pin, client: http.Client());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _url.text = saved.serverUrl ?? '';
      _providerId = saved.providerId;
      _model = saved.model;
      _loading = false;
    });
    if (saved.isConfigured) {
      _loadProviders(saved.serverUrl!, saved.pin!, quiet: true);
    }
  }

  String get _typedPin => _pin.text.isNotEmpty ? _pin.text : (_saved.pin ?? '');

  String _failureText(ServerFailure f, String url) => switch (f) {
    ServerUnreachable() => SettingsScreen.unreachable(url),
    PinRejected() => SettingsScreen.pinRejectedText,
    PinLocked() => SettingsScreen.lockedOutText,
    PinNotSetOnServer() => SettingsScreen.pinNotSetText,
    ServerValidation(:final message) => message,
    ProviderFailed(:final reason) => reason,
    ServerError() ||
    AiUnavailable() ||
    AiTimedOut() ||
    NoFormulaFound() => SettingsScreen.serverErrorText,
  };

  Future<void> _testConnection() async {
    final url = _url.text.trim();
    final urlProblem = serverUrlProblem(url);
    if (urlProblem != null) {
      setState(() {
        _connection = _Status.failed;
        _connectionText = urlProblem;
      });
      return;
    }
    final pin = _typedPin;
    if (pin.isEmpty) {
      setState(() {
        _connection = _Status.failed;
        _connectionText = SettingsScreen.pinEmptyText;
      });
      return;
    }
    setState(() {
      _connection = _Status.busy;
      _connectionText = 'Menguji koneksi ke $url…';
    });
    final client = _client(url, pin);
    try {
      await client.testConnection();
      if (!mounted) return;
      setState(() {
        _connection = _Status.ok;
        _connectionText = SettingsScreen.connectedText;
        _verified = (url: url, pin: pin);
      });
      await _loadProviders(url, pin);
    } on ServerFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _connection = _Status.failed;
        _connectionText = _failureText(f, url);
        _verified = null;
      });
    } finally {
      client.close();
    }
  }

  Future<void> _loadProviders(
    String url,
    String pin, {
    bool quiet = false,
  }) async {
    setState(() => _loadingProviders = true);
    final client = _client(url, pin);
    try {
      final list = await client.providers();
      if (!mounted) return;
      setState(() {
        _providers = list;
        if (list.byId(_providerId) == null) _providerId = null;
        final p = list.byId(_providerId) ?? list.defaultProvider;
        if (p == null || !p.models.any((m) => m.name == _model)) _model = null;
      });
    } on ServerFailure catch (f) {
      if (!mounted || quiet) return;
      setState(() {
        _connection = _Status.failed;
        _connectionText = _failureText(f, url);
      });
    } finally {
      client.close();
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  /// Ubah (admin): the PIN is checked by the server, or against the stored
  /// PIN when the server cannot be reached (so a wrong address can still be
  /// fixed).
  Future<void> _unlock() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(title: 'Ubah (admin)'),
    );
    if (pin == null || !mounted) return;
    final client = _client(_saved.serverUrl!, pin);
    try {
      await client.testConnection();
      if (!mounted) return;
      setState(() => _unlocked = true);
    } on ServerUnreachable {
      if (!mounted) return;
      if (pin == _saved.pin) {
        setState(() => _unlocked = true);
      } else {
        Notices.failure(context, SettingsScreen.pinWrongText);
      }
    } on PinLocked {
      if (mounted) Notices.failure(context, SettingsScreen.lockedOutText);
    } on PinRejected {
      if (mounted) Notices.failure(context, SettingsScreen.pinWrongText);
    } on ServerFailure catch (f) {
      if (mounted) {
        Notices.failure(context, _failureText(f, _saved.serverUrl!));
      }
    } finally {
      client.close();
    }
  }

  AiProvider? get _currentProvider =>
      _providers?.byId(_providerId) ?? _providers?.defaultProvider;

  String? get _currentModel => _model ?? _currentProvider?.defaultModel;

  Future<void> _testAi() async {
    final provider = _currentProvider;
    final model = _currentModel;
    final url = _verified?.url ?? _saved.serverUrl;
    final pin = _verified?.pin ?? _saved.pin;
    if (provider == null || model == null || url == null || pin == null) {
      return;
    }
    setState(() {
      _aiTest = _Status.busy;
      _aiTestText = 'Menguji ${provider.name}…';
    });
    final client = _client(url, pin);
    try {
      final seconds = await client.testAi(provider.id, model);
      if (!mounted) return;
      setState(() {
        _aiTest = _Status.ok;
        _aiTestText =
            '${provider.name} · $model menjawab dalam '
            '${seconds.toStringAsFixed(1).replaceAll('.', ',')} detik.';
      });
    } on ServerFailure catch (f) {
      if (!mounted) return;
      final cause = switch (f) {
        ProviderFailed(:final reason) => reason,
        _ => _failureText(f, url),
      };
      setState(() {
        _aiTest = _Status.failed;
        _aiTestText =
            '${provider.name} tidak menjawab: $cause. '
            'Saat dipakai mengajar, AI akan otomatis memakai Ollama cloud.';
      });
    } finally {
      client.close();
    }
  }

  bool get _connectionChanged =>
      _url.text.trim() != (_saved.serverUrl ?? '') || _pin.text.isNotEmpty;

  bool get _connectionVerified =>
      _verified != null &&
      _verified!.url == _url.text.trim() &&
      _verified!.pin == _typedPin;

  /// First setup needs a passing Tes koneksi; later only when the address
  /// or PIN changed.
  bool get _canSave =>
      _editable &&
      (_saved.isConfigured && !_connectionChanged || _connectionVerified);

  Future<void> _save() async {
    final settings = ServerSettings(
      serverUrl: _verified?.url ?? _saved.serverUrl,
      pin: _verified?.pin ?? _saved.pin,
      providerId: _providerId,
      model: _model,
    );
    await widget.store.save(settings);
    if (!mounted) return;
    setState(() {
      _saved = settings;
      _pin.clear();
    });
    final name =
        _currentProvider?.name ??
        (_providers == null ? 'bawaan server' : 'Ollama cloud');
    Notices.success(context, 'Pengaturan disimpan. Asisten AI memakai $name.');
  }

  Future<void> _changePin() async {
    final url = _saved.serverUrl;
    if (url == null) return;
    final result = await showDialog<({String oldPin, String newPin})>(
      context: context,
      builder: (_) => const _ChangePinDialog(),
    );
    if (result == null || !mounted) return;
    final client = _client(url, result.oldPin);
    try {
      await client.changePin(result.oldPin, result.newPin);
      final updated = ServerSettings(
        serverUrl: _saved.serverUrl,
        pin: result.newPin,
        providerId: _saved.providerId,
        model: _saved.model,
      );
      await widget.store.save(updated);
      if (!mounted) return;
      setState(() => _saved = updated);
      Notices.success(
        context,
        'PIN admin sudah diganti. PIN lama tidak berlaku lagi di semua panel.',
      );
    } on PinRejected {
      if (mounted) {
        Notices.failure(context, 'PIN lama salah. PIN admin tidak berubah.');
      }
    } on ServerUnreachable {
      if (mounted) {
        Notices.failure(
          context,
          'PIN belum diganti karena panel tidak terhubung ke server. Coba lagi.',
        );
      }
    } on ServerFailure catch (f) {
      if (mounted) Notices.failure(context, _failureText(f, url));
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppColors.surface,
              elevation: AppSizes.elevation,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.space8,
                  vertical: AppSizes.space4,
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Kembali'),
                    ),
                    const SizedBox(width: AppSizes.space16),
                    Text('Pengaturan', style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSizes.space24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_saved.isConfigured && !_unlocked)
                                _LockedBanner(onUnlock: _unlock),
                              _connectionSection(theme),
                              const Divider(height: AppSizes.space48),
                              _aiSection(theme),
                              const Divider(height: AppSizes.space48),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Versi aplikasi $appVersion',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                  if (_editable)
                                    OutlinedButton(
                                      onPressed: _canSave ? _save : null,
                                      child: const Text('Simpan'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _url,
          enabled: _editable,
          keyboardType: TextInputType.url,
          style: const TextStyle(fontSize: AppSizes.textBody),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Alamat server',
            helperText: SettingsScreen.exampleUrl,
          ),
        ),
        const SizedBox(height: AppSizes.space16),
        TextField(
          controller: _pin,
          enabled: _editable,
          obscureText: !_showPin,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: AppSizes.textBody),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'PIN admin',
            helperText: _saved.pin != null ? 'PIN tersimpan' : null,
            suffixIcon: IconButton(
              tooltip: _showPin ? 'Sembunyikan PIN' : 'Lihat PIN',
              onPressed: () => setState(() => _showPin = !_showPin),
              icon: Icon(_showPin ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.space16),
        Row(
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSizes.primaryTarget),
              ),
              onPressed: _editable && _connection != _Status.busy
                  ? _testConnection
                  : null,
              child: const Text('Tes koneksi'),
            ),
            const SizedBox(width: AppSizes.space16),
            if (_connectionText != null)
              Expanded(child: _StatusText(_connectionText!, _connection)),
          ],
        ),
      ],
    );
  }

  Widget _aiSection(ThemeData theme) {
    final providers = _providers;
    final children = <Widget>[
      Text('Asisten AI', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSizes.space12),
    ];
    if (_loadingProviders) {
      children.add(
        const _StatusText('Memuat daftar penyedia AI…', _Status.busy),
      );
    } else if (providers == null) {
      children.add(
        const _StatusText(SettingsScreen.noServerText, _Status.idle),
      );
    } else if (providers.providers.isEmpty) {
      children.add(
        const _StatusText(SettingsScreen.noProvidersText, _Status.failed),
      );
    } else {
      final provider = _currentProvider!;
      final defaultName = providers.defaultProvider?.name ?? 'Ollama cloud';
      children.addAll([
        DropdownButtonFormField<String?>(
          initialValue: _providerId,
          isExpanded: true,
          style: const TextStyle(
            fontSize: AppSizes.textBody,
            color: AppColors.text,
          ),
          decoration: const InputDecoration(labelText: 'Penyedia'),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text('Ikuti bawaan server ($defaultName)'),
            ),
            for (final p in providers.providers)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: _editable
              ? (id) => setState(() {
                  _providerId = id;
                  _model = null;
                  _aiTest = _Status.idle;
                  _aiTestText = null;
                })
              : null,
        ),
        const SizedBox(height: AppSizes.space16),
        DropdownButtonFormField<String>(
          key: ValueKey(provider.id),
          initialValue: _currentModel,
          isExpanded: true,
          style: const TextStyle(
            fontSize: AppSizes.textBody,
            color: AppColors.text,
          ),
          decoration: const InputDecoration(labelText: 'Model'),
          items: [
            for (final m in provider.models)
              DropdownMenuItem(
                value: m.name,
                child: Text(
                  m.supportsImages ? m.name : '${m.name} (teks saja)',
                ),
              ),
          ],
          onChanged: _editable
              ? (m) => setState(() {
                  _model = m;
                  _aiTest = _Status.idle;
                  _aiTestText = null;
                })
              : null,
        ),
        const SizedBox(height: AppSizes.space8),
        Text(
          _editable
              ? SettingsScreen.fallbackNote
              : SettingsScreen.adminOnlyAiText,
          style: theme.textTheme.bodySmall,
        ),
        if (_editable) ...[
          const SizedBox(height: AppSizes.space16),
          Row(
            children: [
              OutlinedButton(
                onPressed: _aiTest == _Status.busy ? null : _testAi,
                child: const Text('Tes AI'),
              ),
              const SizedBox(width: AppSizes.space16),
              if (_aiTestText != null)
                Expanded(child: _StatusText(_aiTestText!, _aiTest)),
            ],
          ),
        ],
      ]);
    }
    if (_saved.isConfigured && _unlocked) {
      children.addAll([
        const SizedBox(height: AppSizes.space16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _changePin,
            icon: const Icon(Icons.password),
            label: const Text('Ganti PIN admin'),
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.space24),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.textMuted),
          const SizedBox(width: AppSizes.space8),
          Expanded(
            child: Text(
              SettingsScreen.lockedText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSizes.primaryTarget),
            ),
            onPressed: onUnlock,
            child: const Text('Ubah (admin)'),
          ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.text, this.status);

  final String text;
  final _Status status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      _Status.ok => (Icons.check_circle, AppColors.success),
      _Status.failed => (Icons.error_outline, AppColors.danger),
      _Status.busy => (Icons.hourglass_top, AppColors.textMuted),
      _Status.idle => (Icons.info_outline, AppColors.textMuted),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSizes.space8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: AppSizes.textBody, color: color),
          ),
        ),
      ],
    );
  }
}

/// Asks for the admin PIN (hidden, with a show button).
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});

  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pin.text.isEmpty) {
      setState(() => _error = SettingsScreen.pinEmptyText);
      return;
    }
    Navigator.pop(context, _pin.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _pin,
          autofocus: true,
          obscureText: !_show,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: AppSizes.textBody),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'PIN admin',
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: _show ? 'Sembunyikan PIN' : 'Lihat PIN',
              onPressed: () => setState(() => _show = !_show),
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Buka')),
      ],
    );
  }
}

/// TSK-10: old PIN, new PIN twice, with the rules and the emergency route.
class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _show = false;
  String? _oldError, _newError, _repeatError;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() {
      _oldError = _old.text.isEmpty ? SettingsScreen.pinEmptyText : null;
      _newError = newPinProblem(_new.text);
      if (_newError == null && _new.text == _old.text) {
        _newError = 'PIN baru tidak boleh sama dengan PIN lama.';
      }
      _repeatError = _repeat.text != _new.text
          ? 'Ulangan PIN baru tidak sama.'
          : null;
    });
    if (_oldError != null || _newError != null || _repeatError != null) return;
    Navigator.pop(context, (oldPin: _old.text, newPin: _new.text));
  }

  Widget _field(TextEditingController c, String label, String? error) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.space12),
        child: TextField(
          controller: c,
          obscureText: !_show,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: AppSizes.textBody),
          decoration: InputDecoration(labelText: label, errorText: error),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Ganti PIN admin'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_old, 'PIN lama', _oldError),
              _field(_new, 'PIN baru', _newError),
              _field(_repeat, 'Ulangi PIN baru', _repeatError),
              Text(
                'PIN baru minimal 6 angka, tidak berurutan atau berulang '
                '(mis. bukan 123456 atau 111111).',
                style: muted,
              ),
              TextButton.icon(
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                label: Text(_show ? 'Sembunyikan PIN' : 'Lihat PIN'),
              ),
              Text(
                'Lupa PIN atau PIN sudah diganti orang lain? Minta operator '
                'mengatur ulang PIN lewat server.',
                style: muted,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Ganti PIN')),
      ],
    );
  }
}
