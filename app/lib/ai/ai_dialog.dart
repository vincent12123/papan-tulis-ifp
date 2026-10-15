import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../canvas/stroke.dart';
import '../graph/graph_painter.dart';
import '../server/server_client.dart';
import '../ui/theme.dart';
import 'graph_builder.dart';

/// Runs one AI action on a PNG of the area (SPEC 5.7).
typedef AiRunner = Future<AiAnswer> Function(String kind, Uint8List png);

/// What "Tempel ke papan" puts on the board.
sealed class AiPaste {}

class PasteText extends AiPaste {
  PasteText(this.text);
  final String text;
}

class PasteGraph extends AiPaste {
  PasteGraph(this.graph);

  /// Built at a preview rect; the board moves it into place.
  final GraphItem graph;
}

enum AiAction {
  pecahSoal('pecah_soal', 'Pecah soal', 'memecah soal'),
  soalSerupa('soal_serupa', 'Buat soal serupa', 'membuat soal serupa'),
  ringkas('ringkas', 'Ringkas papan', 'meringkas papan'),
  grafik('grafik', 'Jadikan grafik', 'membuat grafik');

  const AiAction(this.kind, this.label, this.doing);
  final String kind;
  final String label;
  final String doing;

  /// Needs a circled area (Ringkas papan can use the whole page).
  bool get needsArea => this != AiAction.ringkas;
}

/// SCR-05 Asisten AI.
class AiDialog extends StatefulWidget {
  const AiDialog({
    super.key,
    required this.run,
    required this.capture,
    required this.hasArea,
  });

  final AiRunner run;

  /// PNG of the circled area, or of the visible page for Ringkas papan
  /// without an area.
  final Future<Uint8List?> Function() capture;
  final bool hasArea;

  static const reminder = 'Periksa hasil AI sebelum dipakai mengajar.';
  static const privacy =
      'Isi area yang dipilih dikirim ke layanan AI di internet. '
      'Jangan sertakan nama siswa.';
  static const noAreaSoal =
      'Lingkari soal di papan dulu dengan alat Pilih, lalu ketuk Asisten AI lagi.';
  static const noAreaGrafik =
      'Lingkari rumus di papan dulu dengan alat Pilih, lalu ketuk Asisten AI lagi.';
  static const offline =
      'AI belum bisa menjawab karena panel tidak terhubung ke server sekolah. '
      'Area Anda tidak berubah. Tekan Coba lagi.';
  static const unavailable =
      'AI sedang tidak tersedia. Papan Anda tidak berubah. '
      'Coba lagi beberapa menit lagi.';
  static const timedOut =
      'AI tidak menjawab dalam 60 detik. Papan Anda tidak berubah. '
      'Tekan Coba lagi.';
  static const notAllowed =
      'Panel belum diizinkan memakai AI. Periksa PIN admin di Pengaturan.';
  static const noFormula =
      'AI tidak menemukan rumus fungsi yang bisa digambar di area ini. '
      'Tulis rumus seperti y = x² − 3, lalu coba lagi.';
  static String busy(AiAction a) =>
      'AI sedang mengerjakan ${a.doing}… Biasanya sampai 30 detik.';
  static String fellBack(String name) =>
      '$name sedang bermasalah, jadi jawaban ini dari Ollama cloud.';
  static String noLongerAvailable(String name) =>
      '$name tidak lagi tersedia. AI memakai Ollama cloud untuk sementara.';

  @override
  State<AiDialog> createState() => _AiDialogState();
}

class _AiDialogState extends State<AiDialog> {
  AiAction? _running;
  AiAction? _last;
  String? _error;
  String? _empty;
  AiAnswer? _answer;
  GraphItem? _graph;
  int _attempt = 0;

  static const _previewSize = Size(720, 450);

