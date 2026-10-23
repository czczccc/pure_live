import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/cookie_settings_controller.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/shared/platforms/huya/huya_follow_api.dart';
import 'package:pure_live/shared/platforms/huya/huya_site.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_follow_api.dart';
import 'package:pure_live/shared/platforms/bilibili/bilibili_follow_api.dart';

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

  /// Platforms whose account follow list can be imported.
  static const List<String> platforms = <String>['huya', 'bilibili', 'douyin'];

  static final Map<String, Future<void>> _active = <String, Future<void>>{};

  static String cookieFor(String platform) {
    final cookies = CookieSettingsController.to;
    switch (platform) {
      case 'huya':
        return cookies.huyaCookie.v;
      case 'bilibili':
        return cookies.bilibiliCookie.v;
      case 'douyin':
        return cookies.douyinCookie.v;
      default:
        return '';
    }
  }

  static bool hasAccount(String platform) {
    final cookie = cookieFor(platform);
    switch (platform) {
      case 'huya':
        return HuyaSite.parseViewerUidFromCookie(cookie) != null;
      case 'bilibili':
        return cookie.contains('SESSDATA=');
      case 'douyin':
        return RegExp(r'(?:^|;\s*)sessionid(?:_ss)?=[^;\s]').hasMatch(cookie);
      default:
        return false;
    }
  }

  static bool get hasHuyaAccount => hasAccount('huya');

  static bool get hasAnyAccount => platforms.any(hasAccount);

  static FollowedRoomsLoader _defaultLoader(String platform) {
    switch (platform) {
      case 'huya':
        return HuyaFollowApi.fetchFollowedRooms;
      case 'bilibili':
        return BilibiliFollowApi.fetchFollowedRooms;
      case 'douyin':
        return DouyinFollowApi.fetchFollowedRooms;
      default:
        throw ArgumentError.value(platform, 'platform');
    }
  }

  static Future<FollowedRoomSyncResult> syncHuya({FollowedRoomsLoader? loader}) => sync('huya', loader: loader);

  static Future<FollowedRoomSyncResult> sync(String platform, {FollowedRoomsLoader? loader}) async {
    while (_active[platform] != null) {
      await _active[platform];
    }
    final task = _sync(platform, loader ?? _defaultLoader(platform));
    _active[platform] = task.then((_) {}, onError: (_) {});
    try {
      return await task;
    } finally {
      _active.remove(platform);
    }
  }

  static Future<FollowedRoomSyncResult> _sync(String platform, FollowedRoomsLoader loader) async {
    final rooms = await loader(cookieFor(platform));
    final added = await FavoriteRoomController.to.addRoomsDurably(rooms);
    return FollowedRoomSyncResult(fetched: rooms.length, added: added);
  }
}
