import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../server/server_client.dart';
import '../ui/theme.dart';
import '../peraga/peraga_specs.dart';
import '../solid/solid_geometry.dart';
import 'board_document.dart';
import 'smart_suggest.dart';

/// Sends a circled area (PNG) and its ink color to the school server.
typedef FormulaRecognizer = Future<FormulaInsight> Function(
  Uint8List png,
  String color,
);

/// Reads a circled area on the school server (REQ-22).
typedef AreaRecognizer = Future<FormulaInsight> Function(Rect area);

/// What the bar under a circled area does with the server's answer.
class SmartActions {
  const SmartActions({
    required this.onGraph,
    required this.onTidy,
    required this.onSolve,
    this.onVideo,
    this.onPeraga,
    this.onSketch,
  });

  final void Function(Rect area, FormulaInsight insight) onGraph;
  final Future<void> Function(Rect area, FormulaInsight insight) onTidy;
  final void Function(Rect area, FormulaInsight insight) onSolve;

  /// Opens the matching school videos (kimia, REQ-24).
  final void Function(FormulaInsight insight)? onVideo;

  /// Places a simulation or lab that fits the formulas (REQ-26, REQ-28).
  final void Function(Rect area, PeragaKind kind)? onPeraga;

  /// Turns a sketched shape into a solid (REQ-23).
  final void Function(SketchHit sketch, SolidKind kind)? onSketch;
}

/// Menu pintar (SPEC 1.9, ux-flow 1.5): as soon as an area is circled with
/// Pilih, the bar under it shows "Mengenali…", then only the actions that fit
/// what is written there. Like the reference video, no dialog.
class SmartAreaBar extends StatefulWidget {
  const SmartAreaBar({
    super.key,
    required this.page,
    required this.recognize,
    required this.actions,
    this.sketch,
  });

  final PageState page;

  /// A sketched shape in the circle, found on the panel (no server).
  final SketchHit? Function(Rect area)? sketch;
  final AreaRecognizer recognize;
  final SmartActions actions;

  static const reading = 'Mengenali…';
  static const graph = 'Jadikan grafik';
  static const tidy = 'Rapikan rumus';
  static const solve = 'Selesaikan';
  static const balance = 'Setarakan';
  static String videos(int n) => 'Video eksperimen ($n)';
  static String peraga(String name) => 'Peraga: $name';
  static String makeSolid(String name) => 'Jadikan $name';
  static const retry = 'Coba lagi';
  static const noFormula =
      'Tidak ada rumus yang dikenali. Tulis lebih jelas, lalu lingkari lagi.';
  static const offline = 'Panel tidak terhubung ke server sekolah.';
  static const notAllowed =
      'Panel belum terhubung ke server. Periksa alamat dan PIN admin di '
      'Pengaturan.';
  static const unavailable =
      'Pengenal rumus sedang tidak tersedia. Coba lagi beberapa menit lagi.';
  static const locked = 'PIN salah 5 kali. Coba lagi dalam 5 menit.';

  static String messageFor(ServerFailure f) => switch (f) {
    ServerUnreachable() => offline,
    PinRejected() || PinNotSetOnServer() => notAllowed,
    PinLocked() => locked,
    NoFormulaFound() || ServerValidation() => noFormula,
    _ => unavailable,
  };

  @override
  State<SmartAreaBar> createState() => _SmartAreaBarState();
}

