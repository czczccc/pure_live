import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_follow_api.dart';
import 'package:pure_live/shared/platforms/huya/huya_site.dart';

class FollowedRoomSyncResult {
  const FollowedRoomSyncResult({required this.fetched, required this.added});

  final int fetched;
  final int added;
}

typedef FollowedRoomsLoader = Future<List<LiveRoom>> Function(String cookie);

/// Copies the rooms a signed-in platform account follows into the local
/// follow list. It only adds: rooms followed only in the app are kept, and
/// unfollowing on the website does not remove them here.
class FollowedRoomSync {
  FollowedRoomSync._();

  static Future<void>? _activeHuyaSync;

  static bool get hasHuyaAccount => HuyaSite.parseViewerUidFromCookie(CookieSettingsController.to.huyaCookie.v) != null;

  static Future<FollowedRoomSyncResult> syncHuya({FollowedRoomsLoader? loader}) async {
    while (_activeHuyaSync != null) {
      await _activeHuyaSync;
    }
    final task = _syncHuya(loader ?? HuyaFollowApi.fetchFollowedRooms);
    _activeHuyaSync = task.then((_) {}, onError: (_) {});
    try {
      return await task;
    } finally {
      _activeHuyaSync = null;
    }
  }

  static Future<FollowedRoomSyncResult> _syncHuya(FollowedRoomsLoader loader) async {
    final rooms = await loader(CookieSettingsController.to.huyaCookie.v);
    final added = await FavoriteRoomController.to.addRoomsDurably(rooms);
    return FollowedRoomSyncResult(fetched: rooms.length, added: added);
  }
}
