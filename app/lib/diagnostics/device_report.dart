import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// Facts about the panel needed to close SPEC P-01 (Checkpoint 1).
class DeviceReport {
  const DeviceReport({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.screenPixels,
    required this.devicePixelRatio,
    required this.multitouchFeature,
    required this.stylusFeature,
    required this.hasPlayServices,
    required this.hasPlayStore,
  });

  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final Size screenPixels;
  final double devicePixelRatio;

  /// Highest multitouch level the system declares, in Indonesian.
  final String multitouchFeature;
  final bool stylusFeature;
  final bool? hasPlayServices;
  final bool? hasPlayStore;

  String toText({required int maxPointersSeen, required bool stylusSeen}) {
    String yesNo(bool? v) =>
        v == null ? 'tidak diketahui' : (v ? 'ada' : 'tidak ada');
    return [
      'Merek / model: $manufacturer $model',
      'Android: $androidVersion (API $sdkInt)',
      'Resolusi layar: ${screenPixels.width.round()} × ${screenPixels.height.round()} piksel '
          '(rasio ${devicePixelRatio.toStringAsFixed(2)})',
      'Multi-sentuh menurut sistem: $multitouchFeature',
      'Jari bersamaan terbanyak yang tercatat: $maxPointersSeen',
      'Stylus menurut sistem: ${stylusFeature ? 'didukung' : 'tidak dinyatakan'}; '
          'stylus terdeteksi saat menulis: ${stylusSeen ? 'ya' : 'belum'}',
      'Google Play Services: ${yesNo(hasPlayServices)}',
      'Play Store: ${yesNo(hasPlayStore)}',
    ].join('\n');
  }

  static const _channel = MethodChannel('whiteboard_ifp/device');

  static Future<DeviceReport> collect(FlutterView view) async {
    final info = await DeviceInfoPlugin().androidInfo;
    final features = info.systemFeatures.toSet();
    String multitouch;
    if (features.contains('android.hardware.touchscreen.multitouch.jazzhand')) {
      multitouch = '5 titik atau lebih';
    } else if (features.contains(
      'android.hardware.touchscreen.multitouch.distinct',
    )) {
      multitouch = '2 titik terpisah';
    } else if (features.contains('android.hardware.touchscreen.multitouch')) {
      multitouch = '2 titik';
    } else {
      multitouch = 'tidak dinyatakan';
    }
    return DeviceReport(
      manufacturer: info.manufacturer,
      model: info.model,
      androidVersion: info.version.release,
      sdkInt: info.version.sdkInt,
      screenPixels: view.physicalSize,
      devicePixelRatio: view.devicePixelRatio,
      multitouchFeature: multitouch,
      stylusFeature: features.any(
        (f) => f.contains('stylus') || f.contains('pen'),
      ),
      hasPlayServices: await _installed('com.google.android.gms'),
      hasPlayStore: await _installed('com.android.vending'),
    );
  }

  static Future<bool?> _installed(String name) async {
    try {
      return await _channel.invokeMethod<bool>('isPackageInstalled', {
        'name': name,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
