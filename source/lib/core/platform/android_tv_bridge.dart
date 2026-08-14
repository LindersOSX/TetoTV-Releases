import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TvDisplayMode {
  const TvDisplayMode({
    required this.id,
    required this.width,
    required this.height,
    required this.refreshRate,
  });

  final int id;
  final int width;
  final int height;
  final double refreshRate;

  factory TvDisplayMode.fromMap(Map<Object?, Object?> value) => TvDisplayMode(
    id: value['id'] as int? ?? 0,
    width: value['width'] as int? ?? 0,
    height: value['height'] as int? ?? 0,
    refreshRate: (value['refreshRate'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'refreshRate': refreshRate,
  };
}

class TvCodecCapability {
  const TvCodecCapability({
    required this.name,
    required this.mime,
    required this.hardware,
    this.tenBit = false,
    this.maxWidth = 0,
    this.maxHeight = 0,
  });

  final String name;
  final String mime;
  final bool hardware;
  final bool tenBit;
  final int maxWidth;
  final int maxHeight;

  factory TvCodecCapability.fromMap(Map<Object?, Object?> value) =>
      TvCodecCapability(
        name: value['name'] as String? ?? '',
        mime: value['mime'] as String? ?? '',
        hardware: value['hardware'] as bool? ?? false,
        tenBit: value['tenBit'] as bool? ?? false,
        maxWidth: value['maxWidth'] as int? ?? 0,
        maxHeight: value['maxHeight'] as int? ?? 0,
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'mime': mime,
    'hardware': hardware,
    'tenBit': tenBit,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
  };
}

class TvDeviceProfile {
  const TvDeviceProfile({
    required this.manufacturer,
    required this.model,
    required this.sdk,
    required this.abis,
    required this.displayModes,
    required this.hdrTypes,
    required this.codecs,
    required this.audioOutputs,
  });

  const TvDeviceProfile.unknown()
    : manufacturer = 'Unknown',
      model = 'Unknown',
      sdk = 0,
      abis = const [],
      displayModes = const [],
      hdrTypes = const [],
      codecs = const [],
      audioOutputs = const [];

  final String manufacturer;
  final String model;
  final int sdk;
  final List<String> abis;
  final List<TvDisplayMode> displayModes;
  final List<int> hdrTypes;
  final List<TvCodecCapability> codecs;
  final List<Map<String, Object?>> audioOutputs;

  String get key => '$manufacturer/$model/sdk$sdk'.toLowerCase();
  bool get hasHdr => hdrTypes.isNotEmpty;
  bool get hasHdmiAudio => audioOutputs.any((output) => output['hdmi'] == true);

  bool supportsCodec(String? codec) {
    final normalized = codec?.toLowerCase() ?? '';
    final mime = switch (normalized) {
      final value when value.contains('av1') => 'video/av01',
      final value when value.contains('hevc') || value.contains('h265') =>
        'video/hevc',
      final value when value.contains('h264') || value.contains('avc') =>
        'video/avc',
      final value when value.contains('vp9') => 'video/x-vnd.on2.vp9',
      _ => '',
    };
    if (mime.isEmpty) return true;
    return codecs.any((item) => item.mime == mime && item.hardware);
  }

  Map<String, Object?> toJson() => {
    'manufacturer': manufacturer,
    'model': model,
    'sdk': sdk,
    'abis': abis,
    'displayModes': displayModes.map((mode) => mode.toJson()).toList(),
    'hdrTypes': hdrTypes,
    'codecs': codecs.map((codec) => codec.toJson()).toList(),
    'audioOutputs': audioOutputs,
  };

  factory TvDeviceProfile.fromMap(Map<Object?, Object?> value) {
    List<Map<Object?, Object?>> maps(Object? input) =>
        (input as List? ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<Object?, Object?>())
            .toList(growable: false);
    return TvDeviceProfile(
      manufacturer: value['manufacturer'] as String? ?? 'Unknown',
      model: value['model'] as String? ?? 'Unknown',
      sdk: value['sdk'] as int? ?? 0,
      abis: (value['abis'] as List? ?? const []).whereType<String>().toList(),
      displayModes: maps(
        value['displayModes'],
      ).map(TvDisplayMode.fromMap).toList(growable: false),
      hdrTypes: (value['hdrTypes'] as List? ?? const [])
          .whereType<int>()
          .toList(),
      codecs: maps(
        value['codecs'],
      ).map(TvCodecCapability.fromMap).toList(growable: false),
      audioOutputs: maps(value['audioOutputs'])
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false),
    );
  }
}

class MediaAction {
  const MediaAction(this.action, this.value);
  final String action;
  final int? value;
}

class DiscordBridgeEvent {
  const DiscordBridgeEvent(this.type, this.data);

  final String type;
  final Map<Object?, Object?> data;
}

/// A tri-state result keeps a missing or slow native bridge from being
/// mistaken for a phone. Discord may open browser OAuth only after Android
/// explicitly reports [mobile].
enum AndroidDeviceCategory { television, mobile, unknown }

class DiscordTokenBundle {
  const DiscordTokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    required this.scopes,
  });

  final String accessToken;
  final String refreshToken;
  final int tokenType;
  final DateTime expiresAt;
  final String scopes;

  factory DiscordTokenBundle.fromMap(Map<Object?, Object?> value) {
    return DiscordTokenBundle(
      accessToken: value['accessToken'] as String? ?? '',
      refreshToken: value['refreshToken'] as String? ?? '',
      tokenType: (value['tokenType'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (value['expiresAtMs'] as num?)?.toInt() ?? 0,
      ),
      scopes: value['scopes'] as String? ?? '',
    );
  }
}

