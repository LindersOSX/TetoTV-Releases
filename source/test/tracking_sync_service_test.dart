import 'dart:convert';

import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage for unit tests.
// Uses Fake to avoid declaring every platform-specific parameter.
// ---------------------------------------------------------------------------

class _FakeStorage extends Fake implements FlutterSecureStorage {
  final _data = <String, String>{};

  // The public API surface we actually use; all optional keyword args that
  // differ between versions are fine to omit because Fake ignores them.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('read')) {
      final key = invocation.namedArguments[#key] as String;
      return Future<String?>.value(_data[key]);
    }
    if (name.contains('write')) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        _data.remove(key);
      } else {
        _data[key] = value;
      }
      return Future<void>.value();
    }
    if (name.contains('delete')) {
      final key = invocation.namedArguments[#key] as String;
      _data.remove(key);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

// ---------------------------------------------------------------------------
// Fake tracking repository that records update calls.
// ---------------------------------------------------------------------------

class _FakeRepo implements TrackingRepository {
  final List<({int mediaId, int episodes})> updates = [];
  bool shouldFail = false;
  Duration updateDelay = Duration.zero;

  @override
  Future<List<TrackedAnime>> list(TrackingListStatus status) async => const [];

  @override
  Future<int?> currentProgress(int mediaId) async => 0;

  @override
  Future<void> removeFromList({required int mediaId}) async {}

  @override
  Future<void> updateProgress({
    required int mediaId,
    required int completedEpisodes,
  }) async {
    if (updateDelay > Duration.zero) await Future<void>.delayed(updateDelay);
    if (shouldFail) throw Exception('network error');
    updates.add((mediaId: mediaId, episodes: completedEpisodes));
  }

  @override
  Future<void> updateStatus({
    required int mediaId,
    required TrackingListStatus status,
  }) async {}
}

// ---------------------------------------------------------------------------
// Testable subclass that uses fake repositories.
// ---------------------------------------------------------------------------

class _TestSyncService extends TrackingSyncService {
  _TestSyncService(
    super.storage,
    super.tokenLookup, {
    required this.anilistRepo,
    required this.malRepo,
  }) : super.withLookup();

  final _FakeRepo anilistRepo;
  final _FakeRepo malRepo;

  @override
  TrackingRepository buildRepository(TrackingProvider provider, String token) {
    return switch (provider) {
      TrackingProvider.anilist => anilistRepo,
      TrackingProvider.myAnimeList => malRepo,
    };
  }
}

// ---------------------------------------------------------------------------
// Outbox JSON helpers operating directly on _FakeStorage._data.
// ---------------------------------------------------------------------------

const _outboxKey = 'tracking_progress_outbox_v1';

List<Map<String, dynamic>> _readOutbox(_FakeStorage s) {
  final raw = s._data[_outboxKey];
  if (raw == null || raw.isEmpty) return const [];
  return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
}

void _writeOutbox(_FakeStorage s, List<Map<String, dynamic>> entries) {
  s._data[_outboxKey] = jsonEncode(entries);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeStorage storage;
  late _FakeRepo anilistRepo;
  late _FakeRepo malRepo;

  _TestSyncService buildService({
    Map<TrackingProvider, String?> tokens = const {
      TrackingProvider.anilist: 'al-tok',
      TrackingProvider.myAnimeList: 'mal-tok',
    },
  }) {
    return _TestSyncService(
      storage,
      (provider) async => tokens[provider],
      anilistRepo: anilistRepo,
      malRepo: malRepo,
    );
  }

  setUp(() {
    storage = _FakeStorage();
    anilistRepo = _FakeRepo();
    malRepo = _FakeRepo();
  });

  group('syncEpisode', () {
    test('syncs to both trackers when both IDs are supplied', () async {
      final synced = await buildService().syncEpisode(
        completedEpisodes: 5,
        anilistMediaId: 101,
        malMediaId: 202,
      );

      expect(synced, isTrue);
      expect(anilistRepo.updates, hasLength(1));
      expect(anilistRepo.updates.first.mediaId, 101);
      expect(anilistRepo.updates.first.episodes, 5);
      expect(malRepo.updates, hasLength(1));
      expect(malRepo.updates.first.mediaId, 202);
      expect(malRepo.updates.first.episodes, 5);
    });

    test('skips tracker when its token is absent', () async {
      final synced = await buildService(
        tokens: {
          TrackingProvider.anilist: null,
          TrackingProvider.myAnimeList: 'mal-tok',
        },
      ).syncEpisode(completedEpisodes: 3, anilistMediaId: 101, malMediaId: 202);

      expect(synced, isFalse);
      expect(anilistRepo.updates, isEmpty);
      expect(malRepo.updates, hasLength(1));
      expect(_readOutbox(storage), hasLength(1));
      expect(_readOutbox(storage).single['provider'], 'anilist');
    });

    test('queues progress when token lookup fails', () async {
      final service = _TestSyncService(
        storage,
        (provider) async => throw Exception('refresh failed'),
        anilistRepo: anilistRepo,
        malRepo: malRepo,
      );

      final synced = await service.syncEpisode(
        completedEpisodes: 6,
        anilistMediaId: 101,
      );

      expect(synced, isFalse);
      expect(anilistRepo.updates, isEmpty);
      expect(_readOutbox(storage).single['completed_episodes'], 6);
    });

    test('is a no-op when no media IDs are supplied', () async {
      final synced = await buildService().syncEpisode(completedEpisodes: 7);

      expect(synced, isFalse);
      expect(anilistRepo.updates, isEmpty);
      expect(malRepo.updates, isEmpty);
      expect(_readOutbox(storage), isEmpty);
    });

    test('writes failed sync to outbox', () async {
      anilistRepo.shouldFail = true;

      final synced = await buildService().syncEpisode(
        completedEpisodes: 4,
        anilistMediaId: 101,
      );

      expect(synced, isFalse);
      final outbox = _readOutbox(storage);
      expect(outbox, hasLength(1));
      expect(outbox.first['media_id'], 101);
      expect(outbox.first['completed_episodes'], 4);
      expect(outbox.first['provider'], 'anilist');
    });

    test('concurrent failures retain every queued progress update', () async {
      anilistRepo
        ..shouldFail = true
        ..updateDelay = const Duration(milliseconds: 10);
      final service = buildService();

      await Future.wait([
        service.syncEpisode(completedEpisodes: 2, anilistMediaId: 101),
        service.syncEpisode(completedEpisodes: 4, anilistMediaId: 102),
      ]);

      final outbox = _readOutbox(storage);
      expect(outbox, hasLength(2));
      expect(outbox.map((item) => item['media_id']), containsAll([101, 102]));
    });
  });

  group('flush', () {
    test('retains outbox entry while its tracker is disconnected', () async {
      _writeOutbox(storage, [
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 3},
      ]);

      await buildService(
        tokens: const {
          TrackingProvider.anilist: null,
          TrackingProvider.myAnimeList: null,
        },
      ).flush();

      expect(_readOutbox(storage), hasLength(1));
    });

    test('succeeds and clears outbox entry', () async {
      _writeOutbox(storage, [
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 3},
      ]);

      await buildService().flush();

      expect(_readOutbox(storage), isEmpty);
      expect(anilistRepo.updates.first.episodes, 3);
    });

    test('retains only failed entries after partial flush', () async {
      anilistRepo.shouldFail = true;
      _writeOutbox(storage, [
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 4},
        {'provider': 'myanimelist', 'media_id': 202, 'completed_episodes': 4},
      ]);

      await buildService().flush();

      final remaining = _readOutbox(storage);
      expect(remaining, hasLength(1));
      expect(remaining.first['provider'], 'anilist');
      expect(malRepo.updates, hasLength(1));
    });

    test('deduplication in outbox keeps highest episode on failure', () async {
      // If the sync fails, the retry outbox should only keep one entry per
      // media – the one with the highest episode count.
      anilistRepo.shouldFail = true;
      _writeOutbox(storage, [
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 2},
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 5},
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 3},
      ]);

      await buildService().flush();

      // All 3 were attempted but all failed; the outbox should now contain
      // only 1 entry – the one with completedEpisodes == 5.
      final outbox = _readOutbox(storage);
      expect(outbox, hasLength(1));
      expect(outbox.first['completed_episodes'], 5);
    });

    test('no-op when outbox is empty', () async {
      await buildService().flush();

      expect(anilistRepo.updates, isEmpty);
      expect(malRepo.updates, isEmpty);
    });

    test('ignores malformed outbox JSON gracefully', () async {
      storage._data[_outboxKey] = 'NOT_JSON{{';

      // Should not throw; should treat as empty outbox.
      await expectLater(buildService().flush(), completes);
      expect(storage._data[_outboxKey], isNull);
    });
  });

  group('deduplication across syncEpisode + existing outbox', () {
    test('higher episode number wins when same media is in outbox', () async {
      // Seed the outbox with a lower episode count for the same media.
      _writeOutbox(storage, [
        {'provider': 'anilist', 'media_id': 101, 'completed_episodes': 2},
      ]);
      anilistRepo.shouldFail = true; // Force both attempts to fail.

      await buildService().syncEpisode(
        completedEpisodes: 6,
        anilistMediaId: 101,
      );

      // The outbox should contain only episode 6, not both 2 and 6.
      final outbox = _readOutbox(storage);
      expect(outbox, hasLength(1));
      expect(outbox.first['completed_episodes'], 6);
    });
  });
}
