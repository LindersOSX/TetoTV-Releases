import 'dart:async';

import 'package:anime_tv/core/diagnostics/anonymous_crash_reporter.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/telemetry/anonymous_usage_reporter.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/player/application/audio_track_selector.dart';
import 'package:anime_tv/features/catalog/application/filler_episode_providers.dart';
import 'package:anime_tv/features/catalog/domain/filler_episode_lookup.dart';
import 'package:anime_tv/features/player/application/filler_episode_navigation.dart';
import 'package:anime_tv/features/player/application/skip_segment_service.dart';
import 'package:anime_tv/features/player/presentation/filler_skip_notification.dart';
import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/player/presentation/player_failover_coordinator.dart';
import 'package:anime_tv/features/player/presentation/player_presentation_palette.dart';
import 'package:anime_tv/features/player/presentation/player_stream_source_picker.dart';
import 'package:anime_tv/features/player/presentation/teto_player_chrome.dart';
import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/application/debrid_resolver_factory.dart';
import 'package:anime_tv/features/streaming/application/debrid_token_service.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/release_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:anime_tv/features/streaming/data/hosted_release_source.dart';
import 'package:anime_tv/features/streaming/data/stremio_torrent_release_source.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// media_kit_video has no public Android surface-detach API. The concrete
// controller is needed to drain its wid listener before Player.dispose marks
// the native player disposed.
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';

const tetoTvVideoControllerConfiguration = VideoControllerConfiguration(
  enableHardwareAcceleration: true,
  // Start on MediaCodec because Android TV devices consistently render it
  // more smoothly than libmpv's auto-safe probing path. TetoTV's decoded-
  // format and frame-drop watchdogs still move incompatible streams to the
  // software decoder automatically.
  vo: 'gpu',
  hwdec: 'mediacodec',
  androidAttachSurfaceAfterVideoParameters: true,
);

enum PlaybackDecoderMode { hardwareSafe, hardwareDirect, software }

String _mpvColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

typedef _PlaybackMenuResult = ({String type, Object value});

String hwdecForPlaybackMode(PlaybackDecoderMode mode) => switch (mode) {
  PlaybackDecoderMode.hardwareSafe => 'mediacodec',
  PlaybackDecoderMode.hardwareDirect => 'mediacodec',
  PlaybackDecoderMode.software => 'no',
};

String playbackDecoderLabel(PlaybackDecoderMode mode) => switch (mode) {
  PlaybackDecoderMode.hardwareSafe => 'Automatic (adaptive)',
  PlaybackDecoderMode.hardwareDirect => 'Hardware direct',
  PlaybackDecoderMode.software => 'Software compatibility',
};

bool isH264TenBitVideoProfile({
  String? codec,
  String? profile,
  String? format,
  String? pixelFormat,
  String? hardwarePixelFormat,
}) {
  final description = [
    codec,
    profile,
    format,
    pixelFormat,
    hardwarePixelFormat,
  ].whereType<String>().join(' ').toLowerCase();
  final isH264 =
      description.contains('h264') ||
      description.contains('h.264') ||
      description.contains('avc');
  final isTenBit = RegExp(
    r'(?:high[ ._-]?10|hi10p|10[ ._-]?bit|yuv\d+p10|p010)',
  ).hasMatch(description);
  return isH264 && isTenBit;
}

bool resumeSeekNeedsRetry(Duration target, Duration actual) =>
    target > const Duration(seconds: 15) &&
    actual + const Duration(seconds: 5) < target;

/// Marketplace streams often use HLS manifests, CDN referrers, and host
/// quirks that libmpv handles more defensively than a vendor MediaCodec path.
/// Keep debrid files on native Media3, but do not expose third-party web
/// responses to a device-specific native player crash on first open.
bool preferMpvForInitialStream(StreamReady stream) => stream.isWebStream;

bool isLikelyVideoDecodeFailure(String message) {
  final value = message.toLowerCase();
  return const [
    'mediacodec',
    'video decoder',
    'video codec',
    'failed to decode',
    'hardware decoding',
    'video output',
    'surface',
  ].any(value.contains);
}

Duration? playerSeekOffsetForKey(
  LogicalKeyboardKey key, {
  int backSeconds = 10,
  int forwardSeconds = 10,
}) {
  if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.mediaRewind) {
    return Duration(seconds: -backSeconds);
  }
  if (key == LogicalKeyboardKey.keyL ||
      key == LogicalKeyboardKey.mediaFastForward) {
    return Duration(seconds: forwardSeconds);
  }
  return null;
}

String _formatPlayerDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
    this.subtitle,
    this.anilistMediaId,
    this.malMediaId,
    this.episode,
    this.coverImageUrl,
    super.key,
  });

  final String source;
  final String title;
  final DebridService debridService;
  final PlaybackLaunch launch;
  final String? subtitle;
  final int? anilistMediaId;
  final int? malMediaId;
  final int? episode;
  final String? coverImageUrl;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenRouterState();
}

class _TvPlayerScreenRouterState extends ConsumerState<TvPlayerScreen> {
  _TvPlaybackEngine _engine = _TvPlaybackEngine.nativeMedia3;
  late String _activeSource;
  late PlaybackLaunch _activeLaunch;
  AnonymousUsageReporter? _usageReporter;
  bool _profileReady = false;
  Duration? _resumeOverride;
  bool _manualEngineSelection = false;

  int get _anilistMediaId =>
      widget.anilistMediaId ?? _activeLaunch.episode.anilistMediaId;
  int? get _malMediaId => widget.malMediaId ?? _activeLaunch.episode.malMediaId;
  int get _episodeNumber => widget.episode ?? _activeLaunch.episode.episode;
  String? get _coverImageUrl =>
      widget.coverImageUrl ?? _activeLaunch.episode.coverImageUrl;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      _usageReporter = ref.read(anonymousUsageReporterProvider);
      _usageReporter!.setStreaming(true);
    }
    _activeSource = widget.source;
    _activeLaunch = widget.launch;
    final preferred = ref.read(settingsPreferencesProvider).preferredPlayer;
    if (preferred != PreferredPlayer.automatic) {
      _engine = _engineForPreference(preferred);
      _profileReady = true;
    } else if (preferMpvForInitialStream(_activeLaunch.stream)) {
      _engine = _TvPlaybackEngine.mpv;
      _profileReady = true;
    } else {
      unawaited(_loadDevicePreference());
    }
  }

  @override
  void dispose() {
    // Riverpod invalidates ConsumerState.ref before State.dispose is invoked.
    // Use the dependency captured while mounted instead of reading ref here.
    _usageReporter?.setStreaming(false);
    unawaited(_activeLaunch.stream.playbackLease?.close());
    super.dispose();
  }

  Future<void> _adoptPlaybackStream(
    StreamReady stream,
    ReleaseCandidate release,
  ) async {
    final previous = _activeLaunch.stream;
    _activeSource = stream.uri.toString();
    _activeLaunch = PlaybackLaunch(
      stream: stream,
      episode: _activeLaunch.episode,
      selectedRelease: release,
      alternatives: _activeLaunch.alternatives
          .where((candidate) => candidate.infoHash != release.infoHash)
          .toList(growable: false),
      directAlternatives: _activeLaunch.directAlternatives
          .where((option) => option.stream.uri != stream.uri)
          .toList(growable: false),
    );
    if (!identical(previous.playbackLease, stream.playbackLease)) {
      try {
        await previous.playbackLease?.close();
      } catch (_) {
        // The new stream already owns playback. Expiry remains a safe
        // backstop if a platform request prevents immediate proxy teardown.
      }
    }
  }

  Future<void> _loadDevicePreference() async {
    final preferred = ref.read(settingsPreferencesProvider).preferredPlayer;
    if (preferred != PreferredPlayer.automatic) {
      if (!mounted) return;
      setState(() {
        _engine = _engineForPreference(preferred);
        _profileReady = true;
      });
      return;
    }
    final device = await AndroidTvBridge.instance.getDeviceProfile();
    final profile = await TetoTvDatabase.instance.devicePlaybackProfile(
      device.key,
    );
    if (!mounted) return;
    setState(() {
      _engine = switch (profile.preferredEngine) {
        'mpv' => _TvPlaybackEngine.mpv,
        'vlc' => _TvPlaybackEngine.vlc,
        _ => _TvPlaybackEngine.nativeMedia3,
      };
      _profileReady = true;
    });
  }

  @override
  void didUpdateWidget(covariant TvPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.episode != widget.episode ||
        oldWidget.launch.selectedRelease.infoHash !=
            widget.launch.selectedRelease.infoHash) {
      final preferred = ref.read(settingsPreferencesProvider).preferredPlayer;
      _engine = preferred != PreferredPlayer.automatic
          ? _engineForPreference(preferred)
          : preferMpvForInitialStream(widget.launch.stream)
          ? _TvPlaybackEngine.mpv
          : _TvPlaybackEngine.nativeMedia3;
      final previousLease = _activeLaunch.stream.playbackLease;
      _activeSource = widget.source;
      _activeLaunch = widget.launch;
      if (!identical(previousLease, _activeLaunch.stream.playbackLease)) {
        unawaited(previousLease?.close());
      }
      _resumeOverride = null;
      _manualEngineSelection = false;
      _profileReady =
          preferred != PreferredPlayer.automatic ||
          preferMpvForInitialStream(widget.launch.stream);
      if (!_profileReady) unawaited(_loadDevicePreference());
    }
  }

  void _switchEngine(
    _TvPlaybackEngine engine,
    String source,
    ReleaseCandidate release, {
    Duration? resume,
    StreamReady? selectedStream,
    List<PlaybackStreamOption>? discoveredDirectStreams,
    bool manualSelection = false,
  }) {
    final previousStream = _activeLaunch.stream;
    final previousRelease = _activeLaunch.selectedRelease;
    final nextStream =
        selectedStream ??
        StreamReady(
          uri: Uri.parse(source),
          displayName: release.releaseName,
          debridService: previousStream.debridService,
          headers: previousStream.headers,
          externalSubtitle: previousStream.externalSubtitle,
          mediaContentType: previousStream.mediaContentType,
          subtitleContentType: previousStream.subtitleContentType,
          externalSubtitleRejected: previousStream.externalSubtitleRejected,
          playbackLease: previousStream.playbackLease,
          providerId: previousStream.providerId,
          providerName: previousStream.providerName,
        );
    final mergedDirectStreams = playbackStreamOptionsForHandoff(
      currentStream: nextStream,
      currentRelease: release,
      existing: [
        if (previousStream.uri != nextStream.uri)
          PlaybackStreamOption(
            stream: previousStream,
            release: previousRelease,
          ),
        ..._activeLaunch.directAlternatives,
        ...?discoveredDirectStreams,
      ],
    );
    final launch = PlaybackLaunch(
      stream: nextStream,
      episode: _activeLaunch.episode,
      selectedRelease: release,
      alternatives: _activeLaunch.alternatives
          .where((candidate) => candidate.infoHash != release.infoHash)
          .toList(growable: false),
      directAlternatives: mergedDirectStreams
          .where((option) => option.stream.uri != nextStream.uri)
          .toList(growable: false),
    );
    setState(() {
      _activeSource = source;
      _activeLaunch = launch;
      _engine = engine;
      _resumeOverride = resume;
      _manualEngineSelection = manualSelection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (!_profileReady) {
      return ColoredBox(
        color: palette.playerBackground(),
        child: Center(
          child: CircularProgressIndicator(color: palette.secondaryAccent),
        ),
      );
    }
    if (_engine == _TvPlaybackEngine.mpv) {
      return MpvTvPlayerScreen(
        source: _activeSource,
        title: widget.title,
        debridService: widget.debridService,
        launch: _activeLaunch,
        subtitle:
            _activeLaunch.stream.externalSubtitle?.toString() ??
            widget.subtitle,
        anilistMediaId: _anilistMediaId,
        malMediaId: _malMediaId,
        episode: _episodeNumber,
        coverImageUrl: _coverImageUrl,
        initialPosition: _resumeOverride,
        onUseVlc: (position, stream, release, directStreams) => _switchEngine(
          _TvPlaybackEngine.vlc,
          stream.uri.toString(),
          release,
          resume: position,
          selectedStream: stream,
          discoveredDirectStreams: directStreams,
        ),
        onStreamAdopted: _adoptPlaybackStream,
        onSelectEngine: (player, position, stream, release, directStreams) =>
            _switchEngine(
              _engineForPreference(player),
              stream.uri.toString(),
              release,
              resume: position,
              selectedStream: stream,
              discoveredDirectStreams: directStreams,
              manualSelection: true,
            ),
      );
    }
    if (_engine == _TvPlaybackEngine.vlc) {
      return VlcTvPlayerScreen(
        source: _activeSource,
        title: widget.title,
        debridService: widget.debridService,
        launch: _activeLaunch,
        subtitle:
            _activeLaunch.stream.externalSubtitle?.toString() ??
            widget.subtitle,
        anilistMediaId: _anilistMediaId,
        malMediaId: _malMediaId,
        episode: _episodeNumber,
        coverImageUrl: _coverImageUrl,
        initialPosition: _resumeOverride,
        onUseMpv: (position, stream, release, directStreams) => _switchEngine(
          _TvPlaybackEngine.mpv,
          stream.uri.toString(),
          release,
          resume: position,
          selectedStream: stream,
          discoveredDirectStreams: directStreams,
        ),
        onStreamAdopted: _adoptPlaybackStream,
        onSelectEngine: (player, position, stream, release, directStreams) =>
            _switchEngine(
              _engineForPreference(player),
              stream.uri.toString(),
              release,
              resume: position,
              selectedStream: stream,
              discoveredDirectStreams: directStreams,
              manualSelection: true,
            ),
      );
    }
    return NativeMedia3PlayerScreen(
      source: _activeSource,
      title: widget.title,
      debridService: widget.debridService,
      launch: _activeLaunch,
      subtitle:
          _activeLaunch.stream.externalSubtitle?.toString() ?? widget.subtitle,
      anilistMediaId: _anilistMediaId,
      malMediaId: _malMediaId,
      episode: _episodeNumber,
      coverImageUrl: _coverImageUrl,
      initialPosition: _resumeOverride,
      manuallySelected: _manualEngineSelection,
      onUseMpv: (position, stream, release) => _switchEngine(
        _TvPlaybackEngine.mpv,
        stream.uri.toString(),
        release,
        resume: position,
        selectedStream: stream,
      ),
      onUseVlc: (position, stream, release) => _switchEngine(
        _TvPlaybackEngine.vlc,
        stream.uri.toString(),
        release,
        resume: position,
        selectedStream: stream,
      ),
      onStreamAdopted: _adoptPlaybackStream,
    );
  }
}

enum _TvPlaybackEngine { nativeMedia3, mpv, vlc }

_TvPlaybackEngine _engineForPreference(PreferredPlayer preference) =>
    switch (preference) {
      PreferredPlayer.media3 => _TvPlaybackEngine.nativeMedia3,
      PreferredPlayer.vlc => _TvPlaybackEngine.vlc,
      PreferredPlayer.mpv || PreferredPlayer.automatic => _TvPlaybackEngine.mpv,
    };

class MpvTvPlayerScreen extends ConsumerStatefulWidget {
  const MpvTvPlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
    required this.onUseVlc,
    required this.onStreamAdopted,
    this.onSelectEngine,
    this.initialPosition,
    this.subtitle,
    this.anilistMediaId,
    this.malMediaId,
    this.episode,
    this.coverImageUrl,
    super.key,
  });

  final String source;
  final String title;
  final DebridService debridService;
  final PlaybackLaunch launch;
  final void Function(
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
    List<PlaybackStreamOption> directStreams,
  )
  onUseVlc;
  final Future<void> Function(StreamReady stream, ReleaseCandidate release)
  onStreamAdopted;
  final void Function(
    PreferredPlayer player,
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
    List<PlaybackStreamOption> directStreams,
  )?
  onSelectEngine;
  final Duration? initialPosition;
  final String? subtitle;
  final int? anilistMediaId;
  final int? malMediaId;
  final int? episode;
  final String? coverImageUrl;

  @override
  ConsumerState<MpvTvPlayerScreen> createState() => _MpvTvPlayerScreenState();
}