class AppVersionInfo {
  const AppVersionInfo({required this.name, required this.code});

  const AppVersionInfo.unknown() : name = 'unknown', code = 0;

  final String name;
  final int code;

  factory AppVersionInfo.fromMap(Map<Object?, Object?> value) => AppVersionInfo(
    name: value['versionName'] as String? ?? 'unknown',
    code: (value['versionCode'] as num?)?.toInt() ?? 0,
  );
}

class LocalMediaDocument {
  const LocalMediaDocument({
    required this.uri,
    required this.name,
    this.mimeType,
    this.size,
    this.persistedReadPermission = false,
  });

  final Uri uri;
  final String name;
  final String? mimeType;
  final int? size;
  final bool persistedReadPermission;

  factory LocalMediaDocument.fromMap(Map<Object?, Object?> value) {
    final rawUri = value['uri'] as String? ?? '';
    final uri = Uri.tryParse(rawUri);
    if (uri == null ||
        uri.scheme != 'content' ||
        !uri.hasAuthority ||
        uri.authority.trim().isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('Android returned an invalid local video.');
    }
    return LocalMediaDocument(
      uri: uri,
      name: (value['name'] as String?)?.trim().isNotEmpty == true
          ? (value['name'] as String).trim()
          : 'Local video',
      mimeType: (value['mimeType'] as String?)?.trim(),
      size: (value['size'] as num?)?.toInt(),
      persistedReadPermission:
          value['persistedReadPermission'] as bool? ?? false,
    );
  }
}

class ApkCompatibilityInfo {
  const ApkCompatibilityInfo({
    required this.compatible,
    required this.issues,
    this.packageName,
    this.versionCode = 0,
    this.versionName,
    this.minSdk = 0,
    this.archiveAbis = const [],
    this.deviceAbis = const [],
    this.signerMatches = false,
  });

  final bool compatible;
  final List<String> issues;
  final String? packageName;
  final int versionCode;
  final String? versionName;
  final int minSdk;
  final List<String> archiveAbis;
  final List<String> deviceAbis;
  final bool signerMatches;

