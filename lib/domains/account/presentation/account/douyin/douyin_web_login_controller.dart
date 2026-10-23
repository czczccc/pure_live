import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/cookie_sanitizer.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';

const String douyinWebLoginUrl = 'https://www.douyin.com/';
const List<String> _douyinCookieUrls = ['https://www.douyin.com/', 'https://live.douyin.com/', 'https://douyin.com/'];

typedef DouyinWebCookieLoader = Future<String> Function();
typedef DouyinWebLoginCompletion = void Function();

/// True when [cookie] carries a signed-in Douyin web session.
bool hasDouyinSessionCookie(String cookie) {
  for (final part in cookie.split(';')) {
    final index = part.indexOf('=');
    if (index <= 0) continue;
    final name = part.substring(0, index).trim();
    if ((name == 'sessionid' || name == 'sessionid_ss') && part.substring(index + 1).trim().isNotEmpty) return true;
  }
  return false;
}

/// Signs in on the Douyin website inside a WebView. The site's login dialog
/// shows a QR code to scan with the Douyin app; the cookie jar is checked
/// after every page load and on a short timer until `sessionid` appears.
class DouyinWebLoginController extends GetxController {
  DouyinWebLoginController({
    DouyinWebCookieLoader? cookieLoader,
    DouyinWebLoginCompletion? completeLogin,
    this.pollInterval = const Duration(milliseconds: 1500),
  }) : _cookieLoader = cookieLoader ?? _loadBrowserCookie,
       _completeLogin = completeLogin ?? _finishLogin;

  final DouyinWebCookieLoader _cookieLoader;
  final DouyinWebLoginCompletion _completeLogin;
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

  /// Returns true once a session cookie was found and saved.
  Future<bool> checkLogin() async {
    if (_closed || _checking || isCompleted.value) return isCompleted.value;
    _checking = true;
    try {
      final cookie = normalizeAccountCookie(await _cookieLoader());
      if (_closed || !hasDouyinSessionCookie(cookie)) return false;
      CookieSettingsController.to.douyinCookie.v = cookie;
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
    for (final url in _douyinCookieUrls) {
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

Future<void> clearDouyinWebLoginCookies() async {
  try {
    for (final url in _douyinCookieUrls) {
      await CookieManager.instance().deleteCookies(url: WebUri(url), domain: '.douyin.com');
      await CookieManager.instance().deleteCookies(url: WebUri(url));
    }
  } catch (_) {
    // A platform without a WebView cookie store has nothing to clear.
  }
}
