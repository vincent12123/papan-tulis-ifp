import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'board/board_document.dart';
import 'board/board_screen.dart';
import 'board/board_title.dart';
import 'board/media_import.dart';
import 'board/smart_menu.dart';
import 'lesson/lesson_session.dart';
import 'board/video_dialog.dart';
import 'boards/board_list_screen.dart';
import 'data/board_repository.dart';
import 'data/media_store.dart';
import 'ai/ai_dialog.dart';
import 'server/server_client.dart';
import 'server/settings_store.dart';
import 'settings/settings_screen.dart';
import 'ui/theme.dart';

/// Starts the app on the last board (SPEC P-10) and moves between the board
/// and the board list. Handles the SCR-01 loading and damaged-board states.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    this.renderThumbnail,
    this.clock,
    this.media,
    this.files = const DeviceFileSource(),
    this.pdf,
    this.settingsFor,
    this.clientFor,
    this.recorder,
    this.lessonPath,
  });

  final Future<BoardRepository> repository;
  final ThumbnailRenderer? renderThumbnail;
  final DateTime Function()? clock;

  /// Picture/background storage; null disables Gambar and Pasang latar.
  final Future<MediaStore>? media;
  final FileSource files;
  final PdfRasterizer? pdf;

  /// Builds the Pengaturan store once the database is open.
  final SettingsStore Function(BoardRepository repo)? settingsFor;
  final ClientFactory? clientFor;

  /// Microphone for Rekam kelas (REQ-25); null uses the panel's own.
  final LessonRecorder Function()? recorder;

  /// Where the recording is written; null uses the temporary folder.
  final Future<String> Function()? lessonPath;

  /// Loading text appears only when opening takes longer than this.
  static const loadingDelay = Duration(seconds: 1);

  @override
  State<AppShell> createState() => _AppShellState();
}

sealed class _ShellState {}

class _Loading extends _ShellState {
  _Loading(this.title);
  final String? title;
}

class _Ready extends _ShellState {
  _Ready(this.doc);
  final BoardDocument doc;
}

class _Damaged extends _ShellState {
  _Damaged(this.error);
  final BoardCorruptException error;
}

