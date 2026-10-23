import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/domains/live/data/danmaku_sender.dart';
import 'package:pure_live/domains/account/presentation/account/douyin/douyin_web_login_controller.dart';

void main() {
  test('reads cookie values by exact name', () {
    const cookie = 'SESSDATA=a; bili_jct=csrf123; x_bili_jct=no';
    expect(cookieValue(cookie, 'bili_jct'), 'csrf123');
    expect(cookieValue(cookie, 'missing'), isNull);
  });

  test('detects a signed-in Douyin session cookie', () {
    expect(hasDouyinSessionCookie('ttwid=1; sessionid=abc'), isTrue);
    expect(hasDouyinSessionCookie('ttwid=1; sessionid='), isFalse);
    expect(hasDouyinSessionCookie('ttwid=1'), isFalse);
  });

  test('reports missing login before any request', () async {
    final sender = DanmakuSender();
    final room = LiveRoom(platform: 'bilibili', roomId: '1');
    expect((await sender.send(room, 'hi', cookie: '')).status, DanmakuSendStatus.notLoggedIn);
    expect((await sender.send(room, 'hi', cookie: 'SESSDATA=a')).status, DanmakuSendStatus.notLoggedIn);
    expect(
      (await sender.send(LiveRoom(platform: 'huya', roomId: '1'), 'hi', cookie: 'guid=1')).status,
      DanmakuSendStatus.notLoggedIn,
    );
    expect(DanmakuSender.supports('douyu'), isFalse);
  });

  test('Huya send request round-trips through tars', () {
    final req = HuyaSendMessageReq()
      ..sContent = '你好'
      ..lPid = 42
      ..tUserId.lUid = 7;
    final out = TarsOutputStream();
    req.writeTo(out);
    final decoded = HuyaSendMessageReq()..readFrom(TarsInputStream(out.toUint8List()));
    expect(decoded.sContent, '你好');
    expect(decoded.lPid, 42);
    expect(decoded.tUserId.lUid, 7);
    expect(decoded.tBulletFormat.iFontSize, 4);
  });
}