  Future<void> _run(AiAction action) async {
    if (action.needsArea && !widget.hasArea) {
      setState(() {
        _empty = action == AiAction.grafik
            ? AiDialog.noAreaGrafik
            : AiDialog.noAreaSoal;
        _error = null;
      });
      return;
    }
    final attempt = ++_attempt;
    setState(() {
      _running = action;
      _last = action;
      _error = null;
      _empty = null;
      _answer = null;
      _graph = null;
    });
    String? error;
    AiAnswer? answer;
    GraphItem? graph;
    try {
      final png = await widget.capture();
      if (png == null) throw const ServerError();
      answer = await widget.run(action.kind, png);
      if (action == AiAction.grafik) {
        graph = answer.graph == null
            ? null
            : buildGraph(
                answer.graph!,
                Offset.zero & _previewSize,
                'pratinjau',
              );
        if (graph == null) throw const NoFormulaFound();
      }
    } on ServerFailure catch (f) {
      error = switch (f) {
        ServerUnreachable() => AiDialog.offline,
        AiTimedOut() => AiDialog.timedOut,
        PinRejected() || PinNotSetOnServer() => AiDialog.notAllowed,
        NoFormulaFound() => AiDialog.noFormula,
        PinLocked() => 'PIN salah 5 kali. Coba lagi dalam 5 menit.',
        _ => AiDialog.unavailable,
      };
    }
    // Batalkan (or a newer request) makes this answer stale.
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _running = null;
      _error = error;
      _answer = answer;
      _graph = graph;
    });
  }

  void _cancel() => setState(() {
    _attempt++;
    _running = null;
  });

  void _paste() {
    final graph = _graph;
    final text = _answer?.text;
    if (graph != null) {
      Navigator.pop<AiPaste>(context, PasteGraph(graph));
    } else if (text != null) {
      Navigator.pop<AiPaste>(context, PasteText(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answer = _answer;
    final busy = _running != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.space24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 900),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Asisten AI',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (answer != null)
                Text(
                  'Memakai: ${answer.providerName} · ${answer.model}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: AppSizes.space12),
              Row(
                children: [
                  Icon(
                    widget.hasArea ? Icons.check_circle : Icons.info_outline,
                    color: widget.hasArea
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSizes.space8),
                  Expanded(
                    child: Text(
                      widget.hasArea ? 'Area terpilih' : 'Belum ada area terpilih. Ringkas papan memakai seluruh halaman.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.space12),
              Wrap(
                spacing: AppSizes.space8,
                runSpacing: AppSizes.space8,
                children: [
                  for (final a in AiAction.values)
                    OutlinedButton(
                      onPressed: busy ? null : () => _run(a),
                      child: Text(a.label),
                    ),
                ],
              ),
              const Divider(height: AppSizes.space32),
              Flexible(child: _body(theme)),
              const SizedBox(height: AppSizes.space16),
              Text(AiDialog.privacy, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    final running = _running;
    if (running != null) {
      return Row(
        children: [
          const SizedBox(
            width: AppSizes.toolIcon,
            height: AppSizes.toolIcon,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: AppSizes.space16),
          Expanded(
            child: Text(
              AiDialog.busy(running),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          OutlinedButton(onPressed: _cancel, child: const Text('Batalkan')),
        ],
      );
    }
    if (_empty != null) {
      return Text(_empty!, style: theme.textTheme.bodyLarge);
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: const TextStyle(
              fontSize: AppSizes.textBody,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSizes.space12),
          if (_last != null)
            FilledButton(
              onPressed: () => _run(_last!),
              child: const Text('Coba lagi'),
            ),
        ],
      );
    }
    final answer = _answer;
    if (answer == null) return const SizedBox.shrink();
    final note = switch ((answer.fallbackReason, answer.fallbackFromName)) {
      (null, _) || (_, null) => null,
      ('tidak_aktif', final name?) => AiDialog.noLongerAvailable(name),
      (_, final name?) => AiDialog.fellBack(name),
    };
    final graph = _graph;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hasil:', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSizes.space8),
        Flexible(
          child: graph != null
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: AspectRatio(
                      aspectRatio: _previewSize.aspectRatio,
                      child: CustomPaint(painter: _GraphPreview(graph)),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    answer.text ?? '',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
        ),
        const SizedBox(height: AppSizes.space8),
        Text(AiDialog.reminder, style: theme.textTheme.bodySmall),
        if (note != null) Text(note, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSizes.space12),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() {
                _answer = null;
                _graph = null;
              }),
              child: const Text('Buang'),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSizes.primaryTarget),
              ),
              onPressed: _paste,
              child: const Text('Tempel ke papan'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The graph as it will look on the board, scaled into the dialog.
class _GraphPreview extends CustomPainter {
  _GraphPreview(this.graph);
  final GraphItem graph;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / graph.rect.width;
    canvas
      ..save()
      ..scale(scale);
    paintGraph(canvas, graph);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPreview old) => old.graph != graph;
}
