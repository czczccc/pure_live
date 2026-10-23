import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:pure_live/get/get.dart';
import 'package:synchronized/synchronized.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/features/backup/backup_controller.dart';
import 'package:pure_live/features/server_sync/server_sync_codec.dart';
import 'package:pure_live/features/server_sync/server_sync_engine.dart';
import 'package:pure_live/domains/live/data/history_controller.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/iptv/data/iptv_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/tags/tag_management_controller.dart';
import 'package:pure_live/core/config/app_settings_controller.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';
import 'package:pure_live/core/config/page_settings_controller.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/core/config/player_settings_controller.dart';
import 'package:pure_live/core/config/volume_settings_controller.dart';
import 'package:pure_live/core/config/refresh_config_controller.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';

/// Keeps follows, cookies and shared settings in step with the user's own
/// sync server (see sync_server/ in the repository).
class ServerSyncController extends GetxController {
  static ServerSyncController get to => Get.find();

  static const String _stateKey = 'serverSyncState';
  static const Duration interval = Duration(minutes: 2);

  final RxBool enabled = hiveBool('serverSyncEnabled', false);
  final RxString serverUrl = hiveString('serverSyncUrl', '');
  final RxString token = hiveString('serverSyncToken', '');
  final RxInt lastSyncAt = hiveInt('serverSyncLastAt', 0);
  final RxString lastError = ''.obs;
  final RxBool syncing = false.obs;

  final Lock _lock = Lock();
  final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)),
  );
  Timer? _timer;

  bool get configured => serverUrl.v.trim().isNotEmpty && token.v.trim().isNotEmpty;

  @override
  void onReady() {
    super.onReady();
    _schedule();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void _schedule() {
    _timer?.cancel();
    if (!enabled.v || !configured) return;
    unawaited(syncNow(silent: true));
    _timer = Timer.periodic(interval, (_) => unawaited(syncNow(silent: true)));
  }

  /// Saves the connection and starts over from a fresh state, so a new server
  /// or token never receives tombstones meant for the old one.
  Future<void> configure({required String url, required String newToken, required bool enable}) async {
    final normalizedUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final changedTarget = normalizedUrl != serverUrl.v || newToken.trim() != token.v;
    serverUrl.v = normalizedUrl;
    token.v = newToken.trim();
    enabled.v = enable;
    if (changedTarget) await HivePrefUtil.remove(_stateKey);
    lastError.v = '';
    _schedule();
  }

  /// Returns true when the round trip finished.
  Future<bool> syncNow({bool silent = false}) {
    if (!configured) return Future.value(false);
    return _lock.synchronized(() async {
      syncing.v = true;
      try {
        final state = ServerSyncState.decode(HivePrefUtil.getString(_stateKey) ?? '');
        final engine = ServerSyncEngine(state);
        final merged = await engine.sync(
          local: BackupController.to.exportAllSettings(includeSensitiveData: true),
          transport: _post,
          now: DateTime.now().millisecondsSinceEpoch,
          backupVersion: BackupController.backupVersion,
        );
        if (merged != null) await _apply(merged);
        await HivePrefUtil.setString(_stateKey, state.encode());
        lastSyncAt.v = DateTime.now().millisecondsSinceEpoch;
        lastError.v = '';
        return true;
      } catch (e) {
        developer.log('Server sync failed: $e', name: 'ServerSync');
        lastError.v = e is DioException ? (e.response?.statusCode?.toString() ?? e.message ?? e.type.name) : '$e';
        return false;
      } finally {
        syncing.v = false;
      }
    });
  }

  Future<SyncResponse> _post(int since, List<SyncRecord> changes) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '${serverUrl.v}/api/v1/sync',
      data: {
        'since': since,
        'changes': [for (final c in changes) c.toJson()],
      },
      options: Options(headers: {'Authorization': 'Bearer ${token.v}'}),
    );
    return SyncResponse.fromJson(response.data!);
  }

  /// Imports only the sections present in [data]. The regular backup import
  /// resets absent sections to defaults, which a partial sync must not do.
  Future<void> _apply(Map<String, dynamic> data) async {
    Map<String, dynamic> section(String name) => Map<String, dynamic>.from(data[name] as Map);
    final importers = <String, void Function(Map<String, dynamic>)>{
      'app': (json) => Get.find<AppSettingsController>().fromJson(json),
      'theme': (json) => Get.find<ThemeSettingsController>().fromJson(json),
      'roomCard': (json) => Get.find<RoomCardSettingsController>().fromJson(json),
      'font': (json) => Get.find<FontSettingsController>().fromJson(json),
      'player': (json) => Get.find<PlayerSettingsController>().fromJson(json),
      'danmaku': (json) => Get.find<DanmakuSettingsController>().fromJson(json),
      'volume': (json) => Get.find<VolumeSettingsController>().fromJson(json),
      'history': (json) => Get.find<HistoryController>().fromJson(json),
      'iptv': (json) => Get.find<IptvSettingsController>().fromJson(json),
      'refresh': (json) => Get.find<RefreshConfigController>().fromJson(json),
      'page': (json) => Get.find<PageSettingsController>().fromJson(json),
      'tags': (json) => Get.find<TagManagementController>().importFromJson(json),
      'favorite': (json) => Get.find<FavoriteRoomController>().fromJson(json),
      'cookie': (json) =>
          Get.find<CookieSettingsController>().fromJson({...Get.find<CookieSettingsController>().toJson(), ...json}),
    };
    assert(importers.keys.toSet().containsAll(ServerSyncCodec.wholeSections));
    await HivePrefUtil.persistBatch(() {
      for (final entry in importers.entries) {
        if (data[entry.key] is Map) entry.value(section(entry.key));
      }
    });
  }
}
