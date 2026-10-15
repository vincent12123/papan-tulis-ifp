import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Measures frame rate while writing, for calibrating NFR-30 on the panel
/// (Checkpoint 1). Frames are only counted while [isWriting] is true, so idle
/// time between strokes does not drag the average down.
class FpsMeter {
  FpsMeter({required this.isWriting});

  final bool Function() isWriting;

  /// Frames per second over the last second of writing.
  final ValueNotifier<double> current = ValueNotifier(0);

  int _sessionFrames = 0;
  int _sessionMicros = 0;
  int? _lastVsync;
  final List<int> _window = [];
  final List<int> _frameMicros = [];
  bool _attached = false;

  /// Average fps over all writing since the last [reset].
  double get sessionAverage =>
      _sessionMicros == 0 ? 0 : _sessionFrames * 1e6 / _sessionMicros;

  /// 90th percentile of build+raster time in milliseconds.
  double get p90FrameMs {
    if (_frameMicros.isEmpty) return 0;
    final sorted = [..._frameMicros]..sort();
    return sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)] /
        1000;
  }

  void start() {
    if (_attached) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _attached = true;
  }

  void reset() {
    _sessionFrames = 0;
    _sessionMicros = 0;
    _lastVsync = null;
    _window.clear();
    _frameMicros.clear();
    current.value = 0;
  }

  @visibleForTesting
  void addFrame(int vsyncMicros, int totalMicros) {
    if (!isWriting()) {
      _lastVsync = null;
      return;
    }
    final last = _lastVsync;
    // Gaps over 250 ms mean writing paused; don't count them as frame time.
    if (last != null && vsyncMicros - last < 250000) {
      _sessionFrames++;
      _sessionMicros += vsyncMicros - last;
    }
    _lastVsync = vsyncMicros;
    _frameMicros.add(totalMicros);
    if (_frameMicros.length > 5000) _frameMicros.removeAt(0);
    _window.add(vsyncMicros);
    while (_window.isNotEmpty && vsyncMicros - _window.first > 1000000) {
      _window.removeAt(0);
    }
    current.value = _window.length.toDouble();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      addFrame(
        t.timestampInMicroseconds(FramePhase.vsyncStart),
        t.totalSpan.inMicroseconds,
      );
    }
  }

  void dispose() {
    if (_attached) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    current.dispose();
  }
}
