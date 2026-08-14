import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/data/anilist_pairing_client.dart';
import 'package:anime_tv/features/auth/domain/pairing_session.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final trackingTokenServiceProvider = Provider<TrackingTokenService>(
  (ref) => TrackingTokenService(ref.watch(secureStorageProvider)),
);

typedef TrackingPairingClientFactory =
    TrackingPairingClient Function(
      TrackingProvider provider, {
      required String baseUrl,
    });

TrackingPairingClient _createPairingClient(
  TrackingProvider provider, {
  required String baseUrl,
}) => TrackingPairingClient(provider, baseUrl: baseUrl);

class TrackingTokenService {
  TrackingTokenService(
    this._storage, {
    this._clientFactory = _createPairingClient,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final TrackingPairingClientFactory _clientFactory;
  final DateTime Function() _now;
  Future<String?>? _myAnimeListRequest;

  Future<String?> accessToken(TrackingProvider provider) async {
    if (provider != TrackingProvider.myAnimeList) {
      return _readToken(provider);
    }

    // MAL refresh tokens rotate. Sharing the same in-flight refresh prevents
    // parallel Home, My List, and Settings requests from invalidating it.
    final activeRequest = _myAnimeListRequest;
    if (activeRequest != null) return activeRequest;

    final request = _myAnimeListAccessToken();
    _myAnimeListRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_myAnimeListRequest, request)) {
        _myAnimeListRequest = null;
      }
    }
  }

  Future<String?> _readToken(TrackingProvider provider) async {
    final accessToken = await _storage.read(key: provider.tokenStorageKey);
    if (accessToken == null || accessToken.isEmpty) return null;
    return accessToken;
  }

  Future<String?> _myAnimeListAccessToken() async {
    const provider = TrackingProvider.myAnimeList;
    final accessToken = await _readToken(provider);
    if (accessToken == null) return null;

    final expiresAtValue = await _storage.read(
      key: provider.expiresAtStorageKey,
    );
    final expiresAt = DateTime.tryParse(expiresAtValue ?? '');
    final now = _now().toUtc();
    if (expiresAt == null ||
        expiresAt.toUtc().isAfter(now.add(const Duration(minutes: 5)))) {
      return accessToken;
    }

    final refreshToken = await _storage.read(
      key: provider.refreshTokenStorageKey,
    );
    final brokerUrl = await effectiveAuthBrokerBaseUrl(_storage);
    if (refreshToken == null || refreshToken.isEmpty || brokerUrl == null) {
      if (!expiresAt.toUtc().isAfter(now)) {
        throw StateError(
          'The MAL session expired and cannot be refreshed. '
          'Reconnect MAL in Settings.',
        );
      }
      return accessToken;
    }

    late final TrackingTokenSet tokens;
    try {
      tokens = await _clientFactory(
        provider,
        baseUrl: brokerUrl,
      ).refresh(refreshToken);
    } catch (_) {
      // A short broker outage should not log the user out while the current
      // access token is still valid. Once expired, surface the real error.
      if (expiresAt.toUtc().isAfter(now)) return accessToken;
      rethrow;
    }

    if (tokens.refreshToken case final rotated? when rotated.isNotEmpty) {
      // Rotating refresh tokens must be committed before the new access
      // token. A process interruption can then retry with the new refresh
      // token instead of stranding a new access token with an invalidated one.
      await _storage.write(
        key: provider.refreshTokenStorageKey,
        value: rotated,
      );
    }
    await _storage.write(
      key: provider.tokenStorageKey,
      value: tokens.accessToken,
    );
    if (tokens.expiresAt case final newExpiry?) {
      await _storage.write(
        key: provider.expiresAtStorageKey,
        value: newExpiry.toUtc().toIso8601String(),
      );
    } else {
      await _storage.delete(key: provider.expiresAtStorageKey);
    }
    return tokens.accessToken;
  }

  Future<void> save(TrackingProvider provider, String token) async {
    // Clear rotated-session metadata first. If the app is interrupted, the
    // previous access token remains usable but can no longer be silently
    // overwritten by stale refresh metadata.
    await _storage.delete(key: provider.refreshTokenStorageKey);
    await _storage.delete(key: provider.expiresAtStorageKey);
    await _storage.write(key: provider.tokenStorageKey, value: token.trim());
  }

  Future<void> clear(TrackingProvider provider) async {
    await Future.wait([
      _storage.delete(key: provider.tokenStorageKey),
      _storage.delete(key: provider.refreshTokenStorageKey),
      _storage.delete(key: provider.expiresAtStorageKey),
    ]);
  }
}
