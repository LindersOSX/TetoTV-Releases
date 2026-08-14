import 'dart:async';

import 'package:anime_tv/core/diagnostics/anonymous_crash_reporter.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/application/filler_episode_providers.dart';
import 'package:anime_tv/features/catalog/domain/filler_episode_lookup.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/marketplace/data/web_playback_proxy.dart';
import 'package:anime_tv/features/player/application/filler_episode_navigation.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/player/presentation/player_failover_coordinator.dart';
import 'package:anime_tv/features/player/presentation/filler_skip_notification.dart';
import 'package:anime_tv/features/player/presentation/player_stream_source_picker.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/theme_studio_controller.dart';
import 'package:anime_tv/features/streaming/application/debrid_resolver_factory.dart';
import 'package:anime_tv/features/streaming/application/debrid_token_service.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/release_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Backward-compatible name retained for tests and integrations that imported
/// the original Media3 helper. All player engines now call the shared,
/// provider-generic classifier in the streaming domain directly.
bool isTerminalDebridAlternativeFailure(Object error) =>
    isTerminalDebridFailoverFailure(error);

enum NativePlayerReturnNavigation { previousRoute, none }

/// Converts only terminal native-player return statuses into route actions.
///
/// Engine fallbacks, retries, errors, and completion remain owned by the main
/// playback state machine; in particular, this function never asks playback
/// to launch again.
NativePlayerReturnNavigation nativePlayerReturnNavigationForStatus(
  String status,
) => switch (status) {
  'stopped' ||
  'exit' ||
  'cancelled' => NativePlayerReturnNavigation.previousRoute,
  _ => NativePlayerReturnNavigation.none,
};

/// Runs terminal-player cleanup without letting optional bookkeeping prevent
/// the user from leaving playback. Each operation is isolated so one failed
/// database or platform write does not suppress the remaining best-effort
/// updates.
Future<void> runBestEffortNativePlayerExitBookkeeping(
  Iterable<Future<void> Function()> operations, {
  Duration totalTimeout = const Duration(seconds: 2),
}) async {
  final tasks = operations.map((operation) async {
    try {
      await operation().timeout(totalTimeout);
    } catch (_) {
      // Confirmed Exit must always retain its terminal navigation decision.
    }
  });
  await Future.wait(tasks);
}

/// Automatic routing protects known-incompatible streams, while a viewer's
/// explicit Player > Media3 choice must be honored instead of immediately
/// bouncing them back to MPV.
bool shouldRedirectMedia3ToMpv({
  required bool manuallySelected,
  required SeriesPlaybackPreferences preferences,
  required ReleaseCandidate release,
}) =>
    !manuallySelected &&
    (preferences.decoder == 'software' ||
        releaseRequiresSoftwareDecoder(release) ||
        preferences.subtitleDelayMs != 0 ||
        preferences.audioDelayMs != 0);

