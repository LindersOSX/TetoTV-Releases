import 'package:anime_tv/features/player/application/audio_track_selector.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/player/presentation/player_control_overlay.dart';
import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('opens marketplace web streams with the defensive MPV path', () {
    final web = StreamReady(
      uri: Uri.parse('https://cdn.example.test/episode.m3u8'),
      displayName: 'Marketplace stream',
      providerId: 'fixture',
    );
    final debrid = StreamReady(
      uri: Uri.parse('https://cdn.example.test/episode.mkv'),
      displayName: 'Debrid stream',
      debridService: DebridService.realDebrid,
    );

    expect(preferMpvForInitialStream(web), isTrue);
    expect(preferMpvForInitialStream(debrid), isFalse);
  });

  test('manual Media3 selection is not bounced back to MPV', () {
    const release = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Group] Show - 01 [1080p].mkv',
      seeders: 1,
      sourceId: 'test',
    );
    const software = SeriesPlaybackPreferences(decoder: 'software');

    expect(
      shouldRedirectMedia3ToMpv(
        manuallySelected: false,
        preferences: software,
        release: release,
      ),
      isTrue,
    );
    expect(
      shouldRedirectMedia3ToMpv(
        manuallySelected: true,
        preferences: software,
        release: release,
      ),
      isFalse,
    );
  });

  test('prefers English dub audio over Japanese default audio', () {
    const tracks = [
      AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      AudioTrack('2', 'English Dub', 'eng'),
      AudioTrack('3', 'English Commentary', 'eng'),
    ];

    expect(preferredDubAudioTrack(tracks)?.id, '2');
  });

  test('leaves automatic audio unchanged when no dub exists', () {
    const tracks = [
      AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      AudioTrack('2', 'Japanese 5.1', 'jpn'),
    ];

    expect(preferredDubAudioTrack(tracks), isNull);
  });

  test('global sub preference consistently chooses Japanese audio', () {
    const tracks = [
      AudioTrack('1', 'English Dub', 'eng', isDefault: true),
      AudioTrack('2', 'Japanese', 'jpn'),
    ];

    expect(
      preferredAudioTrack(
        tracks,
        preference: PlaybackAudioPreference.sub,
        allowFallback: false,
      )?.id,
      '2',
    );
  });

  test('explicit series audio selects the same language next episode', () {
    const tracks = [
      AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      AudioTrack('2', 'English Dub', 'eng'),
      AudioTrack('3', 'English Commentary', 'eng'),
    ];

    expect(
      preferredAudioTrackForLanguage(
        tracks,
        language: 'eng',
        allowFallback: false,
      )?.id,
      '2',
    );
    expect(
      preferredAudioTrackForLanguage(
        tracks,
        language: 'jpn',
        allowFallback: false,
      )?.id,
      '1',
    );
  });

  test('an anime track labeled only Dub persists as English', () {
    expect(canonicalPlayerLanguage('[DUB] 5.1'), 'eng');
    expect(
      playbackAudioPreferenceForLanguage('eng'),
      PlaybackAudioPreference.dub,
    );
  });

  test('undefined container language falls back to the useful track label', () {
    for (final placeholder in const ['und', 'zxx', 'mul']) {
      expect(canonicalPlayerLanguage(placeholder), isEmpty);
      expect(
        canonicalPlayerTrackLanguage(
          language: placeholder,
          title: 'English Dub 5.1',
        ),
        'eng',
        reason: placeholder,
      );
    }
  });

  test('explicit Dub and Sub survive opposite-language player fallbacks', () {
    expect(
      persistedPlayerAudioLanguage(
        storedLanguage: 'eng',
        audioPreferenceSet: true,
        observedLanguage: 'jpn',
        observedTitle: 'Japanese fallback',
      ),
      'eng',
    );
    expect(
      persistedPlayerAudioLanguage(
        storedLanguage: 'jpn',
        audioPreferenceSet: true,
        observedLanguage: 'eng',
        observedTitle: 'English fallback',
      ),
      'jpn',
    );
  });

  test('manual audio changes replace an explicit series choice', () {
    expect(
      persistedPlayerAudioLanguage(
        storedLanguage: 'jpn',
        audioPreferenceSet: true,
        observedLanguage: 'und',
        observedTitle: 'English Dub',
        manualSelection: true,
      ),
      'eng',
    );
    expect(
      persistedPlayerAudioLanguage(
        storedLanguage: 'eng',
        audioPreferenceSet: false,
        observedLanguage: 'jpn',
      ),
      'jpn',
      reason: 'automatic observations remain persistable before manual choice',
    );
  });

  test('series Dub override wins over a global Sub release preference', () {
    expect(
      effectivePlaybackAudioPreference(
        globalPreference: PlaybackAudioPreference.sub,
        seriesAudioLanguage: 'eng',
        seriesOverride: true,
      ),
      PlaybackAudioPreference.dub,
    );
    expect(
      effectivePlaybackAudioPreference(
        globalPreference: PlaybackAudioPreference.sub,
      ),
      PlaybackAudioPreference.sub,
    );
  });

  test('audio preference has deterministic default-track fallback', () {
    const tracks = [
      AudioTrack('1', 'French', 'fra'),
      AudioTrack('2', 'Spanish', 'spa', isDefault: true),
    ];

    expect(
      preferredAudioTrack(tracks, preference: PlaybackAudioPreference.dub)?.id,
      '2',
    );
  });

  test(
    'waits for a late English track before opening the audio picker',
    () async {
      const japaneseOnly = [
        AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      ];
      const dualAudio = [
        ...japaneseOnly,
        AudioTrack('2', 'English Dub', 'eng', codec: 'aac'),
      ];
      var reads = 0;

      final tracks = await waitForStableTrackSnapshot<List<AudioTrack>>(
        read: () async => ++reads < 3 ? japaneseOnly : dualAudio,
        signature: mediaKitAudioTrackSignature,
        hasTracks: (tracks) => tracks.isNotEmpty,
        pollInterval: const Duration(milliseconds: 1),
        minimumWait: const Duration(milliseconds: 4),
        maximumWait: const Duration(milliseconds: 12),
      );

      expect(tracks.map((track) => track.id), ['1', '2']);
      expect(preferredDubAudioTrack(tracks)?.id, '2');
    },
  );

  test(
    'dual-audio releases wait past a stable single-track snapshot',
    () async {
      const japaneseOnly = [
        AudioTrack('1', 'Japanese', 'jpn', isDefault: true),
      ];
      const dualAudio = [
        ...japaneseOnly,
        AudioTrack('2', 'English Dub', 'eng', codec: 'aac'),
      ];
      var reads = 0;

      final tracks = await waitForStableTrackSnapshot<List<AudioTrack>>(
        read: () async => ++reads < 6 ? japaneseOnly : dualAudio,
        signature: mediaKitAudioTrackSignature,
        hasTracks: (tracks) => tracks.isNotEmpty,
        isComplete: (tracks) => tracks.length >= 2,
        pollInterval: const Duration(milliseconds: 1),
        minimumWait: const Duration(milliseconds: 3),
        maximumWait: const Duration(milliseconds: 10),
      );

      expect(reads, greaterThanOrEqualTo(6));
      expect(tracks.map((track) => track.id), ['1', '2']);
    },
  );

  test('recognizes common dual and multi-audio release labels', () {
    expect(releaseAdvertisesMultipleAudio('[Group] Show - Dual Audio'), isTrue);
    expect(releaseAdvertisesMultipleAudio('Show.Multi-Audio.1080p'), isTrue);
    expect(
      releaseAdvertisesMultipleAudio('Show Japanese Audio 1080p'),
      isFalse,
    );
  });

  test('track signatures detect metadata and VLC list changes', () {
    expect(
      mediaKitAudioTrackSignature(const [AudioTrack('1', 'Japanese', 'jpn')]),
      isNot(
        mediaKitAudioTrackSignature(const [
          AudioTrack('1', 'Japanese', 'jpn'),
          AudioTrack('2', 'English', 'eng'),
        ]),
      ),
    );
    expect(
      vlcAudioTrackSignature(const {1: 'Japanese'}),
      isNot(vlcAudioTrackSignature(const {1: 'Japanese', 2: 'English'})),
    );
  });

  test(
    'starts automatic playback on smooth MediaCodec with adaptive fallback',
    () {
      expect(
        tetoTvVideoControllerConfiguration.enableHardwareAcceleration,
        isTrue,
      );
      expect(tetoTvVideoControllerConfiguration.vo, 'gpu');
      expect(tetoTvVideoControllerConfiguration.hwdec, 'mediacodec');
      expect(
        tetoTvVideoControllerConfiguration
            .androidAttachSurfaceAfterVideoParameters,
        isTrue,
      );
    },
  );

  test('recognizes video failures that should trigger software decoding', () {
    expect(isLikelyVideoDecodeFailure('MediaCodec failed to initialize'), true);
    expect(isLikelyVideoDecodeFailure('No video output available'), true);
    expect(isLikelyVideoDecodeFailure('HTTP 403 forbidden'), false);
  });

  test('offers safe hardware, direct hardware, and software decoders', () {
    expect(
      hwdecForPlaybackMode(PlaybackDecoderMode.hardwareSafe),
      'mediacodec',
    );
    expect(
      hwdecForPlaybackMode(PlaybackDecoderMode.hardwareDirect),
      'mediacodec',
    );
    expect(hwdecForPlaybackMode(PlaybackDecoderMode.software), 'no');
  });

  test('forces software decoding for H.264 Hi10P anime releases', () {
    const hi10 = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Group] Show - 01 [1080p Hi10P x264].mkv',
      seeders: 1,
      sourceId: 'test',
      codec: 'H.264',
    );
    const ordinary = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Group] Show - 01 [1080p x264].mkv',
      seeders: 1,
      sourceId: 'test',
      codec: 'H.264',
    );

    expect(releaseRequiresSoftwareDecoder(hi10), isTrue);
    expect(releaseRequiresSoftwareDecoder(ordinary), isFalse);
  });

  test('detects unlabeled 10-bit H.264 from decoded stream metadata', () {
    expect(
      isH264TenBitVideoProfile(
        codec: 'h264',
        profile: 'High 10',
        format: 'yuv420p10le',
        pixelFormat: 'mediacodec',
      ),
      isTrue,
    );
    expect(
      isH264TenBitVideoProfile(
        codec: 'h264',
        profile: 'High',
        format: 'yuv420p',
      ),
      isFalse,
    );
    expect(
      isH264TenBitVideoProfile(
        codec: 'hevc',
        profile: 'Main 10',
        format: 'yuv420p10le',
      ),
      isFalse,
    );
  });

  test('retries a resume seek only when playback remained near the start', () {
    const target = Duration(minutes: 12, seconds: 30);
    expect(resumeSeekNeedsRetry(target, Duration.zero), isTrue);
    expect(
      resumeSeekNeedsRetry(target, const Duration(minutes: 12, seconds: 28)),
      isFalse,
    );
  });

  test('D-pad arrows navigate controls instead of seeking playback', () {
    expect(playerSeekOffsetForKey(LogicalKeyboardKey.arrowLeft), isNull);
    expect(playerSeekOffsetForKey(LogicalKeyboardKey.arrowRight), isNull);
    expect(
      playerSeekOffsetForKey(LogicalKeyboardKey.mediaRewind),
      const Duration(seconds: -10),
    );
    expect(
      playerSeekOffsetForKey(LogicalKeyboardKey.mediaFastForward),
      const Duration(seconds: 10),
    );
  });

  test('seek target remains usable before stream duration is known', () {
    expect(
      playerSeekTarget(
        position: const Duration(minutes: 3),
        offset: const Duration(seconds: 10),
        duration: Duration.zero,
      ),
      const Duration(minutes: 3, seconds: 10),
    );
    expect(
      playerSeekTarget(
        position: const Duration(seconds: 4),
        offset: const Duration(seconds: -10),
        duration: const Duration(minutes: 24),
      ),
      Duration.zero,
    );
    expect(
      playerSeekTarget(
        position: const Duration(minutes: 23, seconds: 58),
        offset: const Duration(seconds: 10),
        duration: const Duration(minutes: 24),
      ),
      const Duration(minutes: 24),
    );
  });

  test('skip-segment target never lands on the synchronous EOF boundary', () {
    expect(
      safeSkipSegmentTarget(
        requested: const Duration(minutes: 24),
        duration: const Duration(minutes: 24),
      ),
      const Duration(minutes: 23, seconds: 59),
    );
    expect(
      safeSkipSegmentTarget(
        requested: const Duration(minutes: 21, seconds: 30),
        duration: const Duration(minutes: 24),
      ),
      const Duration(minutes: 21, seconds: 30),
    );
    expect(
      safeSkipSegmentTarget(
        requested: const Duration(minutes: 4),
        duration: Duration.zero,
      ),
      const Duration(minutes: 4),
    );
  });

  test('terminal outro remains identifiable behind the eof guard', () {
    expect(
      skipSegmentReachesPlaybackEnd(
        requestedEnd: const Duration(minutes: 24),
        duration: const Duration(minutes: 24),
      ),
      isTrue,
    );
    expect(
      skipSegmentReachesPlaybackEnd(
        requestedEnd: const Duration(minutes: 21, seconds: 30),
        duration: const Duration(minutes: 24),
      ),
      isFalse,
    );
  });

  test('subtitle defaults follow the selected release language', () {
    const sub = ReleaseCandidate(
      infoHash: 'sub',
      magnetUri: 'magnet:?xt=urn:btih:sub',
      releaseName: 'Show 01 English Subbed',
      seeders: 1,
      sourceId: 'test',
      hasSubtitles: true,
    );
    const dub = ReleaseCandidate(
      infoHash: 'dub',
      magnetUri: 'magnet:?xt=urn:btih:dub',
      releaseName: 'Show 01 English Dub',
      seeders: 1,
      sourceId: 'test',
      isDubbed: true,
      hasSubtitles: true,
    );

    expect(subtitlesEnabledByDefault(sub), isTrue);
    expect(subtitlesEnabledByDefault(dub), isFalse);
  });

  test('VLC compatibility mode is independent from its software fallback', () {
    expect(
      vlcHwAccForMode(VlcDecoderMode.hardwareCopy),
      isNot(vlcHwAccForMode(VlcDecoderMode.software)),
    );
    expect(
      vlcDecoderLabel(VlcDecoderMode.hardwareCopy),
      contains('recommended'),
    );
  });

  test('VLC track selection prioritizes English dub and avoids commentary', () {
    final selected = preferredVlcTrack(
      const {
        1: 'Japanese Stereo',
        2: 'English Commentary',
        3: 'English Dub 5.1',
      },
      language: 'eng',
      preferDub: true,
    );
    expect(selected, 3);
    expect(
      preferredVlcTrack(
        const {1: 'Japanese Stereo'},
        language: 'eng',
        preferDub: true,
      ),
      isNull,
    );
    expect(
      preferredVlcTrack(
        const {1: 'English Commentary', 2: 'Japanese Stereo'},
        language: 'eng',
        preferDub: true,
      ),
      2,
      reason: 'a normal fallback must beat container-default commentary',
    );
  });

  test('MPV provisional fallback never leaves default commentary selected', () {
    const tracks = [
      AudioTrack('1', 'English Commentary', 'eng', isDefault: true),
      AudioTrack('2', 'Japanese Stereo', 'jpn'),
    ];

    expect(
      preferredAudioTrackForLanguage(
        tracks,
        language: 'fra',
        allowFallback: false,
      )?.id,
      '2',
    );
    expect(
      preferredAudioTrack(
        tracks,
        preference: PlaybackAudioPreference.dub,
        allowFallback: false,
      )?.id,
      '2',
      reason: 'commentary is not a valid Dub match',
    );
  });

  test('English track matching accepts common ISO aliases', () {
    for (final language in const ['en', 'eng', 'en-US', 'en_GB', 'English']) {
      expect(
        playerTrackMatchesLanguage(
          language: language,
          preferredLanguage: 'eng',
        ),
        isTrue,
        reason: language,
      );
    }
    expect(preferredVlcTrack(const {1: 'ja', 2: 'en'}, language: 'eng'), 2);
  });

  test('double Down requires two distinct presses inside the window', () {
    final detector = PlayerDoubleDownDetector();
    final start = DateTime(2026);

    expect(detector.register(LogicalKeyboardKey.arrowDown, at: start), isFalse);
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 440)),
      ),
      isTrue,
    );
    expect(playerControlsIdleTimeout, const Duration(seconds: 5));
  });

  test('another key or a late Down resets double-Down detection', () {
    final detector = PlayerDoubleDownDetector();
    final start = DateTime(2026);

    detector.register(LogicalKeyboardKey.arrowDown, at: start);
    detector.register(
      LogicalKeyboardKey.arrowRight,
      at: start.add(const Duration(milliseconds: 100)),
    );
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      detector.register(
        LogicalKeyboardKey.arrowDown,
        at: start.add(const Duration(milliseconds: 800)),
      ),
      isFalse,
    );
  });

  test('a held Down cannot reopen a HUD that its key-down dismissed', () {
    expect(
      consumeHiddenPlayerHudDownRepeat(
        key: LogicalKeyboardKey.arrowDown,
        isRepeat: true,
        controlsVisible: false,
      ),
      isTrue,
    );
    expect(
      consumeHiddenPlayerHudDownRepeat(
        key: LogicalKeyboardKey.arrowDown,
        isRepeat: false,
        controlsVisible: false,
      ),
      isFalse,
      reason: 'the initial key-down must still be allowed to show the HUD',
    );
    expect(
      consumeHiddenPlayerHudDownRepeat(
        key: LogicalKeyboardKey.arrowDown,
        isRepeat: true,
        controlsVisible: true,
      ),
      isFalse,
      reason: 'visible controls keep their normal directional behavior',
    );
    expect(
      consumeHiddenPlayerHudDownRepeat(
        key: LogicalKeyboardKey.arrowRight,
        isRepeat: true,
        controlsVisible: false,
      ),
      isFalse,
      reason: 'other directions must still reveal and navigate the HUD',
    );
  });

  test(
    'native player release is joined and can retry after a failure',
    () async {
      final coordinator = PlayerReleaseCoordinator();
      var attempts = 0;
      final first = coordinator.release(() async {
        attempts += 1;
        await Future<void>.delayed(Duration.zero);
        throw StateError('decoder still owns the surface');
      });
      final joined = coordinator.release(() async {
        attempts += 100;
      });

      expect(await Future.wait([first, joined]), [isFalse, isFalse]);
      expect(
        attempts,
        1,
        reason: 'concurrent release must share one operation',
      );
      expect(coordinator.released, isFalse);

      expect(
        await coordinator.release(() async {
          attempts += 1;
        }),
        isTrue,
      );
      expect(attempts, 2);
      expect(coordinator.released, isTrue);
    },
  );
}