class _Failed extends _ShellState {}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  BoardRepository? _repo;
  MediaStore? _media;
  _ShellState _state = _Loading(null);
  bool _showLoading = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  /// Rekam kelas lives as long as the app, so switching boards keeps it.
  LessonSession? _lessonSession;

  LessonSession? get _lesson {
    final settingsFor = widget.settingsFor;
    if (settingsFor == null) return null;
    return _lessonSession ??= LessonSession(
      api: _ShellLessonApi(this),
      recorder: widget.recorder ?? MicRecorder.new,
      tempPath: widget.lessonPath,
    );
  }

  /// Runs [call] with a client built from the saved Pengaturan.
  Future<T> _withClient<T>(Future<T> Function(ServerClient c) call) async {
    final saved = await widget.settingsFor!(_repo!).load();
    if (!saved.isConfigured) throw const PinRejected();
    final client =
        widget.clientFor?.call(saved.serverUrl!, saved.pin!) ??
        ServerClient(baseUrl: saved.serverUrl!, pin: saved.pin!);
    try {
      return await call(client);
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _lessonSession?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    final s = _state;
    if (s is _Ready) s.doc.dispose();
    super.dispose();
  }

  /// Leaving the app (or the panel going to sleep) takes the automatic copy
  /// and refreshes the list thumbnail.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _state;
    if (state == AppLifecycleState.paused && s is _Ready) s.doc.snapshot();
  }

  DateTime _now() => (widget.clock ?? () => DateTime.now().toUtc())();

  Future<void> _start() async {
    try {
      final repo = _repo = await widget.repository;
      _media = await widget.media;
      // Remove pictures no board uses any more (deleted boards/pages).
      final media = _media;
      if (media != null) {
        try {
          await media.collectGarbage(await repo.referencedMedia());
        } catch (_) {
          // Cleanup is best effort; never block opening the board.
        }
      }
      final last = await repo.lastBoardId();
      if (last != null && await repo.boardExists(last)) {
        await _open(last);
      } else {
        await _create();
      }
    } catch (_) {
      if (mounted) setState(() => _state = _Failed());
    }
  }

  void _beginLoading(String? title) {
    _loadingTimer?.cancel();
    _showLoading = false;
    _loadingTimer = Timer(AppShell.loadingDelay, () {
      if (mounted) setState(() => _showLoading = true);
    });
    setState(() => _state = _Loading(title));
  }

  Future<void> _open(String id) async {
    final repo = _repo!;
    final summaries = await repo.listBoards();
    final title = summaries.where((b) => b.id == id).firstOrNull?.title;
    _beginLoading(title);
    try {
      final doc = await BoardDocument.open(
        repo,
        id,
        renderThumbnail: widget.renderThumbnail,
        media: _media,
      );
      _show(doc);
    } on BoardCorruptException catch (e) {
      _loadingTimer?.cancel();
      if (mounted) setState(() => _state = _Damaged(e));
    }
  }

  Future<void> _create() async {
    _beginLoading(null);
    final doc = await BoardDocument.create(
      _repo!,
      defaultBoardTitle(_now()),
      renderThumbnail: widget.renderThumbnail,
      media: _media,
    );
    _show(doc);
  }

  void _show(BoardDocument doc) {
    _loadingTimer?.cancel();
    if (!mounted) {
      doc.dispose();
      return;
    }
    setState(() => _state = _Ready(doc));
  }

  Future<void> _goHome() async {
    final s = _state;
    if (s is! _Ready) return;
    final doc = s.doc;
    await doc.snapshot();
    if (!mounted) return;
    final result = await Navigator.of(context).push<BoardListResult>(
      MaterialPageRoute(
        builder: (_) => BoardListScreen(
          repo: _repo!,
          currentId: doc.id,
          settings: widget.settingsFor?.call(_repo!),
          clientFor: widget.clientFor,
        ),
      ),
    );
    if (!mounted) return;
    final repo = _repo!;
    switch (result) {
      case OpenBoard(:final id) when id != doc.id:
        await _leave(doc);
        await _open(id);
      case NewBoard():
        await _leave(doc);
        await _create();
      default:
        // Back to the same board; it may have been renamed.
        final summary = (await repo.listBoards())
            .where((b) => b.id == doc.id)
            .firstOrNull;
        if (summary != null) {
          doc.title.value = summary.title;
        } else {
          await _leave(doc);
          await _create();
        }
    }
  }

  /// Calls the school server with the PIN and AI choice saved in
  /// Pengaturan; refused like a wrong PIN when nothing is set up yet.
  AiRunner? get _aiRunner {
    final settingsFor = widget.settingsFor;
    if (settingsFor == null) return null;
    return (kind, png) async {
      final saved = await settingsFor(_repo!).load();
      if (!saved.isConfigured) throw const PinRejected();
      final client =
          widget.clientFor?.call(saved.serverUrl!, saved.pin!) ??
          ServerClient(baseUrl: saved.serverUrl!, pin: saved.pin!);
      try {
        return await client.runAi(
          kind: kind,
          png: png,
          providerId: saved.providerId,
          model: saved.model,
        );
      } finally {
        client.close();
      }
    };
  }

  /// Menu pintar (REQ-22) on the school server, with the PIN from
  /// Pengaturan; refused like a wrong PIN when nothing is set up yet.
  FormulaRecognizer? get _formulas {
    final settingsFor = widget.settingsFor;
    if (settingsFor == null) return null;
    return (png, color) async {
      final saved = await settingsFor(_repo!).load();
      if (!saved.isConfigured) throw const PinRejected();
      final client =
          widget.clientFor?.call(saved.serverUrl!, saved.pin!) ??
          ServerClient(baseUrl: saved.serverUrl!, pin: saved.pin!);
      try {
        return await client.recognizeFormula(png: png, color: color);
      } finally {
        client.close();
      }
    };
  }

  /// Catalog videos stream from the school server with the saved PIN.
  VideoSource? get _videos {
    final settingsFor = widget.settingsFor;
    if (settingsFor == null) return null;
    return (id) async {
      final saved = await settingsFor(_repo!).load();
      if (!saved.isConfigured) throw const PinRejected();
      final client =
          widget.clientFor?.call(saved.serverUrl!, saved.pin!) ??
          ServerClient(baseUrl: saved.serverUrl!, pin: saved.pin!);
      try {
        return client.videoAddress(id);
      } finally {
        client.close();
      }
    };
  }

  MediaImporter? _importerFor(BoardDocument doc) {
    final media = _media, pdf = widget.pdf;
    if (media == null || pdf == null) return null;
    return MediaImporter(doc: doc, store: media, files: widget.files, pdf: pdf);
  }

  /// Closes [doc]; a board that was deleted from the list is only disposed.
  Future<void> _leave(BoardDocument doc) async {
    // Stop showing the board before its controllers are disposed.
    setState(() => _state = _Loading(null));
    if (await _repo!.boardExists(doc.id)) {
      await doc.close();
    } else {
      doc.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _Ready(:final doc) => BoardScreen(
        key: ValueKey(doc.id),
        doc: doc,
        onHome: _goHome,
        importer: _importerFor(doc),
        ai: _aiRunner,
        formulas: _formulas,
        videos: _videos,
        lesson: _lesson,
      ),
      _Loading(:final title) => _LoadingView(
        text: _showLoading
            ? (title == null ? 'Membuka papan…' : 'Membuka papan $title…')
            : null,
      ),
      _Damaged(:final error) => _DamagedView(
        error: error,
        onRestore: () async {
          await _repo!.restoreSnapshot(error.boardId);
          await _open(error.boardId);
        },
        onNew: _create,
      ),
      _Failed() => const _LoadingView(
        text:
            'Papan tidak bisa dibuka. Tutup dan buka aplikasi lagi. '
            'Bila terulang, hubungi operator IT sekolah.',
        danger: true,
      ),
    };
  }
}

