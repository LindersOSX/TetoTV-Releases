import 'dart:async';
import 'dart:io';

import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/player/presentation/player_failover_coordinator.dart';
import 'package:anime_tv/features/streaming/domain/release_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const players = {
    'MPV': 'lib/features/player/presentation/tv_player_screen.dart',
    'VLC': 'lib/features/player/presentation/vlc_tv_player_screen.dart',
    'Media3':
        'lib/features/player/presentation/native_media3_player_screen.dart',
  };

  test('completion has no countdown or confirmation in any player', () {
    for (final entry in players.entries) {
      final source = _read(entry.value);
      final completion = _method(source, 'Future<void> _offerNextEpisode()');

      expect(
        completion,
        contains('autoplayNextEpisode'),
        reason: '${entry.key} must honor the per-series autoplay preference',
      );
      expect(completion, contains('await _playNextEpisode()'));
      expect(completion, isNot(contains('showDialog')));
      expect(source, isNot(contains('NextEpisodeDialog')));
      expect(source, isNot(contains('Episode complete')));
      expect(source, isNot(contains('Playing the next episode in')));
    }
  });

  test('MPV and VLC persist completion before gated seamless handoff', () {
    for (final path in [players['MPV']!, players['VLC']!]) {
      final completion = _method(
        _read(path),
        'Future<void> _offerNextEpisode()',
      );
      _expectInOrder(completion, const [
        'await _persistPlayback(',
        'if (!mounted || _engineHandoffInProgress) return',
        'if (!_',
        '.autoplayNextEpisode) return',
        'await _playNextEpisode()',
      ]);
    }
  });

  test('Media3 persists the native completion before autoplay routing', () {
    final source = _read(players['Media3']!);
    final run = _method(source, 'Future<void> _run()');
    _expectInOrder(run, const [
      'await _persistResult(result)',
      "case 'completed':",
      'await _offerNextEpisode()',
    ]);

    final completion = _method(source, 'Future<void> _offerNextEpisode()');
    _expectInOrder(completion, const [
      'if (!_preferences.autoplayNextEpisode)',
      'if (context.canPop())',
      'context.pop()',
      "GoRouter.of(context).go('/anime/\$_mediaId')",
      'return',
      'await _playNextEpisode()',
    ]);
  });

  test('automatic and manual next requests share one deduplicated handoff', () {
    for (final entry in players.entries) {
      final source = _read(entry.value);
      final next = _method(source, 'Future<void> _playNextEpisode()');
      _expectInOrder(next, const [
        '_nextEpisodeHandoff.tryEnter()',
        'final catalog = ref.read(catalogClientProvider)',
      ]);
      expect(next, contains('_nextEpisodeHandoff.leave()'));
    }

    for (final path in [players['MPV']!, players['VLC']!]) {
      final mediaAction = _method(_read(path), 'void _handleMediaAction(');
      expect(mediaAction, contains("case 'next':"));
      expect(mediaAction, contains('unawaited(_playNextEpisode())'));
      expect(mediaAction, isNot(contains('_offerNextEpisode')));
    }
  });

  test(
    'single-flight gate admits only one racing next-episode route',
    () async {
      final gate = PlayerHandoffGate();
      final release = Completer<void>();
      var routes = 0;

      Future<void> requestRoute() async {
        if (!gate.tryEnter()) return;
        try {
          await release.future;
          routes++;
        } finally {
          gate.leave();
        }
      }

      final automatic = requestRoute();
      final manual = requestRoute();
      release.complete();
      await Future.wait([automatic, manual]);
      expect(routes, 1);
    },
  );

  test('pending failover cancellation yields no accepted mutation', () async {
    final pending = Completer<void>();
    var active = true;
    var acceptedMutations = 0;
    final operation = openFirstViablePlayerCandidate<String>(
      candidates: const ['candidate'],
      resumePosition: const Duration(minutes: 12),
      isActive: () => active,
      attempt: (_, _) async {
        await pending.future;
        return true;
      },
    );

    active = false;
    pending.complete();
    final selected = await operation;
    if (selected != null) acceptedMutations++;
    expect(selected, isNull);
    expect(acceptedMutations, 0);
  });

  test('disposal during manifest load never samples prewarm state', () async {
    final pendingLoad = Completer<void>();
    var active = true;
    var snapshotReads = 0;
    final operation = loadPlayerPrewarmSnapshot<String>(
      load: () => pendingLoad.future,
      snapshot: () {
        snapshotReads++;
        return const ['https://source.example/manifest.json'];
      },
      isActive: () => active,
    );

    active = false;
    pendingLoad.complete();
    expect(await operation, isNull);
    expect(snapshotReads, 0);
  });

  test(
    'candidate open failure advances to the next at the exact timestamp',
    () async {
      const resume = Duration(minutes: 17, seconds: 23);
      final attempted = <String>[];
      final positions = <Duration>[];
      final selected = await openFirstViablePlayerCandidate<String>(
        candidates: const ['broken', 'working'],
        resumePosition: resume,
        isActive: () => true,
        attempt: (candidate, position) async {
          attempted.add(candidate);
          positions.add(position);
          if (candidate == 'broken') throw StateError('decoder open failed');
          return true;
        },
      );

      expect(selected, 'working');
      expect(attempted, const ['broken', 'working']);
      expect(positions, const [resume, resume]);
    },
  );

  test('candidate coordinator enforces its explicit bound', () async {
    var attempts = 0;
    final selected = await openFirstViablePlayerCandidate<int>(
      candidates: const [1, 2, 3, 4],
      resumePosition: Duration.zero,
      maxCandidates: 2,
      isActive: () => true,
      attempt: (_, _) async {
        attempts++;
        return false;
      },
    );
    expect(selected, isNull);
    expect(attempts, 2);
  });

  test('failover class policy preserves current class before crossing', () {
    expect(playerFailoverClassOrder(currentIsWeb: true), const [
      PlayerFailoverClass.directWeb,
      PlayerFailoverClass.debrid,
    ]);
    expect(playerFailoverClassOrder(currentIsWeb: false), const [
      PlayerFailoverClass.debrid,
      PlayerFailoverClass.directWeb,
    ]);
  });

  test(
    'authoritative Dub outranks same-provider 4K Sub in both failover classes',
    () async {
      const sub4k = ReleaseCandidate(
        infoHash: 'sub-4k',
        magnetUri: 'magnet:?xt=sub-4k',
        releaseName: '[Preferred] Show 01 2160p Sub',
        seeders: 100,
        sourceId: 'same-source',
        quality: '2160p',
        provider: 'same-provider',
      );
      const dub1080 = ReleaseCandidate(
        infoHash: 'dub-1080',
        magnetUri: 'magnet:?xt=dub-1080',
        releaseName: '[Other] Show 01 1080p Dub',
        seeders: 10,
        sourceId: 'other-source',
        quality: '1080p',
        provider: 'other-provider',
        isDubbed: true,
      );

      final rankedReleases = rankAutomaticPlayerFailoverCandidates(
        // Resolver/quality order deliberately puts the 4K Sub first.
        candidates: const [sub4k, dub1080],
        audioRank: (candidate) =>
            releaseAudioPreferenceRank(candidate, PlaybackAudioPreference.dub),
        affinityRank: (candidate) =>
            candidate.provider == 'same-provider' ? 0 : 1,
      );
      final attemptedReleases = <String>[];
      final openedRelease = await openFirstViablePlayerCandidate(
        candidates: rankedReleases,
        resumePosition: const Duration(minutes: 9, seconds: 41),
        isActive: () => true,
        attempt: (candidate, _) async {
          attemptedReleases.add(candidate.infoHash);
          return true;
        },
      );

      final subDirect = PlaybackStreamOption(
        stream: StreamReady(
          uri: Uri.parse('https://same.example/sub-4k.m3u8'),
          displayName: '4K Sub',
          providerId: 'same-provider',
        ),
        release: sub4k,
      );
      final dubDirect = PlaybackStreamOption(
        stream: StreamReady(
          uri: Uri.parse('https://other.example/dub-1080.m3u8'),
          displayName: '1080p Dub',
          providerId: 'other-provider',
        ),
        release: dub1080,
      );
      final rankedDirect = rankAutomaticPlayerFailoverCandidates(
        // The merged picker order likewise starts with the 4K stream.
        candidates: [subDirect, dubDirect],
        audioRank: (option) => releaseAudioPreferenceRank(
          option.release,
          PlaybackAudioPreference.dub,
        ),
        affinityRank: (option) =>
            option.stream.providerId == 'same-provider' ? 0 : 1,
      );
      final attemptedDirect = <String>[];
      final openedDirect = await openFirstViablePlayerCandidate(
        candidates: rankedDirect,
        resumePosition: const Duration(minutes: 9, seconds: 41),
        isActive: () => true,
        attempt: (candidate, _) async {
          attemptedDirect.add(candidate.release.infoHash);
          return true;
        },
      );

      expect(openedRelease, same(dub1080));
      expect(attemptedReleases, const ['dub-1080']);
      expect(openedDirect, same(dubDirect));
      expect(attemptedDirect, const ['dub-1080']);
    },
  );

  test(
    'debrid failure consumes a delayed secure web result at the same timestamp',
    () async {
      const resume = Duration(minutes: 8, seconds: 41);
      final events = <String>[];
      final webCandidates = <String>[];
      final openedPositions = <Duration>[];
      var preflighted = false;
      String? selected;

      for (final streamClass in playerFailoverClassOrder(currentIsWeb: false)) {
        switch (streamClass) {
          case PlayerFailoverClass.debrid:
            events.add('debrid');
            selected = await openFirstViablePlayerCandidate<String>(
              candidates: const ['failed-debrid'],
              resumePosition: resume,
              isActive: () => true,
              attempt: (_, _) async => throw StateError('engine failed'),
            );
          case PlayerFailoverClass.directWeb:
            events.add('web');
            final discovered = await waitForPlayerFailoverCandidates<String>(
              snapshot: () => webCandidates,
              isActive: () => true,
              delay: (_) async {
                webCandidates.add('delayed-web');
              },
            );
            selected = await openFirstViablePlayerCandidate<String>(
              candidates: discovered,
              resumePosition: resume,
              isActive: () => true,
              attempt: (_, position) async {
                preflighted = true;
                openedPositions.add(position);
                return true;
              },
            );
        }
        if (selected != null) break;
      }

      expect(events, const ['debrid', 'web']);
      expect(selected, 'delayed-web');
      expect(preflighted, isTrue);
      expect(openedPositions, const [resume]);
    },
  );

  test(
    'disabled autoplay returns before advancing while manual Next bypasses it',
    () {
      for (final entry in players.entries) {
        final source = _read(entry.value);
        final completion = _method(source, 'Future<void> _offerNextEpisode()');
        final gate = completion.indexOf('autoplayNextEpisode');
        final disabledReturn = completion.indexOf('return', gate);
        final automaticAdvance = completion.indexOf(
          'await _playNextEpisode()',
          gate,
        );
        expect(gate, greaterThanOrEqualTo(0), reason: entry.key);
        expect(disabledReturn, greaterThan(gate), reason: entry.key);
        expect(
          automaticAdvance,
          greaterThan(disabledReturn),
          reason: entry.key,
        );

        final directNext = _method(source, 'Future<void> _playNextEpisode()');
        expect(
          directNext,
          isNot(contains('autoplayNextEpisode')),
          reason:
              '${entry.key} manual Next must call the immediate handoff path',
        );
      }
    },
  );

  test('all next-episode routes carry current source-affinity hints', () {
    final expectedSources = {
      'MPV': (release: '_currentRelease', stream: '_currentStream'),
      'VLC': (release: '_release', stream: '_currentStream'),
      'Media3': (release: '_release', stream: '_currentStream'),
    };

    for (final entry in players.entries) {
      final next = _method(
        _read(entry.value),
        'Future<void> _playNextEpisode()',
      );
      final expected = expectedSources[entry.key]!;
      expect(
        next,
        contains(
          'final preferredProvider = ${expected.release}.provider?.trim()',
        ),
      );
      expect(
        next,
        contains(
          'final preferredSourceId = ${expected.release}.sourceId.trim()',
        ),
      );
      expect(
        next,
        contains('releaseGroupKey(${expected.release}.releaseName)'),
      );
      expect(
        next,
        contains(
          'final preferredWebProviderId = ${expected.stream}.providerId?.trim()',
        ),
      );
      for (final name in const [
        'preferredProvider',
        'preferredSourceId',
        'preferredAuthor',
        'preferredWebProviderId',
      ]) {
        expect(next, contains("'$name': $name"));
      }
      expect(next, contains('preferredProvider.isNotEmpty'));
      expect(next, contains('preferredSourceId.isNotEmpty'));
      expect(next, contains('preferredAuthor.isNotEmpty'));
      expect(next, contains('preferredWebProviderId.isNotEmpty'));
    }
  });

  test('all engines preserve the failure timestamp during recovery', () {
    final mpv = _method(_read(players['MPV']!), 'Future<void> _tryNextStream(');
    _expectInOrder(mpv, const [
      'final position = _player.state.position',
      'await AndroidTvBridge.instance.getDeviceProfile()',
      'await _switchToNextDirectStream(position)',
      'await _openMedia(resume: position, propagateFailure: true)',
    ]);

    final vlc = _method(_read(players['VLC']!), 'Future<void> _tryNextStream(');
    _expectInOrder(vlc, const [
      'final position = _effectiveHandoffPosition()',
      'await _waitForInFlightDirectDiscovery()',
      'await _switchToNextDirectStream(position)',
      'resumePosition: position',
    ]);
    final restart = _method(
      _read(players['VLC']!),
      'Future<void> _runRestart(',
    );
    _expectInOrder(restart, const [
      'final position = resumePosition ??',
      '_pendingResume = position > Duration.zero ? position : null',
    ]);

    final media3 = _method(_read(players['Media3']!), 'Future<void> _run()');
    _expectInOrder(media3, const [
      'resumePosition: _resumePosition',
      '_resumePosition = result.position < Duration.zero',
      'result.position',
      'await _switchToCompatibleStream(',
    ]);
  });

  test(
    'MPV and VLC direct candidate open failures advance in one operation',
    () {
      final expectations = {
        'MPV': (
          open: 'await _openMedia(',
          propagation: 'if (propagateFailure) rethrow',
        ),
        'VLC': (
          open: 'propagateFailure: true',
          propagation: 'if (propagateFailure) rethrow',
        ),
      };
      for (final entry in expectations.entries) {
        final source = _read(players[entry.key]!);
        final direct = _method(
          source,
          'Future<bool> _switchToNextDirectStream(',
        );
        _expectInOrder(direct, [
          'openFirstViablePlayerCandidate(',
          'attempt: (candidate, resumePosition) async',
          'try {',
          entry.value.open,
          'catch (_)',
          'rethrow',
        ]);
        expect(source, contains(entry.value.propagation));
        expect(direct, isNot(contains('Recovered with')));
      }
    },
  );

  test('failover awaits never use ref or mutate players after disposal', () {
    final mpvSource = _read(players['MPV']!);
    final mpvFailover = _method(mpvSource, 'Future<void> _tryNextStream(');
    _expectInOrder(mpvFailover, const [
      'final tokenService = ref.read(debridTokenServiceProvider)',
      'await AndroidTvBridge.instance.getDeviceProfile()',
      'if (!mounted || _engineHandoffInProgress) return',
      'await _database.recordStreamFailure(',
      'if (!mounted || _engineHandoffInProgress) return',
      'await _switchToNextDirectStream(position)',
    ]);

    for (final name in ['MPV', 'VLC']) {
      final source = _read(players[name]!);
      final preflight = _method(
        source,
        'Future<PlaybackStreamOption?> _preflightDirectStream(',
      );
      _expectInOrder(preflight, const [
        'await const WebStreamValidator().validate(',
        'if (!mounted || _engineHandoffInProgress) {',
        'await validated.session?.close()',
        'uri: validated.uri',
        'externalSubtitle: validated.subtitleUri',
        'playbackLease: validated.session',
      ]);

      final discovery = _method(
        source,
        'Future<void> _startWebSourceDiscovery(',
      );
      _expectInOrder(discovery, const [
        'final aggregator = ref.read(webStreamAggregatorProvider)',
        'final episode = widget.launch.episode',
        'await _sourceDiscoverySubscription?.cancel()',
        'if (!mounted || _engineHandoffInProgress) return',
        'aggregator',
        '.watchSearchIncrementally(episode)',
      ]);
      final afterCancel = discovery.substring(
        discovery.indexOf('await _sourceDiscoverySubscription?.cancel()'),
      );
      expect(afterCancel, isNot(contains('ref.read')));
    }

    final vlcFailure = _method(
      _read(players['VLC']!),
      'Future<void> _recordEngineFailure(',
    );
    _expectInOrder(vlcFailure, const [
      'final database = _database',
      'await AndroidTvBridge.instance.getDeviceProfile()',
      'if (!mounted || _engineHandoffInProgress) return',
      "await database.recordPlayerFailure(device.key, 'vlc')",
    ]);
  });

  test('MPV prewarm captures dependencies and guards both async phases', () {
    final prewarm = _method(
      _read(players['MPV']!),
      'Future<void> _prewarmNextEpisode()',
    );
    _expectInOrder(prewarm, const [
      'final userSourcesController = ref.read(',
      'final tokenService = ref.read(debridTokenServiceProvider)',
      'final userManifests = await loadPlayerPrewarmSnapshot(',
      'if (!mounted || _engineHandoffInProgress || userManifests == null)',
      'await CompositeReleaseSource(sources).search(next)',
      'if (!mounted || _engineHandoffInProgress) return',
      'await _resolveRelease(',
      'tokenService: tokenService',
      'if (!mounted || _engineHandoffInProgress) return',
      '_prewarmed = true',
    ]);
    final afterManifestLoad = prewarm.substring(
      prewarm.indexOf('final userManifests = await loadPlayerPrewarmSnapshot('),
    );
    expect(afterManifestLoad, isNot(contains('ref.read')));
  });

  test(
    'Media3 validates manual and automatic web alternatives before launch',
    () {
      final source = _read(players['Media3']!);
      final picker = _method(source, 'Future<void> _openDirectStreamPicker()');
      _expectInOrder(picker, const [
        'final selected = await showPlayerStreamSourcePicker(',
        'final option = await _preflightDirectStream(selected)',
        'if (!mounted) {',
        'await option?.stream.playbackLease?.close()',
        'if (option == null) return',
        '_currentStream = option.stream',
        '_source = option.stream.uri.toString()',
      ]);
      expect(picker, isNot(contains('_currentStream = selected.stream')));
      expect(picker, isNot(contains('_source = selected.stream.uri')));

      final preflight = _method(
        source,
        'Future<PlaybackStreamOption?> _preflightDirectStream(',
      );
      _expectInOrder(preflight, const [
        'await const WebStreamValidator().validate(',
        'if (!mounted) {',
        'await validated.session?.close()',
        'uri: validated.uri',
        'headers: validated.headers',
        'externalSubtitle: validated.subtitleUri',
        'playbackLease: validated.session',
      ]);

      final automatic = _method(
        source,
        'Future<bool> _switchToCompatibleStream(',
      );
      _expectInOrder(automatic, const [
        'openFirstViablePlayerCandidate(',
        'attempt: (candidate, resumePosition) async',
        'final option = await _preflightDirectStream(',
        'candidate,',
        'silent: true',
        'if (!mounted || !_streamFailoverInProgress) {',
        'await option?.stream.playbackLease?.close()',
        'if (option == null) return false',
        '_currentStream = option.stream',
        '_resumePosition = resumePosition',
        '_automaticStreamAttempts++',
      ]);

      final run = _method(source, 'Future<void> _run()');
      expect(run, contains('headers: _currentStream.headers'));
      expect(run, isNot(contains('headers: selected.stream.headers')));

      final validatorSource = _read(
        'lib/features/marketplace/data/web_playback_proxy.dart',
      );
      _expectInOrder(validatorSource, const [
        'await validateTarget(target)',
        'if (!_sameOrigin(target, redirected))',
        'sanitizeAddonHeaders(sanitized, stripCredentials: true)',
        'target = redirected',
      ]);
      final stripped = sanitizeWebStreamHeaders(const {
        'Authorization': 'Bearer secret',
        'Cookie': 'session=secret',
        'Referer': 'https://provider.example/',
      }, stripCredentials: true);
      expect(stripped, isNot(contains('Authorization')));
      expect(stripped, isNot(contains('Cookie')));
      expect(stripped['Referer'], 'https://provider.example/');
    },
  );

  test('failover is finite, deduplicated, affinity-ranked, and quiet', () {
    for (final name in ['MPV', 'VLC']) {
      final source = _read(players[name]!);
      expect(source, contains('final Set<String> _failedDirectStreamUris'));
      expect(
        source,
        contains('final Set<ReleaseCandidate> _attemptedReleaseAlternatives'),
      );
      final affinity = _method(source, 'int _releaseFailoverAffinity(');
      expect(affinity, contains('sameProvider'));
      expect(affinity, contains('sameSource'));
      expect(affinity, contains('sameAuthor'));
      final wait = _method(
        source,
        'Future<void> _waitForInFlightDirectDiscovery()',
      );
      expect(wait, contains('waitForPlayerFailoverCandidates('));
      expect(wait, contains('snapshot: _remainingDirectFailoverCandidates'));
      final direct = _method(source, 'Future<bool> _switchToNextDirectStream(');
      expect(direct, contains('openFirstViablePlayerCandidate('));
      expect(direct, isNot(contains('_showMessage')));
      expect(direct, isNot(contains('_showTrackMessage')));
    }

    final media3 = _read(players['Media3']!);
    expect(media3, contains('_maxAutomaticStreamAttempts = 4'));
    expect(media3, contains('_maxFailoverCandidatesPerRequest = 12'));
    expect(media3, contains('_streamFailoverInProgress'));
    expect(media3, contains('_failedDirectStreamUris'));
    expect(media3, contains('_attemptedReleaseAlternatives'));
    final failover = _method(media3, 'Future<bool> _switchToCompatibleStream(');
    _expectInOrder(failover, const [
      '_diagnostic = null',
      'openFirstViablePlayerCandidate(',
      '_remainingReleaseFailoverCandidates().take(',
      "_status = 'No compatible streams remain'",
      '_diagnostic = terminalFailure?.toString() ?? reason',
    ]);
  });

  test('all engines apply audio-first ordering only to automatic failover', () {
    for (final entry in players.entries) {
      final source = _read(entry.value);
      final direct = _method(
        source,
        'List<PlaybackStreamOption> _remainingDirectFailoverCandidates()',
      );
      _expectInOrder(direct, const [
        'rankAutomaticPlayerFailoverCandidates(',
        'audioRank:',
        'releaseAudioPreferenceRank(',
        'affinityRank:',
      ]);

      final releases = _method(
        source,
        'List<ReleaseCandidate> _remainingReleaseFailoverCandidates()',
      );
      _expectInOrder(releases, const [
        'rankAutomaticPlayerFailoverCandidates(',
        'audioRank:',
        'releaseAudioPreferenceRank(',
        'affinityRank:',
      ]);
      expect(direct, contains('_effectiveAudioPreference'));
      expect(releases, contains('_effectiveAudioPreference'));
    }

    final manualPicker = _read(
      'lib/features/player/presentation/player_stream_source_picker.dart',
    );
    expect(
      manualPicker,
      isNot(contains('rankAutomaticPlayerFailoverCandidates')),
    );
    _expectInOrder(manualPicker, const [
      'int comparePlaybackStreamOptions(',
      'final quality = playbackStreamQualityRank(',
      'final provider = leftProvider.compareTo(rightProvider)',
    ]);
  });

  test(
    'stream class order prefers current class before cross-class fallback',
    () {
      for (final name in ['MPV', 'VLC']) {
        final failover = _method(
          _read(players[name]!),
          'Future<void> _tryNextStream(',
        );
        _expectInOrder(failover, const [
          'final classOrder = playerFailoverClassOrder(',
          'currentIsWeb: _currentStream.isWebStream',
          'final directFirst = classOrder.first == PlayerFailoverClass.directWeb',
          'if (directFirst)',
          'await _switchToNextDirectStream(position)',
          '_remainingReleaseFailoverCandidates().take(12)',
          'if (!directFirst)',
          'await _waitForInFlightDirectDiscovery()',
          'await _switchToNextDirectStream(position)',
        ]);
      }

      final media3 = _method(
        _read(players['Media3']!),
        'Future<bool> _switchToCompatibleStream(',
      );
      _expectInOrder(media3, const [
        'final classOrder = playerFailoverClassOrder(',
        'currentIsWeb: _currentStream.isWebStream',
        'final directFirst = classOrder.first == PlayerFailoverClass.directWeb',
        'if (directFirst && await tryDirectCandidates()) return true',
        'if (await tryDebridCandidates()) return true',
        'if (!directFirst && await tryDirectCandidates()) return true',
      ]);
    },
  );

  test('enabled web discovery also runs during debrid playback', () {
    for (final name in ['MPV', 'VLC', 'Media3']) {
      final source = _read(players[name]!);
      final discovery = _method(
        source,
        'Future<void> _startWebSourceDiscovery(',
      );
      expect(discovery, contains('webStreamsEnabled'));
      expect(discovery, contains('watchSearchIncrementally(episode)'));
      expect(discovery, isNot(contains('_currentStream.isWebStream')));
      expect(source, contains('unawaited(_startWebSourceDiscovery())'));
    }

    final media3 = _read(players['Media3']!);
    final direct = _method(media3, 'Future<bool> _switchToCompatibleStream(');
    _expectInOrder(direct, const [
      'Future<bool> tryDirectCandidates() async',
      'await _waitForInFlightDirectDiscovery()',
      'openFirstViablePlayerCandidate(',
      'await _preflightDirectStream(',
      '_resumePosition = resumePosition',
    ]);
  });

  test('proxy leases transfer only after candidate playback is accepted', () {
    final router = _read(players['MPV']!);
    final adoption = _method(router, 'Future<void> _adoptPlaybackStream(');
    _expectInOrder(adoption, const [
      'final previous = _activeLaunch.stream',
      '_activeLaunch = PlaybackLaunch(',
      'if (!identical(previous.playbackLease, stream.playbackLease))',
      'await previous.playbackLease?.close()',
    ]);
    final routerDispose = _method(router, 'void dispose()');
    expect(
      routerDispose,
      contains('unawaited(_activeLaunch.stream.playbackLease?.close())'),
    );

    final engineOpen = {
      'MPV': 'await _openMedia(resume: resume, propagateFailure: true)',
      'VLC': 'await _restart(',
    };
    for (final entry in engineOpen.entries) {
      final picker = _method(
        _read(players[entry.key]!),
        'Future<void> _openStreamSourcePicker()',
      );
      _expectInOrder(picker, [
        'final option = await _preflightDirectStream(selected)',
        entry.value,
        'await widget.onStreamAdopted(option.stream, option.release)',
        '} catch (_)',
        'await option.stream.playbackLease?.close()',
      ]);
    }
  });

  test('all direct stream validation proxies subtitle and MIME metadata', () {
    for (final name in ['MPV', 'VLC', 'Media3']) {
      final preflight = _method(
        _read(players[name]!),
        'Future<PlaybackStreamOption?> _preflightDirectStream(',
      );
      _expectInOrder(preflight, const [
        'subtitleUri: option.stream.externalSubtitle',
        'externalSubtitle: validated.subtitleUri',
        'mediaContentType: validated.contentType',
        'subtitleContentType: validated.subtitleContentType',
        'externalSubtitleRejected: validated.subtitleRejected',
        'playbackLease: validated.session',
      ]);
    }

    final media3Run = _method(_read(players['Media3']!), 'Future<void> _run()');
    expect(
      media3Run,
      contains('mediaContentType: _currentStream.mediaContentType'),
    );
    expect(
      media3Run,
      contains('subtitleContentType: _currentStream.subtitleContentType'),
    );
    expect(
      media3Run,
      contains('trustedPlaybackProxy: WebPlaybackProxy.instance'),
    );
  });

  test('native proxy trust is separate from local-media Discord suppression', () {
    final native = _read(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt',
    );
    _expectInOrder(native, const [
      'val trustedLocalSource =',
      'val trustedPlaybackProxy =',
      'suppressDiscordPresence = trustedLocalSource',
      'playbackProxyOrigin = if (trustedPlaybackProxy)',
    ]);
    expect(
      native,
      contains('localSourceOrigin == null && playbackProxyOrigin == null'),
    );
  });
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _method(String source, String token) {
  final start = source.indexOf(token);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $token');
  final next = source.indexOf('\n  Future<', start + token.length);
  final voidNext = source.indexOf('\n  void ', start + token.length);
  final candidates = [if (next >= 0) next, if (voidNext >= 0) voidNext]..sort();
  final end = candidates.isEmpty ? source.length : candidates.first;
  return source.substring(start, end);
}

void _expectInOrder(String source, List<String> tokens) {
  var previous = -1;
  for (final token in tokens) {
    final index = source.indexOf(token, previous + 1);
    expect(
      index,
      greaterThan(previous),
      reason: 'Missing/out of order: $token',
    );
    previous = index;
  }
}
