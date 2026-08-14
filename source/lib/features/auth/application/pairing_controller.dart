import 'dart:async';

import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/features/auth/data/anilist_pairing_client.dart';
import 'package:anime_tv/features/auth/domain/pairing_session.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

const authBrokerUrlStorageKey = 'auth_broker_base_url';

class AuthBrokerNotConfigured implements Exception {
  const AuthBrokerNotConfigured();

  @override
  String toString() =>
      'AniList and MAL QR login requires the TetoTV OAuth broker.';
}

String? normalizeAuthBrokerBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri
      .replace(
        path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
        query: null,
        fragment: null,
      )
      .toString();
}

Future<String?> effectiveAuthBrokerBaseUrl(FlutterSecureStorage storage) async {
  final saved = await storage.read(key: authBrokerUrlStorageKey);
  final savedUrl = normalizeAuthBrokerBaseUrl(saved ?? '');
  if (savedUrl != null) return savedUrl;
  return normalizeAuthBrokerBaseUrl(AppConfig.authBrokerBaseUrl);
}

final pairingControllerProvider = StateNotifierProvider.autoDispose
    .family<PairingController, AsyncValue<PairingSession?>, TrackingProvider>((
      ref,
      provider,
    ) {
      return PairingController(provider, ref.watch(secureStorageProvider));
    });

class PairingController extends StateNotifier<AsyncValue<PairingSession?>> {
  PairingController(this._provider, this._storage)
    : super(const AsyncData(null));

  final TrackingProvider _provider;
  final FlutterSecureStorage _storage;
  TrackingPairingClient? _activeClient;
  Timer? _pollTimer;
  bool _polling = false;
  int _consecutivePollFailures = 0;
  int _generation = 0;

  Future<void> start() async {
    final generation = ++_generation;
    _pollTimer?.cancel();
    _activeClient = null;
    _consecutivePollFailures = 0;
    state = const AsyncLoading();
    try {
      final configuredUrl = await effectiveAuthBrokerBaseUrl(_storage);
      if (!mounted || generation != _generation) return;
      if (configuredUrl == null) {
        throw const AuthBrokerNotConfigured();
      }
      final client = TrackingPairingClient(_provider, baseUrl: configuredUrl);
      _activeClient = client;
      await client.ensureReady();
      if (!mounted || generation != _generation) return;
      final session = await client.createSession();
      if (!mounted || generation != _generation) return;
      state = AsyncData(session);
      _pollTimer = Timer.periodic(
        session.pollInterval,
        (_) => _poll(generation),
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _poll(int generation) async {
    if (!mounted || generation != _generation) return;
    final client = _activeClient;
    if (_polling || client == null) return;
    final session = state.valueOrNull;
    if (session == null || session.status != PairingStatus.pending) return;
    if (DateTime.now().isAfter(session.expiresAt)) {
      _pollTimer?.cancel();
      state = AsyncData(session.copyWith(status: PairingStatus.expired));
      return;
    }

    _polling = true;
    try {
      final result = await client.poll(session);
      if (!mounted || generation != _generation) return;
      _consecutivePollFailures = 0;
      if (result.status == PairingStatus.authorized) {
        final token = result.accessToken;
        if (token == null || token.isEmpty) {
          throw const FormatException(
            'Pairing completed without an access token.',
          );
        }
        final refreshToken = result.refreshToken;
        final expiresAt = result.expiresAt;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _storage.write(
            key: _provider.refreshTokenStorageKey,
            value: refreshToken,
          );
        } else {
          await _storage.delete(key: _provider.refreshTokenStorageKey);
        }
        await _storage.write(key: _provider.tokenStorageKey, value: token);
        if (expiresAt != null) {
          await _storage.write(
            key: _provider.expiresAtStorageKey,
            value: expiresAt.toUtc().toIso8601String(),
          );
        } else {
          await _storage.delete(key: _provider.expiresAtStorageKey);
        }
        if (!mounted || generation != _generation) return;
        _pollTimer?.cancel();
      } else if (result.status == PairingStatus.expired) {
        _pollTimer?.cancel();
      }
      state = AsyncData(session.copyWith(status: result.status));
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= 3 ||
          DateTime.now().isAfter(session.expiresAt)) {
        state = AsyncError(error, stackTrace);
        _pollTimer?.cancel();
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    _activeClient = null;
    super.dispose();
  }
}
