import 'package:pure_live/core/index.dart';
import 'package:pure_live/features/server_sync/server_sync_controller.dart';

class ServerSyncPage extends StatefulWidget {
  const ServerSyncPage({super.key});

  @override
  State<ServerSyncPage> createState() => _ServerSyncPageState();
}

class _ServerSyncPageState extends State<ServerSyncPage> {
  final controller = ServerSyncController.to;
  late final TextEditingController _url = TextEditingController(text: controller.serverUrl.v);
  late final TextEditingController _token = TextEditingController(text: controller.token.v);
  late bool _enabled = controller.enabled.v;
  bool _obscure = true;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save({bool thenSync = false}) async {
    await controller.configure(url: _url.text, newToken: _token.text, enable: _enabled);
    if (!thenSync || !controller.configured) return;
    final ok = await controller.syncNow();
    ToastUtil.show(ok ? i18n('server_sync_done') : '${i18n('server_sync_failed')}: ${controller.lastError.v}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('server_sync'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(i18n('server_sync_hint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: i18n('server_sync_url'),
              hintText: 'https://sync.example.com',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: i18n('server_sync_token'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i18n('server_sync_enable')),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          Obx(() {
            final at = controller.lastSyncAt.v;
            final status = at == 0
                ? i18n('server_sync_never')
                : '${i18n('server_sync_last')}: ${DateTime.fromMillisecondsSinceEpoch(at).toString().substring(0, 19)}';
            final error = controller.lastError.v;
            return Text(error.isEmpty ? status : '$status\n${i18n('server_sync_failed')}: $error');
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _save(), child: Text(i18n('server_sync_save'))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Obx(
                  () => FilledButton(
                    onPressed: controller.syncing.v ? null : () => _save(thenSync: true),
                    child: Text(i18n('server_sync_now')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
