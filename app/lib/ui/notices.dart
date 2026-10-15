import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Small bar at the top center (ux-flow §6 Notifikasi berhasil): above the
/// canvas instead of the bottom so it never covers the toolbar.
/// Success notices close after 4 seconds; failures stay until closed.
class Notices {
  Notices._();

  static const successDuration = Duration(seconds: 4);
  static OverlayEntry? _entry;

  static void success(BuildContext context, String text) =>
      _show(context, text, AppColors.success, persistent: false);

  static void failure(BuildContext context, String text) =>
      _show(context, text, AppColors.danger, persistent: true);

  /// Something worth reading that is not an error; stays until closed.
  static void warning(BuildContext context, String text) =>
      _show(context, text, AppColors.warning, persistent: true);

  static void _show(
    BuildContext context,
    String text,
    Color color, {
    required bool persistent,
  }) {
    hide();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _NoticeBar(
        text: text,
        color: color,
        persistent: persistent,
        onDone: () {
          if (identical(_entry, entry)) hide();
        },
      ),
    );
    overlay.insert(entry);
    _entry = entry;
  }

  static void hide() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

/// Owns its own timer so it is cancelled with the widget tree.
class _NoticeBar extends StatefulWidget {
  const _NoticeBar({
    required this.text,
    required this.color,
    required this.persistent,
    required this.onDone,
  });

  final String text;
  final Color color;
  final bool persistent;
  final VoidCallback onDone;

  @override
  State<_NoticeBar> createState() => _NoticeBarState();
}

class _NoticeBarState extends State<_NoticeBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.persistent) {
      _timer = Timer(Notices.successDuration, widget.onDone);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: AppSizes.space16,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Material(
            color: widget.color,
            elevation: AppSizes.elevation,
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.space16,
                vertical: AppSizes.space8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.persistent
                        ? Icons.error_outline
                        : Icons.check_circle,
                    color: AppColors.onPrimary,
                  ),
                  const SizedBox(width: AppSizes.space8),
                  Flexible(
                    child: Text(
                      widget.text,
                      style: const TextStyle(
                        fontSize: AppSizes.textBody,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                  if (widget.persistent) ...[
                    const SizedBox(width: AppSizes.space8),
                    IconButton(
                      tooltip: 'Tutup',
                      color: AppColors.onPrimary,
                      onPressed: widget.onDone,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
