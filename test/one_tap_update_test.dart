import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/version/one_tap_update.dart';

void main() {
  test('picks the release asset for this device', () {
    expect(oneTapAssetName(os: 'android', abi: Abi.androidArm64, windowsInstalled: false), 'android-arm64-v8a');
    expect(oneTapAssetName(os: 'android', abi: Abi.androidArm, windowsInstalled: false), 'android-armeabi-v7a');
    expect(oneTapAssetName(os: 'windows', abi: Abi.windowsX64, windowsInstalled: true), 'windows-x64-setup.exe');
    expect(oneTapAssetName(os: 'windows', abi: Abi.windowsX64, windowsInstalled: false), isNull);
    expect(oneTapAssetName(os: 'linux', abi: Abi.linuxX64, windowsInstalled: false), isNull);
  });
}
