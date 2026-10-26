import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/network/app_webview_environment.dart';

/// Sends danmaku through the platform's own web page in a hidden WebView.
///
/// Huya and Douyin sign their chat requests in page scripts that change
/// often. Typing into the real chat box lets the site do that signing, so
/// only the account cookie has to be right.
class WebDanmakuSender {
  WebDanmakuSender._();

  static final WebDanmakuSender instance = WebDanmakuSender._();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  HeadlessInAppWebView? _view;
  String _url = '';
  String _cookie = '';
  Future<String> _queue = Future.value('');

  /// Returns 'ok', or a short reason the page could not send.
  Future<String> send({required String url, required String domain, required String cookie, required String text}) {
    final next = _queue.then((_) => _send(url, domain, cookie, text), onError: (_) => _send(url, domain, cookie, text));
    _queue = next.catchError((_) => '');
    return next;
  }

  Future<String> _send(String url, String domain, String cookie, String text) async {
    if (_view == null || _url != url || _cookie != cookie) {
      await dispose();
      await _applyCookies(url, domain, cookie);
      _url = url;
      _cookie = cookie;
      final loaded = Completer<void>();
      _view = HeadlessInAppWebView(
        webViewEnvironment: AppWebViewEnvironment.instance,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          userAgent: _userAgent,
          preferredContentMode: UserPreferredContentMode.DESKTOP,
          mediaPlaybackRequiresUserGesture: true,
        ),
        onLoadStop: (_, _) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      await _view!.run();
      await loaded.future.timeout(const Duration(seconds: 25), onTimeout: () {});
    }
    final controller = _view?.webViewController;
    if (controller == null) return 'webview';
    final result = await controller.callAsyncJavaScript(functionBody: _script, arguments: {'text': text});
    final value = result?.value?.toString() ?? result?.error ?? 'script';
    return value;
  }

  Future<void> _applyCookies(String url, String domain, String cookie) async {
    final cookies = AppWebViewEnvironment.cookies();
    for (final part in cookie.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isEmpty) continue;
      try {
        await cookies.setCookie(url: WebUri(url), name: name, value: value, domain: domain, path: '/');
      } catch (_) {
        // One malformed cookie must not block the rest.
      }
    }
  }

  Future<void> dispose() async {
    final view = _view;
    _view = null;
    _url = '';
    _cookie = '';
    if (view != null) await view.dispose();
  }

  /// Waits for the chat box, fills it the way the site's framework notices,
  /// then presses send. Covers Huya's `#pub_msg_input` and Douyin's chat
  /// textarea or rich-text editor.
  static const String _script = r'''
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const inputSelectors = [
  '#pub_msg_input',
  'textarea.webcast-chatroom___textarea',
  '.webcast-chatroom___textarea',
  '[class*="chatroom"] textarea',
  '[class*="chatroom"] [contenteditable="true"]',
  '[data-e2e="chat-input"]',
  'textarea',
  '[contenteditable="true"]',
];
const buttonSelectors = [
  '#msg_send_bt',
  '.webcast-chatroom___send-btn',
  '[class*="send-btn"]',
  '[class*="sendBtn"]',
  '[data-e2e="chat-send"]',
];
let box = null;
for (let i = 0; i < 40 && !box; i++) {
  for (const s of inputSelectors) {
    const el = document.querySelector(s);
    if (el) { box = el; break; }
  }
  if (!box) await sleep(500);
}
if (!box) return 'nochatbox';
box.focus();
if (box.tagName === 'TEXTAREA' || box.tagName === 'INPUT') {
  const proto = box.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(box, text);
  box.dispatchEvent(new Event('input', { bubbles: true }));
  box.dispatchEvent(new Event('change', { bubbles: true }));
} else {
  document.execCommand('selectAll', false);
  document.execCommand('insertText', false, text);
}
await sleep(300);
let button = null;
for (const s of buttonSelectors) {
  const el = document.querySelector(s);
  if (el) { button = el; break; }
}
if (button) {
  button.click();
} else {
  const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true };
  box.dispatchEvent(new KeyboardEvent('keydown', opts));
  box.dispatchEvent(new KeyboardEvent('keyup', opts));
}
await sleep(800);
const left = box.value !== undefined ? box.value : box.textContent;
if (left && left.trim() === text.trim()) return 'notsent';
const login = document.querySelector('.UDBSdkLgn, #UDBSdkLgn, [class*="login-dialog"], [class*="loginModal"]');
if (login && login.offsetParent !== null) return 'login';
return 'ok';
''';
}
