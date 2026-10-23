import 'dart:convert';

/// One synced record, as stored on the sync server.
class SyncRecord {
  const SyncRecord({required this.collection, required this.key, this.data, this.deleted = false, this.updatedAt = 0});

  factory SyncRecord.fromJson(Map<String, dynamic> json) => SyncRecord(
    collection: json['collection'] as String,
    key: json['key'] as String,
    data: json['data'],
    deleted: json['deleted'] == true,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );

  final String collection;
  final String key;
  final Object? data;
  final bool deleted;
  final int updatedAt;

  String get id => recordId(collection, key);

  Map<String, dynamic> toJson() => {
    'collection': collection,
    'key': key,
    if (!deleted) 'data': data,
    'deleted': deleted,
    'updatedAt': updatedAt,
  };
}

String recordId(String collection, String key) => '$collection\u0000$key';

/// Splits a backup export into server records and assembles one back.
///
/// List-like data that two devices commonly change independently (followed
/// rooms and areas, shield words, blocked danmaku users, account cookies) is
/// split per item, so concurrent edits merge. Every other section is one
/// record, and its newest edit wins as a whole.
class ServerSyncCodec {
  ServerSyncCodec._();

  static const String favoriteRoom = 'favoriteRoom';
  static const String favoriteArea = 'favoriteArea';
  static const String shieldWord = 'shieldWord';
  static const String blockedUser = 'blockedUser';
  static const String cookie = 'cookie';
  static const String section = 'section';

  /// Whole sections that follow the user across devices. Window geometry,
  /// startup, exit, proxy, WebDAV and wallpaper settings stay per device.
  static const List<String> wholeSections = <String>[
    'app',
    'theme',
    'roomCard',
    'font',
    'player',
    'danmaku',
    'volume',
    'history',
    'iptv',
    'tags',
    'refresh',
    'page',
  ];

  static const List<String> _favoriteRestKeys = <String>['hotAreasList', 'preferPlatform'];

  /// Collections whose records belong to the backup's `favorite` section.
  static const Set<String> favoriteCollections = <String>{favoriteRoom, favoriteArea, shieldWord, blockedUser};

  static String roomKey(Map room) =>
      '${(room['platform'] ?? '').toString().trim().toLowerCase()}:'
      '${(room['roomId'] ?? '').toString().trim().toLowerCase()}';

  static String areaKey(Map area) =>
      '${(area['platform'] ?? '').toString().trim().toLowerCase()}:'
      '${area['areaType'] ?? ''}:${area['areaId'] ?? ''}';

  /// Returns record id -> (collection, key, data) for the current state.
  static Map<String, SyncRecord> encode(Map<String, dynamic> backup) {
    final out = <String, SyncRecord>{};
    void put(String collection, String key, Object? data) {
      out[recordId(collection, key)] = SyncRecord(collection: collection, key: key, data: data);
    }

    final favorite = backup['favorite'];
    if (favorite is Map) {
      var order = 0;
      for (final room in (favorite['favoriteRooms'] as List? ?? const [])) {
        if (room is Map) put(favoriteRoom, roomKey(room), {'order': order++, 'room': room});
      }
      order = 0;
      for (final area in (favorite['favoriteAreas'] as List? ?? const [])) {
        if (area is Map) put(favoriteArea, areaKey(area), {'order': order++, 'area': area});
      }
      for (final word in (favorite['shieldList'] as List? ?? const [])) {
        put(shieldWord, word.toString(), true);
      }
      for (final user in (favorite['blockedDanmakuUsers'] as List? ?? const [])) {
        put(blockedUser, user.toString(), true);
      }
      put(section, 'favorite', {
        for (final key in _favoriteRestKeys)
          if (favorite.containsKey(key)) key: favorite[key],
      });
    }

    final cookies = backup['cookie'];
    if (cookies is Map) {
      for (final entry in cookies.entries) {
        put(cookie, entry.key.toString(), entry.value);
      }
    }

    for (final name in wholeSections) {
      if (backup.containsKey(name)) put(section, name, backup[name]);
    }
    return out;
  }

  /// Builds a partial backup from live (non-deleted) records. Only sections
  /// the records describe are present, so importing it leaves the rest alone.
  static Map<String, dynamic> decode(Iterable<SyncRecord> records, {required int backupVersion}) {
    final live = records.where((r) => !r.deleted).toList();
    final touchesFavorite = records.any((r) => favoriteCollections.contains(r.collection));
    final backup = <String, dynamic>{'backupVersion': backupVersion, 'sensitiveDataIncluded': false};

    List<Map> ordered(String collection, String field) {
      final items = live.where((r) => r.collection == collection && r.data is Map).toList()
        ..sort((a, b) {
          final byOrder = ((a.data as Map)['order'] as num? ?? 0).compareTo((b.data as Map)['order'] as num? ?? 0);
          return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
        });
      return [for (final r in items) Map<String, dynamic>.from((r.data as Map)[field] as Map)];
    }

    List<String> keys(String collection) => [
      for (final r in live)
        if (r.collection == collection) r.key,
    ]..sort();

    final favoriteRest = live.where((r) => r.collection == section && r.key == 'favorite').firstOrNull;
    if (touchesFavorite || favoriteRest != null) {
      backup['favorite'] = <String, dynamic>{
        if (favoriteRest?.data is Map) ...Map<String, dynamic>.from(favoriteRest!.data as Map),
        'favoriteRooms': ordered(favoriteRoom, 'room'),
        'favoriteAreas': ordered(favoriteArea, 'area'),
        'shieldList': keys(shieldWord),
        'blockedDanmakuUsers': keys(blockedUser),
      };
    }

    final cookieRecords = live.where((r) => r.collection == cookie).toList();
    if (cookieRecords.isNotEmpty) {
      backup['cookie'] = <String, dynamic>{for (final r in cookieRecords) r.key: r.data};
      backup['sensitiveDataIncluded'] = true;
    }

    for (final r in live) {
      if (r.collection == section && r.key != 'favorite' && wholeSections.contains(r.key)) {
        backup[r.key] = r.data;
      }
    }
    return backup;
  }

  static String fingerprint(Object? data) => jsonEncode(data);
}
