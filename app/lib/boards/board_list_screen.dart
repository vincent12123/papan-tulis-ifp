import 'package:flutter/material.dart';

import '../board/board_title.dart';
import '../data/board_repository.dart';
import '../ui/notices.dart';
import '../server/settings_store.dart';
import '../settings/settings_screen.dart';
import '../ui/theme.dart';

/// What the teacher chose on the board list.
sealed class BoardListResult {}

class OpenBoard extends BoardListResult {
  OpenBoard(this.id);
  final String id;
}

class NewBoard extends BoardListResult {}

/// SCR-02 Daftar Papan ("Papan saya"). Pengaturan (SCR-06) is added with
/// Checkpoint 5.
class BoardListScreen extends StatefulWidget {
  const BoardListScreen({
    super.key,
    required this.repo,
    required this.currentId,
    this.settings,
    this.clientFor,
  });

  final BoardRepository repo;

  /// The board that is open behind this screen.
  final String currentId;

  /// Pengaturan (SCR-06); null hides the button (tests without storage).
  final SettingsStore? settings;
  final ClientFactory? clientFor;

  static const emptyText =
      'Belum ada papan. Ketuk Papan baru untuk mulai menulis.';
  static const errorText =
      'Daftar papan tidak bisa dimuat. Tutup dan buka aplikasi lagi. '
      'Bila terulang, hubungi operator IT sekolah.';

  @override
  State<BoardListScreen> createState() => _BoardListScreenState();
}

class _BoardListScreenState extends State<BoardListScreen> {
  late Future<List<BoardSummary>> _boards = widget.repo.listBoards();
  bool _currentDeleted = false;

  void _reload() => setState(() {
    _boards = widget.repo.listBoards();
  });

  Future<void> _rename(BoardSummary board) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: board.title),
    );
    if (title == null || !mounted) return;
    try {
      await widget.repo.renameBoard(board.id, title);
      if (!mounted) return;
      Notices.success(context, 'Nama papan diubah.');
      _reload();
    } on StorageFullException {
      if (mounted) {
        Notices.failure(
          context,
          'Nama papan belum tersimpan karena ruang penyimpanan panel penuh.',
        );
      }
    }
  }

  Future<void> _delete(BoardSummary board) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus papan ${board.title}?'),
        content: Text(
          'Seluruh ${board.pageCount} halamannya ikut terhapus dan tidak bisa dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.repo.deleteBoard(board.id);
    if (!mounted) return;
    if (board.id == widget.currentId) _currentDeleted = true;
    Notices.success(context, 'Papan ${board.title} dihapus.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // If the open board was deleted there is nothing to go back to: a new
      // board is opened instead.
      canPop: !_currentDeleted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop<BoardListResult>(context, NewBoard());
      },
      child: Scaffold(
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
                      if (!_currentDeleted)
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Kembali ke papan'),
                        ),
                      const SizedBox(width: AppSizes.space16),
                      Expanded(
                        child: Text(
                          'Papan saya',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (widget.settings != null)
                        TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SettingsScreen(
                                store: widget.settings!,
                                clientFor: widget.clientFor,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Pengaturan'),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.space24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSizes.primaryTarget),
                    ),
                    onPressed: () =>
                        Navigator.pop<BoardListResult>(context, NewBoard()),
                    icon: const Icon(Icons.add),
                    label: const Text('Papan baru'),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<BoardSummary>>(
                  future: _boards,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _Skeleton();
                    }
                    if (snapshot.hasError) {
                      return _Message(BoardListScreen.errorText, danger: true);
                    }
                    final boards = snapshot.data!;
                    if (boards.isEmpty) {
                      return const _Message(BoardListScreen.emptyText);
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.space24,
                        0,
                        AppSizes.space24,
                        AppSizes.space24,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 360,
                            mainAxisSpacing: AppSizes.space16,
                            crossAxisSpacing: AppSizes.space16,
                            childAspectRatio: 0.95,
                          ),
                      itemCount: boards.length,
                      itemBuilder: (context, i) => _BoardCard(
                        board: boards[i],
                        isCurrent: boards[i].id == widget.currentId,
                        onOpen: () => Navigator.pop<BoardListResult>(
                          context,
                          OpenBoard(boards[i].id),
                        ),
                        onRename: () => _rename(boards[i]),
                        onDelete: () => _delete(boards[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatWib(DateTime utc) {
  final title = defaultBoardTitle(utc); // "Papan 14 Okt 2026 11.30"
  return title.substring('Papan '.length);
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.isCurrent,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final BoardSummary board;
  final bool isCurrent;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
                  ),
                  child: board.thumbnail == null
                      ? null
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSizes.radiusSmall,
                          ),
                          child: Image.memory(
                            board.thumbnail!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            semanticLabel: 'Gambar mini ${board.title}',
                          ),
                        ),
                ),
              ),
              const SizedBox(height: AppSizes.space8),
              Text(
                board.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${board.pageCount} hlm · ${_formatWib(board.updatedAt)}'
                '${isCurrent ? ' · sedang dibuka' : ''}',
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Ganti nama ${board.title}',
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Hapus ${board.title}',
                    color: AppColors.danger,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Nama papan tidak boleh kosong.');
      return;
    }
    Navigator.pop(context, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganti nama papan'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _text,
          autofocus: true,
          style: const TextStyle(fontSize: AppSizes.textBody),
          decoration: InputDecoration(
            labelText: 'Nama papan',
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.space24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppSizes.textBody,
            color: danger ? AppColors.danger : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Grey card shapes while boards load (SCR-02 Memuat).
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat daftar papan',
      child: GridView.count(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.space24),
        crossAxisCount: 4,
        mainAxisSpacing: AppSizes.space16,
        crossAxisSpacing: AppSizes.space16,
        childAspectRatio: 0.95,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 4; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
              ),
            ),
        ],
      ),
    );
  }
}