class _MpvTvPlayerScreenState extends ConsumerState<MpvTvPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  late final TetoTvDatabase _database;

  Map<String, String> get _httpHeaders => {
    'Accept': '*/*',
    'User-Agent': 'TetoTV/1.10 Android libmpv',
    ..._currentStream.headers,
  };
  final _playerRootFocus = FocusNode(debugLabel: 'player.root');
  final _playControlFocus = FocusNode(debugLabel: 'player.play');
  final _skipControlFocus = FocusNode(debugLabel: 'player.skip-segment');
  Timer? _controlsTimer;
  Timer? _videoWatchdog;
  Timer? _performanceWatchdog;
  StreamSubscription<Duration>? _progressSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _controlsVisible = true;
  bool _progressHandled = false;
  bool _completionHandled = false;
  final PlayerHandoffGate _nextEpisodeHandoff = PlayerHandoffGate();
  bool _preferredAudioSelected = false;
  bool _preferredSubtitleSelected = false;
  String? _trackMessage;
  String? _playbackError;
  StreamSubscription<void>? _completedSubscription;
  List<SkipSegment> _skips = const [];
  Timer? _skipLoadTimer;
  Duration? _skipDurationCandidate;
  bool _skipLoadInFlight = false;
  bool _skipLoadComplete = false;
  int _skipLoadAttempts = 0;
  SkipSegment? _activeSkip;
  bool _canSkipNow = false;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  bool _videoFrameSeen = false;
  bool _softwareFallbackUsed = false;
  bool _changingDecoder = false;
  int _watchdogAttempts = 0;
  int _lastDroppedFrames = 0;
  int _highDropSamples = 0;
  bool _checkingPerformance = false;
  bool _checkingDecodedVideo = false;
  bool _playbackPersistenceReady = false;
  PlaybackDecoderMode _decoderMode = PlaybackDecoderMode.hardwareSafe;
  BoxFit _videoFit = BoxFit.contain;
  double _playbackRate = 1;
  double _subtitleSize = 34;
  int _subtitlePosition = 100;
  int _subtitleDelayMs = 0;
  int _audioDelayMs = 0;
  bool _highContrastSubtitles = false;
  late String _source;
  late ReleaseCandidate _currentRelease;
  late StreamReady _currentStream;
  List<PlaybackStreamOption> _directStreamOptions = const [];
  StreamSubscription<WebStreamSearchProgress>? _sourceDiscoverySubscription;
  final Set<String> _failedDirectStreamUris = {};
  final Set<ReleaseCandidate> _attemptedReleaseAlternatives = {};
  bool _failingOver = false;
  bool _prewarming = false;
  bool _prewarmed = false;
  DateTime _lastCheckpointSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMediaSessionUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<MediaAction>? _mediaActionSubscription;
  SeriesPlaybackPreferences _seriesPreferences =
      const SeriesPlaybackPreferences();
  bool _seriesPreferencesReady = false;
  PlaybackAudioPreference _audioPreference = PlaybackAudioPreference.dub;
  Uint8List? _seekPreview;
  Duration? _seekPreviewPosition;
  Timer? _seekPreviewTimer;
  Duration? _queuedSeekTarget;
  Completer<void>? _seekDrainCompleter;
  final Set<Future<void>> _trickplayOperations = <Future<void>>{};
  Future<bool>? _skipSeekOperation;
  bool _skipInProgress = false;
  int _seekBackSeconds = 10;
  int _seekForwardSeconds = 10;
  Color _captionTextColor = Colors.white;
  Color _captionBackgroundColor = Colors.transparent;
  final Set<String> _autoFocusedSkipSegments = {};
  final Set<String> _consumedSkipSegments = {};
  bool _allowExit = false;
  bool _confirmingExit = false;
  TapDownDetails? _touchDoubleTapDetails;
  bool _requestedVlcFallback = false;
  bool _reportedPlaybackSuccess = false;
  bool _engineHandoffInProgress = false;
  bool _handoffAttemptActive = false;
  bool _handoffReleaseFailed = false;
  bool _playerReleasedForHandoff = false;
  bool _nativePlaybackStateClearedForHandoff = false;
  bool _routePopScheduled = false;
  Duration? _pendingHandoffPosition;
  final PlayerReleaseCoordinator _handoffRelease = PlayerReleaseCoordinator();
  final Set<Future<void>> _playerMutationOperations = <Future<void>>{};
  Duration? _pendingInheritedResume;
  bool _lastResumeSeekSucceeded = true;

  bool get _hasUntriedDirectStream => hasUntriedDirectWebStream(
    current: _currentStream,
    options: _directStreamOptions,
    failedUris: _failedDirectStreamUris,
  );
  PlaybackAudioPreference get _effectiveAudioPreference =>
      _seriesPreferences.audioPreferenceSet
      ? playbackAudioPreferenceForLanguage(_seriesPreferences.audioLanguage) ??
            _audioPreference
      : _audioPreference;

  Future<void> _bootstrapPlayback() async {
    Duration? resume = widget.initialPosition;
    try {
      final appearance = ref.read(settingsPreferencesProvider);
      _audioPreference = appearance.preferredAudio;
      _seekBackSeconds = appearance.seekBackSeconds;
      _seekForwardSeconds = appearance.seekForwardSeconds;
      _captionTextColor = Color(appearance.captionTextColor);
      _captionBackgroundColor = Color(appearance.captionBackgroundColor);
      if (widget.anilistMediaId case final mediaId?) {
        _seriesPreferences = await _database.seriesPreferences(mediaId);
        _seriesPreferencesReady = true;
        if (_seriesPreferences.audioPreferenceSet) {
          _audioPreference =
              playbackAudioPreferenceForLanguage(
                _seriesPreferences.audioLanguage,
              ) ??
              _audioPreference;
        }
        _decoderMode = switch (_seriesPreferences.decoder) {
          'hardware-direct' => PlaybackDecoderMode.hardwareDirect,
          'software' => PlaybackDecoderMode.software,
          _ => PlaybackDecoderMode.hardwareSafe,
        };
        _videoFit = switch (_seriesPreferences.videoFit) {
          'cover' => BoxFit.cover,
          'fill' => BoxFit.fill,
          _ => BoxFit.contain,
        };
        _subtitleSize = _seriesPreferences.subtitleSize == 34
            ? appearance.captionTextSize
            : _seriesPreferences.subtitleSize;
        _subtitlePosition = _seriesPreferences.subtitlePosition;
        _subtitleDelayMs = _seriesPreferences.subtitleDelayMs;
        _audioDelayMs = _seriesPreferences.audioDelayMs;
        _highContrastSubtitles = _seriesPreferences.highContrastSubtitles;
        if (resume == null &&
            !widget.launch.episode.startFromBeginning &&
            widget.episode != null) {
          final checkpoint = await _database.checkpoint(
            mediaId,
            widget.episode!,
          );
          if (checkpoint != null &&
              !checkpoint.completed &&
              checkpoint.position > const Duration(seconds: 15) &&
              checkpoint.progress < .95) {
            resume = checkpoint.position;
          }
        }
      }
      if (_decoderMode == PlaybackDecoderMode.hardwareSafe &&
          releaseRequiresSoftwareDecoder(_currentRelease)) {
        _decoderMode = PlaybackDecoderMode.software;
        _softwareFallbackUsed = true;
      }
      if (!_seriesPreferences.subtitlePreferenceSet) {
        _seriesPreferences = _seriesPreferences.copyWith(
          subtitleEnabled: subtitlesEnabledForAudioPreference(
            _currentRelease,
            _audioPreference,
          ),
        );
      }
      if (!mounted || _engineHandoffInProgress) return;
      await _openMedia(resume: resume);
      if (resume != null && mounted && !_engineHandoffInProgress) {
        _showTrackMessage(
          _lastResumeSeekSucceeded
              ? 'Resumed at ${_formatPlayerDuration(resume)}'
              : 'Could not restore the saved position',
        );
      }
    } finally {
      _playbackPersistenceReady = true;
    }
  }

  @override
  void initState() {
    super.initState();
    // Final checkpoints and preferences are written during State.dispose,
    // after Riverpod has invalidated ConsumerState.ref.
    _database = ref.read(tetoTvDatabaseProvider);
    _source = widget.source;
    _currentRelease = widget.launch.selectedRelease;
    _currentStream = widget.launch.stream;
    _pendingInheritedResume = widget.initialPosition;
    _directStreamOptions = mergePlaybackStreamOptions([
      PlaybackStreamOption(stream: _currentStream, release: _currentRelease),
      ...widget.launch.directAlternatives,
    ], const []);
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'TetoTV',
        // Debrid streams are seekable HTTP sources; a 48 MiB cache keeps
        // playback smooth without starving low-memory Fire TV devices.
        bufferSize: 48 * 1024 * 1024,
        libass: true,
        libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
        libassAndroidFontName: 'Noto Sans',
      ),
    );
    _controller = VideoController(
      _player,
      configuration: tetoTvVideoControllerConfiguration,
    );
    _progressSubscription = _player.stream.position.listen(_onPosition);
    _durationSubscription = _player.stream.duration.listen(
      _scheduleSkipSegmentLoad,
    );
    _tracksSubscription = _player.stream.tracks.listen(_onTracksChanged);
    _errorSubscription = _player.stream.error.listen((message) {
      if (isLikelyVideoDecodeFailure(message) &&
          !_softwareFallbackUsed &&
          !_hasUntriedDirectStream) {
        unawaited(_restartWithSoftwareDecoder());
        return;
      }
      unawaited(_tryNextStream(message));
    });
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) _handlePlaybackCompleted();
    });
    _videoParamsSubscription = _player.stream.videoParams.listen((params) {
      if (params.w == null || params.h == null) return;
      _videoFrameSeen = true;
      if (!_reportedPlaybackSuccess) {
        _reportedPlaybackSuccess = true;
        unawaited(_recordEngineSuccess());
      }
      _videoWatchdog?.cancel();
      debugPrint('\n--- PLAYBACK DIAGNOSTICS ---');
      debugPrint('Resolution: ${params.w}x${params.h}');
      debugPrint('Pixel format: ${params.pixelformat ?? "unknown"}');
      debugPrint('Hardware Pixel format: ${params.hwPixelformat ?? "unknown"}');
      debugPrint('Color matrix: ${params.colormatrix ?? "unknown"}');
      debugPrint('Color levels (range): ${params.colorlevels ?? "unknown"}');
      debugPrint('Primaries (HDR/SDR): ${params.primaries ?? "unknown"}');
      debugPrint('Gamma: ${params.gamma ?? "unknown"}');
      debugPrint(
        'Video Codec: ${_player.state.track.video.codec ?? "unknown"}',
      );
      debugPrint(
        'Audio Codec: ${_player.state.track.audio.codec ?? "unknown"}',
      );
      debugPrint('Player/Backend: media_kit (libmpv)');
      debugPrint('VO/hwdec: gpu / ${hwdecForPlaybackMode(_decoderMode)}');
      debugPrint('----------------------------\n');
      unawaited(_matchContentFrameRate());
      unawaited(_inspectDecodedVideo(params));
    });
    _playingSubscription = _player.stream.playing.listen((_) {
      unawaited(_updateMediaSession(force: true));
    });
    _mediaActionSubscription = AndroidTvBridge.instance.mediaActions.listen(
      _handleMediaAction,
    );
    unawaited(_bootstrapPlayback());
    _scheduleSkipSegmentLoad(_player.state.duration);
    unawaited(_startWebSourceDiscovery());
    _scheduleControlsHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playControlFocus.requestFocus();
      if (_currentStream.externalSubtitleRejected) {
        _showTrackMessage(
          'External subtitles were blocked because they were unsafe or unsupported.',
        );
      }
    });
  }

  bool get _canApplyTrackSelection =>
      mounted && !_engineHandoffInProgress && !_playerReleasedForHandoff;

  void _onTracksChanged(Tracks tracks) {
    unawaited(_runTrackedTrackSelection(tracks));
  }

  Future<void> _runTrackedTrackSelection(Tracks tracks) async {
    try {
      await _trackPlayerMutation(() => _selectPreferredTracks(tracks));
    } catch (error, stackTrace) {
      if (_canApplyTrackSelection) {
        debugPrint('MPV track selection failed: $error\n$stackTrace');
      }
    }
  }

  Future<void> _applyPreferredAudio(Tracks tracks) async {
    if (_preferredAudioSelected || !_canApplyTrackSelection) return;
    final device = await AndroidTvBridge.instance.getDeviceProfile();
    // Device-profile lookup crosses the platform channel. The player route can
    // begin an engine handoff while it is pending, so never resume against a
    // player whose release has already started.
    if (_preferredAudioSelected || !_canApplyTrackSelection) return;
    final preferred = _seriesPreferences.audioPreferenceSet
        ? preferredAudioTrackForLanguage(
            tracks.audio,
            language: _seriesPreferences.audioLanguage,
            preferSurround: device.hasHdmiAudio,
            // A demuxer may announce its default track before publishing the
            // rest. Do not lock a temporary fallback.
            allowFallback: false,
          )
        : preferredAudioTrack(
            tracks.audio,
            preference: _audioPreference,
            preferSurround: device.hasHdmiAudio,
            allowFallback: false,
          );
    if (preferred == null || !_canApplyTrackSelection) return;
    final matchesPreference = _seriesPreferences.audioPreferenceSet
        ? playerTrackMatchesAudioLanguage(
            preferred,
            _seriesPreferences.audioLanguage,
          )
        : playerTrackMatchesAudioPreference(preferred, _audioPreference);
    await _player.setAudioTrack(preferred);
    if (!_canApplyTrackSelection) return;
    // A failed engine command must remain retryable on the next track snapshot.
    _preferredAudioSelected = matchesPreference;
    _showTrackMessage(
      'Preferred audio: '
      '${preferred.title ?? preferred.language ?? _audioPreference.displayName}',
    );
  }

  Future<void> _selectPreferredTracks(Tracks tracks) async {
    await _applyPreferredAudio(tracks);
    if (!_canApplyTrackSelection ||
        _preferredSubtitleSelected ||
        !_seriesPreferences.subtitleEnabled) {
      return;
    }
    final language = _seriesPreferences.subtitleLanguage.toLowerCase();
    final matches =
        tracks.subtitle
            .where((track) => track.id != 'auto' && track.id != 'no')
            .where(
              (track) =>
                  playerTrackLanguageScore(
                    language: track.language,
                    title: track.title,
                    preferredLanguage: language,
                    subtitle: true,
                  ) >
                  0,
            )
            .toList(growable: false)
          ..sort(
            (a, b) =>
                playerTrackLanguageScore(
                  language: b.language,
                  title: b.title,
                  preferredLanguage: language,
                  subtitle: true,
                ).compareTo(
                  playerTrackLanguageScore(
                    language: a.language,
                    title: a.title,
                    preferredLanguage: language,
                    subtitle: true,
                  ),
                ),
          );
    final preferred = matches.firstOrNull;
    if (preferred == null || !_canApplyTrackSelection) return;
    _preferredSubtitleSelected = true;
    await _player.setSubtitleTrack(preferred);
  }

  void _onPosition(Duration position) {
    _checkSkips(position);
    if (_playbackPersistenceReady) {
      unawaited(_persistPlayback(position));
      unawaited(_updateMediaSession());
    }
    final duration = _player.state.duration;
    _scheduleSkipSegmentLoad(duration);
    if (duration.inSeconds <= 0) return;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    if (!_prewarmed && !_prewarming && ratio >= .65) {
      unawaited(_prewarmNextEpisode());
    }
    if (_progressHandled || widget.episode == null) return;
    if (widget.anilistMediaId == null && widget.malMediaId == null) return;
    final threshold = ref
        .read(settingsPreferencesProvider)
        .trackerUpdateThreshold;
    if (!trackerUpdateThresholdReached(
      position: position,
      duration: duration,
      threshold: threshold,
    )) {
      return;
    }
    _progressHandled = true;
    unawaited(_syncProgress());
  }

  void _checkSkips(Duration position) {
    final active = _skips
        .where(
          (skip) =>
              skip.contains(position) &&
              !_consumedSkipSegments.contains(
                '${skip.kind.name}:${skip.start.inMilliseconds}',
              ),
        )
        .firstOrNull;
    if (active != null) {
      final settings = ref.read(settingsPreferencesProvider);
      final autoSkip =
          (active.kind == SkipSegmentKind.opening && settings.autoSkipIntros) ||
          (active.kind == SkipSegmentKind.ending && settings.autoSkipOutros);
      final key = '${active.kind.name}:${active.start.inMilliseconds}';
      if (autoSkip && !_skipInProgress && _consumedSkipSegments.add(key)) {
        if (mounted) {
          setState(() {
            _activeSkip = null;
            _canSkipNow = false;
          });
        }
        unawaited(_autoSkipSegment(active));
        return;
      }
    }
    final canSkip = active != null;
    if (_canSkipNow != canSkip) {
      setState(() {
        _canSkipNow = canSkip;
        _activeSkip = active;
      });
      if (canSkip && !_controlsVisible) {
        _focusSkipOnce(active);
      }
    } else if (!identical(_activeSkip, active)) {
      setState(() => _activeSkip = active);
      if (active != null && !_controlsVisible) _focusSkipOnce(active);
    }
  }

  Future<void> _autoSkipSegment(SkipSegment segment) async {
    if (_skipInProgress || _engineHandoffInProgress) return;
    _skipInProgress = true;
    final segmentKey = '${segment.kind.name}:${segment.start.inMilliseconds}';
    try {
      final duration = _player.state.duration;
      final wasPlaying = _player.state.playing;
      final succeeded = await _seekForSkip(
        safeSkipSegmentTarget(requested: segment.end, duration: duration),
      );
      if (!succeeded) throw StateError('skip seek failed');
      if (mounted && !_engineHandoffInProgress) {
        _showTrackMessage(
          segment.kind == SkipSegmentKind.opening
              ? 'Intro skipped'
              : 'Outro skipped',
        );
      }
      if (!wasPlaying &&
          segment.kind == SkipSegmentKind.ending &&
          skipSegmentReachesPlaybackEnd(
            requestedEnd: segment.end,
            duration: duration,
          )) {
        _handlePlaybackCompleted();
      }
    } catch (_) {
      _consumedSkipSegments.remove(segmentKey);
      if (mounted && !_engineHandoffInProgress) {
        _showTrackMessage('Could not skip this segment');
      }
    } finally {
      _skipInProgress = false;
      if (mounted && !_engineHandoffInProgress) {
        _checkSkips(_player.state.position);
      }
    }
  }

  void _focusSkipOnce(SkipSegment segment) {
    final key = '${segment.kind.name}:${segment.start.inMilliseconds}';
    if (!_autoFocusedSkipSegments.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controlsVisible && _activeSkip == segment) {
        _skipControlFocus.requestFocus();
      }
    });
  }

  void _scheduleSkipSegmentLoad(Duration duration) {
    if (_skipLoadComplete ||
        _skipLoadInFlight ||
        _engineHandoffInProgress ||
        duration <= Duration.zero) {
      return;
    }
    final previous = _skipDurationCandidate;
    _skipDurationCandidate = duration;
    if (previous != null &&
        (previous - duration).abs() <= const Duration(seconds: 1) &&
        _skipLoadTimer?.isActive == true) {
      return;
    }
    _skipLoadTimer?.cancel();
    _skipLoadTimer = Timer(const Duration(milliseconds: 1200), () {
      unawaited(_loadSkipSegments(duration));
    });
  }

  Future<int?> _resolveSkipMalMediaId() async {
    final known = widget.malMediaId ?? widget.launch.episode.malMediaId;
    if (known != null && known > 0) return known;
    final anilistId =
        widget.anilistMediaId ?? widget.launch.episode.anilistMediaId;
    if (anilistId <= 0) return null;
    try {
      return (await ref.read(catalogClientProvider).details(anilistId)).idMal;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSkipSegments(Duration duration) async {
    if (_skipLoadComplete ||
        _skipLoadInFlight ||
        _engineHandoffInProgress ||
        !mounted) {
      return;
    }
    _skipLoadInFlight = true;
    _skipLoadAttempts++;
    var externalFailed = false;
    try {
      final episode = widget.episode ?? widget.launch.episode.episode;
      final malMediaId = await _resolveSkipMalMediaId();
      final externalFuture = malMediaId == null || episode <= 0
          ? Future<List<SkipSegment>>.value(const <SkipSegment>[])
          : AniSkipClient()
                .segments(
                  malMediaId: malMediaId,
                  episode: episode,
                  episodeDuration: duration,
                )
                .catchError((_) {
                  externalFailed = true;
                  return const <SkipSegment>[];
                });
      if (malMediaId == null && _currentStream.isWebStream) {
        externalFailed = true;
      }
      final embedded = await _embeddedChapterSkipsWithRetry(duration);
      if (mounted && !_engineHandoffInProgress && embedded.isNotEmpty) {
        setState(() => _skips = embedded);
        _checkSkips(_player.state.position);
      }
      final external = await externalFuture;
      if (!mounted || _engineHandoffInProgress) return;
      final currentDuration = _player.state.duration;
      if ((currentDuration - duration).abs() > const Duration(seconds: 1)) {
        _skipDurationCandidate = currentDuration;
        return;
      }
      setState(() => _skips = mergeSkipSegments(embedded, external));
      _checkSkips(_player.state.position);
      _skipLoadComplete = !externalFailed || _skipLoadAttempts >= 4;
    } catch (_) {
      // Chapter and community skip data are optional playback enhancements.
      externalFailed = true;
    } finally {
      _skipLoadInFlight = false;
      if (mounted && !_skipLoadComplete && _skipLoadAttempts < 4) {
        _scheduleSkipSegmentLoad(_player.state.duration);
      }
    }
  }

  Future<List<SkipSegment>> _embeddedChapterSkipsWithRetry(
    Duration duration,
  ) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (_engineHandoffInProgress) return const [];
      final segments = await _embeddedChapterSkips(duration);
      if (segments.isNotEmpty) return segments;
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return const [];
  }

  Future<List<SkipSegment>> _embeddedChapterSkips(Duration duration) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return const [];
    try {
      final count = int.tryParse(
        await platform.getProperty('chapter-list/count'),
      );
      if (count == null || count <= 0 || count > 100) return const [];
      final chapters = <MediaChapter>[];
      for (var index = 0; index < count; index++) {
        final title = await platform.getProperty('chapter-list/$index/title');
        final seconds = double.tryParse(
          await platform.getProperty('chapter-list/$index/time'),
        );
        if (seconds == null || seconds < 0) continue;
        chapters.add(
          MediaChapter(
            title: title,
            start: Duration(milliseconds: (seconds * 1000).round()),
          ),
        );
      }
      return skipSegmentsFromChapters(chapters, duration);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _playNextEpisode() async {
    if (!mounted || widget.anilistMediaId == null || widget.episode == null) {
      return;
    }
    if (!_nextEpisodeHandoff.tryEnter()) return;
    try {
      final catalog = ref.read(catalogClientProvider);
      final fillerRepository = ref.read(fillerEpisodeRepositoryProvider);
      final unavailableNoticeController = ref.read(
        fillerUnavailableNotifiedSeriesProvider.notifier,
      );
      final skipFillerEpisodes = _seriesPreferences.skipFillerEpisodes;
      final details = await catalog.details(widget.anilistMediaId!);
      if (!mounted) return;
      final requestedEpisode = widget.episode! + 1;
      if (details.episodes != null && requestedEpisode > details.episodes!) {
        return; // No more episodes
      }
      final totalEpisodes = episodeNavigationCeiling(
        requestedEpisode: requestedEpisode,
        declaredTotalEpisodes: details.episodes,
        nextAiringEpisode: details.nextAiringEpisode,
      );
      final decision = await resolveFillerEpisodeNavigation(
        repository: fillerRepository,
        identity: FillerSeriesIdentity.fromAnime(details),
        requestedEpisode: requestedEpisode,
        totalEpisodes: totalEpisodes,
        skipEnabled: skipFillerEpisodes,
      );
      if (!mounted) return;
      if (decision.dataUnavailable &&
          consumeFillerUnavailableNotice(
            unavailableNoticeController,
            widget.anilistMediaId!,
          )) {
        showFillerDataUnavailableNotice(context, episode: requestedEpisode);
      }
      await showFillerSkipNotification(context, decision);
      if (!mounted || decision.episode == null) return;
      final nextEp = decision.episode!;
      if (!mounted) return;
      final preferredProvider = _currentRelease.provider?.trim();
      final preferredSourceId = _currentRelease.sourceId.trim();
      final preferredAuthor = releaseGroupKey(_currentRelease.releaseName);
      final preferredWebProviderId = _currentStream.providerId?.trim();
      final query = {
        'anilistId': widget.anilistMediaId.toString(),
        'title': details.title,
        'synonyms': details.synonyms.join('|'),
        'episode': nextEp.toString(),
        'autoplay': '1',
        if (preferredProvider != null && preferredProvider.isNotEmpty)
          'preferredProvider': preferredProvider,
        if (preferredSourceId.isNotEmpty)
          'preferredSourceId': preferredSourceId,
        if (preferredAuthor != null && preferredAuthor.isNotEmpty)
          'preferredAuthor': preferredAuthor,
        if (preferredWebProviderId != null && preferredWebProviderId.isNotEmpty)
          'preferredWebProviderId': preferredWebProviderId,
        if (details.seasonYear != null) 'year': details.seasonYear.toString(),
        if (details.coverImageUrl != null) 'cover': details.coverImageUrl!,
        if (widget.malMediaId != null) 'malId': widget.malMediaId.toString(),
      };
      final completedPosition = _player.state.duration > Duration.zero
          ? _player.state.duration
          : _player.state.position;
      if (!await _prepareForEngineHandoff(completedPosition)) return;
      if (!mounted) return;
      try {
        final navigation = GoRouter.of(context).pushReplacement<void>(
          Uri(path: '/resolve', queryParameters: query).toString(),
        );
        unawaited(
          navigation.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              if (mounted) _popPlayerRouteAfterHandoff(Navigator.of(context));
            },
          ),
        );
      } catch (_) {
        // Playback is already released. Fall back to the normal player-route
        // pop instead of leaving a hidden, non-interactive screen behind.
        if (mounted) _popPlayerRouteAfterHandoff(Navigator.of(context));
      }
    } catch (_) {
      // Completion remains on the current player when the next episode cannot
      // be prepared. A later manual Next action may retry the handoff.
    } finally {
      if (!_engineHandoffInProgress) {
        _nextEpisodeHandoff.leave();
      }
    }
  }

  Future<void> _syncProgress() async {
    if (widget.episode == null) return;
    try {
      final synced = await ref
          .read(trackingSyncServiceProvider)
          .syncEpisode(
            completedEpisodes: widget.episode!,
            anilistMediaId: widget.anilistMediaId,
            malMediaId: widget.malMediaId,
          );
      if (!mounted) return;
      ref.invalidate(
        linkedTrackingProgressProvider((
          anilistMediaId: widget.anilistMediaId,
          malMediaId: widget.malMediaId,
        )),
      );
      if (synced) {
        ref.invalidate(trackingHomeProvider);
      }
    } catch (_) {}
  }

  Future<void> _openMedia({Duration? resume, bool propagateFailure = false}) =>
      _trackPlayerMutation(() async {
        _completionHandled = false;
        final persistenceWasReady = _playbackPersistenceReady;
        if (resume != null) _playbackPersistenceReady = false;
        try {
          await _configureNativePlayback();
          await _player.open(
            Media(_source, httpHeaders: _httpHeaders),
            play: true,
          );
          await _applySubtitle();
          if (resume != null) {
            _lastResumeSeekSucceeded = await _restoreResumePosition(resume);
          }
          if (_engineHandoffInProgress) return;
          _startVideoWatchdog();
          _startPerformanceWatchdog();
        } catch (error, stackTrace) {
          if (propagateFailure) rethrow;
          if (mounted && !_engineHandoffInProgress) {
            unawaited(
              recordAnonymousHandledError(
                area: AnonymousErrorArea.playback,
                error: error,
                stack: stackTrace,
              ),
            );
            setState(() => _playbackError = error.toString());
          }
        } finally {
          if (persistenceWasReady) _playbackPersistenceReady = true;
        }
      });

  Future<void> _trackPlayerMutation(Future<void> Function() action) async {
    if (_engineHandoffInProgress) return;
    final operation = action();
    _playerMutationOperations.add(operation);
    try {
      await operation;
    } finally {
      _playerMutationOperations.remove(operation);
    }
  }

  void _handlePlaybackCompleted() {
    if (_completionHandled || _engineHandoffInProgress) return;
    _completionHandled = true;
    if (!_progressHandled &&
        widget.episode != null &&
        (widget.anilistMediaId != null || widget.malMediaId != null)) {
      _progressHandled = true;
      unawaited(_syncProgress());
    }
    unawaited(_offerNextEpisode());
  }

  Future<bool> _seekForSkip(Duration target) {
    if (_engineHandoffInProgress) return Future<bool>.value(false);
    late final Future<bool> operation;
    operation =
        (() async {
          try {
            await _player.seek(target);
            return true;
          } catch (_) {
            return false;
          }
        })().whenComplete(() {
          if (identical(_skipSeekOperation, operation)) {
            _skipSeekOperation = null;
          }
        });
    _skipSeekOperation = operation;
    return operation;
  }

  Future<void> _waitForPlayerMutations() async {
    while (_playerMutationOperations.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_playerMutationOperations));
    }
  }

  Future<bool> _restoreResumePosition(Duration resume) async {
    if (_player.state.duration <= Duration.zero) {
      try {
        await _player.stream.duration
            .firstWhere((duration) => duration > Duration.zero)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Some streams do not expose duration until after their first seek.
      }
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_engineHandoffInProgress) return false;
      try {
        await _player.seek(resume);
      } catch (_) {
        // Network demuxers can reject seeks until their index is available.
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!resumeSeekNeedsRetry(resume, _player.state.position)) {
        _pendingInheritedResume = null;
        return true;
      }
    }
    return false;
  }

  Duration _effectiveHandoffPosition() {
    final position = _player.state.position;
    final inherited = _pendingInheritedResume;
    if (inherited != null &&
        inherited > position &&
        position < const Duration(seconds: 2)) {
      return inherited;
    }
    return position;
  }

  Future<void> _configureNativePlayback() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = <String, String>{
      'hwdec': hwdecForPlaybackMode(_decoderMode),
      'hwdec-software-fallback': '1',
      'vd-lavc-check-hw-profile': 'yes',
      'framedrop': 'vo',
      'demuxer-lavf-probesize': '67108864',
      'demuxer-lavf-analyzeduration': '10',
      'network-timeout': '20',
      'cache': 'yes',
      'cache-pause-initial': 'yes',
      'cache-pause-wait': '2',
      'cache-secs': '45',
      'demuxer-readahead-secs': '20',
      'demuxer-max-bytes': '${48 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${8 * 1024 * 1024}',
      'video-sync': 'audio',
      'interpolation': 'no',
      'deband': 'no',
      'scale': 'bilinear',
      'cscale': 'bilinear',
      'dscale': 'bilinear',
      'sub-pos': '$_subtitlePosition',
      'sub-delay': '${_subtitleDelayMs / 1000}',
      'audio-delay': '${_audioDelayMs / 1000}',
      'sub-border-size': _highContrastSubtitles ? '4' : '2.5',
      'sub-color': _mpvColor(_captionTextColor),
      'sub-back-color': _mpvColor(
        _highContrastSubtitles
            ? const Color(0xDD000000)
            : _captionBackgroundColor,
      ),
    };
    for (final property in properties.entries) {
      try {
        await platform.setProperty(property.key, property.value);
      } catch (_) {
        // libmpv builds vary slightly; unsupported tuning must not block play.
      }
    }
  }

  Future<void> _applyPlayerTuning() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = <String, String>{
      'sub-scale': '${_subtitleSize / 34}',
      'sub-pos': '$_subtitlePosition',
      'sub-delay': '${_subtitleDelayMs / 1000}',
      'audio-delay': '${_audioDelayMs / 1000}',
      'sub-border-size': _highContrastSubtitles ? '4' : '2.5',
      'sub-color': _mpvColor(_captionTextColor),
      'sub-back-color': _mpvColor(
        _highContrastSubtitles
            ? const Color(0xDD000000)
            : _captionBackgroundColor,
      ),
    };
    for (final property in properties.entries) {
      try {
        await platform.setProperty(property.key, property.value);
      } catch (_) {
        // Keep playback alive on mpv builds missing an optional property.
      }
    }
  }

  Future<void> _applySubtitle() async {
    if (!_seriesPreferences.subtitleEnabled) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final subtitle =
        _currentStream.externalSubtitle?.toString() ?? widget.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      if (subtitle.startsWith('asset:///')) {
        final assetKey = subtitle.substring('asset:///'.length);
        final data = await rootBundle.loadString(assetKey);
        await _player.setSubtitleTrack(
          SubtitleTrack.data(data, title: 'Bundled styled subtitles'),
        );
      } else {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(subtitle, title: 'External subtitles'),
        );
      }
    }
  }

  Future<void> _persistPlayback(Duration position, {bool force = false}) async {
    if (!_playbackPersistenceReady) return;
    final mediaId = widget.anilistMediaId;
    final episode = widget.episode;
    if (mediaId == null || episode == null) return;
    var now = DateTime.now();
    if (!force &&
        now.difference(_lastCheckpointSave) < const Duration(seconds: 10)) {
      return;
    }
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    if (!now.isAfter(_lastCheckpointSave)) {
      now = _lastCheckpointSave.add(const Duration(milliseconds: 1));
    }
    _lastCheckpointSave = now;
    final completed = position.inMilliseconds / duration.inMilliseconds >= .93;
    await _database.saveCheckpoint(
      PlaybackCheckpoint(
        anilistMediaId: mediaId,
        malMediaId: widget.malMediaId,
        episode: episode,
        title: widget.launch.episode.title,
        coverImageUrl: widget.coverImageUrl,
        position: completed ? duration : position,
        duration: duration,
        updatedAt: now,
        completed: completed,
      ),
    );
    if ((force || completed) && mounted) {
      ref.invalidate(recentPlaybackProvider);
      ref.invalidate(latestPlaybackProvider(mediaId));
    }
    if (!completed && position > const Duration(seconds: 30)) {
      await AndroidTvBridge.instance.publishWatchNext(
        mediaId: mediaId,
        episode: episode,
        title: widget.launch.episode.title,
        posterUrl: widget.coverImageUrl,
        position: position,
        duration: duration,
      );
    } else if (completed) {
      await AndroidTvBridge.instance.removeWatchNext(mediaId);
    }
  }

  Future<void> _updateMediaSession({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastMediaSessionUpdate) < const Duration(seconds: 5)) {
      return;
    }
    _lastMediaSessionUpdate = now;
    await AndroidTvBridge.instance.updateMediaSession(
      title: widget.launch.episode.title,
      episode: widget.episode ?? 1,
      position: _player.state.position,
      duration: _player.state.duration,
      playing: _player.state.playing,
      artworkUrl: widget.coverImageUrl,
      seekBackSeconds: _seekBackSeconds,
      seekForwardSeconds: _seekForwardSeconds,
    );
  }

  void _handleMediaAction(MediaAction action) {
    if (_engineHandoffInProgress) return;
    switch (action.action) {
      case 'play':
        unawaited(_player.play());
      case 'pause':
        unawaited(_player.pause());
      case 'seekTo':
        unawaited(_seekTo(Duration(milliseconds: action.value ?? 0)));
      case 'seekBy':
        unawaited(_seekBy(Duration(milliseconds: action.value ?? 0)));
      case 'next':
        unawaited(_playNextEpisode());
      case 'previous':
        unawaited(_seekBy(-_player.state.position));
    }
  }

  Future<void> _matchContentFrameRate() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    for (final property in const ['container-fps', 'estimated-vf-fps']) {
      try {
        final value = await platform.getProperty(property);
        final fps = double.tryParse(value);
        if (fps != null && fps >= 20 && fps <= 120) {
          await AndroidTvBridge.instance.setPreferredFrameRate(fps);
          return;
        }
      } catch (_) {
        // Try the next libmpv property.
      }
    }
  }

  Future<StreamReady?> _resolveRelease(
    ReleaseCandidate release,
    EpisodeReference episode, {
    DebridTokenService? tokenService,
  }) async {
    if (!mounted || _engineHandoffInProgress) return null;
    final DebridTokenService capturedTokenService =
        tokenService ?? ref.read(debridTokenServiceProvider);
    String? token;
    try {
      token = await capturedTokenService.accessToken(widget.debridService);
    } catch (_) {
      throw DebridProviderAccessException(
        widget.debridService,
        detail:
            'Your ${widget.debridService.displayName} connection could not be '
            'refreshed. Reconnect it in Accounts, then try again.',
      );
    }
    if (!mounted || _engineHandoffInProgress) return null;
    if (token == null || token.isEmpty) {
      throw DebridProviderAccessException(widget.debridService);
    }
    final source = SingleReleaseSource(release);
    final resolver = createDebridStreamResolver(
      service: widget.debridService,
      token: token,
      source: source,
    );
    await for (final resolution in resolver.resolve(episode)) {
      if (!mounted || _engineHandoffInProgress) return null;
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _tryNextStream(String reason) async {
    if (!mounted || _engineHandoffInProgress || _failingOver) return;
    _failingOver = true;
    final position = _player.state.position;
    final tokenService = ref.read(debridTokenServiceProvider);
    Object? terminalFailure;
    try {
      final classOrder = playerFailoverClassOrder(
        currentIsWeb: _currentStream.isWebStream,
      );
      final directFirst = classOrder.first == PlayerFailoverClass.directWeb;
      final profile = await AndroidTvBridge.instance.getDeviceProfile();
      if (!mounted || _engineHandoffInProgress) return;
      await _database.recordStreamFailure(
        deviceKey: profile.key,
        infoHash: _currentRelease.infoHash,
        reason: reason,
      );
      if (!mounted || _engineHandoffInProgress) return;
      if (directFirst) {
        await _waitForInFlightDirectDiscovery();
        if (!mounted || _engineHandoffInProgress) return;
        if (await _switchToNextDirectStream(position)) return;
      }
      if (!mounted || _engineHandoffInProgress) return;
      for (final candidate in _remainingReleaseFailoverCandidates().take(12)) {
        _attemptedReleaseAlternatives.add(candidate);
        final previousSource = _source;
        final previousRelease = _currentRelease;
        final previousStream = _currentStream;
        final previousPreferences = _seriesPreferences;
        final previousAudioSelected = _preferredAudioSelected;
        final previousSubtitleSelected = _preferredSubtitleSelected;
        final previousSoftwareFallbackUsed = _softwareFallbackUsed;
        final previousDecoderMode = _decoderMode;
        final previousVideoFrameSeen = _videoFrameSeen;
        try {
          final ready = await _resolveRelease(
            candidate,
            widget.launch.episode,
            tokenService: tokenService,
          );
          if (!mounted || _engineHandoffInProgress) return;
          if (ready == null) continue;
          _source = ready.uri.toString();
          _currentRelease = candidate;
          _currentStream = ready;
          _seriesPreferences = _seriesPreferences.copyWith(
            subtitleEnabled: subtitlesEnabledForAudioPreference(
              candidate,
              _audioPreference,
            ),
          );
          _preferredAudioSelected = false;
          _preferredSubtitleSelected = false;
          _softwareFallbackUsed = false;
          _decoderMode = releaseRequiresSoftwareDecoder(candidate)
              ? PlaybackDecoderMode.software
              : PlaybackDecoderMode.hardwareSafe;
          _softwareFallbackUsed = _decoderMode == PlaybackDecoderMode.software;
          _videoFrameSeen = false;
          await _openMedia(resume: position, propagateFailure: true);
          if (!mounted || _engineHandoffInProgress) return;
          await widget.onStreamAdopted(ready, candidate);
          if (_skips.isEmpty) {
            _skipLoadComplete = false;
            _skipLoadAttempts = 0;
            _skipDurationCandidate = null;
            _scheduleSkipSegmentLoad(_player.state.duration);
          }
          setState(() => _playbackError = null);
          return;
        } catch (error) {
          if (!mounted || _engineHandoffInProgress) return;
          _source = previousSource;
          _currentRelease = previousRelease;
          _currentStream = previousStream;
          _seriesPreferences = previousPreferences;
          _preferredAudioSelected = previousAudioSelected;
          _preferredSubtitleSelected = previousSubtitleSelected;
          _softwareFallbackUsed = previousSoftwareFallbackUsed;
          _decoderMode = previousDecoderMode;
          _videoFrameSeen = previousVideoFrameSeen;
          if (isTerminalDebridFailoverFailure(error)) {
            terminalFailure = error;
            break;
          }
          // Continue only through candidate-specific/cache-miss failures.
        }
      }
      if (!directFirst) {
        if (!mounted || _engineHandoffInProgress) return;
        await _waitForInFlightDirectDiscovery();
        if (!mounted || _engineHandoffInProgress) return;
        if (await _switchToNextDirectStream(position)) return;
      }
      if (mounted && !_engineHandoffInProgress) {
        await _fallbackToVlc(
          terminalFailure?.toString() ??
              'Every compatible debrid stream failed. $reason',
        );
      }
    } finally {
      _failingOver = false;
    }
  }

  Future<bool> _switchToNextDirectStream(Duration position) async {
    if (!mounted || _engineHandoffInProgress) {
      return false;
    }
    if (_currentStream.isWebStream) {
      _failedDirectStreamUris.add(_currentStream.uri.toString());
    }
    final opened = await openFirstViablePlayerCandidate(
      candidates: _remainingDirectFailoverCandidates(),
      resumePosition: position,
      isActive: () => mounted && !_engineHandoffInProgress,
      attempt: (candidate, resumePosition) async {
        final requestedUri = candidate.stream.uri;
        _failedDirectStreamUris.add(requestedUri.toString());
        final previousSource = _source;
        final previousRelease = _currentRelease;
        final previousStream = _currentStream;
        final previousAudioSelected = _preferredAudioSelected;
        final previousSubtitleSelected = _preferredSubtitleSelected;
        final previousSoftwareFallbackUsed = _softwareFallbackUsed;
        final previousDecoderMode = _decoderMode;
        final previousVideoFrameSeen = _videoFrameSeen;
        PlaybackStreamOption? preparedOption;
        try {
          final option = await _preflightDirectStream(candidate, silent: true);
          preparedOption = option;
          if (!mounted || _engineHandoffInProgress) {
            await option?.stream.playbackLease?.close();
            return false;
          }
          if (option == null) return false;
          if (validatedRedirectWasAlreadyAttempted(
            requestedUri: requestedUri,
            validatedUri: option.stream.uri,
            attemptedUris: _failedDirectStreamUris,
          )) {
            await option.stream.playbackLease?.close();
            return false;
          }
          _failedDirectStreamUris.add(option.stream.uri.toString());
          _currentStream = option.stream;
          _currentRelease = option.release;
          _source = option.stream.uri.toString();
          _preferredAudioSelected = false;
          _preferredSubtitleSelected = false;
          _softwareFallbackUsed = false;
          _decoderMode = releaseRequiresSoftwareDecoder(option.release)
              ? PlaybackDecoderMode.software
              : PlaybackDecoderMode.hardwareSafe;
          _softwareFallbackUsed = _decoderMode == PlaybackDecoderMode.software;
          _videoFrameSeen = false;
          await _openMedia(resume: resumePosition, propagateFailure: true);
          if (!mounted || _engineHandoffInProgress) {
            await option.stream.playbackLease?.close();
            return false;
          }
          await widget.onStreamAdopted(option.stream, option.release);
          preparedOption = null;
          setState(() => _playbackError = null);
          return true;
        } catch (_) {
          await preparedOption?.stream.playbackLease?.close();
          if (!mounted || _engineHandoffInProgress) rethrow;
          _source = previousSource;
          _currentRelease = previousRelease;
          _currentStream = previousStream;
          _preferredAudioSelected = previousAudioSelected;
          _preferredSubtitleSelected = previousSubtitleSelected;
          _softwareFallbackUsed = previousSoftwareFallbackUsed;
          _decoderMode = previousDecoderMode;
          _videoFrameSeen = previousVideoFrameSeen;
          rethrow;
        }
      },
    );
    return opened != null;
  }

  Future<void> _waitForInFlightDirectDiscovery() async {
    if (_remainingDirectFailoverCandidates().isNotEmpty) {
      return;
    }
    await _startWebSourceDiscovery();
    if (!mounted || _engineHandoffInProgress) return;
    await waitForPlayerFailoverCandidates(
      snapshot: _remainingDirectFailoverCandidates,
      isActive: () => mounted && !_engineHandoffInProgress,
    );
  }

  List<ReleaseCandidate> _remainingReleaseFailoverCandidates() {
    final candidates = widget.launch.alternatives
        .where(
          (candidate) => !_attemptedReleaseAlternatives.contains(candidate),
        )
        .toList();
    return rankAutomaticPlayerFailoverCandidates(
      candidates: candidates,
      audioRank: (candidate) =>
          releaseAudioPreferenceRank(candidate, _effectiveAudioPreference),
      affinityRank: _releaseFailoverAffinity,
    );
  }

  List<PlaybackStreamOption> _remainingDirectFailoverCandidates() {
    final candidates = _directStreamOptions
        .where(
          (option) =>
              option.stream.isWebStream &&
              !_failedDirectStreamUris.contains(option.stream.uri.toString()),
        )
        .toList();
    final currentProvider = _currentStream.providerId?.trim().toLowerCase();
    int affinityRank(PlaybackStreamOption option) {
      final provider = option.stream.providerId?.trim().toLowerCase();
      final providerRank =
          provider != null && provider.isNotEmpty && provider == currentProvider
          ? 0
          : 1;
      return (providerRank * 4) + _releaseFailoverAffinity(option.release);
    }

    return rankAutomaticPlayerFailoverCandidates(
      candidates: candidates,
      audioRank: (option) =>
          releaseAudioPreferenceRank(option.release, _effectiveAudioPreference),
      affinityRank: affinityRank,
    );
  }

  int _releaseFailoverAffinity(ReleaseCandidate candidate) {
    final currentProvider = _currentRelease.provider?.trim().toLowerCase();
    final candidateProvider = candidate.provider?.trim().toLowerCase();
    final sameProvider =
        currentProvider != null &&
        currentProvider.isNotEmpty &&
        candidateProvider == currentProvider;
    final sameSource =
        _currentRelease.sourceId.trim().toLowerCase() ==
        candidate.sourceId.trim().toLowerCase();
    final currentAuthor = releaseGroupKey(_currentRelease.releaseName);
    final sameAuthor =
        currentAuthor != null &&
        releaseGroupKey(candidate.releaseName) == currentAuthor;
    if ((sameProvider || sameSource) && sameAuthor) return 0;
    if (sameProvider || sameSource) return 1;
    if (sameAuthor) return 2;
    return 3;
  }

  Future<void> _retryCurrentStream() async {
    final position = _player.state.position;
    if (mounted) setState(() => _playbackError = null);
    try {
      await _openMedia(resume: position);
      _showTrackMessage('Stream restarted');
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    }
  }

  Future<void> _returnToStreamPicker() async {
    final navigator = Navigator.of(context);
    final position = _effectiveHandoffPosition();
    _pendingHandoffPosition = position;
    if (!await _prepareForEngineHandoff(position)) return;
    _popPlayerRouteAfterHandoff(navigator);
  }

  void _popPlayerRouteAfterHandoff(NavigatorState navigator) {
    if (!mounted || _routePopScheduled) return;
    _routePopScheduled = true;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted) unawaited(navigator.maybePop());
    });
  }

  Future<void> _recordEngineSuccess() async {
    if (_currentStream.providerId case final providerId?) {
      await _database.recordProviderSuccess(providerId);
      return;
    }
    final device = await AndroidTvBridge.instance.getDeviceProfile();
    await _database.recordPlayerSuccess(device.key, 'mpv');
  }

  Future<void> _detachAndroidVideoOutputBeforeRelease() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final platformController = await _controller.platform.future;
      if (platformController is! AndroidVideoController) return;

      // SurfaceProducer sends an asynchronous wid=0 update when Flutter
      // unmounts the Texture. AndroidVideoController's listener seeks after
      // applying that update, so allowing it to run after Player.dispose()
      // produces "[Player] has been disposed". Stop future producers first,
      // detach while the Player is alive, then use the controller's own lock
      // as the completion barrier for every listener already in flight.
      platformController.wid.removeListener(platformController.widListener);
      await platformController.videoParamsSubscription?.cancel();
      platformController.videoParamsSubscription = null;
      platformController.wid.value = 0;
      await platformController.widListener();
    } catch (_) {
      // Decoder release remains authoritative if an already-broken video
      // output cannot finish its best-effort surface detach.
    }
  }

  Future<bool> _prepareForEngineHandoff(Duration position) async {
    if (_handoffAttemptActive) return false;
    _handoffAttemptActive = true;
    _handoffReleaseFailed = false;
    _pendingHandoffPosition ??= position;
    _engineHandoffInProgress = true;
    _controlsTimer?.cancel();
    _videoWatchdog?.cancel();
    _performanceWatchdog?.cancel();
    _seekPreviewTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = false);

    try {
      // Remove the texture from the widget tree before stopping libmpv.
      // Starting another native engine while mpv still owns its Surface/audio
      // session can terminate the process on resource-constrained TV firmware.
      await WidgetsBinding.instance.endOfFrame;
      await _waitForPlayerMutations();
      _videoWatchdog?.cancel();
      _performanceWatchdog?.cancel();
      _queuedSeekTarget = null;
      await _waitForSeekDrain();
      final skipSeek = _skipSeekOperation;
      if (skipSeek != null) await skipSeek;
      final trickplayOperations = List<Future<void>>.of(_trickplayOperations);
      if (trickplayOperations.isNotEmpty) {
        await Future.wait(trickplayOperations);
      }
    } catch (_) {
      // A failed in-flight command has already completed. Continue to the
      // authoritative native release instead of leaving a broken decoder up.
    }
    try {
      await _persistPlayback(position, force: true);
    } catch (_) {
      // A failed checkpoint must not strand the user in the old engine.
    }
    try {
      await _saveSeriesPreferences();
    } catch (_) {
      // Preferences are best effort; decoder ownership still has to end.
    }
    try {
      await _progressSubscription?.cancel();
      await _durationSubscription?.cancel();
      await _tracksSubscription?.cancel();
      await _errorSubscription?.cancel();
      await _completedSubscription?.cancel();
      await _videoParamsSubscription?.cancel();
      await _playingSubscription?.cancel();
      await _mediaActionSubscription?.cancel();
      await _sourceDiscoverySubscription?.cancel();
    } catch (_) {
      // Stream callbacks guard on _engineHandoffInProgress. Native release is
      // still the authoritative safety boundary if a Dart cancellation fails.
    }
    final released = await _handoffRelease.release(() async {
      try {
        await _player.stop();
      } catch (_) {
        // dispose() is authoritative and may still release a backend whose
        // explicit stop command failed during a decoder error.
      }
      await _detachAndroidVideoOutputBeforeRelease();
      await _player.dispose();
      _playerReleasedForHandoff = true;
    });
    if (!released) {
      _handoffAttemptActive = false;
      _handoffReleaseFailed = true;
      if (mounted) {
        setState(() {
          _trackMessage =
              'Could not release the player safely. Press Exit to retry.';
        });
      }
      return false;
    }
    try {
      await AndroidTvBridge.instance.clearMediaSession();
      await AndroidTvBridge.instance.clearPreferredFrameRate();
    } catch (_) {
      // The decoder is already released; platform-session cleanup is best
      // effort and must not reopen the old engine.
    }
    _nativePlaybackStateClearedForHandoff = true;
    _handoffAttemptActive = false;
    return mounted;
  }

  Future<void> _fallbackToVlc(String reason) async {
    if (_requestedVlcFallback) return;
    _requestedVlcFallback = true;
    if (_currentStream.providerId case final providerId?) {
      await _database.recordProviderFailure(providerId, reason);
    } else {
      final device = await AndroidTvBridge.instance.getDeviceProfile();
      await _database.recordPlayerFailure(device.key, 'mpv');
    }
    await _database.recordDiagnosticEvent(
      category: 'player-mpv',
      message: reason,
    );
    final position = _effectiveHandoffPosition();
    if (await _prepareForEngineHandoff(position)) {
      widget.onUseVlc(
        position,
        _currentStream,
        _currentRelease,
        List.unmodifiable(_directStreamOptions),
      );
    }
  }

  Future<void> _prewarmNextEpisode() async {
    if (!mounted ||
        _engineHandoffInProgress ||
        _prewarming ||
        _prewarmed ||
        widget.episode == null) {
      return;
    }
    _prewarming = true;
    final userSourcesController = ref.read(
      userTorrentSourcesControllerProvider.notifier,
    );
    final userSourcesSubscription = ref.listenManual(
      userTorrentSourcesControllerProvider,
      (_, _) {},
    );
    final tokenService = ref.read(debridTokenServiceProvider);
    final launchEpisode = widget.launch.episode;
    final nextEpisodeNumber = widget.episode! + 1;
    final currentRelease = _currentRelease;
    final audioPreference = _audioPreference;
    try {
      final userManifests = await loadPlayerPrewarmSnapshot(
        load: userSourcesController.load,
        snapshot: () => userSourcesSubscription.read().manifestUrls,
        isActive: () => mounted && !_engineHandoffInProgress,
      );
      if (!mounted || _engineHandoffInProgress || userManifests == null) return;
      final sources = <ReleaseSource>[
        for (final manifestUrl in userManifests)
          StremioTorrentReleaseSource(manifestUrl: manifestUrl),
        if (AppConfig.hasReleaseResolver)
          HostedReleaseSource(baseUrl: AppConfig.releaseResolverBaseUrl),
      ];
      if (sources.isEmpty) return;
      final next = EpisodeReference(
        anilistMediaId: launchEpisode.anilistMediaId,
        malMediaId: launchEpisode.malMediaId,
        year: launchEpisode.year,
        title: launchEpisode.title,
        alternativeTitles: launchEpisode.alternativeTitles,
        coverImageUrl: launchEpisode.coverImageUrl,
        episode: nextEpisodeNumber,
      );
      final releases = await CompositeReleaseSource(sources).search(next);
      if (!mounted || _engineHandoffInProgress) return;
      if (releases.isEmpty) return;
      final currentGroup = releaseGroupKey(currentRelease.releaseName);
      final currentProvider = currentRelease.provider?.toLowerCase();
      releases.sort((a, b) {
        final group = (releaseGroupKey(a.releaseName) == currentGroup ? 0 : 1)
            .compareTo(releaseGroupKey(b.releaseName) == currentGroup ? 0 : 1);
        if (group != 0 && currentGroup != null) return group;
        final provider = (a.provider?.toLowerCase() == currentProvider ? 0 : 1)
            .compareTo(b.provider?.toLowerCase() == currentProvider ? 0 : 1);
        if (provider != 0 && currentProvider != null) return provider;
        final audio = releaseAudioPreferenceRank(
          a,
          audioPreference,
        ).compareTo(releaseAudioPreferenceRank(b, audioPreference));
        if (audio != 0) return audio;
        return b.seeders.compareTo(a.seeders);
      });
      await _resolveRelease(releases.first, next, tokenService: tokenService);
      if (!mounted || _engineHandoffInProgress) return;
      _prewarmed = true;
    } catch (_) {
      // Prewarming is intentionally invisible and never blocks playback.
    } finally {
      userSourcesSubscription.close();
      if (mounted) _prewarming = false;
    }
  }

  Future<void> _saveSeriesPreferences() async {
    final mediaId = widget.anilistMediaId;
    if (mediaId == null || !_seriesPreferencesReady) return;
    final audio = _player.state.track.audio;
    final subtitle = _player.state.track.subtitle;
    // Some dual-audio containers label a stream (for example, "English
    // Dub") without setting its ISO language field. Persist the normalized
    // title in that case so the next episode does not silently fall back to
    // the previous Japanese preference.
    final audioLanguage = persistedPlayerAudioLanguage(
      storedLanguage: _seriesPreferences.audioLanguage,
      audioPreferenceSet: _seriesPreferences.audioPreferenceSet,
      observedLanguage: audio.language,
      observedTitle: audio.title,
    );
    final subtitleLanguage = canonicalPlayerLanguage(
      subtitle.language ?? subtitle.title,
    );
    _seriesPreferences = _seriesPreferences.copyWith(
      audioLanguage: audioLanguage,
      subtitleLanguage: subtitleLanguage.isEmpty
          ? _seriesPreferences.subtitleLanguage
          : subtitleLanguage,
      subtitleEnabled: subtitle.id != 'no',
      subtitlePreferenceSet: true,
      subtitleSize: _subtitleSize,
      subtitlePosition: _subtitlePosition,
      subtitleDelayMs: _subtitleDelayMs,
      audioDelayMs: _audioDelayMs,
      decoder: switch (_decoderMode) {
        PlaybackDecoderMode.hardwareDirect => 'hardware-direct',
        PlaybackDecoderMode.software => 'software',
        _ => 'hardware-safe',
      },
      videoFit: switch (_videoFit) {
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        _ => 'contain',
      },
      highContrastSubtitles: _highContrastSubtitles,
      preferredReleaseProvider: _currentRelease.provider,
      clearPreferredReleaseProvider: _currentRelease.provider == null,
      preferredReleaseGroup: releaseGroupKey(_currentRelease.releaseName),
      clearPreferredReleaseGroup:
          releaseGroupKey(_currentRelease.releaseName) == null,
    );
    await _database.saveSeriesPreferences(mediaId, _seriesPreferences);
  }

  Future<void> _saveDecoderPreference() async {
    final mediaId = widget.anilistMediaId;
    if (mediaId == null) return;
    _seriesPreferences = _seriesPreferences.copyWith(
      decoder: switch (_decoderMode) {
        PlaybackDecoderMode.hardwareDirect => 'hardware-direct',
        PlaybackDecoderMode.software => 'software',
        _ => 'hardware-safe',
      },
    );
    await _database.saveSeriesPreferences(mediaId, _seriesPreferences);
  }

  Future<void> _offerNextEpisode() async {
    if (!mounted || widget.episode == null || widget.anilistMediaId == null) {
      return;
    }
    try {
      await _persistPlayback(_player.state.duration, force: true);
    } catch (_) {
      // Completion still needs to remain usable when checkpoint storage or the
      // platform watch-next provider is temporarily unavailable.
    }
    if (!mounted || _engineHandoffInProgress) return;
    if (!_seriesPreferences.autoplayNextEpisode) return;
    await _playNextEpisode();
  }

  void _startVideoWatchdog() {
    _videoWatchdog?.cancel();
    _watchdogAttempts = 0;
    _scheduleVideoWatchdogCheck();
  }

  void _scheduleVideoWatchdogCheck() {
    _videoWatchdog = Timer(const Duration(seconds: 8), () {
      if (!mounted || _videoFrameSeen || _changingDecoder) {
        return;
      }
      _watchdogAttempts++;
      if ((_player.state.buffering ||
              _player.state.position < const Duration(seconds: 2)) &&
          _watchdogAttempts < 4) {
        _scheduleVideoWatchdogCheck();
        return;
      }
      if (_hasUntriedDirectStream || _softwareFallbackUsed) {
        unawaited(_tryNextStream('No video frames were rendered.'));
      } else {
        unawaited(_restartWithSoftwareDecoder());
      }
    });
  }

  Future<void> _restartWithSoftwareDecoder() =>
      _switchDecoder(PlaybackDecoderMode.software, automatic: true);

  void _startPerformanceWatchdog() {
    _performanceWatchdog?.cancel();
    _lastDroppedFrames = 0;
    _highDropSamples = 0;
    _performanceWatchdog = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_checkPlaybackPerformance()),
    );
  }

  Future<String?> _optionalNativeProperty(
    NativePlayer platform,
    String name,
  ) async {
    try {
      final value = await platform.getProperty(name);
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _inspectDecodedVideo(VideoParams params) async {
    if (_checkingDecodedVideo ||
        _changingDecoder ||
        _decoderMode == PlaybackDecoderMode.software) {
      return;
    }
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    _checkingDecodedVideo = true;
    try {
      final values = await Future.wait([
        _optionalNativeProperty(platform, 'current-tracks/video/codec'),
        _optionalNativeProperty(platform, 'current-tracks/video/codec-profile'),
        _optionalNativeProperty(platform, 'current-tracks/video/format-name'),
        _optionalNativeProperty(platform, 'video-dec-params/pixelformat'),
        _optionalNativeProperty(platform, 'hwdec-current'),
      ]);
      final hardwareDecoder = values[4];
      if (hardwareDecoder == null || hardwareDecoder == 'no') return;
      if (isH264TenBitVideoProfile(
        codec: values[0] ?? _player.state.track.video.codec,
        profile: values[1],
        format: values[2],
        pixelFormat: values[3] ?? params.pixelformat,
        hardwarePixelFormat: params.hwPixelformat,
      )) {
        await _switchDecoder(
          PlaybackDecoderMode.software,
          automatic: true,
          reason: '10-bit H.264 detected; corrected video mode enabled',
        );
      }
    } finally {
      _checkingDecodedVideo = false;
    }
  }

  Future<void> _checkPlaybackPerformance() async {
    if (_checkingPerformance ||
        _changingDecoder ||
        !_player.state.playing ||
        _player.state.buffering) {
      return;
    }
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    _checkingPerformance = true;
    try {
      final value = await platform.getProperty('frame-drop-count');
      final dropped = int.tryParse(value) ?? _lastDroppedFrames;
      final delta = dropped >= _lastDroppedFrames
          ? dropped - _lastDroppedFrames
          : dropped;
      _lastDroppedFrames = dropped;
      _highDropSamples = delta >= 10 ? _highDropSamples + 1 : 0;
      if (_highDropSamples < 2) return;
      _highDropSamples = 0;
      if (_hasUntriedDirectStream) {
        await _tryNextStream(
          'This stream is dropping too many frames on this device.',
        );
      } else if (_decoderMode != PlaybackDecoderMode.software) {
        await _switchDecoder(
          PlaybackDecoderMode.software,
          automatic: true,
          reason: 'Playback was dropping frames; compatibility mode enabled',
        );
      } else {
        await _tryNextStream(
          'This stream is dropping too many frames on this device.',
        );
      }
    } catch (_) {
      // Frame statistics are optional across libmpv builds.
    } finally {
      _checkingPerformance = false;
    }
  }

  Future<void> _switchDecoder(
    PlaybackDecoderMode mode, {
    bool automatic = false,
    String? reason,
  }) => _trackPlayerMutation(() async {
    if (_changingDecoder || mode == _decoderMode) return;
    _changingDecoder = true;
    _decoderMode = mode;
    _softwareFallbackUsed = mode == PlaybackDecoderMode.software;
    _videoWatchdog?.cancel();
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    final persistenceWasReady = _playbackPersistenceReady;
    _playbackPersistenceReady = false;
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('hwdec', hwdecForPlaybackMode(mode));
        await platform.setProperty('hwdec-software-fallback', '1');
      }
      _preferredAudioSelected = false;
      _preferredSubtitleSelected = false;
      _videoFrameSeen = false;
      await _player.open(
        Media(_source, httpHeaders: _httpHeaders),
        play: automatic || wasPlaying,
      );
      if (position > Duration.zero) await _restoreResumePosition(position);
      await _applySubtitle();
      await _applyPlayerTuning();
      await _saveDecoderPreference();
      _startVideoWatchdog();
      _startPerformanceWatchdog();
      if (mounted) {
        setState(() => _playbackError = null);
        _showTrackMessage(
          automatic
              ? reason ??
                    'Video failed to start; software compatibility enabled'
              : '${playbackDecoderLabel(mode)} enabled',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    } finally {
      if (persistenceWasReady) _playbackPersistenceReady = true;
      _changingDecoder = false;
    }
  });

  Future<void> _retryPlayback() => _trackPlayerMutation(() async {
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    final persistenceWasReady = _playbackPersistenceReady;
    _playbackPersistenceReady = false;
    setState(() => _playbackError = null);
    try {
      _videoFrameSeen = false;
      await _configureNativePlayback();
      await _player.open(
        Media(_source, httpHeaders: _httpHeaders),
        play: wasPlaying,
      );
      if (position > Duration.zero) await _restoreResumePosition(position);
      await _applySubtitle();
      await _applyPlayerTuning();
      _startVideoWatchdog();
      _startPerformanceWatchdog();
      _showTrackMessage('Stream restarted');
    } catch (error) {
      if (mounted) setState(() => _playbackError = error.toString());
    } finally {
      if (persistenceWasReady) _playbackPersistenceReady = true;
    }
  });

  Stream<WebStreamSearchProgress> _webSourceSearch({bool refresh = false}) =>
      ref
          .read(webStreamAggregatorProvider)
          .watchSearchIncrementally(widget.launch.episode, refresh: refresh);

  Future<void> _startWebSourceDiscovery({bool restart = false}) async {
    if (!mounted || _engineHandoffInProgress) return;
    final webStreamsEnabled = ref
        .read(settingsPreferencesProvider)
        .webStreamsEnabled;
    final aggregator = ref.read(webStreamAggregatorProvider);
    final episode = widget.launch.episode;
    if (!webStreamsEnabled) return;
    if (_sourceDiscoverySubscription != null && !restart) return;
    await _sourceDiscoverySubscription?.cancel();
    if (!mounted || _engineHandoffInProgress) return;
    _sourceDiscoverySubscription = aggregator
        .watchSearchIncrementally(episode)
        .listen((progress) {
          if (!mounted || _engineHandoffInProgress) return;
          _mergeDirectStreamOptions(
            progress.aggregation.streams.map(playbackOptionForWebStream),
          );
        }, onError: (_) {});
  }

  void _mergeDirectStreamOptions(Iterable<PlaybackStreamOption> options) {
    final merged = mergePlaybackStreamOptions(_directStreamOptions, options);
    final before = _directStreamOptions
        .map((option) => option.stream.uri.toString())
        .join('\n');
    final after = merged
        .map((option) => option.stream.uri.toString())
        .join('\n');
    if (before == after) return;
    setState(() => _directStreamOptions = merged);
  }

  Future<PlaybackStreamOption?> _preflightDirectStream(
    PlaybackStreamOption option, {
    bool silent = false,
  }) async {
    if (!mounted || _engineHandoffInProgress) return null;
    if (!option.stream.isWebStream) return option;
    if (!silent) {
      _showTrackMessage('Checking ${playbackStreamOptionLabel(option)}...');
    }
    try {
      final validated = await const WebStreamValidator().validate(
        option.stream.uri,
        option.stream.headers,
        subtitleUri: option.stream.externalSubtitle,
      );
      if (!mounted || _engineHandoffInProgress) {
        await validated.session?.close();
        return null;
      }
      final validatedOption = PlaybackStreamOption(
        stream: StreamReady(
          uri: validated.uri,
          displayName: option.stream.displayName,
          headers: validated.headers,
          externalSubtitle: validated.subtitleUri,
          mediaContentType: validated.contentType,
          subtitleContentType: validated.subtitleContentType,
          externalSubtitleRejected: validated.subtitleRejected,
          playbackLease: validated.session,
          providerId: option.stream.providerId,
          providerName: option.stream.providerName,
        ),
        release: option.release,
      );
      return validatedOption;
    } catch (error) {
      if (!mounted || _engineHandoffInProgress) return null;
      _failedDirectStreamUris.add(option.stream.uri.toString());
      if (!silent) {
        _showTrackMessage(
          'That source is unavailable: '
          "${error.toString().replaceFirst('FormatException: ', '')}",
        );
      }
      return null;
    }
  }

  Future<void> _openStreamSourcePicker() async {
    _controlsTimer?.cancel();
    final selected = await showPlayerStreamSourcePicker(
      context: context,
      initialOptions: _directStreamOptions,
      selectedUri: _currentStream.uri,
      onOptionsChanged: (options) {
        if (mounted) setState(() => _directStreamOptions = options);
      },
      discover:
          _currentStream.isWebStream &&
              ref.read(settingsPreferencesProvider).webStreamsEnabled
          ? _webSourceSearch
          : null,
    );
    if (!mounted) return;
    if (selected == null || selected.stream.uri == _currentStream.uri) {
      _showControls();
      return;
    }

    final option = await _preflightDirectStream(selected);
    if (!mounted) {
      await option?.stream.playbackLease?.close();
      return;
    }
    if (option == null) {
      _showControls();
      return;
    }
    final resume = _player.state.position;
    final previousSource = _source;
    final previousStream = _currentStream;
    final previousRelease = _currentRelease;
    final previousDirectStreamOptions = _directStreamOptions;
    final previousDecoderMode = _decoderMode;
    final previousSoftwareFallbackUsed = _softwareFallbackUsed;
    final previousVideoFrameSeen = _videoFrameSeen;
    _failedDirectStreamUris.clear();
    _currentStream = option.stream;
    _source = option.stream.uri.toString();
    _currentRelease = option.release;
    _directStreamOptions = mergePlaybackStreamOptions(
      [option],
      _directStreamOptions.where(
        (candidate) =>
            candidate.stream.uri != selected.stream.uri &&
            candidate.stream.uri != previousStream.uri,
      ),
    );
    _preferredAudioSelected = false;
    _preferredSubtitleSelected = false;
    _softwareFallbackUsed = false;
    _decoderMode = releaseRequiresSoftwareDecoder(option.release)
        ? PlaybackDecoderMode.software
        : PlaybackDecoderMode.hardwareSafe;
    _softwareFallbackUsed = _decoderMode == PlaybackDecoderMode.software;
    _videoFrameSeen = false;
    if (mounted) setState(() => _playbackError = null);
    try {
      await _openMedia(resume: resume, propagateFailure: true);
      if (!mounted || _engineHandoffInProgress) {
        await option.stream.playbackLease?.close();
        return;
      }
      await widget.onStreamAdopted(option.stream, option.release);
    } catch (_) {
      await option.stream.playbackLease?.close();
      _source = previousSource;
      _currentStream = previousStream;
      _currentRelease = previousRelease;
      _directStreamOptions = previousDirectStreamOptions;
      _decoderMode = previousDecoderMode;
      _softwareFallbackUsed = previousSoftwareFallbackUsed;
      _videoFrameSeen = previousVideoFrameSeen;
      if (mounted && !_engineHandoffInProgress) {
        await _openMedia(resume: resume);
        _showTrackMessage(
          'That source could not start. Restored the previous stream.',
        );
      }
      return;
    }
    if (option.stream.externalSubtitleRejected) {
      _showTrackMessage(
        'Playing without the unsafe or unsupported external subtitles.',
      );
    }
    _showTrackMessage('Playing ${playbackStreamOptionLabel(option)}');
    _showControls();
  }

  // TODO: Remove after older persisted player-route labels are migrated.
  // ignore: unused_element
  static String _streamOptionLabel(PlaybackStreamOption option) {
    final quality = option.release.quality?.trim();
    final provider =
        option.stream.providerName ??
        option.release.provider ??
        option.release.sourceId;
    return [
      if (quality != null && quality.isNotEmpty) quality,
      provider,
    ].join(' • ');
  }

  Future<void> _openCaptionSizePicker() async {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    final selected = await showPlayerCaptionSizePicker(
      context: context,
      current: _subtitleSize,
    );
    if (!mounted) return;
    if (selected == null) {
      _scheduleControlsHide();
      return;
    }
    if (selected != _subtitleSize) {
      setState(() => _subtitleSize = selected);
      _showTrackMessage('Caption size: ${playerCaptionSizeLabel(selected)}');
      await _applyPlayerTuning();
      if (!mounted) return;
      await _saveSeriesPreferences();
      if (!mounted) return;
    }
    _scheduleControlsHide();
  }

  Future<void> _openPlaybackMenu() async {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    final result = await showDialog<_PlaybackMenuResult>(
      context: context,
      barrierColor: const Color(0xD9000000),
      builder: (context) => _PlaybackOptionsDialog(
        decoderMode: _decoderMode,
        videoFit: _videoFit,
        playbackRate: _playbackRate,
        subtitleSize: _subtitleSize,
        subtitlePosition: _subtitlePosition,
        subtitleDelayMs: _subtitleDelayMs,
        audioDelayMs: _audioDelayMs,
        highContrastSubtitles: _highContrastSubtitles,
        hasAlternateStreams: widget.launch.alternatives.any(
          (candidate) => !_attemptedReleaseAlternatives.contains(candidate),
        ),
        hasDirectSources: _currentStream.isWebStream,
      ),
    );
    if (!mounted) return;
    if (result == null) {
      _scheduleControlsHide();
      return;
    }
    switch (result.type) {
      case 'decoder':
        await _switchDecoder(result.value as PlaybackDecoderMode);
      case 'fit':
        setState(() => _videoFit = result.value as BoxFit);
        _showTrackMessage(_fitLabel(_videoFit));
      case 'rate':
        final rate = result.value as double;
        await _player.setRate(rate);
        if (!mounted) return;
        setState(() => _playbackRate = rate);
        _showTrackMessage('Playback speed ${rate}x');
      case 'subtitleSize':
        setState(() => _subtitleSize = result.value as double);
        _showTrackMessage('Subtitle size ${_subtitleSize.round()}');
      case 'subtitlePosition':
        setState(() => _subtitlePosition = result.value as int);
        _showTrackMessage('Subtitle position $_subtitlePosition%');
      case 'subtitleDelay':
        setState(() => _subtitleDelayMs = result.value as int);
        _showTrackMessage('Subtitle delay ${_subtitleDelayMs}ms');
      case 'audioDelay':
        setState(() => _audioDelayMs = result.value as int);
        _showTrackMessage('Audio delay ${_audioDelayMs}ms');
      case 'contrast':
        setState(() => _highContrastSubtitles = result.value as bool);
        _showTrackMessage(
          _highContrastSubtitles
              ? 'High contrast subtitles on'
              : 'High contrast subtitles off',
        );
      case 'nextStream':
        await _tryNextStream('Stream changed manually.');
      case 'sources':
        await _openStreamSourcePicker();
      case 'retry':
        await _retryPlayback();
    }
    if (!mounted) return;
    await _applyPlayerTuning();
    if (!mounted) return;
    await _saveSeriesPreferences();
    if (!mounted) return;
    _scheduleControlsHide();
  }

  Future<void> _openPlayerPicker() async {
    _controlsTimer?.cancel();
    final selected = await showPlayerEnginePicker(
      context: context,
      current: PreferredPlayer.mpv,
    );
    if (!mounted || selected == null || selected == PreferredPlayer.mpv) {
      if (mounted) _showControls();
      return;
    }
    final position = _effectiveHandoffPosition();
    final stream = _currentStream;
    final release = _currentRelease;
    final directStreams = List<PlaybackStreamOption>.unmodifiable(
      _directStreamOptions,
    );
    if (!await _prepareForEngineHandoff(position)) return;
    final callback = widget.onSelectEngine;
    if (callback != null) {
      callback(selected, position, stream, release, directStreams);
      return;
    }
    if (selected == PreferredPlayer.vlc) {
      widget.onUseVlc(position, stream, release, directStreams);
      return;
    }
    _showTrackMessage('This player is not available from this screen');
    _showControls();
  }

  void _cycleFit() {
    final next = switch (_videoFit) {
      BoxFit.contain => BoxFit.cover,
      BoxFit.cover => BoxFit.fill,
      _ => BoxFit.contain,
    };
    setState(() => _videoFit = next);
    unawaited(_saveSeriesPreferences());
    _showTrackMessage(_fitLabel(next));
  }

  static String _fitLabel(BoxFit fit) => switch (fit) {
    BoxFit.cover => 'Picture: Fill screen',
    BoxFit.fill => 'Picture: Stretch',
    _ => 'Picture: Fit',
  };

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_engineHandoffInProgress) return KeyEventResult.handled;

    final key = event.logicalKey;
    if (consumeHiddenPlayerHudDownRepeat(
      key: key,
      isRepeat: event is KeyRepeatEvent,
      controlsVisible: _controlsVisible,
    )) {
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.arrowDown &&
        _controlsVisible) {
      _hideControls();
      return KeyEventResult.handled;
    }
    final directionalKey =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final controlsWereHidden = !_controlsVisible;
    _showControls(focusControls: controlsWereHidden && directionalKey);
    if (!node.hasPrimaryFocus &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (node.hasPrimaryFocus && directionalKey) {
      _showControls(focusControls: true);
      return KeyEventResult.handled;
    }
    if (playerSeekOffsetForKey(
          key,
          backSeconds: _seekBackSeconds,
          forwardSeconds: _seekForwardSeconds,
        )
        case final offset?) {
      _seekBy(offset);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.keyK) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_openSubtitleTrackPicker());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI && _canSkipNow) {
      _skipCurrentSegment();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.gameButtonY) {
      unawaited(_openPlaybackMenu());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (_softwareFallbackUsed) {
        _showTrackMessage('Compatibility decoder is already enabled');
      } else {
        unawaited(_restartWithSoftwareDecoder());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.gameButtonX) {
      _cycleFit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _seekBy(Duration offset) async {
    if (_engineHandoffInProgress) return;
    _queuedSeekTarget = playerSeekTarget(
      position: _queuedSeekTarget ?? _player.state.position,
      offset: offset,
      duration: _player.state.duration,
    );
    await _drainSeekQueue();
  }

  Future<void> _seekTo(Duration target) async {
    if (_engineHandoffInProgress) return;
    _queuedSeekTarget = playerSeekTarget(
      position: target,
      offset: Duration.zero,
      duration: _player.state.duration,
    );
    await _drainSeekQueue();
  }

  Future<void> _drainSeekQueue() async {
    final activeDrain = _seekDrainCompleter;
    if (activeDrain != null) {
      await activeDrain.future;
      return;
    }
    final drain = Completer<void>();
    _seekDrainCompleter = drain;
    try {
      while (_queuedSeekTarget != null) {
        final target = _queuedSeekTarget!;
        _queuedSeekTarget = null;
        await _player.seek(target);
        if (!_engineHandoffInProgress) {
          final operation = _captureTrickplay(target);
          _trickplayOperations.add(operation);
          unawaited(
            operation.whenComplete(() {
              _trickplayOperations.remove(operation);
            }),
          );
        }
      }
    } catch (_) {
      _queuedSeekTarget = null;
      if (mounted && !_engineHandoffInProgress) {
        _showTrackMessage('Could not seek to that position');
      }
    } finally {
      if (identical(_seekDrainCompleter, drain)) {
        _seekDrainCompleter = null;
      }
      if (!drain.isCompleted) drain.complete();
    }
  }

  Future<void> _waitForSeekDrain() async {
    final drain = _seekDrainCompleter;
    if (drain != null) await drain.future;
  }

  Future<void> _captureTrickplay(Duration target) async {
    try {
      final bytes = await _player.screenshot(format: 'image/jpeg');
      if (!mounted ||
          _engineHandoffInProgress ||
          bytes == null ||
          bytes.isEmpty) {
        return;
      }
      _seekPreviewTimer?.cancel();
      setState(() {
        _seekPreview = bytes;
        _seekPreviewPosition = target;
      });
      _seekPreviewTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _seekPreview = null);
      });
    } catch (_) {
      // Some protected video surfaces do not permit screenshots.
    }
  }

  Future<void> _openAudioTrackPicker() async {
    final expectsMultipleAudio = releaseAdvertisesMultipleAudio(
      _currentRelease.releaseName,
    );
    if (expectsMultipleAudio) {
      _showTrackMessage('Checking every embedded audio track…');
    }
    final tracks = await waitForStableTrackSnapshot<List<AudioTrack>>(
      read: () async {
        if (!mounted || _engineHandoffInProgress) return const <AudioTrack>[];
        return _player.state.tracks.audio
            .where((track) => track.id != 'auto' && track.id != 'no')
            .toList(growable: false);
      },
      signature: mediaKitAudioTrackSignature,
      hasTracks: (tracks) => tracks.isNotEmpty,
      // A stable first track is not proof that demuxing is finished. Always
      // use the short bounded window for a possible second track; release
      // names advertising dual audio receive the longer window below.
      isComplete: (tracks) => tracks.length >= 2,
      maximumWait: expectsMultipleAudio
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2),
    );
    if (!mounted || _engineHandoffInProgress) return;
    if (tracks.isEmpty) {
      _showTrackMessage('This file has no selectable embedded audio tracks');
      return;
    }
    _controlsTimer?.cancel();
    final currentId = _player.state.track.audio.id;
    final selectedId = await showPlayerTrackPicker<String>(
      context: context,
      title: tracks.length == 1
          ? expectsMultipleAudio
                ? 'Audio track (only 1 detected)'
                : 'Audio track (1 found)'
          : 'Audio tracks (${tracks.length} found)',
      icon: Icons.audiotrack_rounded,
      selectedValue: currentId,
      options: tracks
          .map(
            (track) => PlayerTrackOption<String>(
              value: track.id,
              label: track.title ?? track.language ?? 'Track ${track.id}',
              detail: mediaKitAudioTrackDetail(track),
              icon: Icons.surround_sound_rounded,
            ),
          )
          .toList(growable: false),
    );
    if (!mounted) return;
    if (selectedId == null) {
      _showControls();
      return;
    }
    final selected = tracks.firstWhere((track) => track.id == selectedId);
    _preferredAudioSelected = true;
    await _player.setAudioTrack(selected);
    final selectedLanguage = persistedPlayerAudioLanguage(
      storedLanguage: _seriesPreferences.audioLanguage,
      audioPreferenceSet: _seriesPreferences.audioPreferenceSet,
      observedLanguage: selected.language,
      observedTitle: selected.title,
      manualSelection: true,
    );
    _seriesPreferences = _seriesPreferences.copyWith(
      audioLanguage: selectedLanguage,
      audioPreferenceSet: true,
    );
    await _saveSeriesPreferences();
    _showTrackMessage(
      'Audio: ${selected.title ?? selected.language ?? 'Track ${selected.id}'}',
    );
    _showControls();
  }

  Future<void> _skipCurrentSegment() async {
    if (_skipInProgress || _engineHandoffInProgress) return;
    final segment = _activeSkip;
    if (segment == null) return;
    _skipInProgress = true;
    final target = safeSkipSegmentTarget(
      requested: segment.end,
      duration: _player.state.duration,
    );
    final segmentKey = '${segment.kind.name}:${segment.start.inMilliseconds}';
    _consumedSkipSegments.add(segmentKey);
    if (mounted) {
      setState(() {
        _activeSkip = null;
        _canSkipNow = false;
      });
    }
    try {
      final duration = _player.state.duration;
      final wasPlaying = _player.state.playing;
      final succeeded = await _seekForSkip(target);
      if (!succeeded) throw StateError('skip seek failed');
      if (mounted && !_engineHandoffInProgress) {
        _showTrackMessage(segment.actionLabel.replaceFirst('Skip', 'Skipped'));
      }
      if (!wasPlaying &&
          segment.kind == SkipSegmentKind.ending &&
          skipSegmentReachesPlaybackEnd(
            requestedEnd: segment.end,
            duration: duration,
          )) {
        _handlePlaybackCompleted();
      }
    } catch (_) {
      _consumedSkipSegments.remove(segmentKey);
      if (mounted && !_engineHandoffInProgress) {
        _showTrackMessage('Could not skip this segment');
      }
    } finally {
      _skipInProgress = false;
      if (mounted && !_engineHandoffInProgress) {
        _checkSkips(_player.state.position);
      }
    }
  }

  Future<void> _openSubtitleTrackPicker() async {
    var embedded = _player.state.tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    for (var attempt = 0; embedded.isEmpty && attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      embedded = _player.state.tracks.subtitle
          .where((track) => track.id != 'auto' && track.id != 'no')
          .toList(growable: false);
    }
    final tracks = <SubtitleTrack>[SubtitleTrack.no(), ...embedded];
    _controlsTimer?.cancel();
    final currentId = _player.state.track.subtitle.id;
    final selectedId = await showPlayerTrackPicker<String>(
      context: context,
      title: 'Closed captions',
      icon: Icons.closed_caption_rounded,
      selectedValue: currentId,
      options: tracks
          .map(
            (track) => PlayerTrackOption<String>(
              value: track.id,
              label: track.id == 'no'
                  ? 'Off'
                  : track.title ?? track.language ?? 'Track ${track.id}',
              detail: track.id == 'no'
                  ? 'Disable captions'
                  : playerTrackMatchesLanguage(
                      language: track.language,
                      title: track.title,
                      preferredLanguage: 'eng',
                    )
                  ? 'English'
                  : track.language,
              icon: track.id == 'no'
                  ? Icons.closed_caption_disabled_rounded
                  : Icons.closed_caption_rounded,
            ),
          )
          .toList(growable: false),
    );
    if (!mounted) return;
    if (selectedId == null) {
      _showControls();
      return;
    }
    final selected = tracks.firstWhere((track) => track.id == selectedId);
    _preferredSubtitleSelected = true;
    await _player.setSubtitleTrack(selected);
    unawaited(_saveSeriesPreferences());
    _showTrackMessage(
      selected.id == 'no'
          ? 'Subtitles: Off'
          : 'Subtitles: '
                '${selected.title ?? selected.language ?? 'Track ${selected.id}'}',
    );
    _showControls();
  }

  void _showTrackMessage(String message) {
    if (!mounted) return;
    setState(() => _trackMessage = message);
    Timer(const Duration(seconds: 2), () {
      if (mounted && _trackMessage == message) {
        setState(() => _trackMessage = null);
      }
    });
  }

  void _showControls({bool focusControls = false}) {
    if (mounted) setState(() => _controlsVisible = true);
    if (focusControls) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playControlFocus.requestFocus();
      });
    }
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(playerControlsIdleTimeout, () {
      if (mounted) _hideControls();
    });
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    if (mounted && _controlsVisible) {
      setState(() => _controlsVisible = false);
    }
    _playerRootFocus.requestFocus();
  }

  void _handleSurfaceTap() {
    if (_engineHandoffInProgress) return;
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _handleSurfaceDoubleTap() {
    if (_engineHandoffInProgress) return;
    final details = _touchDoubleTapDetails;
    if (details == null || !mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    final x = details.localPosition.dx;
    if (x < width / 3) {
      unawaited(_seekBy(Duration(seconds: -_seekBackSeconds)));
    } else if (x > width * 2 / 3) {
      unawaited(_seekBy(Duration(seconds: _seekForwardSeconds)));
    } else {
      unawaited(_player.playOrPause());
    }
    _showControls();
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit || _routePopScheduled || !mounted) return;
    if (_engineHandoffInProgress) {
      if (_handoffAttemptActive || !_handoffReleaseFailed) return;
      final navigator = Navigator.of(context);
      final position = _pendingHandoffPosition ?? Duration.zero;
      if (await _prepareForEngineHandoff(position)) {
        _popPlayerRouteAfterHandoff(navigator);
      }
      return;
    }
    _confirmingExit = true;
    // The HUD idle timer belongs to the player route, not the modal. If it
    // fires while the confirmation is open it hides the controls and requests
    // the video surface focus through the dialog on some Android TV devices.
    _controlsTimer?.cancel();
    final wasPlaying = _player.state.playing;
    bool? exit;
    try {
      if (wasPlaying) {
        // A decoder that is already failing may reject pause. Exiting must
        // remain reachable even in that state, so the dialog is independent
        // of a successful pause acknowledgement.
        try {
          await _player.pause();
        } catch (_) {}
      }
      if (!mounted) return;
      exit = await showPlayerExitConfirmation(context);
    } catch (_) {
      // A transient route/dialog failure must not permanently consume Back.
      exit = false;
    } finally {
      _confirmingExit = false;
    }
    if (!mounted) return;
    if (exit == true) {
      final navigator = Navigator.of(context);
      final position = _effectiveHandoffPosition();
      _pendingHandoffPosition = position;
      if (await _prepareForEngineHandoff(position)) {
        _popPlayerRouteAfterHandoff(navigator);
      }
    } else {
      if (wasPlaying) {
        try {
          await _player.play();
        } catch (_) {
          // Keep the player screen responsive if a broken decoder cannot resume.
        }
      }
      if (mounted) _showControls(focusControls: true);
    }
  }

  @override
  void dispose() {
    _skipLoadTimer?.cancel();
    _durationSubscription?.cancel();
    if (!_engineHandoffInProgress && !_playerReleasedForHandoff) {
      unawaited(_persistPlayback(_player.state.position, force: true));
      unawaited(_saveSeriesPreferences());
    }
    if (!_nativePlaybackStateClearedForHandoff) {
      unawaited(AndroidTvBridge.instance.clearMediaSession());
      unawaited(AndroidTvBridge.instance.clearPreferredFrameRate());
    }
    _controlsTimer?.cancel();
    _videoWatchdog?.cancel();
    _performanceWatchdog?.cancel();
    _seekPreviewTimer?.cancel();
    if (!_engineHandoffInProgress) {
      _progressSubscription?.cancel();
      _tracksSubscription?.cancel();
      _errorSubscription?.cancel();
      _completedSubscription?.cancel();
      _videoParamsSubscription?.cancel();
      _playingSubscription?.cancel();
      _mediaActionSubscription?.cancel();
      _sourceDiscoverySubscription?.cancel();
    }
    // Unexpected route disposal does not pass through the awaited handoff
    // path. Close the mutation gate before releasing libmpv and join any
    // already-running async track callback inside the release coordinator.
    _engineHandoffInProgress = true;
    _playerRootFocus.dispose();
    _playControlFocus.dispose();
    _skipControlFocus.dispose();
    if (!_playerReleasedForHandoff) {
      unawaited(
        _handoffRelease.release(() async {
          try {
            await _waitForPlayerMutations();
          } catch (_) {
            // A failed command is already terminal. Decoder disposal remains
            // authoritative during unexpected route teardown.
          }
          try {
            await _player.stop();
          } catch (_) {
            // dispose() is still authoritative for a failed decoder.
          }
          await _detachAndroidVideoOutputBeforeRelease();
          await _player.dispose();
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmExit());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _playerRootFocus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleSurfaceTap,
            onDoubleTapDown: (details) => _touchDoubleTapDetails = details,
            onDoubleTap: _handleSurfaceDoubleTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_engineHandoffInProgress)
                  Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: _videoFit,
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      style: TextStyle(
                        color: _captionTextColor,
                        fontSize: _subtitleSize,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 5,
                            offset: Offset(2, 2),
                          ),
                        ],
                        backgroundColor: _highContrastSubtitles
                            ? const Color(0xDD000000)
                            : _captionBackgroundColor,
                      ),
                    ),
                  )
                else
                  const ColoredBox(
                    key: ValueKey('mpv-engine-handoff-shield'),
                    color: Colors.black,
                  ),
                if (!_engineHandoffInProgress)
                  StreamBuilder<bool>(
                    stream: _player.stream.buffering,
                    initialData: _player.state.buffering,
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return Center(
                        child: CircularProgressIndicator(
                          color: palette.secondaryAccent,
                        ),
                      );
                    },
                  ),
                if (!_engineHandoffInProgress)
                  Positioned(
                    left: 34,
                    right: 34,
                    top: 28,
                    child: StreamBuilder<bool>(
                      stream: _player.stream.playing,
                      initialData: _player.state.playing,
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 12),
                                ],
                              ),
                        );
                      },
                    ),
                  ),
                if (!_engineHandoffInProgress)
                  ExcludeFocus(
                    excluding: !_controlsVisible,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: _UnifiedMpvPlayerChrome(
                          player: _player,
                          title: widget.title,
                          streamLabel:
                              _currentStream.providerName ??
                              '${widget.debridService.displayName} stream',
                          decoderMode: _decoderMode,
                          playFocusNode: _playControlFocus,
                          seekBackSeconds: _seekBackSeconds,
                          seekForwardSeconds: _seekForwardSeconds,
                          onRewind: () =>
                              _seekBy(Duration(seconds: -_seekBackSeconds)),
                          onPlayPause: _player.playOrPause,
                          onForward: () =>
                              _seekBy(Duration(seconds: _seekForwardSeconds)),
                          onAudio: _openAudioTrackPicker,
                          onSubtitles: _openSubtitleTrackPicker,
                          onCaptionSize: _openCaptionSizePicker,
                          onFit: _cycleFit,
                          onCompatibility: () => unawaited(_openPlayerPicker()),
                          onSources: _currentStream.isWebStream
                              ? _openStreamSourcePicker
                              : null,
                          onOptions: _openPlaybackMenu,
                          onDismiss: _hideControls,
                        ),
                      ),
                    ),
                  ),
                if (_canSkipNow && _activeSkip != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    right: MediaQuery.sizeOf(context).width < 720 ? 16 : 38,
                    bottom: _controlsVisible
                        ? (MediaQuery.sizeOf(context).height < 480 ? 132 : 184)
                        : 26,
                    child: TetoSkipSegmentOverlay(
                      focusNode: _skipControlFocus,
                      label: _activeSkip!.actionLabel,
                      onPressed: _skipCurrentSegment,
                    ),
                  ),
                if (_playbackError case final error?)
                  Positioned(
                    left: 34,
                    right: 34,
                    bottom: 110,
                    child: _PlaybackError(
                      message: error,
                      onRetry: () => unawaited(_retryCurrentStream()),
                      onNextStream: () =>
                          unawaited(_tryNextStream('Selected after failure')),
                      onSwitchEngine: () => unawaited(
                        _fallbackToVlc('VLC selected after playback failure'),
                      ),
                      onChooseStream: () => unawaited(_returnToStreamPicker()),
                    ),
                  ),
                if (_trackMessage case final message?)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: palette.playerSurface(
                          defaultColor: const Color(0xEE0A0A0A),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                if (_seekPreview case final preview?)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 116,
                    child: Center(
                      child: Container(
                        width: 210,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: palette.playerSurface(
                            defaultColor: Colors.black,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.accentBright),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.memory(
                                preview,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _formatPlayerDuration(
                                _seekPreviewPosition ?? Duration.zero,
                              ),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedMpvPlayerChrome extends StatelessWidget {
  const _UnifiedMpvPlayerChrome({
    required this.player,
    required this.title,
    required this.streamLabel,
    required this.decoderMode,
    required this.playFocusNode,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onAudio,
    required this.onSubtitles,
    required this.onCaptionSize,
    required this.onFit,
    required this.onCompatibility,
    this.onSources,
    required this.onOptions,
    required this.onDismiss,
  });

  final Player player;
  final String title;
  final String streamLabel;
  final PlaybackDecoderMode decoderMode;
  final FocusNode playFocusNode;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onCaptionSize;
  final VoidCallback onFit;
  final VoidCallback onCompatibility;
  final VoidCallback? onSources;
  final VoidCallback onOptions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, positionSnapshot) => StreamBuilder<Duration>(
        stream: player.stream.duration,
        initialData: player.state.duration,
        builder: (context, durationSnapshot) => StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, playingSnapshot) => TetoPlayerChrome(
            engineKey: 'mpv',
            engineLabel: 'MPV - ${playbackDecoderLabel(decoderMode)}',
            title: title,
            streamLabel: streamLabel,
            position: positionSnapshot.data ?? Duration.zero,
            duration: durationSnapshot.data ?? Duration.zero,
            isPlaying: playingSnapshot.data ?? false,
            playFocusNode: playFocusNode,
            seekBackSeconds: seekBackSeconds,
            seekForwardSeconds: seekForwardSeconds,
            onRewind: onRewind,
            onPlayPause: onPlayPause,
            onForward: onForward,
            onAudio: onAudio,
            onSubtitles: onSubtitles,
            onCaptionSize: onCaptionSize,
            onPicture: onFit,
            onFixVideo: onCompatibility,
            onSources: onSources,
            onOptions: onOptions,
            onDismiss: onDismiss,
          ),
        ),
      ),
    );
  }
}