class _SmartAreaBarState extends State<SmartAreaBar> {
  Rect? _area;
  SketchHit? _sketch;
  FormulaInsight? _insight;
  String? _error;
  bool _busy = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    widget.page.ink.area.addListener(_areaChanged);
    _areaChanged();
  }

  @override
  void didUpdateWidget(SmartAreaBar old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      old.page.ink.area.removeListener(_areaChanged);
      widget.page.ink.area.addListener(_areaChanged);
      _areaChanged();
    }
  }

  @override
  void dispose() {
    widget.page.ink.area.removeListener(_areaChanged);
    super.dispose();
  }

  void _areaChanged() {
    final area = widget.page.ink.area.value;
    if (area == _area) return;
    _area = area;
    _sketch = area == null ? null : widget.sketch?.call(area);
    if (area == null) {
      _attempt++;
      setState(() {
        _insight = null;
        _error = null;
        _busy = false;
      });
      return;
    }
    _recognize(area);
  }

  Future<void> _recognize(Rect area) async {
    final attempt = ++_attempt;
    setState(() {
      _insight = null;
      _error = null;
      _busy = true;
    });
    FormulaInsight? insight;
    String? error;
    try {
      insight = await widget.recognize(area);
    } on ServerFailure catch (f) {
      error = SmartAreaBar.messageFor(f);
    }
    // A newer circle (or none) makes this answer stale.
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _busy = false;
      _insight = insight;
      _error = error;
    });
  }

  Future<void> _run(Future<void> Function(Rect, FormulaInsight) action) async {
    final area = _area;
    final insight = _insight;
    if (area == null || insight == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(area, insight);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _sketchButtons() {
    final sketch = _sketch;
    final make = widget.actions.onSketch;
    if (sketch == null || make == null) return const [];
    return [
      for (final kind in sketch.kinds)
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppSizes.primaryTarget),
          ),
          onPressed: () => make(sketch, kind),
          icon: const Icon(Icons.view_in_ar),
          label: Text(SmartAreaBar.makeSolid(kind.label)),
        ),
    ];
  }

  List<Widget> _buttons() => [..._sketchButtons(), ..._formulaButtons()];

  List<Widget> _formulaButtons() {
    final insight = _insight;
    // A sketch is not a formula: no "nothing recognized" next to its buttons.
    final error = _error == SmartAreaBar.noFormula && _sketch != null
        ? null
        : _error;
    if (_busy && insight == null) {
      return [
        FilledButton.tonalIcon(
          onPressed: null,
          icon: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          label: Text(SmartAreaBar.reading),
        ),
      ];
    }
    if (error != null) {
      return [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: AppColors.surface,
            elevation: AppSizes.elevation,
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.space16,
                vertical: AppSizes.space8,
              ),
              child: Text(error, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
        if (error != SmartAreaBar.noFormula)
          OutlinedButton(
            onPressed: () => _recognize(_area!),
            child: const Text(SmartAreaBar.retry),
          ),
      ];
    }
    if (insight == null) return const [];
    final actions = widget.actions;
    final enabled = !_busy;
    FilledButton primary(String label, IconData icon, VoidCallback onTap) =>
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppSizes.primaryTarget),
          ),
          onPressed: enabled ? onTap : null,
          icon: Icon(icon),
          label: Text(label),
        );
    return [
      if (insight.kind == 'fungsi' && insight.graph != null)
        primary(
          SmartAreaBar.graph,
          Icons.show_chart,
          () => _run((a, i) async => actions.onGraph(a, i)),
        ),
      primary(
        SmartAreaBar.tidy,
        Icons.auto_fix_high,
        () => _run(actions.onTidy),
      ),
      if (insight.solution != null)
        primary(
          insight.kind == 'kimia' ? SmartAreaBar.balance : SmartAreaBar.solve,
          insight.kind == 'kimia' ? Icons.balance : Icons.calculate_outlined,
          () => _run((a, i) async => actions.onSolve(a, i)),
        ),
      if (actions.onPeraga != null)
        for (final kind in peragaFor(insight))
          primary(
            SmartAreaBar.peraga(kind.label),
            Icons.science_outlined,
            () => _run((a, i) async => actions.onPeraga!(a, kind)),
          ),
      if (insight.videos.isNotEmpty && actions.onVideo != null)
        primary(
          SmartAreaBar.videos(insight.videos.length),
          Icons.ondemand_video,
          () => actions.onVideo!(insight),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: page.view.revision,
        builder: (context, _) {
          final area = _area;
          final buttons = _buttons();
          if (area == null || buttons.isEmpty) return const SizedBox.shrink();
          final below = page.view.toScreen(area.bottomLeft);
          final above = page.view.toScreen(area.topLeft);
          const gap = AppSizes.space16;
          const h = AppSizes.primaryTarget;
          // Under the area like the video; above it when there is no room.
          final top = below.dy + gap + h <= box.maxHeight
              ? below.dy + gap
              : math.max(0.0, above.dy - gap - h);
          final width = math.min(box.maxWidth, 720.0);
          final left = below.dx
              .clamp(0.0, math.max(0.0, box.maxWidth - width))
              .toDouble();
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Wrap(
                  spacing: AppSizes.space8,
                  runSpacing: AppSizes.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: buttons,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
