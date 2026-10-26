import 'package:pure_live/core/network/app_webview_environment.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/account/presentation/account/douyin/douyin_web_login_controller.dart';

class DouyinWebLoginPage extends GetView<DouyinWebLoginController> {
  const DouyinWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('douyin_login')),
        actions: [
          TextButton(
            key: const ValueKey('douyin-web-login-manual-cookie'),
            onPressed: () => Get.offAndToNamed(RoutePath.kDouyinCookie),
            child: Text(i18n('douyin_manual_cookie')),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [Expanded(child: Text(i18n('douyin_web_login_tip'), style: AppTextStyles.t13))],
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              webViewEnvironment: AppWebViewEnvironment.instance,
              initialUrlRequest: URLRequest(url: WebUri(douyinWebLoginUrl)),
              onLoadStop: controller.onLoadStop,
              initialSettings: InAppWebViewSettings(
                // The desktop site offers QR login in its login dialog.
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                preferredContentMode: UserPreferredContentMode.DESKTOP,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
