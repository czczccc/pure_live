import 'dart:convert';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/http_client.dart';
import 'package:pure_live/core/consts/platform_ids.dart';

class BilibiliFollowException implements Exception {
  const BilibiliFollowException(this.reason);

  /// `not_logged_in`, `rejected` or `bad_response`.
  final String reason;

  @override
  String toString() => 'BilibiliFollowException($reason)';
}

/// Reads the live rooms a signed-in Bilibili account follows, from the list
/// behind the live site's "我的关注" page.
class BilibiliFollowApi {
  static const String endpoint = 'https://api.live.bilibili.com/xlive/web-ucenter/user/following';
  static const int pageSize = 29;
  static const int _maxPages = 60;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static Future<List<LiveRoom>> fetchFollowedRooms(String cookie) async {
    if (!cookie.contains('SESSDATA=')) throw const BilibiliFollowException('not_logged_in');
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    for (var page = 1; page <= _maxPages; page++) {
      final body = await HttpClient.instance.getJson(
        endpoint,
        queryParameters: {'page': page, 'page_size': pageSize, 'ignoreRecord': 1, 'hit_ab': true},
        header: {'user-agent': _userAgent, 'referer': 'https://link.bilibili.com/', 'Cookie': cookie},
      );
      final parsed = parsePage(body);
      var added = 0;
      for (final room in parsed.rooms) {
        if (seen.add(room.roomId!)) {
          rooms.add(room);
          added++;
        }
      }
      if (added == 0 || page >= parsed.totalPages) break;
    }
    return rooms;
  }

  @visibleForTesting
  static ({List<LiveRoom> rooms, int totalPages}) parsePage(dynamic body) {
    dynamic data = body;
    if (data is String) {
      try {
        data = json.decode(data);
      } catch (_) {
        throw const BilibiliFollowException('bad_response');
      }
    }
    if (data is! Map) throw const BilibiliFollowException('bad_response');
    final code = int.tryParse('${data['code'] ?? ''}');
    if (code == -101) throw const BilibiliFollowException('not_logged_in');
    if (code != 0) throw const BilibiliFollowException('rejected');
    final result = data['data'];
    if (result is! Map) throw const BilibiliFollowException('bad_response');
    final list = result['list'];
    if (list is! List) throw const BilibiliFollowException('bad_response');
    final rooms = <LiveRoom>[];
    for (final item in list) {
      if (item is! Map) continue;
      final roomId = '${item['roomid'] ?? ''}'.trim();
      if (roomId.isEmpty || roomId == '0') continue;
      final isLive = '${item['live_status']}' == '1';
      rooms.add(
        LiveRoom(
          roomId: roomId,
          userId: '${item['uid'] ?? ''}',
          title: '${item['title'] ?? ''}',
          nick: '${item['uname'] ?? ''}',
          avatar: '${item['face'] ?? ''}',
          cover: '${item['room_cover'] ?? ''}',
          area: '${item['area_name_v2'] ?? item['area_name'] ?? ''}',
          watching: '${item['online'] ?? 0}',
          liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
          status: isLive,
          platform: PlatformIds.bilibili,
        ),
      );
    }
    final totalPages = int.tryParse('${result['totalPage'] ?? result['total_page'] ?? ''}') ?? 1;
    return (rooms: rooms, totalPages: totalPages);
  }
}
