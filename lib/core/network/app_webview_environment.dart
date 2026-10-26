import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/platform/app_path_manager.dart';

/// The WebView2 environment every Windows WebView and cookie lookup shares.
///
/// Without one, WebView2 keeps its profile beside the executable. An install
/// under Program Files cannot write there, so the WebView stays blank. The
/// profile lives in the app's writable data root instead, and the login pages
/// read cookies from that same profile.
class AppWebViewEnvironment {
  const AppWebViewEnvironment._();

  static WebViewEnvironment? _environment;
  static bool _available = true;

  /// Null on platforms other than Windows, or when WebView2 is missing.
  static WebViewEnvironment? get instance => _environment;

  /// False on Windows when the WebView2 runtime is not installed.
  static bool get available => _available;

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isWindows || _environment != null) return;
    try {
      final version = await WebViewEnvironment.getAvailableVersion();
      if (version == null) {
        _available = false;
        return;
      }
      final folder = Directory(p.join(AppPathManager().basePath, 'WEBVIEW2'));
      await folder.create(recursive: true);
      _environment = await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: folder.path));
    } catch (e) {
      debugPrint('WebView2 environment unavailable: $e');
    }
  }

  static CookieManager cookies() => CookieManager.instance(webViewEnvironment: _environment);
}
