import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'lesson_session.dart';

/// Rekam kelas texts (ux-flow 1.6, usulan).
abstract final class LessonTexts {
  static const record = 'Rekam';
  static String recording(Duration d) => 'Merekam ${_clock(d)} · Selesai';
  static const processing = 'Ringkasan diproses…';
  static const ready = 'Ringkasan siap';
  static const failed = 'Ringkasan gagal';

  static const consentTitle = 'Rekam pelajaran?';
  static const consentBody =
      'Suara di kelas akan direkam lalu dikirim ke server sekolah untuk '
      'dibuat ringkasan. Rekaman dihapus setelah diolah. Hindari menyebut '
      'nama atau data pribadi siswa.';
  static const cancel = 'Batal';
  static const start = 'Mulai rekam';

  static const resultTitle = 'Ringkasan pelajaran';
  static const discard = 'Buang';
  static const paste = 'Tempel ke papan';
  static const retry = 'Coba lagi';
  static const reminder = 'Periksa ringkasan sebelum dibagikan ke siswa.';

  static String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The top-bar control: Rekam → Merekam 12:34 · Selesai → Ringkasan
/// diproses… → Ringkasan siap / gagal. Never blocks writing.
class LessonButton extends StatelessWidget {
  const LessonButton({
    super.key,
    required this.session,
    required this.onStart,
    required this.onOpen,
  });

  final LessonSession session;
  final VoidCallback onStart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => switch (session.phase) {
      LessonPhase.idle => OutlinedButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.mic_none),
        label: const Text(LessonTexts.record),
      ),
      LessonPhase.recording => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
        onPressed: session.stop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(LessonTexts.recording(session.elapsed)),
      ),
      LessonPhase.sending || LessonPhase.processing => FilledButton.tonalIcon(
        onPressed: null,
        icon: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        label: Text(LessonTexts.processing),
      ),
      LessonPhase.ready => FilledButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.summarize_outlined),
        label: const Text(LessonTexts.ready),
      ),
      LessonPhase.failed => OutlinedButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.error_outline, color: AppColors.danger),
        label: const Text(LessonTexts.failed),
      ),
    },
  );
}

/// Asks before recording a class (privacy, REQ-25).
Future<bool> confirmLessonRecording(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LessonTexts.consentTitle),
        content: const Text(LessonTexts.consentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(LessonTexts.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(LessonTexts.start),
          ),
        ],
      ),
    ) ??
    false;

enum LessonChoice { discard, paste, retry }

/// The summary (or why it failed), with Buang / Tempel ke papan / Coba lagi.
class LessonResultDialog extends StatelessWidget {
  const LessonResultDialog({super.key, required this.session});

  final LessonSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = session.summary;
    final ok = session.phase == LessonPhase.ready && summary != null;
    return AlertDialog(
      title: const Text(LessonTexts.resultTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ok ? summary : session.error ?? LessonSession.failedGeneric,
                style: theme.textTheme.bodyLarge,
              ),
              if (ok) ...[
                const SizedBox(height: AppSizes.space16),
                Text(LessonTexts.reminder, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, LessonChoice.discard),
          child: const Text(LessonTexts.discard),
        ),
        if (!ok && session.canRetry)
          OutlinedButton(
            onPressed: () => Navigator.pop(context, LessonChoice.retry),
            child: const Text(LessonTexts.retry),
          ),
        if (ok)
          FilledButton(
            onPressed: () => Navigator.pop(context, LessonChoice.paste),
            child: const Text(LessonTexts.paste),
          ),
      ],
    );
  }
}
