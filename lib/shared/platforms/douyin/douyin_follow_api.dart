import 'dart:convert';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/http_client.dart';
import 'package:pure_live/core/consts/platform_ids.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_utils.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_request_params.dart';

class DouyinFollowException implements Exception {
  const DouyinFollowException(this.reason);

  /// `not_logged_in`, `rejected` or `bad_response`.
  final String reason;

  @override
  String toString() => 'DouyinFollowException($reason)';
}

/// Reads followed anchors from the live site's "关注" feed. Douyin's web feed
/// only lists followed anchors that are live right now, so each sync adds the
/// ones currently streaming; repeated syncs fill the list over time.
class DouyinFollowApi {
  static const String endpoint = 'https://live.douyin.com/webcast/web/feed/follow/';
  static const int _maxPages = 20;

  static Future<List<LiveRoom>> fetchFollowedRooms(String cookie) async {
    if (!RegExp(r'(?:^|;\s*)sessionid(?:_ss)?=[^;\s]').hasMatch(cookie)) {
      throw const DouyinFollowException('not_logged_in');
    }
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    var offset = 0;
    for (var page = 0; page < _maxPages; page++) {
      final url = DouyinUtils.buildRequestUrl(endpoint, {
        'app_name': 'douyin_web',
        'live_id': '1',
        'enter_from': 'web_homepage_follow',
        'scene': 'aweme_pc_follow_top',
        'channel': 'channel_pc_web',
        'offset': '$offset',
        'count': '20',
      });
      final body = await HttpClient.instance.getJson(
        url,
        header: {
          'user-agent': DouyinRequestParams.kDefaultUserAgent,
          'referer': 'https://live.douyin.com/',
          'Cookie': cookie,
        },
      );
      final parsed = parsePage(body);
      var added = 0;
      for (final room in parsed.rooms) {
        if (seen.add(room.roomId!)) {
          rooms.add(room);
          added++;
        }
      }
      if (added == 0 || !parsed.hasMore) break;
      offset += parsed.rooms.length;
    }
    return rooms;
  }

  @visibleForTesting
  static ({List<LiveRoom> rooms, bool hasMore}) parsePage(dynamic body) {
    dynamic data = body;
    if (data is String) {
      try {
        data = json.decode(data);
      } catch (_) {
        throw const DouyinFollowException('bad_response');
      }
    }
    if (data is! Map) throw const DouyinFollowException('bad_response');
    final code = int.tryParse('${data['status_code'] ?? ''}');
    if (code == 20003) throw const DouyinFollowException('not_logged_in');
    if (code != 0) throw const DouyinFollowException('rejected');
    final result = data['data'];
    if (result is! Map) throw const DouyinFollowException('bad_response');
    final list = result['data'];
    if (list is! List) return (rooms: const <LiveRoom>[], hasMore: false);
    final rooms = <LiveRoom>[];
    for (final item in list) {
      if (item is! Map) continue;
      final webRid = '${item['web_rid'] ?? ''}'.trim();
      final room = item['room'];
      if (webRid.isEmpty || room is! Map) continue;
      final owner = room['owner'] is Map ? room['owner'] as Map : const {};
      final stats = room['stats'] is Map ? room['stats'] as Map : const {};
      rooms.add(
        LiveRoom(
          roomId: webRid,
          userId: '${owner['id_str'] ?? ''}',
          title: '${room['title'] ?? ''}',
          nick: '${owner['nickname'] ?? ''}',
          avatar: _firstUrl(owner['avatar_thumb']),
          cover: _firstUrl(room['cover']),
          watching: '${stats['user_count_str'] ?? ''}',
          liveStatus: LiveStatus.live,
          status: true,
          link: 'https://live.douyin.com/$webRid',
          platform: PlatformIds.douyin,
        ),
      );
    }
    final hasMore = result['has_more'] == true || '${result['has_more']}' == '1';
    return (rooms: rooms, hasMore: hasMore);
  }

  static String _firstUrl(dynamic image) {
    if (image is! Map) return '';
    final urls = image['url_list'];
    return urls is List && urls.isNotEmpty ? '${urls.first}' : '';
  }
}