  factory ApkCompatibilityInfo.fromMap(Map<Object?, Object?> value) =>
      ApkCompatibilityInfo(
        compatible: value['compatible'] as bool? ?? false,
        issues: (value['issues'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        packageName: value['packageName'] as String?,
        versionCode: (value['versionCode'] as num?)?.toInt() ?? 0,
        versionName: value['versionName'] as String?,
        minSdk: (value['minSdk'] as num?)?.toInt() ?? 0,
        archiveAbis: (value['archiveAbis'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        deviceAbis: (value['deviceAbis'] as List? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        signerMatches: value['signerMatches'] as bool? ?? false,
      );
}

class NativePlaybackResult {
  const NativePlaybackResult({
    required this.status,
    required this.position,
    required this.duration,
    this.completed = false,
    this.firstFrameRendered = false,
    this.droppedFrames = 0,
    this.decoder,
    this.error,
    this.subtitleSize,
    this.subtitleBackgroundColor,
    this.highContrastSubtitles,
    this.audioLanguage,
    this.audioPreferenceSet = false,
    this.subtitleLanguage,
    this.subtitlesEnabled,
    this.diagnostics = const {},
  });

  final String status;
  final Duration position;
  final Duration duration;
  final bool completed;
  final bool firstFrameRendered;
  final int droppedFrames;
  final String? decoder;
  final String? error;
  final double? subtitleSize;
  final int? subtitleBackgroundColor;
  final bool? highContrastSubtitles;
  final String? audioLanguage;
  final bool audioPreferenceSet;
  final String? subtitleLanguage;
  final bool? subtitlesEnabled;
  final Map<String, Object?> diagnostics;

  bool get failed => status == 'error' || status == 'no_first_frame';

  factory NativePlaybackResult.fromMap(Map<Object?, Object?> value) =>
      NativePlaybackResult(
        status: value['status'] as String? ?? 'exit',
        position: Duration(
          milliseconds: (value['positionMs'] as num?)?.round() ?? 0,
        ),
        duration: Duration(
          milliseconds: (value['durationMs'] as num?)?.round() ?? 0,
        ),
        completed: value['completed'] as bool? ?? false,
        firstFrameRendered: value['firstFrameRendered'] as bool? ?? false,
        droppedFrames: (value['droppedFrames'] as num?)?.round() ?? 0,
        decoder: value['decoder'] as String?,
        error: value['error'] as String?,
        subtitleSize: (value['subtitleSize'] as num?)?.toDouble(),
        subtitleBackgroundColor: (value['subtitleBackgroundColor'] as num?)
            ?.toInt()
            .toUnsigned(32),
        highContrastSubtitles: value['highContrastSubtitles'] as bool?,
        audioLanguage: value['audioLanguage'] as String?,
        audioPreferenceSet: value['audioPreferenceSet'] as bool? ?? false,
        subtitleLanguage: value['subtitleLanguage'] as String?,
        subtitlesEnabled: value['subtitlesEnabled'] as bool?,
        diagnostics: {
          for (final key in const [
            'surfaceReady',
            'manufacturer',
            'model',
            'sdk',
            'abis',
            'memoryClassMb',
            'lowMemoryDevice',
            'videoMime',
            'videoCodecs',
            'videoWidth',
            'videoHeight',
            'videoFrameRate',
            'audioMime',
            'audioCodecs',
          ])
            if (value.containsKey(key)) key: value[key],
        },
      );

  factory NativePlaybackResult.platformError(Object error) =>
      NativePlaybackResult(
        status: 'error',
        position: Duration.zero,
        duration: Duration.zero,
        error: error.toString(),
      );
}

class AndroidTvBridge {
  AndroidTvBridge._() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  static final instance = AndroidTvBridge._();
  static const _channel = MethodChannel('dev.tetotv/android_tv');
  final _mediaActions = StreamController<MediaAction>.broadcast();
  final _discordEvents = StreamController<DiscordBridgeEvent>.broadcast();
  TvDeviceProfile? _cachedProfile;
  AndroidDeviceCategory? _cachedDeviceCategory;

  Stream<MediaAction> get mediaActions => _mediaActions.stream;
  Stream<DiscordBridgeEvent> get discordEvents => _discordEvents.stream;

  Future<void> playHomeEasterEgg({
    Duration maximumDuration = const Duration(seconds: 10),
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('playHomeEasterEgg', {
        'maximumDurationMs': maximumDuration.inMilliseconds,
      });
    } on PlatformException {
      // This hidden decoration must never interfere with Home navigation.
    } on MissingPluginException {
      // Desktop/widget hosts intentionally do not install the Android bridge.
    }
  }

  Future<void> stopHomeEasterEgg() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stopHomeEasterEgg');
    } on PlatformException {
      // Best effort only; Android also releases the local player on destroy.
    } on MissingPluginException {
      // Desktop/widget hosts intentionally do not install the Android bridge.
    }
  }

  Future<AndroidDeviceCategory> getDeviceCategory({
    bool refresh = false,
  }) async {
    if (!refresh && _cachedDeviceCategory != null) {
      return _cachedDeviceCategory!;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AndroidDeviceCategory.mobile;
    }
    try {
      final television = await _channel.invokeMethod<bool>('isTelevision');
      if (television == null) return AndroidDeviceCategory.unknown;
      return _cachedDeviceCategory = television
          ? AndroidDeviceCategory.television
          : AndroidDeviceCategory.mobile;
    } on PlatformException {
      return AndroidDeviceCategory.unknown;
    } on MissingPluginException {
      return AndroidDeviceCategory.unknown;
    }
  }

  Future<bool> isTelevision({bool refresh = false}) async =>
      await getDeviceCategory(refresh: refresh) ==
      AndroidDeviceCategory.television;

  Future<dynamic> _handleMethod(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<Object?, Object?>();
    switch (call.method) {
      case 'mediaAction':
        if (args == null) return;
        _mediaActions.add(
          MediaAction(args['action'] as String? ?? '', args['value'] as int?),
        );
        return;
      case 'discordConnectionState':
      case 'discordPresenceError':
        _discordEvents.add(DiscordBridgeEvent(call.method, args ?? const {}));
        return;
      case 'discordTokenExpiring':
        _discordEvents.add(DiscordBridgeEvent(call.method, const {}));
        return;
    }
  }

  Future<Map<Object?, Object?>> discordSdkInfo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const {'available': false, 'status': 'unsupported'};
    }
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(
            'discordSdkInfo',
          ) ??
          const {'available': false, 'status': 'unavailable'};
    } on PlatformException {
      return const {'available': false, 'status': 'unavailable'};
    } on MissingPluginException {
      return const {'available': false, 'status': 'unavailable'};
    }
  }

