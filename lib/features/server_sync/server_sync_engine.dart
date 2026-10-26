import 'dart:convert';

import 'package:pure_live/features/server_sync/server_sync_codec.dart';

typedef SyncTransport = Future<SyncResponse> Function(int since, List<SyncRecord> changes);

class SyncResponse {
  const SyncResponse({required this.cursor, required this.changes});

  factory SyncResponse.fromJson(Map<String, dynamic> json) => SyncResponse(
    cursor: (json['cursor'] as num).toInt(),
    changes: [
      for (final c in (json['changes'] as List? ?? const [])) SyncRecord.fromJson(Map<String, dynamic>.from(c)),
    ],
  );

  final int cursor;
  final List<SyncRecord> changes;
}

/// What this device last agreed with the server.
class ServerSyncState {
  ServerSyncState({this.cursor = 0, Map<String, String>? snapshot, Map<String, SyncRecord>? store})
    : snapshot = snapshot ?? <String, String>{},
      store = store ?? <String, SyncRecord>{};

  factory ServerSyncState.decode(String raw) {
    if (raw.isEmpty) return ServerSyncState();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ServerSyncState(
      cursor: (json['cursor'] as num? ?? 0).toInt(),
      snapshot: Map<String, String>.from(json['snapshot'] as Map? ?? const {}),
      store: {
        for (final r in (json['store'] as List? ?? const []))
          SyncRecord.fromJson(Map<String, dynamic>.from(r)).id: SyncRecord.fromJson(Map<String, dynamic>.from(r)),
      },
    );
  }

  /// Last server cursor seen; 0 before the first sync.
  int cursor;

  /// Record id -> fingerprint of the data this device last had in sync.
  final Map<String, String> snapshot;

  /// The server's records as of [cursor], tombstones included.
  final Map<String, SyncRecord> store;

  bool get isFresh => cursor == 0 && snapshot.isEmpty;

  String encode() => jsonEncode({
    'cursor': cursor,
    'snapshot': snapshot,
    'store': [for (final r in store.values) r.toJson()],
  });
}

/// Diffs the local state against the last synced snapshot, pushes the
/// difference and returns the merged state the device should adopt.
class ServerSyncEngine {
  ServerSyncEngine(this.state);

  final ServerSyncState state;

  /// Returns a partial backup to import, or null when local data already
  /// matches the server.
  Future<Map<String, dynamic>?> sync({
    required Map<String, dynamic> local,
    required SyncTransport transport,
    required int now,
    required int backupVersion,
  }) async {
    final current = ServerSyncCodec.encode(local);
    final fresh = state.isFresh;

    // A device joining for the first time reads the server before writing,
    // so its default settings and empty cookies do not replace real ones.
    if (fresh) _merge(await transport(0, const []));

    final changes = <SyncRecord>[];
    for (final entry in current.entries) {
      final record = entry.value;
      final fingerprint = ServerSyncCodec.fingerprint(record.data);
      if (state.snapshot[entry.key] == fingerprint) continue;
      final remote = state.store[entry.key];
      // An empty remote value (a device that never signed in) must not
      // replace an account this device already has.
      if (fresh && remote != null && !remote.deleted && !_isBlank(remote.data)) {
        final perItem = ServerSyncCodec.favoriteCollections.contains(record.collection);
        if (!perItem || ServerSyncCodec.fingerprint(remote.data) == fingerprint) continue;
      }
      changes.add(SyncRecord(collection: record.collection, key: record.key, data: record.data, updatedAt: now));
    }
    for (final id in state.snapshot.keys) {
      if (current.containsKey(id)) continue;
      final remote = state.store[id];
      if (remote == null) continue;
      changes.add(SyncRecord(collection: remote.collection, key: remote.key, deleted: true, updatedAt: now));
    }

    if (changes.isNotEmpty || !fresh) _merge(await transport(state.cursor, changes));

    var differs = false;
    state.snapshot.clear();
    for (final record in state.store.values) {
      if (record.deleted) {
        if (current.containsKey(record.id)) differs = true;
        continue;
      }
      final fingerprint = ServerSyncCodec.fingerprint(record.data);
      state.snapshot[record.id] = fingerprint;
      final local = current[record.id];
      if (local == null || ServerSyncCodec.fingerprint(local.data) != fingerprint) differs = true;
    }
    if (!differs) return null;
    return ServerSyncCodec.decode(state.store.values, backupVersion: backupVersion);
  }

  static bool _isBlank(Object? data) => data == null || (data is String && data.trim().isEmpty);

  void _merge(SyncResponse response) {
    for (final record in response.changes) {
      state.store[record.id] = record;
    }
    state.cursor = response.cursor;
  }
}
