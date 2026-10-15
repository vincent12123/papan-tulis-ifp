import 'package:flutter/material.dart';

import '../ui/notices.dart';
import '../ui/theme.dart';
import 'board_document.dart';
import 'page_thumbnail.dart';

/// SCR-03 Panel Halaman: slides in from the left edge over the board.
/// Tap a thumbnail to open that page; long-press and drag to reorder.
class PagePanel extends StatelessWidget {
  const PagePanel({
    super.key,
    required this.doc,
    required this.screen,
    required this.onClose,
    required this.onSetBackground,
    required this.onRemoveBackground,
  });

  final BoardDocument doc;
  final Size screen;
  final VoidCallback onClose;

  /// Pasang latar: pick a PDF or picture for the open page (TSK-04).
  final VoidCallback onSetBackground;

  /// Lepas latar: remove the open page's background.
  final VoidCallback onRemoveBackground;

  static const width = 320.0;

  Future<void> _confirmDelete(BuildContext context) async {
    final number = doc.current.value + 1;
    if (doc.pages.length <= 1) {
      Notices.failure(context, 'Papan harus punya minimal satu halaman.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus halaman $number?'),
        content: const Text('Tulisan dan gambar di halaman ini ikut terhapus.'),
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
    if (ok == true) doc.deletePage(number - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      child: SizedBox(
        width: width,
        child: ListenableBuilder(
          listenable: Listenable.merge([doc.pagesRevision, doc.current]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.space16,
                  AppSizes.space8,
                  AppSizes.space4,
                  AppSizes.space8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Halaman',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup panel Halaman',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.space16,
                  ),
                  itemCount: doc.pages.length,
                  onReorderItem: doc.movePage,
                  itemBuilder: (context, i) {
                    final page = doc.pages[i];
                    final open = i == doc.current.value;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(page.id),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSizes.space12,
                        ),
                        child: Semantics(
                          button: true,
                          selected: open,
                          label:
                              'Halaman ${i + 1}${open ? ', sedang dibuka' : ''}',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: () => doc.goTo(i),
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusMedium,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(AppSizes.space4),
                              decoration: BoxDecoration(
                                color: open ? AppColors.primaryContainer : null,
                                border: Border.all(
                                  color: open
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: open ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radiusMedium,
                                ),
                              ),
                              child: Column(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: PageThumbnail(
                                      ink: page.ink,
                                      screen: screen,
                                      media: doc.images,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.space4),
                                  Text(
                                    open ? '${i + 1} · dibuka' : '${i + 1}',
                                    style: TextStyle(
                                      fontSize: AppSizes.textBody,
                                      fontWeight: open
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: open
                                          ? AppColors.primary
                                          : AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        final n = doc.addPage();
                        Notices.success(context, 'Halaman $n ditambahkan.');
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Halaman baru'),
                    ),
                    const SizedBox(height: AppSizes.space8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final source = doc.current.value + 1;
                              doc.duplicatePage(source - 1);
                              Notices.success(
                                context,
                                'Halaman $source diduplikat.',
                              );
                            },
                            child: const Text('Duplikat'),
                          ),
                        ),
                        const SizedBox(width: AppSizes.space8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                            onPressed: () => _confirmDelete(context),
                            child: const Text('Hapus'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.space8),
                    if (doc.page.background == null)
                      OutlinedButton.icon(
                        onPressed: onSetBackground,
                        icon: const Icon(Icons.wallpaper),
                        label: const Text('Pasang latar'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: onRemoveBackground,
                        icon: const Icon(Icons.layers_clear_outlined),
                        label: const Text('Lepas latar'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
