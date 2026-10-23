import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_follow_api.dart';
import 'package:pure_live/shared/platforms/bilibili/bilibili_follow_api.dart';

void main() {
  test('parses a Bilibili following page', () {
    final page = BilibiliFollowApi.parsePage({
      'code': 0,
      'data': {
        'totalPage': 2,
        'list': [
          {'roomid': 123, 'uid': 9, 'uname': 'up', 'title': 't', 'live_status': 1, 'area_name_v2': '游戏'},
          {'roomid': 0, 'uname': 'no room'},
        ],
      },
    });
    expect(page.totalPages, 2);
    expect(page.rooms.single.roomId, '123');
    expect(page.rooms.single.platform, 'bilibili');
    expect(page.rooms.single.status, isTrue);
    expect(() => BilibiliFollowApi.parsePage({'code': -101}), throwsA(isA<BilibiliFollowException>()));
  });

  test('parses a Douyin follow feed page', () {
    final page = DouyinFollowApi.parsePage({
      'status_code': 0,
      'data': {
        'has_more': false,
        'data': [
          {
            'web_rid': '456',
            'room': {
              'title': 'live',
              'owner': {
                'nickname': 'anchor',
                'avatar_thumb': {
                  'url_list': ['https://a/1.jpg'],
                },
              },
              'stats': {'user_count_str': '1万'},
            },
          },
        ],
      },
    });
    expect(page.hasMore, isFalse);
    expect(page.rooms.single.roomId, '456');
    expect(page.rooms.single.nick, 'anchor');
    expect(page.rooms.single.avatar, 'https://a/1.jpg');
    expect(() => DouyinFollowApi.parsePage({'status_code': 20003}), throwsA(isA<DouyinFollowException>()));
  });
}
