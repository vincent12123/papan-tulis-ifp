import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The INTERNET permission lives only in the debug manifest by default; a
  // release APK without it fails Tes koneksi with "tidak bisa terhubung".
  test('release manifest allows network access to the school server', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });
}
