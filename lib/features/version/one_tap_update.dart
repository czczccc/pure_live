import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/download_apk_dialog.dart';
import 'package:pure_live/features/version/app_update_flow.dart';

/// The release asset name this device installs, or null when it has no
/// one-tap update (portable builds, other platforms).
String? oneTapAssetName({required String os, required Abi abi, required bool windowsInstalled}) {
  if (os == 'android') {
    return switch (abi) {
      Abi.androidArm64 => 'android-arm64-v8a',
      Abi.androidArm => 'android-armeabi-v7a',
      Abi.androidX64 => 'android-x86_64',
      _ => null,
    };
  }
  if (os == 'windows' && windowsInstalled) return 'windows-x64-setup.exe';
  return null;
}

/// An Inno Setup install leaves its uninstaller beside the executable; a
/// portable zip does not, and must not be replaced by the installer.
bool get _windowsInstalled {
  final dir = p.dirname(Platform.resolvedExecutable);
  return File(p.join(dir, 'unins000.exe')).existsSync();
}

/// Downloads the new version and starts its installer in one step. Falls
/// back to the version page, where the user picks a package, when this
/// device has no matching asset.
Future<void> runOneTapUpdate() async {
  final name = oneTapAssetName(
    os: Platform.operatingSystem,
    abi: Abi.current(),
    windowsInstalled: Platform.isWindows && _windowsInstalled,
  );
  String? url;
  if (name != null) {
    await VersionUtil().checkUpdate();
    for (final asset in VersionUtil.latestAssets) {
      if (asset['name'] == name) url = asset['url']?.toString();
    }
  }
  if (url == null || url.isEmpty) {
    Get.toNamed(RoutePath.kVersionPage);
    return;
  }
  final sources = getMirrorUrls(url, githubOriginOnly: SettingsService.to.app.useGitHubOriginForUpdates.v);
  if (sources.isEmpty) return;

  if (Platform.isAndroid && !await requestStorageInstallPermission()) {
    ToastUtil.show(i18n('grant_install_permission'));
    openAppSettings();
    return;
  }

  final temp = await getTemporaryDirectory();
  final fileName = Platform.isWindows
      ? 'PureLive-${VersionUtil.latestVersion}-setup.exe'
      : 'PureLive-${VersionUtil.latestVersion}.apk';
  await Get.dialog<bool>(
    DownloadApkDialog(
      apkUrl: sources.first,
      version: VersionUtil.latestVersion,
      fileName: fileName,
      downloadDirectoryProvider: () async => Directory(p.join(temp.path, 'update')),
      showOpenFolder: false,
      installAutomatically: true,
      fileOpener: Platform.isWindows ? _runWindowsInstaller : null,
    ),
    barrierDismissible: false,
  );
}

/// Runs the installer silently, then starts the updated app. The installer
/// closes this process itself (CloseApplications), so exit right away.
Future<DownloadedFileOpenResult> _runWindowsInstaller(String setupPath) async {
  try {
    final exe = Platform.resolvedExecutable;
    // A script avoids Windows argument quoting; it waits for the installer,
    // then starts the updated app.
    final script = File(p.join(p.dirname(setupPath), 'run_update.cmd'));
    await script.writeAsString(
      '@echo off\r\n'
      'chcp 65001 >nul\r\n'
      'start "" /wait "$setupPath" /SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS\r\n'
      'start "" "$exe"\r\n',
    );
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
    Future<void>.delayed(const Duration(milliseconds: 500), () => exit(0));
    return const DownloadedFileOpenResult.opened();
  } catch (e) {
    return DownloadedFileOpenResult.failed('$e');
  }
}
