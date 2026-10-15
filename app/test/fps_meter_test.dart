import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/diagnostics/fps_meter.dart';

void main() {
  test('counts only frames while writing and ignores pauses', () {
    var writing = true;
    final meter = FpsMeter(isWriting: () => writing);
    const frame = 16667; // 60 Hz in microseconds

    for (var i = 0; i <= 60; i++) {
      meter.addFrame(i * frame, 8000);
    }
    expect(meter.sessionAverage, closeTo(60, 0.5));

    // Idle frames are not counted.
    writing = false;
    for (var i = 61; i < 120; i++) {
      meter.addFrame(i * frame, 8000);
    }
    expect(meter.sessionAverage, closeTo(60, 0.5));

    // A long pause before writing resumes does not lower the average.
    writing = true;
    for (var i = 0; i <= 30; i++) {
      meter.addFrame(10000000 + i * frame * 2, 8000);
    }
    expect(meter.sessionAverage, lessThan(60));
    expect(meter.sessionAverage, greaterThan(40));
    expect(meter.p90FrameMs, closeTo(8, 0.01));
    meter.dispose();
  });

  test('reset clears the session', () {
    final meter = FpsMeter(isWriting: () => true);
    meter.addFrame(0, 1000);
    meter.addFrame(16667, 1000);
    meter.reset();
    expect(meter.sessionAverage, 0);
    expect(meter.current.value, 0);
    meter.dispose();
  });
}
