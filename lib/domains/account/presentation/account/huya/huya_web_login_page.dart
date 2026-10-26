import 'package:pure_live/core/network/app_webview_environment.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/account/presentation/account/huya/huya_web_login_controller.dart';

class HuyaWebLoginPage extends GetView<HuyaWebLoginController> {
  const HuyaWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('huya_login')),
        actions: [
          TextButton(
            key: const ValueKey('huya-web-login-manual-cookie'),
            onPressed: () => Get.offAndToNamed(RoutePath.kHuyaCookie),
            child: Text(i18n('huya_manual_cookie')),
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
                children: [Expanded(child: Text(i18n('huya_web_login_tip'), style: AppTextStyles.t13))],
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              webViewEnvironment: AppWebViewEnvironment.instance,
              initialUrlRequest: URLRequest(url: WebUri(huyaWebLoginUrl)),
              onLoadStop: controller.onLoadStop,
              initialSettings: InAppWebViewSettings(
                // The desktop site exposes the account login dialog directly.
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
