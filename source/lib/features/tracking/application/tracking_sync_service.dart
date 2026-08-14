import 'dart:async';
import 'dart:convert';

import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/tracking/data/anilist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/data/myanimelist_tracking_repository.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _trackingOutboxKey = 'tracking_progress_outbox_v1';

final trackingSyncServiceProvider = Provider<TrackingSyncService>(
  (ref) => TrackingSyncService(
    ref.watch(secureStorageProvider),
    ref.watch(trackingTokenServiceProvider),
  ),
);

final trackingOutboxFlushProvider = FutureProvider<void>(
  (ref) => ref.watch(trackingSyncServiceProvider).flush(),
);

/// Callback type for resolving an access token for a given [TrackingProvider].
typedef TokenLookup = Future<String?> Function(TrackingProvider);

class TrackingSyncService {
  TrackingSyncService(this._storage, TrackingTokenService tokenService)
    : _tokenLookup = tokenService.accessToken;

  /// Constructs a service suitable for unit tests, accepting a raw
  /// token-lookup callback instead of a concrete [TrackingTokenService].
  TrackingSyncService.withLookup(this._storage, this._tokenLookup);

  final FlutterSecureStorage _storage;
  final TokenLookup _tokenLookup;
  Future<void> _operationTail = Future<void>.value();

  Future<bool> syncEpisode({
    required int completedEpisodes,
    int? anilistMediaId,
    int? malMediaId,
  }) => _serialize(() async {
    await _flushUnlocked();
    final pending = <_PendingProgress>[];
    if (anilistMediaId != null) {
      pending.add(
        _PendingProgress(
          provider: TrackingProvider.anilist,
          mediaId: anilistMediaId,
          completedEpisodes: completedEpisodes,
        ),
      );
    }
    if (malMediaId != null) {
      pending.add(
        _PendingProgress(
          provider: TrackingProvider.myAnimeList,
          mediaId: malMediaId,
          completedEpisodes: completedEpisodes,
        ),
      );
    }
    if (pending.isEmpty) return false;
    return _syncAll(pending, preserveExistingOutbox: true);
  });

  Future<void> flush() => _serialize(_flushUnlocked);

  Future<void> _flushUnlocked() async {
    final pending = await _readOutbox();
    if (pending.isEmpty) return;
    await _syncAll(pending, preserveExistingOutbox: false);
  }

  /// Serializes outbox reads and writes so simultaneous player callbacks do
  /// not overwrite newer progress with an older snapshot.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    }();
  }

  Future<bool> _syncAll(
    List<_PendingProgress> pending, {
    required bool preserveExistingOutbox,
  }) async {
    var allSucceeded = true;
    final retry = preserveExistingOutbox
        ? await _readOutbox()
        : <_PendingProgress>[];
    for (final item in pending) {
      try {
        final token = await _tokenLookup(item.provider);
        if (token == null || token.isEmpty) {
          allSucceeded = false;
          retry.add(item);
          continue;
        }
        final repository = buildRepository(item.provider, token);
        await repository.updateProgress(
          mediaId: item.mediaId,
          completedEpisodes: item.completedEpisodes,
        );
      } catch (_) {
        allSucceeded = false;
        retry.add(item);
      }
    }
    await _writeOutbox(_deduplicate(retry));
    return allSucceeded;
  }

  /// Creates a [TrackingRepository] for the given [provider] and [token].
  ///
  /// Override in tests to inject a fake repository.
  TrackingRepository buildRepository(TrackingProvider provider, String token) {
    return switch (provider) {
      TrackingProvider.anilist => AniListTrackingRepository(accessToken: token),
      TrackingProvider.myAnimeList => MyAnimeListTrackingRepository(
        accessToken: token,
      ),
    };
  }

  Future<List<_PendingProgress>> _readOutbox() async {
    final value = await _storage.read(key: _trackingOutboxKey);
    if (value == null || value.isEmpty) return [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_PendingProgress.fromJson)
          .toList();
    } catch (_) {
      // A corrupted outbox can never be retried successfully. Clear it so
      // every future launch does not repeatedly parse the same bad payload.
      await _storage.delete(key: _trackingOutboxKey);
      return [];
    }
  }

  Future<void> _writeOutbox(List<_PendingProgress> items) async {
    if (items.isEmpty) {
      await _storage.delete(key: _trackingOutboxKey);
      return;
    }
    await _storage.write(
      key: _trackingOutboxKey,
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<_PendingProgress> _deduplicate(List<_PendingProgress> items) {
    final result = <String, _PendingProgress>{};
    for (final item in items) {
      final key = '${item.provider.slug}:${item.mediaId}';
      final existing = result[key];
      if (existing == null ||
          item.completedEpisodes > existing.completedEpisodes) {
        result[key] = item;
      }
    }
    return result.values.toList(growable: false);
  }
}

class _PendingProgress {
  const _PendingProgress({
    required this.provider,
    required this.mediaId,
    required this.completedEpisodes,
  });

  final TrackingProvider provider;
  final int mediaId;
  final int completedEpisodes;

  factory _PendingProgress.fromJson(Map<String, dynamic> json) {
    return _PendingProgress(
      provider: TrackingProvider.values.firstWhere(
        (provider) => provider.slug == json['provider'],
      ),
      mediaId: json['media_id'] as int,
      completedEpisodes: json['completed_episodes'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.slug,
    'media_id': mediaId,
    'completed_episodes': completedEpisodes,
  };
}
