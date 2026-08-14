import 'dart:async';

import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AnonymousUsageState { active, streaming }

class AnonymousUsageSession {
  const AnonymousUsageSession({
    required this.token,
    required this.heartbeatInterval,
  });

  final String token;
  final Duration heartbeatInterval;
}

abstract interface class AnonymousUsageClient {
  Future<AnonymousUsageSession> createSession();

  Future<void> heartbeat(String token, AnonymousUsageState state);

  Future<void> closeSession(String token);
}

class BrokerAnonymousUsageClient implements AnonymousUsageClient {
  BrokerAnonymousUsageClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _validatedBrokerOrigin(),
              connectTimeout: const Duration(seconds: 6),
              sendTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              responseType: ResponseType.json,
              followRedirects: false,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  static String _validatedBrokerOrigin() {
    final uri = Uri.tryParse(AppConfig.sourcePairingBrokerBaseUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError('Anonymous usage broker is not configured safely.');
    }
    return uri.origin;
  }

  @override
  Future<AnonymousUsageSession> createSession() async {
    final response = await _dio.post<Object?>('/v1/app-presence/sessions');
    final body = response.data;
    if (body is! Map) throw const FormatException('Invalid presence response.');
    final token = body['session_token'];
    final interval = body['heartbeat_interval'];
    if (token is! String ||
        token.length < 32 ||
        token.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token) ||
        interval is! num ||
        interval < 15 ||
        interval > 120) {
      throw const FormatException('Invalid presence response.');
    }
    return AnonymousUsageSession(
      token: token,
      heartbeatInterval: Duration(seconds: interval.round()),
    );
  }

  @override
  Future<void> heartbeat(String token, AnonymousUsageState state) =>
      _dio.put<void>(
        '/v1/app-presence/sessions/current',
        data: {'state': state.name},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

  @override
  Future<void> closeSession(String token) => _dio.delete<void>(
    '/v1/app-presence/sessions/current',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
}

/// Maintains one short-lived, anonymous process session. No identifier is
/// persisted and failures are intentionally silent so telemetry can never
/// block startup or playback.
class AnonymousUsageReporter with WidgetsBindingObserver {
  AnonymousUsageReporter(this._client) {
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  final AnonymousUsageClient _client;
  bool _enabled = false;
  bool _streaming = false;
  bool _resumed = true;
  bool _requestInFlight = false;
  bool _disposed = false;
  String? _token;
  Timer? _timer;
  Duration _interval = const Duration(seconds: 45);

  void setEnabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    if (value) {
      unawaited(_synchronize());
    } else {
      unawaited(_endSession());
    }
  }

  void setStreaming(bool value) {
    if (_disposed || value == _streaming) return;
    _streaming = value;
    unawaited(_synchronize(forceHeartbeat: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed || _streaming) {
      unawaited(_synchronize(forceHeartbeat: true));
    } else {
      unawaited(_endSession());
    }
  }

  bool get _shouldReport => _enabled && (_resumed || _streaming);

  Future<void> _synchronize({bool forceHeartbeat = false}) async {
    if (_disposed || !_shouldReport || _requestInFlight) return;
    _requestInFlight = true;
    try {
      if (_token == null) {
        final session = await _client.createSession();
        if (_disposed || !_shouldReport) {
          await _bestEffortClose(session.token);
          return;
        }
        _token = session.token;
        _interval = session.heartbeatInterval;
        _scheduleHeartbeat();
        forceHeartbeat = true;
      }
      if (forceHeartbeat && _token != null) {
        await _client.heartbeat(
          _token!,
          _streaming
              ? AnonymousUsageState.streaming
              : AnonymousUsageState.active,
        );
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) _token = null;
      _scheduleRetryIfNeeded();
      // Counts are optional and approximate. Never interrupt the app or log
      // potentially identifying network details when the broker is offline.
    } catch (_) {
      _scheduleRetryIfNeeded();
      // Counts are optional and approximate. Never interrupt the app or log
      // potentially identifying network details when the broker is offline.
    } finally {
      _requestInFlight = false;
    }
  }

  void _scheduleRetryIfNeeded() {
    if (!_shouldReport || _disposed || _timer != null) return;
    _timer = Timer(const Duration(seconds: 45), () {
      _timer = null;
      unawaited(_synchronize(forceHeartbeat: true));
    });
  }

  void _scheduleHeartbeat() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      if (_shouldReport) {
        unawaited(_synchronize(forceHeartbeat: true));
      } else {
        unawaited(_endSession());
      }
    });
  }

  Future<void> _endSession() async {
    _timer?.cancel();
    _timer = null;
    final token = _token;
    _token = null;
    if (token != null) await _bestEffortClose(token);
  }

  Future<void> _bestEffortClose(String token) async {
    try {
      await _client.closeSession(token);
    } catch (_) {
      // The broker expires abandoned sessions automatically within minutes.
    }
  }

  void dispose() {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _timer?.cancel();
    final token = _token;
    _token = null;
    if (token != null) unawaited(_bestEffortClose(token));
  }
}

final anonymousUsageClientProvider = Provider<AnonymousUsageClient>(
  (ref) => BrokerAnonymousUsageClient(),
);

final anonymousUsageReporterProvider = Provider<AnonymousUsageReporter>((ref) {
  final reporter = AnonymousUsageReporter(
    ref.watch(anonymousUsageClientProvider),
  );
  ref.listen<bool>(
    settingsPreferencesProvider.select(
      (preferences) => preferences.anonymousUsageCountEnabled,
    ),
    (_, enabled) => reporter.setEnabled(enabled),
    fireImmediately: true,
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});