  Future<DiscordTokenBundle> discordAuthenticate() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'discordAuthenticate',
    );
    if (result == null) {
      throw PlatformException(
        code: 'DISCORD_AUTH_EMPTY',
        message: 'Discord did not return an account token.',
      );
    }
    return DiscordTokenBundle.fromMap(result);
  }

  Future<void> discordCancelAuthentication() async {
    await _channel.invokeMethod<void>('discordCancelAuthentication');
  }

  Future<DiscordTokenBundle> discordRefreshToken(String refreshToken) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'discordRefreshToken',
      {'refreshToken': refreshToken},
    );
    if (result == null) {
      throw PlatformException(
        code: 'DISCORD_REFRESH_EMPTY',
        message: 'Discord did not return a refreshed token.',
      );
    }
    return DiscordTokenBundle.fromMap(result);
  }

  Future<void> discordConnect(DiscordTokenBundle token) async {
    await _channel.invokeMethod<void>('discordConnect', {
      'accessToken': token.accessToken,
      'tokenType': token.tokenType,
    });
  }

  Future<bool> discordRevoke(String token) async {
    return await _channel.invokeMethod<bool>('discordRevoke', {
          'token': token,
        }) ??
        false;
  }

  Future<void> discordDisconnect() async {
    await _channel.invokeMethod<void>('discordDisconnect');
  }

  Future<TvDeviceProfile> getDeviceProfile({bool refresh = false}) async {
    if (!refresh && _cachedProfile != null) return _cachedProfile!;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const TvDeviceProfile.unknown();
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getDeviceProfile',
      );
      return _cachedProfile = result == null
          ? const TvDeviceProfile.unknown()
          : TvDeviceProfile.fromMap(result);
    } on PlatformException {
      return const TvDeviceProfile.unknown();
    }
  }

  Future<AppVersionInfo> getAppVersion() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const AppVersionInfo.unknown();
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getAppVersion',
      );
      return result == null
          ? const AppVersionInfo.unknown()
          : AppVersionInfo.fromMap(result);
    } on PlatformException {
      return const AppVersionInfo.unknown();
    }
  }

  Future<String> installApk(String path) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(
        code: 'APK_INSTALL_UNSUPPORTED',
        message: 'APK installation is only supported on Android.',
      );
    }
    return await _channel.invokeMethod<String>('installApk', {'path': path}) ??
        'launched';
  }

  Future<ApkCompatibilityInfo> inspectApk(String path) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const ApkCompatibilityInfo(
        compatible: false,
        issues: ['APK installation is only supported on Android.'],
      );
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'inspectApk',
      {'path': path},
    );
    return result == null
        ? const ApkCompatibilityInfo(
            compatible: false,
            issues: ['Android could not inspect the downloaded APK.'],
          )
        : ApkCompatibilityInfo.fromMap(result);
  }

  Future<String?> voiceSearch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final result = await _channel.invokeMethod<String>('voiceSearch');
    final query = result?.trim() ?? '';
    return query.isEmpty ? null : query;
  }

  /// Opens Android's permission-scoped document picker for one video.
  ///
  /// The returned content URI may refer to internal storage or a mounted USB
  /// provider. Android owns the picker and grants only read access to the
  /// selected document, so no broad storage permission is required.
  Future<LocalMediaDocument?> pickLocalVideo() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(
        code: 'LOCAL_MEDIA_UNSUPPORTED',
        message: 'Local media is only available on Android devices.',
      );
    }
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'pickLocalVideo',
    );
    return value == null ? null : LocalMediaDocument.fromMap(value);
  }

  /// Removes only disposable application cache and downloaded update files.
  /// Accounts, preferences, sources, history, databases, and secure storage
  /// live outside Android's cache directories and are intentionally retained.
  Future<int> clearAppCache() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(
        code: 'APP_STORAGE_UNSUPPORTED',
        message: 'Storage cleanup is only supported on Android.',
      );
    }
    return await _channel.invokeMethod<int>('clearAppCache') ?? 0;
  }

  /// Requests Android to erase this application's complete private data.
  /// A successful request terminates the process, so callers should not expect
  /// the returned Future to complete on a physical device.
  Future<void> resetApplicationData() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(
        code: 'APP_STORAGE_UNSUPPORTED',
        message: 'Reset is only supported on Android.',
      );
    }
    final accepted =
        await _channel.invokeMethod<bool>('resetApplicationData') ?? false;
    if (!accepted) {
      throw PlatformException(
        code: 'APP_RESET_REJECTED',
        message: 'Android could not start the application reset.',
      );
    }
  }

  Future<void> setAnonymousCrashReportingEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('setAnonymousCrashReportingEnabled', {
      'enabled': enabled,
    });
  }

  Future<bool> storePendingAnonymousCrashReport(
    Map<String, Object?> report,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>(
          'storePendingAnonymousCrashReport',
          report,
        ) ??
        false;
  }

  Future<Map<String, Object?>?> getPendingAnonymousCrashReport() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getPendingAnonymousCrashReport',
    );
    return value?.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> acknowledgeAnonymousCrashReport(String reportId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('acknowledgeAnonymousCrashReport', {
      'reportId': reportId,
    });
  }

  Future<void> clearPendingAnonymousCrashReports() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('clearPendingAnonymousCrashReports');
  }

  Future<void> setPreferredFrameRate(double fps) async {
    if (fps <= 0 || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<int>('setPreferredFrameRate', {'fps': fps});
    } on PlatformException {
      // Mode switching is optional and unsupported by some Fire OS builds.
    }
  }

  Future<void> clearPreferredFrameRate() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('clearPreferredFrameRate');
    } on PlatformException {
      // Best effort only.
    }
  }

  /// Starts the dedicated Android Media3 player activity.
  ///
  /// Video is rendered by a native SurfaceView in a separate activity. This is
  /// deliberately not an AndroidView/Flutter texture: several Fire TV devices
  /// corrupt or drop frames when a decoder has to copy video through Flutter's
  /// texture compositor.
  Future<NativePlaybackResult> startNativePlayer({
    required Uri source,
    required String title,
    required String checkpointKey,
    required String releaseName,
    required String streamLabel,
    required Duration resumePosition,
    required bool startFromBeginning,
    DateTime? resumeUpdatedAt,
    String? externalSubtitle,
    String? mediaContentType,
    String? subtitleContentType,
    bool externalSubtitleRejected = false,
    String audioLanguage = 'eng',
    String subtitleLanguage = 'eng',
    bool subtitlesEnabled = true,
    double subtitleSize = 34,
    int subtitlePosition = 100,
    bool highContrastSubtitles = false,
    int subtitleTextColor = 0xFFFFFFFF,
    int subtitleBackgroundColor = 0x00000000,
    int seekBackSeconds = 10,
    int seekForwardSeconds = 10,
    bool autoSkipIntros = false,
    bool autoSkipOutros = false,
    String videoFit = 'contain',
    int? malMediaId,
    int? episodeNumber,
    String? artworkUrl,
    bool hasDirectSources = false,
    Map<String, String> headers = const {},
    bool trustedLocalSource = false,
    bool trustedPlaybackProxy = false,
    Map<String, Object> theme = const {},
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const NativePlaybackResult(
        status: 'unsupported',
        position: Duration.zero,
        duration: Duration.zero,
        error: 'The native Media3 player is only available on Android.',
      );
    }
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'startNativePlayer',
        {
          'source': source.toString(),
          'title': title,
          'checkpointKey': checkpointKey,
          'releaseName': releaseName,
          'streamLabel': streamLabel,
          'resumeMs': resumePosition.inMilliseconds,
          'resumeProvided':
              resumeUpdatedAt != null || resumePosition > Duration.zero,
          if (resumeUpdatedAt != null)
            'resumeUpdatedAtMs': resumeUpdatedAt.millisecondsSinceEpoch,
          'startFromBeginning': startFromBeginning,
          if (externalSubtitle != null && externalSubtitle.isNotEmpty)
            'externalSubtitle': externalSubtitle,
          if (mediaContentType != null && mediaContentType.isNotEmpty)
            'mimeType': mediaContentType,
          if (subtitleContentType != null && subtitleContentType.isNotEmpty)
            'subtitleMimeType': subtitleContentType,
          if (externalSubtitleRejected) 'externalSubtitleRejected': true,
          'audioLanguage': audioLanguage,
          'subtitleLanguage': subtitleLanguage,
          'subtitlesEnabled': subtitlesEnabled,
          'subtitleSize': subtitleSize,
          'subtitlePosition': subtitlePosition,
          'highContrastSubtitles': highContrastSubtitles,
          'subtitleTextColor': subtitleTextColor,
          'subtitleBackgroundColor': subtitleBackgroundColor,
          'seekBackMs': seekBackSeconds * 1000,
          'seekForwardMs': seekForwardSeconds * 1000,
          'autoSkipIntros': autoSkipIntros,
          'autoSkipOutros': autoSkipOutros,
          'videoFit': videoFit,
          'malMediaId': ?malMediaId,
          'episodeNumber': ?episodeNumber,
          'hasDirectSources': hasDirectSources,
          if (artworkUrl != null && artworkUrl.isNotEmpty)
            'artworkUrl': artworkUrl,
          if (headers.isNotEmpty) 'headers': headers,
          if (trustedLocalSource) 'trustedLocalSource': true,
          if (trustedPlaybackProxy) 'trustedPlaybackProxy': true,
          for (final key in const [
            'themeBackgroundColor',
            'themeSurfaceColor',
            'themeAccentColor',
            'themeAccentBrightColor',
            'themeFocusColor',
            'themePrimaryTextColor',
            'themeMutedTextColor',
          ])
            if (theme[key] case final int color) key: color,
        },
      );
      return value == null
          ? const NativePlaybackResult(
              status: 'exit',
              position: Duration.zero,
              duration: Duration.zero,
            )
          : NativePlaybackResult.fromMap(value);
    } on PlatformException catch (error) {
      return NativePlaybackResult.platformError(error);
    }
  }

  Future<void> updateMediaSession({
    required String title,
    required int episode,
    required Duration position,
    required Duration duration,
    required bool playing,
    String? artworkUrl,
    int seekBackSeconds = 10,
    int seekForwardSeconds = 10,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('updateMediaSession', {
        'title': title,
        'subtitle': 'Episode $episode',
        'episode': episode,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'playing': playing,
        if (artworkUrl != null && artworkUrl.isNotEmpty)
          'artworkUrl': artworkUrl,
        'seekBackMs': seekBackSeconds * 1000,
        'seekForwardMs': seekForwardSeconds * 1000,
      });
    } on PlatformException {
      // Playback must continue even when a vendor MediaSession is unavailable.
    }
  }

  Future<void> clearMediaSession() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('clearMediaSession');
    } on PlatformException {
      // System media controls are optional on some vendor TV builds.
    }
  }

  Future<void> removeWatchNext(int mediaId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('removeWatchNext', {
        'mediaId': mediaId,
      });
    } on PlatformException {
      // Watch Next is optional and absent on Fire TV and some operator boxes.
    }
  }

  Future<void> publishWatchNext({
    required int mediaId,
    required int episode,
    required String title,
    required Duration position,
    required Duration duration,
    String? posterUrl,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<int>('publishWatchNext', {
        'mediaId': mediaId,
        'episode': episode,
        'title': title,
        'description': 'Continue episode $episode on TetoTV',
        'posterUrl': posterUrl,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      });
    } on PlatformException {
      // Fire TV and some operator devices do not expose the Watch Next provider.
    }
  }

  Future<bool> scheduleReminder({
    required int mediaId,
    required int episode,
    required String title,
    required DateTime airingAt,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final reminderAt = airingAt.subtract(const Duration(minutes: 10));
    if (reminderAt.isBefore(DateTime.now())) return false;
    try {
      return await _channel.invokeMethod<bool>('scheduleReminder', {
            'mediaId': mediaId,
            'episode': episode,
            'title': title,
            'atMillis': reminderAt.millisecondsSinceEpoch,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