/// SCR-01 Memuat: dimmed canvas, text only after 1 second.
class _LoadingView extends StatelessWidget {
  const _LoadingView({this.text, this.danger = false});

  final String? text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: text == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(AppSizes.space24),
                child: Text(
                  text!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppSizes.textBody,
                    color: danger ? AppColors.danger : AppColors.textMuted,
                  ),
                ),
              ),
      ),
    );
  }
}

/// SCR-01 Gagal (papan rusak).
class _DamagedView extends StatelessWidget {
  const _DamagedView({
    required this.error,
    required this.onRestore,
    required this.onNew,
  });

  final BoardCorruptException error;
  final VoidCallback onRestore;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final taken = error.snapshotTakenAt;
    final title = error.title.isEmpty ? '' : '${error.title} ';
    final text = taken == null
        ? 'Papan $title'
              'tidak bisa dibuka karena berkasnya rusak.'
        : 'Papan $title'
              'tidak bisa dibuka karena berkasnya rusak. '
              'Salinan otomatis terakhir pukul ${_wibTime(taken)} masih ada.';
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.danger,
                  size: AppSizes.primaryTarget,
                ),
                const SizedBox(height: AppSizes.space16),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: AppSizes.textBody,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppSizes.space24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSizes.space16,
                  runSpacing: AppSizes.space8,
                  children: [
                    if (taken != null) ...[
                      FilledButton(
                        onPressed: onRestore,
                        child: const Text('Pulihkan salinan'),
                      ),
                    ],
                    (taken == null
                        ? FilledButton(
                            onPressed: onNew,
                            child: const Text('Buat papan baru'),
                          )
                        : OutlinedButton(
                            onPressed: onNew,
                            child: const Text('Buat papan baru'),
                          )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _wibTime(DateTime utc) {
  final wib = utc.toUtc().add(const Duration(hours: 7));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(wib.hour)}.${two(wib.minute)}';
}

class _ShellLessonApi implements LessonApi {
  _ShellLessonApi(this._shell);
  final _AppShellState _shell;

  @override
  Future<String> upload(Uint8List audio, List<String> formulas) =>
      _shell._withClient((c) => c.uploadLesson(audio, formulas));

  @override
  Future<LessonStatus> status(String id) =>
      _shell._withClient((c) => c.lessonStatus(id));
}
