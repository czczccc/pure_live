import 'package:dio/dio.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/core/tars/types.dart';
import 'package:pure_live/core/tars/base_tars_http.dart';
import 'package:pure_live/core/tars/codec/tars_struct.dart';
import 'package:pure_live/core/tars/codec/tars_displayer.dart';
import 'package:pure_live/core/tars/codec/tars_input_stream.dart';
import 'package:pure_live/core/tars/codec/tars_output_stream.dart';
import 'package:pure_live/shared/platforms/huya/huya_danmaku.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_utils.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_danmaku.dart';
import 'package:pure_live/shared/platforms/bilibili/bilibili_danmaku.dart';
import 'package:pure_live/shared/platforms/douyin/douyin_request_params.dart';

enum DanmakuSendStatus { sent, notLoggedIn, unsupported, failed }

class DanmakuSendResult {
  const DanmakuSendResult(this.status, [this.message = '']);

  final DanmakuSendStatus status;

  /// The platform's own reason when it rejected the message.
  final String message;

  bool get sent => status == DanmakuSendStatus.sent;
}

/// Reads one cookie value from a `name=value; ...` header.
String? cookieValue(String cookie, String name) {
  for (final part in cookie.split(';')) {
    final index = part.indexOf('=');
    if (index > 0 && part.substring(0, index).trim() == name) return part.substring(index + 1).trim();
  }
  return null;
}

/// Token from an `x-ware-csrf-token` header such as `0,<token>,86370000,success,<sid>`.
String? douyinCsrfTokenFromHeader(String? header) {
  final parts = (header ?? '').split(',');
  if (parts.length < 2 || parts[1].trim().isEmpty) return null;
  return parts[1].trim();
}

