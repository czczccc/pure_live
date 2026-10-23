import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/server_sync/server_sync_codec.dart';
import 'package:pure_live/features/server_sync/server_sync_engine.dart';

/// In-memory stand-in for sync_server: newest updatedAt wins per record.
class FakeServer {
  final Map<String, SyncRecord> rows = {};
  final Map<String, int> seqs = {};
  int seq = 0;

  Future<SyncResponse> call(int since, List<SyncRecord> changes) async {
    for (final c in changes) {
      final existing = rows[c.id];
      seq++;
      if (existing == null || c.updatedAt > existing.updatedAt) {
        rows[c.id] = c;
        seqs[c.id] = seq;
      }
    }
    final out = rows.values.where((r) => seqs[r.id]! > since).toList()
      ..sort((a, b) => seqs[a.id]!.compareTo(seqs[b.id]!));
    final cursor = out.isEmpty ? since : seqs[out.last.id]!;
    return SyncResponse(cursor: cursor, changes: out);
  }
}

Map<String, dynamic> room(String platform, String id) => {'platform': platform, 'roomId': id, 'nick': id};

Map<String, dynamic> backup({
  List<Map<String, dynamic>> rooms = const [],
  Map<String, dynamic>? cookie,
  Map<String, dynamic>? theme,
}) => {
  'backupVersion': 3,
  'favorite': {
    'favoriteRooms': rooms,
    'favoriteAreas': <Map>[],
    'shieldList': <String>[],
    'blockedDanmakuUsers': <String>[],
    'hotAreasList': ['huya'],
    'preferPlatform': 'huya',
  },
  'cookie': ?cookie,
  'theme': ?theme,
};

class Device {
  Device(this.data);
  Map<String, dynamic> data;
  final engine = ServerSyncEngine(ServerSyncState());

  Future<void> sync(FakeServer server, int now) async {
    final merged = await engine.sync(local: data, transport: server.call, now: now, backupVersion: 3);
    if (merged == null) return;
    data = {...data, ...merged};
  }

  List<String> get roomIds => [for (final r in data['favorite']['favoriteRooms']) '${r['platform']}:${r['roomId']}'];
}

void main() {
  test('first join keeps server cookies and merges follows from both devices', () async {
    final server = FakeServer();
    final windows = Device(backup(rooms: [room('huya', '1')], cookie: {'huyaCookie': 'yyuid=1', 'bilibiliCookie': ''}));
    await windows.sync(server, 100);

    final android = Device(backup(rooms: [room('bilibili', '2')], cookie: {'huyaCookie': '', 'bilibiliCookie': ''}));
    await android.sync(server, 200);

    expect(android.data['cookie']['huyaCookie'], 'yyuid=1');
    expect(android.roomIds.toSet(), {'huya:1', 'bilibili:2'});

    await windows.sync(server, 300);
    expect(windows.roomIds.toSet(), {'huya:1', 'bilibili:2'});
  });

  test('unfollow and cookie changes propagate, newest whole section wins', () async {
    final server = FakeServer();
    final a = Device(backup(rooms: [room('huya', '1'), room('huya', '2')], theme: {'mode': 'dark'}));
    await a.sync(server, 100);
    final b = Device(backup());
    await b.sync(server, 110);
    expect(b.roomIds.toSet(), {'huya:1', 'huya:2'});
    expect(b.data['theme'], {'mode': 'dark'});

    a.data = backup(rooms: [room('huya', '2')], theme: {'mode': 'dark'});
    await a.sync(server, 200);
    b.data = {
      ...b.data,
      'theme': {'mode': 'light'},
      'cookie': {'douyinCookie': 'sid=9'},
    };
    await b.sync(server, 210);

    expect(b.roomIds, ['huya:2']);
    await a.sync(server, 300);
    expect(a.data['theme'], {'mode': 'light'});
    expect(a.data['cookie']['douyinCookie'], 'sid=9');

    // Nothing left to exchange.
    expect(await a.engine.sync(local: a.data, transport: server.call, now: 400, backupVersion: 3), isNull);
  });

  test('state survives encode and decode', () async {
    final server = FakeServer();
    final a = Device(backup(rooms: [room('huya', '1')]));
    await a.sync(server, 100);
    final restored = ServerSyncState.decode(a.engine.state.encode());
    expect(restored.cursor, a.engine.state.cursor);
    expect(restored.snapshot, a.engine.state.snapshot);
    expect(restored.store.keys, a.engine.state.store.keys);
  });
}
