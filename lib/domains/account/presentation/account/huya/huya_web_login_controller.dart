import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/cookie_sanitizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_site.dart';

const String huyaWebLoginUrl = 'https://www.huya.com/';

typedef HuyaWebCookieLoader = Future<String> Function();
typedef HuyaWebLoginCompletion = void Function();

/// Signs in on the Huya website inside a WebView and keeps the resulting
/// account cookie. Huya's login is an in-page dialog that never redirects, so
/// the cookie jar is checked after every page load and on a short timer until
/// the account cookie (`yyuid`) appears.
class HuyaWebLoginController extends GetxController {
  HuyaWebLoginController({
    HuyaWebCookieLoader? cookieLoader,
    HuyaWebLoginCompletion? completeLogin,
    this.pollInterval = const Duration(milliseconds: 1500),
  }) : _cookieLoader = cookieLoader ?? _loadBrowserCookie,
       _completeLogin = completeLogin ?? _finishLogin;

  final HuyaWebCookieLoader _cookieLoader;
  final HuyaWebLoginCompletion _completeLogin;
  final Duration pollInterval;

  final isCompleted = false.obs;
  Timer? _pollTimer;
  bool _checking = false;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(checkLogin()));
  }

  void onLoadStop(InAppWebViewController _, WebUri? _) => unawaited(checkLogin());

  /// Returns true once an account cookie was found and saved.
  Future<bool> checkLogin() async {
    if (_closed || _checking || isCompleted.value) return isCompleted.value;
    _checking = true;
    try {
      final cookie = normalizeAccountCookie(await _cookieLoader());
      if (_closed || HuyaSite.parseViewerUidFromCookie(cookie) == null) return false;
      CookieSettingsController.to.huyaCookie.v = cookie;
      isCompleted.value = true;
      _pollTimer?.cancel();
      _completeLogin();
      return true;
    } catch (_) {
      return false;
    } finally {
      _checking = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _pollTimer?.cancel();
    super.onClose();
  }

  static Future<String> _loadBrowserCookie() async {
    final byName = <String, String>{};
    for (final url in const ['https://www.huya.com/', 'https://huya.com/']) {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        byName.putIfAbsent(cookie.name, () => '${cookie.value}');
      }
    }
    return byName.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  static void _finishLogin() {
    final context = Get.context;
    if (context != null) Navigator.of(context).pop(true);
  }
}

Future<void> clearHuyaWebLoginCookies() async {
  try {
    for (final url in const ['https://www.huya.com/', 'https://huya.com/']) {
      await CookieManager.instance().deleteCookies(url: WebUri(url), domain: '.huya.com');
      await CookieManager.instance().deleteCookies(url: WebUri(url));
    }
  } catch (_) {
    // A platform without a WebView cookie store has nothing to clear.
  }
}
