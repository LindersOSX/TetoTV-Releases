import 'package:anime_tv/features/auth/data/real_debrid_oauth_client.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storage = FlutterSecureStorage();

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('saving a manual token clears stale OAuth refresh metadata', () async {
    FlutterSecureStorage.setMockInitialValues({
      realDebridTokenStorageKey: 'old-oauth-token',
      realDebridRefreshTokenStorageKey: 'stale-refresh-token',
      realDebridClientIdStorageKey: 'stale-client-id',
      realDebridClientSecretStorageKey: 'stale-client-secret',
      realDebridAccessExpiryStorageKey: DateTime.utc(2020).toIso8601String(),
    });
    final controller = RealDebridSettingsController(
      storage,
      (_) => _ValidRealDebridClient(),
    );

    expect(await controller.saveAndValidate('manual-api-token'), isTrue);
    expect(
      await storage.read(key: realDebridTokenStorageKey),
      'manual-api-token',
    );
    expect(await storage.read(key: realDebridRefreshTokenStorageKey), isNull);
    expect(await storage.read(key: realDebridClientIdStorageKey), isNull);
    expect(await storage.read(key: realDebridClientSecretStorageKey), isNull);
    expect(await storage.read(key: realDebridAccessExpiryStorageKey), isNull);
  });

  test('rejects and does not persist a non-Premium account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = RealDebridSettingsController(
      storage,
      (_) => _FreeRealDebridClient(),
    );

    expect(await controller.saveAndValidate('free-account-token'), isFalse);
    expect(await storage.read(key: realDebridTokenStorageKey), isNull);
    expect(controller.state.hasSavedToken, isFalse);
    expect(controller.state.errorMessage, contains('active Premium plan'));
  });

  test('keeps a valid account visible during a refresh outage', () async {
    final now = DateTime.utc(2026, 8, 8, 12);
    FlutterSecureStorage.setMockInitialValues({
      realDebridTokenStorageKey: 'still-valid-token',
      realDebridRefreshTokenStorageKey: 'refresh-token',
      realDebridClientIdStorageKey: 'client-id',
      realDebridClientSecretStorageKey: 'client-secret',
      realDebridAccessExpiryStorageKey: now
          .add(const Duration(minutes: 2))
          .toIso8601String(),
    });
    final controller = RealDebridSettingsController(
      storage,
      (_) => _ValidRealDebridClient(),
      oauthClient: _FailingOAuthClient(),
      now: () => now,
    );

    await controller.load();

    expect(controller.state.hasSavedToken, isTrue);
    expect(controller.state.account?.isPremium, isTrue);
    expect(controller.state.errorMessage, isNull);
  });
}

class _ValidRealDebridClient extends RealDebridClient {
  _ValidRealDebridClient() : super(token: 'test');

  @override
  Future<RealDebridAccount> account() async =>
      const RealDebridAccount(id: 1, username: 'test-user', type: 'premium');
}

class _FreeRealDebridClient extends RealDebridClient {
  _FreeRealDebridClient() : super(token: 'test');

  @override
  Future<RealDebridAccount> account() async =>
      const RealDebridAccount(id: 2, username: 'free-user', type: 'free');
}

class _FailingOAuthClient extends RealDebridOAuthClient {
  @override
  Future<RealDebridTokenSet> refresh({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async => throw StateError('temporary OAuth outage');
}
