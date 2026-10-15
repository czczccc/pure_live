import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/shared/platforms/huya/huya_follow_api.dart';

void main() {
  test('parses a subscription page into Huya rooms', () {
    final page = HuyaFollowApi.parsePage({
      'status': 1000,
      'result': {
        'totalCount': 3,
        'list': [
          {
            'uid': 123,
            'nick': '主播A',
            'avatar180': 'https://a/avatar.jpg',
            'profileRoom': 880201,
            'isLive': true,
            'gameName': '英雄联盟',
            'intro': '上分',
            'screenshot': 'https://a/cover.jpg',
            'totalCount': 4567,
          },
          {'nick': '下播了', 'profileRoom': '11342412', 'isLive': 0},
          {'nick': '没有房间', 'profileRoom': 0},
        ],
      },
    });

    expect(page.totalCount, 3);
    expect(page.rooms.map((room) => room.roomId), ['880201', '11342412']);
    final live = page.rooms.first;
    expect(live.platform, 'huya');
    expect(live.nick, '主播A');
    expect(live.title, '上分');
    expect(live.area, '英雄联盟');
    expect(live.liveStatus, LiveStatus.live);
    expect(page.rooms.last.liveStatus, LiveStatus.offline);
  });

  test('accepts a JSON string body', () {
    final page = HuyaFollowApi.parsePage('{"status":1000,"result":{"list":[{"profileRoom":"1","isLive":"1"}]}}');
    expect(page.rooms.single.roomId, '1');
    expect(page.totalCount, 1);
  });

  test('rejects error statuses and unreadable bodies', () {
    expect(
      () => HuyaFollowApi.parsePage({'status': 401, 'message': 'not login'}),
      throwsA(isA<HuyaFollowException>().having((e) => e.reason, 'reason', 'rejected')),
    );
    expect(() => HuyaFollowApi.parsePage('<html>'), throwsA(isA<HuyaFollowException>()));
  });

  test('refuses to request without an account cookie', () {
    expect(
      HuyaFollowApi.fetchFollowedRooms('guid=abc'),
      throwsA(isA<HuyaFollowException>().having((e) => e.reason, 'reason', 'not_logged_in')),
    );
  });
}