/// Orchestrates TetoTV's dedicated native Android player.
///
/// The actual video never enters a Flutter texture. Android Media3 owns a
/// SurfaceView in a separate full-screen activity; this Flutter screen only
/// supplies the debrid URL, restores/saves progress, and handles engine or
/// stream fallback after the native activity returns.
class NativeMedia3PlayerScreen extends ConsumerStatefulWidget {
  const NativeMedia3PlayerScreen({
    required this.source,
    required this.title,
    required this.debridService,
    required this.launch,
    required this.onUseMpv,
    required this.onUseVlc,
    required this.onStreamAdopted,
    this.initialPosition,
    this.subtitle,
    this.anilistMediaId,
    this.malMediaId,
    this.episode,
    this.coverImageUrl,
    this.manuallySelected = false,
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
  final Duration? initialPosition;
  final bool manuallySelected;
  final void Function(
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
  )
  onUseMpv;
  final void Function(
    Duration position,
    StreamReady stream,
    ReleaseCandidate release,
  )
  onUseVlc;
  final Future<void> Function(StreamReady stream, ReleaseCandidate release)
  onStreamAdopted;

  @override
  ConsumerState<NativeMedia3PlayerScreen> createState() =>
      _NativeMedia3PlayerScreenState();
}

class _NativeMedia3PlayerScreenState
    extends ConsumerState<NativeMedia3PlayerScreen> {
  static const _maxAutomaticStreamAttempts = 4;
  static const _maxFailoverCandidatesPerRequest = 12;

  late String _source;
  late ReleaseCandidate _release;
  late StreamReady _currentStream;
  List<PlaybackStreamOption> _directStreamOptions = const [];
  StreamSubscription<WebStreamSearchProgress>? _sourceDiscoverySubscription;
  SeriesPlaybackPreferences _preferences = const SeriesPlaybackPreferences();
  PlaybackAudioPreference _globalAudioPreference = PlaybackAudioPreference.dub;
  Duration _resumePosition = Duration.zero;
  DateTime? _resumeUpdatedAt;
  int _automaticStreamAttempts = 0;
  final Set<String> _failedDirectStreamUris = {};
  final Set<ReleaseCandidate> _attemptedReleaseAlternatives = {};
  bool _startFromBeginning = false;
  bool _syncHandled = false;
  final PlayerHandoffGate _nextEpisodeHandoff = PlayerHandoffGate();
  bool _streamFailoverInProgress = false;
  bool _running = false;
  bool _nativeReleaseFailed = false;
  int? _resolvedMalMediaId;
  String _status = 'Opening the native TV player…';
  String? _diagnostic;

  int get _mediaId =>
      widget.anilistMediaId ?? widget.launch.episode.anilistMediaId;
  int get _episodeNumber => widget.episode ?? widget.launch.episode.episode;
  int? get _malMediaId =>
      _resolvedMalMediaId ??
      widget.malMediaId ??
      widget.launch.episode.malMediaId;
  PlaybackAudioPreference get _effectiveAudioPreference =>
      _preferences.audioPreferenceSet
      ? playbackAudioPreferenceForLanguage(_preferences.audioLanguage) ??
            _globalAudioPreference
      : _globalAudioPreference;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _release = widget.launch.selectedRelease;
    _currentStream = widget.launch.stream;
    _directStreamOptions = mergePlaybackStreamOptions([
      PlaybackStreamOption(stream: _currentStream, release: _release),
      ...widget.launch.directAlternatives,
    ], const []);
    unawaited(_startWebSourceDiscovery());
    _resolvedMalMediaId = widget.malMediaId ?? widget.launch.episode.malMediaId;
    _startFromBeginning = widget.launch.episode.startFromBeginning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_running || !mounted) return;
    _running = true;
    try {
      final malMediaIdFuture = _resolveSkipMalMediaId();
      await _loadResumeAndPreferences();
      _resolvedMalMediaId = await malMediaIdFuture;
      if (!mounted) return;
      final appearance = ref.read(settingsPreferencesProvider);
      // Media3 intentionally owns the fast hardware-decoding path. Preserve
      // the user's compatibility choice and send known Hi10P or delay-tuned
      // streams straight to MPV, which can software-decode and apply A/V delay.
      if (shouldRedirectMedia3ToMpv(
        manuallySelected: widget.manuallySelected,
        preferences: _preferences,
        release: _release,
      )) {
        if (mounted) {
          widget.onUseMpv(_resumePosition, _currentStream, _release);
        }
        return;
      }
      while (mounted) {
        _globalAudioPreference = appearance.preferredAudio;
        final effectiveAudio = _effectiveAudioPreference;
        setState(() {
          _status = _automaticStreamAttempts == 0
              ? 'Opening the native TV player…'
              : 'Opening a more compatible stream…';
          _diagnostic = null;
        });
        final result = await AndroidTvBridge.instance.startNativePlayer(
          source: Uri.parse(_source),
          title: widget.title,
          checkpointKey: '$_mediaId:$_episodeNumber',
          releaseName: _release.releaseName,
          streamLabel:
              _currentStream.providerName ??
              '${widget.debridService.displayName} stream',
          resumePosition: _resumePosition,
          resumeUpdatedAt: _resumeUpdatedAt,
          startFromBeginning: _startFromBeginning,
          externalSubtitle:
              _currentStream.externalSubtitle?.toString() ?? widget.subtitle,
          mediaContentType: _currentStream.mediaContentType,
          subtitleContentType: _currentStream.subtitleContentType,
          externalSubtitleRejected: _currentStream.externalSubtitleRejected,
          headers: _currentStream.headers,
          trustedPlaybackProxy: WebPlaybackProxy.instance
              .isOwnedPlaybackProxyUri(_currentStream.uri),
          audioLanguage: _preferences.audioPreferenceSet
              ? _preferences.audioLanguage
              : effectiveAudio.audioLanguage,
          subtitleLanguage: _preferences.subtitleLanguage,
          subtitlesEnabled: _preferences.subtitlePreferenceSet
              ? _preferences.subtitleEnabled
              : subtitlesEnabledForAudioPreference(_release, effectiveAudio),
          subtitleSize: _preferences.subtitleSize == 34
              ? appearance.captionTextSize
              : _preferences.subtitleSize,
          subtitlePosition: _preferences.subtitlePosition,
          highContrastSubtitles: _preferences.highContrastSubtitles,
          subtitleTextColor: appearance.captionTextColor,
          subtitleBackgroundColor: appearance.captionBackgroundColor,
          seekBackSeconds: appearance.seekBackSeconds,
          seekForwardSeconds: appearance.seekForwardSeconds,
          autoSkipIntros: appearance.autoSkipIntros,
          autoSkipOutros: appearance.autoSkipOutros,
          videoFit: _preferences.videoFit,
          malMediaId: _malMediaId,
          episodeNumber: _episodeNumber,
          artworkUrl: widget.coverImageUrl,
          hasDirectSources: _currentStream.isWebStream,
          theme: ref
              .read(themeStudioControllerProvider)
              .palette
              .nativePlayerThemePayload,
        );
        if (!mounted) return;
        final returnNavigation = nativePlayerReturnNavigationForStatus(
          result.status,
        );
        if (returnNavigation == NativePlayerReturnNavigation.previousRoute) {
          // The native Activity is gone at this point, so do not leave its
          // launch message visible while checkpoints are copied into Flutter's
          // database.
          setState(() => _status = 'Closing video…');
        }
        _startFromBeginning = false;
        _resumePosition = result.position < Duration.zero
            ? Duration.zero
            : result.position;
        _resumeUpdatedAt = DateTime.now();
        if (returnNavigation == NativePlayerReturnNavigation.previousRoute) {
          await runBestEffortNativePlayerExitBookkeeping([
            () => _persistResult(result),
            () => _syncResultIfThresholdReached(result),
            () => _recordPlayerSuccess(result),
          ]);
        } else {
          // Retries, fallbacks, completion, and cancellation preserve their
          // existing strict bookkeeping/error behavior.
          await _persistResult(result);
          await _syncResultIfThresholdReached(result);
          await _recordPlayerSuccess(result);
        }
        if (!mounted) return;

        switch (returnNavigation) {
          case NativePlayerReturnNavigation.previousRoute:
            if (context.canPop()) {
              context.pop();
            } else {
              // A player opened from a shallow/deep-link stack still has a
              // deterministic series destination instead of falling through
              // to Home or leaving the closing screen mounted.
              GoRouter.of(context).go('/anime/$_mediaId');
            }
            return;
          case NativePlayerReturnNavigation.none:
            break;
        }

        switch (result.status) {
          case 'completed':
          case 'ended':
            await _syncProgress();
            if (!mounted) return;
            await _offerNextEpisode();
            return;
          case 'retry':
            continue;
          case 'next_stream':
            await _openDirectStreamPicker();
            continue;
          case 'use_vlc':
          case 'fallback_vlc':
            if (mounted) {
              widget.onUseVlc(_resumePosition, _currentStream, _release);
            }
            return;
          case 'use_mpv':
          case 'fallback_mpv':
            if (mounted) {
              widget.onUseMpv(_resumePosition, _currentStream, _release);
            }
            return;
          case 'error':
          case 'no_first_frame':
            unawaited(
              recordAnonymousHandledError(
                area: AnonymousErrorArea.playback,
                error: StateError(
                  result.error ?? 'Native player status: ${result.status}',
                ),
                stack: StackTrace.current,
              ),
            );
            await _recordFailure(result);
            if (!mounted) return;
            if (await _switchToCompatibleStream(
              result.error ?? 'Media3 could not render this stream',
            )) {
              continue;
            }
            // MPV keeps libass and unusual-codec support as the second engine.
            // VLC remains available manually from MPV or on a future retry.
            if (mounted) {
              widget.onUseMpv(_resumePosition, _currentStream, _release);
            }
            return;
          case 'unsupported':
            if (mounted) {
              widget.onUseMpv(_resumePosition, _currentStream, _release);
            }
            return;
          case 'release_failed':
            setState(() {
              _nativeReleaseFailed = true;
              _status = 'The native player could not close safely';
              _diagnostic =
                  result.error ??
                  'Return to the episode and reopen the stream before trying another player.';
            });
            return;
          default:
            if (context.canPop()) context.pop();
            return;
        }
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      unawaited(
        recordAnonymousHandledError(
          area: AnonymousErrorArea.playback,
          error: error,
          stack: stackTrace,
        ),
      );
      setState(() {
        _status = 'The native player could not be opened';
        _diagnostic = error.toString();
      });
    } finally {
      _running = false;
    }
  }

  Future<int?> _resolveSkipMalMediaId() async {
    final known = _malMediaId;
    if (known != null && known > 0) return known;
    if (_mediaId <= 0) return null;
    try {
      return (await ref.read(catalogClientProvider).details(_mediaId)).idMal;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openDirectStreamPicker() async {
    if (!mounted) return;
    final selected = await showPlayerStreamSourcePicker(
      context: context,
      initialOptions: _directStreamOptions,
      selectedUri: _currentStream.uri,
      onOptionsChanged: (options) {
        if (mounted) setState(() => _directStreamOptions = options);
      },
    );
    if (!mounted ||
        selected == null ||
        selected.stream.uri == _currentStream.uri) {
      return;
    }
    final option = await _preflightDirectStream(selected);
    if (!mounted) {
      await option?.stream.playbackLease?.close();
      return;
    }
    if (option == null) return;
    final previousStream = _currentStream;
    _failedDirectStreamUris.clear();
    _currentStream = option.stream;
    _release = option.release;
    _source = option.stream.uri.toString();
    _directStreamOptions = mergePlaybackStreamOptions(
      [option],
      _directStreamOptions.where(
        (candidate) =>
            candidate.stream.uri != selected.stream.uri &&
            candidate.stream.uri != previousStream.uri,
      ),
    );
    await widget.onStreamAdopted(option.stream, option.release);
  }

  Future<PlaybackStreamOption?> _preflightDirectStream(
    PlaybackStreamOption option, {
    bool silent = false,
  }) async {
    if (!mounted) return null;
    if (!option.stream.isWebStream) return option;
    if (!silent) {
      setState(() {
        _status = 'Checking ${playbackStreamOptionLabel(option)}...';
        _diagnostic = null;
      });
    }
    try {
      final validated = await const WebStreamValidator().validate(
        option.stream.uri,
        option.stream.headers,
        subtitleUri: option.stream.externalSubtitle,
      );
      if (!mounted) {
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
      if (!mounted) return null;
      _failedDirectStreamUris.add(option.stream.uri.toString());
      if (!silent) {
        setState(() {
          _status = 'That source is unavailable';
          _diagnostic = error.toString().replaceFirst('FormatException: ', '');
        });
      }
      return null;
    }
  }

  Future<void> _startWebSourceDiscovery() async {
    if (!mounted || _sourceDiscoverySubscription != null) return;
    final webStreamsEnabled = ref
        .read(settingsPreferencesProvider)
        .webStreamsEnabled;
    final aggregator = ref.read(webStreamAggregatorProvider);
    final episode = widget.launch.episode;
    if (!webStreamsEnabled) return;
    _sourceDiscoverySubscription = aggregator
        .watchSearchIncrementally(episode)
        .listen((progress) {
          if (!mounted) return;
          _directStreamOptions = mergePlaybackStreamOptions(
            _directStreamOptions,
            progress.aggregation.streams.map(playbackOptionForWebStream),
          );
        }, onError: (_) {});
  }

  Future<void> _waitForInFlightDirectDiscovery() async {
    if (_remainingDirectFailoverCandidates().isNotEmpty) return;
    await _startWebSourceDiscovery();
    if (!mounted || !_streamFailoverInProgress) return;
    await waitForPlayerFailoverCandidates(
      snapshot: _remainingDirectFailoverCandidates,
      isActive: () => mounted && _streamFailoverInProgress,
    );
  }

  Future<void> _retryAfterFailure() async {
    if (mounted) setState(() => _diagnostic = null);
    await _run();
  }

  Future<void> _nextStreamAfterFailure() async {
    final switched = await _switchToCompatibleStream(
      _diagnostic ?? 'Selected after playback failure',
    );
    if (switched) await _run();
  }

  Future<void> _loadResumeAndPreferences() async {
    if (!mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    _preferences = await database.seriesPreferences(_mediaId);
    if (widget.initialPosition case final handoffPosition?) {
      // A live engine handoff is more recent than the launch-time "start from
      // beginning" choice. Keeping that flag would make native Media3 discard
      // the position MPV/VLC just handed us and restart at zero.
      _startFromBeginning = false;
      _resumePosition = handoffPosition < Duration.zero
          ? Duration.zero
          : handoffPosition;
      _resumeUpdatedAt = DateTime.now();
      return;
    }
    if (!mounted || _startFromBeginning) return;
    final checkpoint = await database.checkpoint(_mediaId, _episodeNumber);
    if (!mounted) return;
    if (checkpoint != null) {
      // Even a completed or intentionally reset checkpoint is authoritative:
      // its timestamp acts as a zero-position tombstone so an older native
      // crash checkpoint cannot resurrect already-cleared progress.
      _resumeUpdatedAt = checkpoint.updatedAt;
      _resumePosition =
          !checkpoint.completed &&
              checkpoint.position > const Duration(seconds: 15) &&
              checkpoint.progress < .95
          ? checkpoint.position
          : Duration.zero;
    }
  }

  Future<void> _persistResult(NativePlaybackResult result) async {
    if (!mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    final settingsController = ref.read(settingsPreferencesProvider.notifier);
    final normalizedSize = result.subtitleSize?.clamp(18, 60).toDouble();
    final audioLanguage = canonicalPlayerTrackLanguage(
      language: result.audioLanguage,
    );
    final subtitleLanguage = result.subtitleLanguage == null
        ? null
        : canonicalPlayerLanguage(result.subtitleLanguage);
    var nextPreferences = _preferences;
    nextPreferences = nextPreferences.copyWith(
      preferredReleaseProvider: _release.provider,
      clearPreferredReleaseProvider: _release.provider == null,
      preferredReleaseGroup: releaseGroupKey(_release.releaseName),
      clearPreferredReleaseGroup: releaseGroupKey(_release.releaseName) == null,
    );
    if (normalizedSize != null) {
      nextPreferences = nextPreferences.copyWith(subtitleSize: normalizedSize);
    }
    if (audioLanguage.isNotEmpty || result.audioPreferenceSet) {
      nextPreferences = nextPreferences.copyWith(
        audioLanguage: persistedPlayerAudioLanguage(
          storedLanguage: nextPreferences.audioLanguage,
          audioPreferenceSet: nextPreferences.audioPreferenceSet,
          observedLanguage: audioLanguage,
          manualSelection: result.audioPreferenceSet,
        ),
        audioPreferenceSet: result.audioPreferenceSet
            ? true
            : nextPreferences.audioPreferenceSet,
      );
    }
    if (subtitleLanguage != null && subtitleLanguage.isNotEmpty) {
      nextPreferences = nextPreferences.copyWith(
        subtitleLanguage: subtitleLanguage,
      );
    }
    if (result.subtitlesEnabled case final enabled?) {
      nextPreferences = nextPreferences.copyWith(
        subtitleEnabled: enabled,
        subtitlePreferenceSet: true,
      );
    }
    if (result.highContrastSubtitles case final enabled?) {
      nextPreferences = nextPreferences.copyWith(
        highContrastSubtitles: enabled,
      );
    }
    if (nextPreferences.toJson().toString() !=
        _preferences.toJson().toString()) {
      _preferences = nextPreferences;
      await database.saveSeriesPreferences(_mediaId, _preferences);
    }
    if (result.subtitleBackgroundColor case final backgroundColor?) {
      await settingsController.setCaptionBackgroundColor(backgroundColor);
    }
    if (result.duration <= Duration.zero) {
      return;
    }
    final duration = result.duration;
    final position = result.position < Duration.zero
        ? Duration.zero
        : result.position > duration
        ? duration
        : result.position;
    final completed =
        result.completed ||
        position.inMilliseconds / duration.inMilliseconds >= .93;
    await database.saveCheckpoint(
      PlaybackCheckpoint(
        anilistMediaId: _mediaId,
        malMediaId: _malMediaId,
        episode: _episodeNumber,
        title: widget.launch.episode.title,
        coverImageUrl: widget.coverImageUrl,
        position: completed ? duration : position,
        duration: duration,
        updatedAt: DateTime.now(),
        completed: completed,
      ),
    );
    if (completed) {
      await AndroidTvBridge.instance.removeWatchNext(_mediaId);
    }
    if (!mounted) return;
    ref.invalidate(recentPlaybackProvider);
    ref.invalidate(latestPlaybackProvider(_mediaId));
    if (!completed && position > const Duration(seconds: 30)) {
      await AndroidTvBridge.instance.publishWatchNext(
        mediaId: _mediaId,
        episode: _episodeNumber,
        title: widget.launch.episode.title,
        posterUrl: widget.coverImageUrl,
        position: position,
        duration: duration,
      );
    }
  }

  Future<void> _recordPlayerSuccess(NativePlaybackResult result) async {
    if (!result.firstFrameRendered) return;
    if (!mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    final profile = await AndroidTvBridge.instance.getDeviceProfile();
    if (!mounted) return;
    await database.recordPlayerSuccess(profile.key, 'media3');
  }

  Future<void> _syncResultIfThresholdReached(
    NativePlaybackResult result,
  ) async {
    if (_syncHandled || !mounted) return;
    if (widget.anilistMediaId == null &&
        widget.launch.episode.anilistMediaId <= 0 &&
        _malMediaId == null) {
      return;
    }
    final ended = result.status == 'completed' || result.status == 'ended';
    final threshold = ref
        .read(settingsPreferencesProvider)
        .trackerUpdateThreshold;
    if (!trackerUpdateThresholdReached(
      position: result.position,
      duration: result.duration,
      threshold: threshold,
      playbackEnded: ended,
    )) {
      return;
    }
    await _syncProgress();
  }

  Future<void> _recordFailure(NativePlaybackResult result) async {
    try {
      if (!mounted) return;
      final database = ref.read(tetoTvDatabaseProvider);
      final infoHash = _release.infoHash;
      final profile = await AndroidTvBridge.instance.getDeviceProfile();
      if (!mounted) return;
      final details = <String>[
        result.error ?? 'Native playback failed',
        if (result.decoder?.isNotEmpty == true) 'decoder=${result.decoder}',
        'firstFrame=${result.firstFrameRendered}',
        'droppedFrames=${result.droppedFrames}',
        for (final entry in result.diagnostics.entries)
          '${entry.key}=${entry.value}',
      ].join('; ');
      await database.recordStreamFailure(
        deviceKey: profile.key,
        infoHash: infoHash,
        reason: details,
      );
      await database.recordPlayerFailure(profile.key, 'media3');
      await database.recordDiagnosticEvent(
        category: 'player-media3',
        message: details,
      );
    } catch (_) {
      // Failure history improves future ranking but must never block fallback.
    }
  }

  Future<bool> _switchToCompatibleStream(String reason) async {
    if (!mounted ||
        _streamFailoverInProgress ||
        _automaticStreamAttempts >= _maxAutomaticStreamAttempts) {
      return false;
    }
    _streamFailoverInProgress = true;
    final tokenService = ref.read(debridTokenServiceProvider);
    Object? terminalFailure;
    try {
      setState(() {
        _status = 'Recovering playback…';
        _diagnostic = null;
      });

      Future<bool> tryDirectCandidates() async {
        if (_currentStream.isWebStream) {
          _failedDirectStreamUris.add(_currentStream.uri.toString());
        }
        await _waitForInFlightDirectDiscovery();
        if (!mounted || !_streamFailoverInProgress) return false;
        final opened = await openFirstViablePlayerCandidate(
          candidates: _remainingDirectFailoverCandidates(),
          resumePosition: _resumePosition,
          maxCandidates: _maxFailoverCandidatesPerRequest,
          isActive: () => mounted && _streamFailoverInProgress,
          attempt: (candidate, resumePosition) async {
            final requestedUri = candidate.stream.uri;
            _failedDirectStreamUris.add(requestedUri.toString());
            final option = await _preflightDirectStream(
              candidate,
              silent: true,
            );
            if (!mounted || !_streamFailoverInProgress) {
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
            _source = option.stream.uri.toString();
            _release = option.release;
            _currentStream = option.stream;
            // Media3's native Activity receives this unchanged resume value on
            // the next loop iteration.
            _resumePosition = resumePosition;
            _automaticStreamAttempts++;
            await widget.onStreamAdopted(option.stream, option.release);
            return true;
          },
        );
        return opened != null;
      }

      Future<bool> tryDebridCandidates() async {
        for (final candidate in _remainingReleaseFailoverCandidates().take(
          _maxFailoverCandidatesPerRequest,
        )) {
          _attemptedReleaseAlternatives.add(candidate);
          // Do not burn CPU on H.264 Hi10P during automatic Fire TV recovery.
          // MPV software mode remains available when explicitly selected.
          if (releaseRequiresSoftwareDecoder(candidate)) continue;
          StreamReady? ready;
          try {
            ready = await _resolveRelease(
              candidate,
              tokenService: tokenService,
            );
            if (!mounted || !_streamFailoverInProgress) return false;
          } catch (error) {
            if (!mounted || !_streamFailoverInProgress) return false;
            if (isTerminalDebridFailoverFailure(error)) {
              terminalFailure = error;
              break;
            }
            // This release failed independently. Keep walking the ranked list.
            continue;
          }
          if (ready == null) continue;
          _source = ready.uri.toString();
          _release = candidate;
          _currentStream = ready;
          _automaticStreamAttempts++;
          await widget.onStreamAdopted(ready, candidate);
          return true;
        }
        return false;
      }

      final classOrder = playerFailoverClassOrder(
        currentIsWeb: _currentStream.isWebStream,
      );
      final directFirst = classOrder.first == PlayerFailoverClass.directWeb;
      if (directFirst && await tryDirectCandidates()) return true;
      if (!mounted || !_streamFailoverInProgress) return false;
      if (await tryDebridCandidates()) return true;
      if (!mounted || !_streamFailoverInProgress) return false;
      if (!directFirst && await tryDirectCandidates()) return true;
      if (!mounted || !_streamFailoverInProgress) return false;

      if (mounted) {
        setState(() {
          _status = 'No compatible streams remain';
          _diagnostic = terminalFailure?.toString() ?? reason;
        });
      }
      return false;
    } finally {
      _streamFailoverInProgress = false;
    }
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

  int _releaseFailoverAffinity(ReleaseCandidate candidate) {
    final currentProvider = _release.provider?.trim().toLowerCase();
    final candidateProvider = candidate.provider?.trim().toLowerCase();
    final sameProvider =
        currentProvider != null &&
        currentProvider.isNotEmpty &&
        candidateProvider == currentProvider;
    final sameSource =
        _release.sourceId.trim().toLowerCase() ==
        candidate.sourceId.trim().toLowerCase();
    final currentAuthor = releaseGroupKey(_release.releaseName);
    final sameAuthor =
        currentAuthor != null &&
        releaseGroupKey(candidate.releaseName) == currentAuthor;
    if ((sameProvider || sameSource) && sameAuthor) return 0;
    if (sameProvider || sameSource) return 1;
    if (sameAuthor) return 2;
    return 3;
  }

  Future<StreamReady?> _resolveRelease(
    ReleaseCandidate release, {
    DebridTokenService? tokenService,
  }) async {
    if (!mounted) return null;
    final DebridTokenService capturedTokenService =
        tokenService ?? ref.read(debridTokenServiceProvider);
    final debridService = widget.debridService;
    final episode = widget.launch.episode;
    String? token;
    try {
      token = await capturedTokenService.accessToken(debridService);
    } catch (_) {
      throw DebridProviderAccessException(
        debridService,
        detail:
            'Your ${debridService.displayName} connection could not be '
            'refreshed. Reconnect it in Accounts, then try again.',
      );
    }
    if (!mounted) return null;
    if (token == null || token.isEmpty) {
      throw DebridProviderAccessException(debridService);
    }
    final source = SingleReleaseSource(release);
    final resolver = createDebridStreamResolver(
      service: debridService,
      token: token,
      source: source,
    );
    await for (final resolution in resolver.resolve(episode)) {
      if (!mounted) return null;
      if (resolution is StreamReady) return resolution;
    }
    return null;
  }

  Future<void> _syncProgress() async {
    if (_syncHandled || !mounted) return;
    _syncHandled = true;
    final syncService = ref.read(trackingSyncServiceProvider);
    final completedEpisodes = _episodeNumber;
    final anilistMediaId = _mediaId;
    final malMediaId = _malMediaId;
    try {
      await syncService.syncEpisode(
        completedEpisodes: completedEpisodes,
        anilistMediaId: anilistMediaId,
        malMediaId: malMediaId,
      );
      if (mounted) {
        ref.invalidate(
          linkedTrackingProgressProvider((
            anilistMediaId: anilistMediaId,
            malMediaId: malMediaId,
          )),
        );
        ref.invalidate(trackingHomeProvider);
      }
    } catch (_) {
      // The tracking service queues/retries independently of video playback.
    }
  }

  Future<void> _offerNextEpisode() async {
    if (!mounted) return;
    if (!_preferences.autoplayNextEpisode) {
      if (context.canPop()) {
        context.pop();
      } else {
        GoRouter.of(context).go('/anime/$_mediaId');
      }
      return;
    }
    await _playNextEpisode();
  }

  Future<void> _playNextEpisode() async {
    if (!mounted || !_nextEpisodeHandoff.tryEnter()) return;
    var routeStarted = false;
    try {
      final catalog = ref.read(catalogClientProvider);
      final fillerRepository = ref.read(fillerEpisodeRepositoryProvider);
      final unavailableNoticeController = ref.read(
        fillerUnavailableNotifiedSeriesProvider.notifier,
      );
      final skipFillerEpisodes = _preferences.skipFillerEpisodes;
      final details = await catalog.details(_mediaId);
      if (!mounted) return;
      final requestedEpisode = _episodeNumber + 1;
      if (details.episodes != null && requestedEpisode > details.episodes!) {
        if (mounted && context.canPop()) context.pop();
        return;
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
            _mediaId,
          )) {
        showFillerDataUnavailableNotice(context, episode: requestedEpisode);
      }
      await showFillerSkipNotification(context, decision);
      if (!mounted) return;
      if (decision.episode == null) {
        setState(() {
          _status = 'No non-filler episodes remain';
          _diagnostic = 'Turn off Skip filler on the series page to play them.';
        });
        return;
      }
      final nextEpisode = decision.episode!;
      if (!mounted) return;
      final preferredProvider = _release.provider?.trim();
      final preferredSourceId = _release.sourceId.trim();
      final preferredAuthor = releaseGroupKey(_release.releaseName);
      final preferredWebProviderId = _currentStream.providerId?.trim();
      context.pushReplacement(
        Uri(
          path: '/resolve',
          queryParameters: {
            'anilistId': _mediaId.toString(),
            'title': details.title,
            'synonyms': details.synonyms.join('|'),
            'episode': nextEpisode.toString(),
            'autoplay': '1',
            if (preferredProvider != null && preferredProvider.isNotEmpty)
              'preferredProvider': preferredProvider,
            if (preferredSourceId.isNotEmpty)
              'preferredSourceId': preferredSourceId,
            if (preferredAuthor != null && preferredAuthor.isNotEmpty)
              'preferredAuthor': preferredAuthor,
            if (preferredWebProviderId != null &&
                preferredWebProviderId.isNotEmpty)
              'preferredWebProviderId': preferredWebProviderId,
            if (details.seasonYear != null)
              'year': details.seasonYear.toString(),
            if (details.coverImageUrl != null) 'cover': details.coverImageUrl!,
            if (_malMediaId != null) 'malId': _malMediaId.toString(),
          },
        ).toString(),
      );
      routeStarted = true;
    } catch (_) {
      if (mounted && context.canPop()) context.pop();
    } finally {
      if (!routeStarted) _nextEpisodeHandoff.leave();
    }
  }

  @override
  void dispose() {
    unawaited(_sourceDiscoverySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_diagnostic == null)
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      color: Color(0xFFE63B55),
                      strokeWidth: 4,
                    ),
                  )
                else
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFFF929B),
                    size: 46,
                  ),
                const SizedBox(height: 22),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_diagnostic != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _diagnostic!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF9B9BA5)),
                  ),
                ],
                const SizedBox(height: 24),
                if (_diagnostic != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _nativeReleaseFailed
                        ? [
                            FilledButton.icon(
                              autofocus: true,
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Back to episode'),
                            ),
                          ]
                        : [
                            FilledButton.icon(
                              autofocus: true,
                              onPressed: _retryAfterFailure,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry stream'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _nextStreamAfterFailure,
                              icon: const Icon(Icons.skip_next_rounded),
                              label: const Text('Try another stream'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                if (context.canPop()) context.pop();
                              },
                              icon: const Icon(Icons.list_rounded),
                              label: const Text('Choose stream'),
                            ),
                          ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (!_nativeReleaseFailed) ...[
                  OutlinedButton(
                    onPressed: () => widget.onUseMpv(
                      _resumePosition,
                      _currentStream,
                      _release,
                    ),
                    child: const Text('Use MPV compatibility player'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => widget.onUseVlc(
                      _resumePosition,
                      _currentStream,
                      _release,
                    ),
                    child: const Text('Use VLC software player'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
