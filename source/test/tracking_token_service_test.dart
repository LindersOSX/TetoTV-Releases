import 'dart:async';

import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/data/anilist_pairing_client.dart';
import 'package:anime_tv/features/auth/domain/pairing_session.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();
  final now = DateTime.utc(2026, 8, 2, 12);

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('shares one rotating MAL refresh across concurrent callers', () async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.myAnimeList.tokenStorageKey: 'old-access',
      TrackingProvider.myAnimeList.refreshTokenStorageKey: 'old-refresh',
      TrackingProvider.myAnimeList.expiresAtStorageKey: now
          .add(const Duration(minutes: 2))
          .toIso8601String(),
      authBrokerUrlStorageKey: 'https://auth.example.test',
    });
    final refresh = Completer<TrackingTokenSet>();
    final client = _FakePairingClient(() => refresh.future);
    final service = TrackingTokenService(
      storage,
      clientFactory: (_, {required baseUrl}) => client,
      now: () => now,
    );

    final first = service.accessToken(TrackingProvider.myAnimeList);
    final second = service.accessToken(TrackingProvider.myAnimeList);
    await Future<void>.delayed(Duration.zero);
    expect(client.refreshCalls, 1);

    refresh.complete(
      TrackingTokenSet(
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );
    expect(await Future.wait([first, second]), ['new-access', 'new-access']);
    expect(
      await storage.read(
        key: TrackingProvider.myAnimeList.refreshTokenStorageKey,
      ),
      'new-refresh',
    );
  });

  test('keeps a still-valid MAL token during a broker outage', () async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.myAnimeList.tokenStorageKey: 'still-valid',
      TrackingProvider.myAnimeList.refreshTokenStorageKey: 'refresh',
      TrackingProvider.myAnimeList.expiresAtStorageKey: now
          .add(const Duration(minutes: 2))
          .toIso8601String(),
      authBrokerUrlStorageKey: 'https://auth.example.test',
    });
    final service = TrackingTokenService(
      storage,
      clientFactory: (_, {required baseUrl}) =>
          _FakePairingClient(() async => throw StateError('broker sleeping')),
      now: () => now,
    );

    expect(
      await service.accessToken(TrackingProvider.myAnimeList),
      'still-valid',
    );
  });

  test('requires reconnect when an expired MAL token cannot refresh', () async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.myAnimeList.tokenStorageKey: 'expired',
      TrackingProvider.myAnimeList.expiresAtStorageKey: now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    final service = TrackingTokenService(storage, now: () => now);

    await expectLater(
      service.accessToken(TrackingProvider.myAnimeList),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Reconnect MAL'),
        ),
      ),
    );
  });

  test('manual token entry clears stale QR refresh metadata', () async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.myAnimeList.tokenStorageKey: 'old-access',
      TrackingProvider.myAnimeList.refreshTokenStorageKey: 'old-refresh',
      TrackingProvider.myAnimeList.expiresAtStorageKey: now.toIso8601String(),
    });
    final service = TrackingTokenService(storage, now: () => now);

    await service.save(TrackingProvider.myAnimeList, '  manual-access  ');

    expect(
      await storage.read(key: TrackingProvider.myAnimeList.tokenStorageKey),
      'manual-access',
    );
    expect(
      await storage.read(
        key: TrackingProvider.myAnimeList.refreshTokenStorageKey,
      ),
      isNull,
    );
    expect(
      await storage.read(key: TrackingProvider.myAnimeList.expiresAtStorageKey),
      isNull,
    );
  });
}

class _FakePairingClient extends TrackingPairingClient {
  _FakePairingClient(this._refresh)
    : super(TrackingProvider.myAnimeList, baseUrl: 'https://auth.example.test');

  final Future<TrackingTokenSet> Function() _refresh;
  int refreshCalls = 0;

  @override
  Future<TrackingTokenSet> refresh(String refreshToken) {
    refreshCalls++;
    return _refresh();
  }
}
