import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/ink_controller.dart';
import '../ui/theme.dart';
import 'device_report.dart';
import 'fps_meter.dart';

/// Measurement tools for testing on the panel (P-01, NFR-30). Only built into
/// test APKs: `flutter build apk --dart-define=DIAGNOSTICS=true`.
const bool kDiagnostics = bool.fromEnvironment('DIAGNOSTICS');

typedef ReportCollector = Future<DeviceReport> Function(FlutterView view);

/// fps readout plus "Isi 3000 goresan" and "Info panel" for the board's top
/// bar.
class DiagnosticsActions extends StatelessWidget {
  const DiagnosticsActions({
    super.key,
    required this.ink,
    required this.fps,
    required this.canvasSize,
    this.collectReport = DeviceReport.collect,
  });

  static const loadTestCount = 3000;

  final InkController ink;
  final FpsMeter fps;
  final Size Function() canvasSize;
  final ReportCollector collectReport;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([fps.current, ink.committedRevision]),
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'fps ${fps.current.value.round()} · '
              'rata-rata ${fps.sessionAverage.toStringAsFixed(1)} · '
              '${ink.strokes.length} goresan',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSizes.space8),
          OutlinedButton(
            onPressed: () {
              ink.addLoadTestStrokes(loadTestCount, canvasSize());
              fps.reset();
            },
            child: const Text('Isi $loadTestCount goresan'),
          ),
          const SizedBox(width: AppSizes.space8),
          OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DeviceReportDialog(
                future: collectReport(View.of(context)),
                ink: ink,
                fps: fps,
              ),
            ),
            child: const Text('Info panel'),
          ),
        ],
      ),
    );
  }
}

class DeviceReportDialog extends StatelessWidget {
  const DeviceReportDialog({
    super.key,
    required this.future,
    required this.ink,
    required this.fps,
  });

  final Future<DeviceReport> future;
  final InkController ink;
  final FpsMeter fps;

  String _measurement() =>
      'Goresan di kanvas: ${ink.strokes.length}\n'
      'fps menulis rata-rata: ${fps.sessionAverage.toStringAsFixed(1)}\n'
      'Waktu frame p90: ${fps.p90FrameMs.toStringAsFixed(1)} ms';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Info panel'),
      content: SizedBox(
        width: 720,
        child: FutureBuilder<DeviceReport>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Text('Membaca info panel…');
            }
            final device = snapshot.hasData
                ? snapshot.data!.toText(
                    maxPointersSeen: ink.maxSimultaneousPointers,
                    stylusSeen: ink.stylusSeen,
                  )
                : 'Info perangkat tidak bisa dibaca di panel ini.';
            final text = '$device\n\n${_measurement()}';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text),
                const SizedBox(height: AppSizes.space16),
                Text(
                  'Foto layar ini atau salin teksnya, lalu kirim ke pengembang.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSizes.space8),
                OutlinedButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                  child: const Text('Salin teks'),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