/// Sends real danmaku to the platform with the account cookie the user signed
/// in with. Only Bilibili, Douyin and Huya are supported.
class DanmakuSender {
  DanmakuSender({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  final Dio _dio;

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static bool supports(String? platform) =>
      const {'bilibili', 'douyin', 'huya'}.contains(platform?.trim().toLowerCase());

  Future<DanmakuSendResult> send(LiveRoom room, String text, {required String cookie}) async {
    final message = text.trim();
    if (message.isEmpty) return const DanmakuSendResult(DanmakuSendStatus.failed);
    if (cookie.trim().isEmpty) return const DanmakuSendResult(DanmakuSendStatus.notLoggedIn);
    try {
      switch (room.platform?.trim().toLowerCase()) {
        case 'bilibili':
          return await _sendBilibili(room, message, cookie);
        case 'douyin':
          return await _sendDouyin(room, message, cookie);
        case 'huya':
          return await _sendHuya(room, message, cookie);
        default:
          return const DanmakuSendResult(DanmakuSendStatus.unsupported);
      }
    } on DioException catch (e) {
      return DanmakuSendResult(DanmakuSendStatus.failed, e.response?.statusCode?.toString() ?? e.type.name);
    } catch (e) {
      return DanmakuSendResult(DanmakuSendStatus.failed, '$e');
    }
  }

  Future<DanmakuSendResult> _sendBilibili(LiveRoom room, String message, String cookie) async {
    final csrf = cookieValue(cookie, 'bili_jct');
    if (csrf == null || csrf.isEmpty) return const DanmakuSendResult(DanmakuSendStatus.notLoggedIn);
    final args = room.danmakuData;
    final roomId = args is BiliBiliDanmakuArgs ? args.roomId : int.tryParse(room.roomId ?? '');
    if (roomId == null || roomId <= 0) return const DanmakuSendResult(DanmakuSendStatus.failed, 'room');
    final response = await _dio.post<Map<String, dynamic>>(
      'https://api.live.bilibili.com/msg/send',
      data: FormData.fromMap({
        'bubble': 0,
        'msg': message,
        'color': 16777215,
        'mode': 1,
        'fontsize': 25,
        'rnd': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'roomid': roomId,
        'csrf': csrf,
        'csrf_token': csrf,
      }),
      options: Options(
        headers: {
          'Cookie': cookie,
          'User-Agent': _desktopUserAgent,
          'Origin': 'https://live.bilibili.com',
          'Referer': 'https://live.bilibili.com/$roomId',
        },
      ),
    );
    final data = response.data ?? const {};
    if (data['code'] == 0) return const DanmakuSendResult(DanmakuSendStatus.sent);
    if (data['code'] == -101) return const DanmakuSendResult(DanmakuSendStatus.notLoggedIn);
    return DanmakuSendResult(DanmakuSendStatus.failed, '${data['message'] ?? data['msg'] ?? data['code']}');
  }

  Future<DanmakuSendResult> _sendDouyin(LiveRoom room, String message, String cookie) async {
    final args = room.danmakuData;
    final roomId = args is DouyinDanmakuArgs ? args.roomId : '';
    final webRid = args is DouyinDanmakuArgs ? args.webRid : (room.roomId ?? '');
    if (roomId.isEmpty) return const DanmakuSendResult(DanmakuSendStatus.failed, 'room');
    final url = DouyinUtils.buildRequestUrl('https://live.douyin.com/webcast/room/chat/', {
      'app_name': 'douyin_web',
      'live_id': '1',
      'enter_from': 'web_live',
      'room_id': roomId,
      'content': message,
      'type': '0',
      'common_label_list': '[]',
    });
    final headers = {
      'Cookie': cookie,
      'User-Agent': DouyinRequestParams.kDefaultUserAgent,
      'Origin': 'https://live.douyin.com',
      'Referer': 'https://live.douyin.com/$webRid',
    };
    final csrf = await _douyinCsrfToken(url, headers);
    final response = await _dio.post<Map<String, dynamic>>(
      url,
      options: Options(headers: {...headers, 'x-secsdk-csrf-token': ?csrf}),
    );
    final data = response.data ?? const {};
    final code = data['status_code'];
    if (code == 0) return const DanmakuSendResult(DanmakuSendStatus.sent);
    final extra = data['data'];
    final prompt = extra is Map ? (extra['prompts'] ?? extra['message']) : null;
    if (code == 20003) return const DanmakuSendResult(DanmakuSendStatus.notLoggedIn);
    return DanmakuSendResult(DanmakuSendStatus.failed, '${prompt ?? data['status_message'] ?? code}');
  }

  /// Douyin's web POST endpoints reject requests without the secsdk CSRF
  /// token, which a HEAD request to the same URL hands out.
  Future<String?> _douyinCsrfToken(String url, Map<String, String> headers) async {
    try {
      final response = await _dio.head<void>(
        url,
        options: Options(
          headers: {...headers, 'x-secsdk-csrf-request': '1', 'x-secsdk-csrf-version': '1.2.22'},
          validateStatus: (_) => true,
        ),
      );
      return douyinCsrfTokenFromHeader(response.headers.value('x-ware-csrf-token'));
    } catch (_) {
      return null;
    }
  }

  Future<DanmakuSendResult> _sendHuya(LiveRoom room, String message, String cookie) async {
    final uid = int.tryParse(cookieValue(cookie, 'yyuid') ?? '');
    if (uid == null || uid <= 0) return const DanmakuSendResult(DanmakuSendStatus.notLoggedIn);
    final args = room.danmakuData;
    final presenterUid = args is HuyaDanmakuArgs ? args.uid : 0;
    if (presenterUid <= 0) return const DanmakuSendResult(DanmakuSendStatus.failed, 'room');
    final request = HuyaSendMessageReq()
      ..tUserId = (HuyaUserId()
        ..lUid = uid
        ..sGuid = cookieValue(cookie, 'guid') ?? ''
        ..sToken = cookieValue(cookie, 'udb_biztoken') ?? ''
        ..sHuYaUA = 'webh5&2405231432&websocket'
        ..sCookie = cookie)
      ..sContent = message
      ..lPid = presenterUid;
    final client = BaseTarsHttp(
      'https://wup.huya.com',
      'liveui',
      timeOut: 10,
      headers: {
        'Cookie': cookie,
        'User-Agent': _desktopUserAgent,
        'Origin': 'https://www.huya.com',
        'Referer': 'https://www.huya.com/${room.roomId ?? ''}',
      },
    );
    try {
      final response = await client.tupRequestWithRspCode('sendMessage', request, HuyaSendMessageRsp());
      final rsp = response.response;
      if (response.code == 0 && rsp != null && rsp.iStatus == 0) return const DanmakuSendResult(DanmakuSendStatus.sent);
      final notice = rsp?.sInvalidContent ?? '';
      return DanmakuSendResult(
        DanmakuSendStatus.failed,
        notice.isNotEmpty ? notice : 'status ${rsp?.iStatus ?? response.code}',
      );
    } finally {
      client.dio.close(force: true);
    }
  }
}

/// `liveui.sendMessage` request, as the Huya web player sends it.
class HuyaSendMessageReq extends TarsStruct {
  HuyaUserId tUserId = HuyaUserId(); // tag 0
  String sContent = ''; // tag 1
  String sExpand = ''; // tag 2
  int iShowMode = 0; // tag 3
  HuyaContentFormat tFormat = HuyaContentFormat(); // tag 4
  HuyaBulletFormat tBulletFormat = HuyaBulletFormat(); // tag 5
  int lPid = 0; // tag 7

  @override
  void readFrom(TarsInputStream inputStream) {
    tUserId = inputStream.read(tUserId, 0, false);
    sContent = inputStream.read(sContent, 1, false);
    sExpand = inputStream.read(sExpand, 2, false);
    iShowMode = inputStream.read(iShowMode, 3, false);
    tFormat = inputStream.read(tFormat, 4, false);
    tBulletFormat = inputStream.read(tBulletFormat, 5, false);
    lPid = inputStream.read(lPid, 7, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(tUserId, 0);
    outputStream.write(sContent, 1);
    outputStream.write(sExpand, 2);
    outputStream.write(iShowMode, 3);
    outputStream.write(tFormat, 4);
    outputStream.write(tBulletFormat, 5);
    outputStream.write(lPid, 7);
  }

  @override
  TarsStruct deepCopy() => HuyaSendMessageReq()
    ..tUserId = tUserId
    ..sContent = sContent
    ..sExpand = sExpand
    ..iShowMode = iShowMode
    ..tFormat = tFormat
    ..tBulletFormat = tBulletFormat
    ..lPid = lPid;

  @override
  void displayAsString(StringBuffer sb, int level) {
    TarsDisplayer(sb, level: level)
      ..DisplayString(sContent, 'sContent')
      ..DisplayInt(lPid, 'lPid');
  }
}

class HuyaContentFormat extends TarsStruct {
  int iFontColor = -1;
  int iFontSize = 4;
  int iPopupStyle = 0;
  int iNickNameFontColor = -1;
  int iDarkFontColor = -1;
  int iDarkNickNameFontColor = -1;

  @override
  void readFrom(TarsInputStream inputStream) {
    iFontColor = inputStream.read(iFontColor, 0, false);
    iFontSize = inputStream.read(iFontSize, 1, false);
    iPopupStyle = inputStream.read(iPopupStyle, 2, false);
    iNickNameFontColor = inputStream.read(iNickNameFontColor, 3, false);
    iDarkFontColor = inputStream.read(iDarkFontColor, 4, false);
    iDarkNickNameFontColor = inputStream.read(iDarkNickNameFontColor, 5, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(iFontColor, 0);
    outputStream.write(iFontSize, 1);
    outputStream.write(iPopupStyle, 2);
    outputStream.write(iNickNameFontColor, 3);
    outputStream.write(iDarkFontColor, 4);
    outputStream.write(iDarkNickNameFontColor, 5);
  }

  @override
  TarsStruct deepCopy() => HuyaContentFormat();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HuyaBulletFormat extends TarsStruct {
  int iFontColor = -1;
  int iFontSize = 4;
  int iTextSpeed = 0;
  int iTransitionType = 1;
  int iPopupStyle = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    iFontColor = inputStream.read(iFontColor, 0, false);
    iFontSize = inputStream.read(iFontSize, 1, false);
    iTextSpeed = inputStream.read(iTextSpeed, 2, false);
    iTransitionType = inputStream.read(iTransitionType, 3, false);
    iPopupStyle = inputStream.read(iPopupStyle, 4, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(iFontColor, 0);
    outputStream.write(iFontSize, 1);
    outputStream.write(iTextSpeed, 2);
    outputStream.write(iTransitionType, 3);
    outputStream.write(iPopupStyle, 4);
  }

  @override
  TarsStruct deepCopy() => HuyaBulletFormat();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HuyaSendMessageRsp extends TarsStruct {
  int iStatus = 0; // tag 0
  String sInvalidContent = ''; // tag 1

  @override
  void readFrom(TarsInputStream inputStream) {
    iStatus = inputStream.read(iStatus, 0, false);
    sInvalidContent = inputStream.read(sInvalidContent, 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(iStatus, 0);
    outputStream.write(sInvalidContent, 1);
  }

  @override
  TarsStruct deepCopy() => HuyaSendMessageRsp()
    ..iStatus = iStatus
    ..sInvalidContent = sInvalidContent;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}
