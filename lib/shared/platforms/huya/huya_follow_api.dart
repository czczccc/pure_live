import 'dart:convert';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/http_client.dart';
import 'package:pure_live/core/consts/platform_ids.dart';
import 'package:pure_live/shared/platforms/huya/huya_site.dart';

/// One page of the rooms a signed-in Huya account subscribes to.
class HuyaFollowPage {
  const HuyaFollowPage({required this.rooms, required this.totalCount});

  final List<LiveRoom> rooms;
  final int totalCount;
}

class HuyaFollowException implements Exception {
  const HuyaFollowException(this.reason);

  /// `not_logged_in` when the cookie carries no account, `rejected` when Huya
  /// answered with an error status, `bad_response` for an unreadable body.
  final String reason;

  @override
  String toString() => 'HuyaFollowException($reason)';
}

/// Reads the account's subscription list from the endpoint the Huya website's
/// "我的订阅" panel uses. The list is account data, so it needs the login
/// cookie and the account's `yyuid`.
class HuyaFollowApi {
  static const String endpoint = 'https://fw.huya.com/dispatch';
  static const int pageSize = 50;
  static const int _maxPages = 40;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static Future<List<LiveRoom>> fetchFollowedRooms(String cookie) async {
    final uid = HuyaSite.parseViewerUidFromCookie(cookie);
    if (uid == null) throw const HuyaFollowException('not_logged_in');
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    for (var page = 1; page <= _maxPages; page++) {
      final body = await HttpClient.instance.getJson(
        endpoint,
        queryParameters: {'do': 'subscribeList', 'uid': uid, 'page': page, 'pageSize': pageSize},
        header: {'user-agent': _userAgent, 'referer': 'https://www.huya.com/', 'Cookie': cookie},
      );
      final parsed = parsePage(body);
      var added = 0;
      for (final room in parsed.rooms) {
        if (seen.add(room.roomId!)) {
          rooms.add(room);
          added++;
        }
      }
      if (added == 0 || parsed.rooms.length < pageSize || rooms.length >= parsed.totalCount) break;
    }
    return rooms;
  }

  @visibleForTesting
  static HuyaFollowPage parsePage(dynamic body) {
    dynamic data = body;
    if (data is String) {
      try {
        data = json.decode(data);
      } catch (_) {
        throw const HuyaFollowException('bad_response');
      }
    }
    if (data is! Map) throw const HuyaFollowException('bad_response');
    final status = int.tryParse('${data['status'] ?? ''}');
    if (status != null && status != 1000 && status != 200 && status != 0) {
      throw const HuyaFollowException('rejected');
    }
    final result = data['result'] ?? data['data'];
    if (result is! Map) throw const HuyaFollowException('bad_response');
    final list = result['list'] ?? result['datas'];
    if (list is! List) throw const HuyaFollowException('bad_response');

    final rooms = <LiveRoom>[];
    for (final item in list) {
      if (item is! Map) continue;
      final room = _parseRoom(item);
      if (room != null) rooms.add(room);
    }
    final total = int.tryParse('${result['totalCount'] ?? result['total'] ?? ''}') ?? rooms.length;
    return HuyaFollowPage(rooms: rooms, totalCount: total);
  }

  static LiveRoom? _parseRoom(Map item) {
    final roomId = _text(item['profileRoom'] ?? item['lProfileRoom'] ?? item['roomId']);
    if (roomId.isEmpty || roomId == '0') return null;
    final isLive = _isLive(item['isLive'] ?? item['iIsLive'] ?? item['liveStatus']);
    final title = _text(item['intro'] ?? item['introduction'] ?? item['liveDesc'] ?? item['roomName']);
    final viewers = _text(item['totalCount'] ?? item['activityCount']);
    return LiveRoom(
      roomId: roomId,
      userId: _text(item['uid'] ?? item['lUid']),
      title: title,
      nick: _text(item['nick'] ?? item['sNick']),
      avatar: _text(item['avatar180'] ?? item['avatar'] ?? item['sAvatar180']),
      cover: _text(item['screenshot'] ?? item['sScreenshot']),
      area: _text(item['gameName'] ?? item['gameFullName']),
      watching: viewers.isEmpty ? '0' : viewers,
      popularity: viewers,
      audienceMetricType: AudienceMetricType.popularity,
      liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
      status: isLive,
      platform: PlatformIds.huya,
    );
  }

  static String _text(dynamic value) => value == null ? '' : value.toString().trim();

  static bool _isLive(dynamic value) {
    if (value is bool) return value;
    final text = _text(value).toLowerCase();
    return text == '1' || text == 'true';
  }
}