class _PlaybackOptionsDialog extends StatelessWidget {
  const _PlaybackOptionsDialog({
    required this.decoderMode,
    required this.videoFit,
    required this.playbackRate,
    required this.subtitleSize,
    required this.subtitlePosition,
    required this.subtitleDelayMs,
    required this.audioDelayMs,
    required this.highContrastSubtitles,
    required this.hasAlternateStreams,
    required this.hasDirectSources,
  });

  final PlaybackDecoderMode decoderMode;
  final BoxFit videoFit;
  final double playbackRate;
  final double subtitleSize;
  final int subtitlePosition;
  final int subtitleDelayMs;
  final int audioDelayMs;
  final bool highContrastSubtitles;
  final bool hasAlternateStreams;
  final bool hasDirectSources;

  void _close(BuildContext context, String type, Object value) {
    Navigator.of(context).pop<_PlaybackMenuResult>((type: type, value: value));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: palette.playerSurface(),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: .55)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: palette.accentBright),
                    const SizedBox(width: 9),
                    Text(
                      'Playback options',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    Text(
                      'Changes apply immediately',
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _OptionSection(
                  title: 'DECODER',
                  children: [
                    for (final mode in PlaybackDecoderMode.values)
                      _OptionChip(
                        label: playbackDecoderLabel(mode),
                        selected: decoderMode == mode,
                        autofocus: decoderMode == mode,
                        onPressed: () => _close(context, 'decoder', mode),
                      ),
                    _OptionChip(
                      label: 'Restart stream',
                      icon: Icons.refresh_rounded,
                      onPressed: () => _close(context, 'retry', true),
                    ),
                    if (hasAlternateStreams)
                      _OptionChip(
                        label: 'Try next stream',
                        icon: Icons.swap_horiz_rounded,
                        onPressed: () => _close(context, 'nextStream', true),
                      ),
                    if (hasDirectSources)
                      _OptionChip(
                        label: 'Sources & quality',
                        icon: Icons.video_library_rounded,
                        onPressed: () => _close(context, 'sources', true),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _OptionSection(
                  title: 'PICTURE',
                  children: [
                    _OptionChip(
                      label: 'Fit',
                      selected: videoFit == BoxFit.contain,
                      onPressed: () => _close(context, 'fit', BoxFit.contain),
                    ),
                    _OptionChip(
                      label: 'Fill screen',
                      selected: videoFit == BoxFit.cover,
                      onPressed: () => _close(context, 'fit', BoxFit.cover),
                    ),
                    _OptionChip(
                      label: 'Stretch',
                      selected: videoFit == BoxFit.fill,
                      onPressed: () => _close(context, 'fit', BoxFit.fill),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _OptionSection(
                  title: 'SPEED',
                  children: [
                    for (final rate in const [.75, 1.0, 1.25, 1.5, 2.0])
                      _OptionChip(
                        label: '${rate}x',
                        selected: playbackRate == rate,
                        onPressed: () => _close(context, 'rate', rate),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _OptionSection(
                  title: 'SUBTITLE SIZE',
                  children: [
                    for (final size in const [28.0, 34.0, 42.0, 50.0])
                      _OptionChip(
                        label: switch (size) {
                          28 => 'Small',
                          34 => 'Medium',
                          42 => 'Large',
                          _ => 'Extra large',
                        },
                        selected: subtitleSize == size,
                        onPressed: () => _close(context, 'subtitleSize', size),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _OptionSection(
                  title: 'SUBTITLE STYLE',
                  children: [
                    for (final position in const [78, 90, 100])
                      _OptionChip(
                        label: switch (position) {
                          78 => 'Higher',
                          90 => 'Raised',
                          _ => 'Bottom',
                        },
                        selected: subtitlePosition == position,
                        onPressed: () =>
                            _close(context, 'subtitlePosition', position),
                      ),
                    _OptionChip(
                      label: highContrastSubtitles
                          ? 'High contrast on'
                          : 'High contrast off',
                      selected: highContrastSubtitles,
                      onPressed: () =>
                          _close(context, 'contrast', !highContrastSubtitles),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _OptionSection(
                  title: 'SYNC',
                  children: [
                    for (final delay in const [-500, -250, 0, 250, 500])
                      _OptionChip(
                        label: 'Subs ${delay > 0 ? '+' : ''}${delay}ms',
                        selected: subtitleDelayMs == delay,
                        onPressed: () =>
                            _close(context, 'subtitleDelay', delay),
                      ),
                    for (final delay in const [-250, 0, 250])
                      _OptionChip(
                        label: 'Audio ${delay > 0 ? '+' : ''}${delay}ms',
                        selected: audioDelayMs == delay,
                        onPressed: () => _close(context, 'audioDelay', delay),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionSection extends StatelessWidget {
  const _OptionSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final label = Text(
          title,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        );
        final options = Wrap(spacing: 7, runSpacing: 7, children: children);
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 7), options],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 112, child: label),
            Expanded(child: options),
          ],
        );
      },
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = selected
        ? palette.playerPrimaryActionText()
        : palette.playerPrimaryText();
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        color: selected ? palette.accent : palette.playerSelectableSurface(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final value?) ...[
              Icon(value, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({
    required this.message,
    required this.onRetry,
    required this.onNextStream,
    required this.onSwitchEngine,
    required this.onChooseStream,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onNextStream;
  final VoidCallback onSwitchEngine;
  final VoidCallback onChooseStream;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final errorAccent = palette.usesDefaultPlayerPalette
        ? const Color(0xFFFF929B)
        : palette.accentBright;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: palette.playerRaisedSurface(
            defaultColor: const Color(0xEE391D29),
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: errorAccent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: errorAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RecoveryAction(
                  label: 'Retry stream',
                  icon: Icons.refresh_rounded,
                  primary: true,
                  onPressed: onRetry,
                ),
                _RecoveryAction(
                  label: 'Next stream',
                  icon: Icons.skip_next_rounded,
                  onPressed: onNextStream,
                ),
                _RecoveryAction(
                  label: 'Use VLC',
                  icon: Icons.swap_horiz_rounded,
                  onPressed: onSwitchEngine,
                ),
                _RecoveryAction(
                  label: 'Choose stream',
                  icon: Icons.list_rounded,
                  onPressed: onChooseStream,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryAction extends StatelessWidget {
  const _RecoveryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = primary
        ? palette.playerPrimaryActionText()
        : palette.playerPrimaryText();
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: primary
              ? palette.accent
              : palette.playerSelectableSurface(
                  defaultColor: const Color(0xFF202026),
                ),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: palette.playerPrimaryText().withValues(alpha: .12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DebridOnlyPlaybackScreen extends StatelessWidget {
  const DebridOnlyPlaybackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.playerBackground(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 68, color: palette.secondaryAccent),
            const SizedBox(height: 18),
            const Text(
              'Playback blocked',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 620,
              child: Text(
                'TetoTV only accepts streams resolved through a connected '
                'supported debrid account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedText, fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
