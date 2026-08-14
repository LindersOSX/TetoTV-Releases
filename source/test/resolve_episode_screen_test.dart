import 'dart:async';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:anime_tv/features/streaming/data/all_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/premiumize_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/presentation/resolve_episode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('similar releases prefer the same group, then provider', () {
    const sameGroup = ReleaseCandidate(
      infoHash: '1111111111111111111111111111111111111111',
      magnetUri: 'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
      releaseName: '[SubsPlease] Show - 02 [1080p].mkv',
      seeders: 5,
      sourceId: 'other-source',
      provider: 'Other provider',
    );
    const sameProvider = ReleaseCandidate(
      infoHash: '2222222222222222222222222222222222222222',
      magnetUri: 'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
      releaseName: '[Different] Show - 02 [1080p].mkv',
      seeders: 500,
      sourceId: 'preferred-source',
      provider: 'Preferred provider',
    );
    const unrelated = ReleaseCandidate(
      infoHash: '3333333333333333333333333333333333333333',
      magnetUri: 'magnet:?xt=urn:btih:3333333333333333333333333333333333333333',
      releaseName: '[Other] Show - 02 [1080p].mkv',
      seeders: 900,
      sourceId: 'other-source',
      provider: 'Other provider',
    );
    final releases = [unrelated, sameProvider, sameGroup]
      ..sort(
        (left, right) => compareStreamReleases(
          left,
          right,
          preferredProvider: 'Preferred provider',
          preferredReleaseGroup: 'subsplease',
        ),
      );

    expect(releases, [sameGroup, sameProvider, unrelated]);
    expect(releaseGroupKey('[SubsPlease] Show - 02'), 'subsplease');
    expect(releaseGroupKey('Show - 02'), isNull);
  });

  test(
    'autoplay affinity prefers provider plus author, then provider, then rank',
    () {
      const exact = ReleaseCandidate(
        infoHash: '1111111111111111111111111111111111111111',
        magnetUri:
            'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
        releaseName: '[Same Group] Show - 02 English Dub',
        seeders: 1,
        sourceId: 'exact',
        provider: 'Same Provider',
        isDubbed: true,
      );
      const providerOnly = ReleaseCandidate(
        infoHash: '2222222222222222222222222222222222222222',
        magnetUri:
            'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 500,
        sourceId: 'provider',
        provider: 'Same Provider',
        isDubbed: true,
      );
      const global = ReleaseCandidate(
        infoHash: '3333333333333333333333333333333333333333',
        magnetUri:
            'magnet:?xt=urn:btih:3333333333333333333333333333333333333333',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 5000,
        sourceId: 'global',
        provider: 'Other Provider',
        isDubbed: true,
      );
      final releases = [global, providerOnly, exact]
        ..sort(
          (left, right) => compareAutoplayReleases(
            left,
            right,
            preferredProvider: ' same provider ',
            preferredAuthor: '[Same Group]',
            preferredAudio: PlaybackAudioPreference.dub,
          ),
        );

      expect(releases, [exact, providerOnly, global]);
    },
  );

  test('autoplay affinity never overrides the preferred audio class', () {
    const preferredProviderSub = ReleaseCandidate(
      infoHash: '1111111111111111111111111111111111111111',
      magnetUri: 'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
      releaseName: '[Same Group] Show - 02',
      seeders: 500,
      sourceId: 'sub',
      provider: 'Same Provider',
    );
    const otherProviderDub = ReleaseCandidate(
      infoHash: '2222222222222222222222222222222222222222',
      magnetUri: 'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
      releaseName: '[Other Group] Show - 02 English Dub',
      seeders: 1,
      sourceId: 'dub',
      provider: 'Other Provider',
      isDubbed: true,
    );

    expect(
      compareAutoplayReleases(
        otherProviderDub,
        preferredProviderSub,
        preferredProvider: 'Same Provider',
        preferredAuthor: 'Same Group',
        preferredAudio: PlaybackAudioPreference.dub,
      ),
      lessThan(0),
    );
  });

  test('stable source affinity survives a provider change with both hints', () {
    const sameSource = ReleaseCandidate(
      infoHash: '1111111111111111111111111111111111111111',
      magnetUri: 'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
      releaseName: '[Same Group] Same source English Dub',
      seeders: 1,
      sourceId: 'same-source',
      provider: 'Renamed Provider',
      isDubbed: true,
    );
    const providerMatch = ReleaseCandidate(
      infoHash: '2222222222222222222222222222222222222222',
      magnetUri: 'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
      releaseName: '[Other Group] Provider match English Dub',
      seeders: 2,
      sourceId: 'other-source',
      provider: 'Preferred Provider',
      isDubbed: true,
    );

    expect(
      compareAutoplayReleases(
        sameSource,
        providerMatch,
        preferredProvider: 'Preferred Provider',
        preferredSourceId: 'same-source',
        preferredAuthor: 'Same Group',
        preferredAudio: PlaybackAudioPreference.dub,
      ),
      lessThan(0),
    );
  });

  test('author-only affinity ranks above an unrelated release', () {
    const sameAuthor = ReleaseCandidate(
      infoHash: '3333333333333333333333333333333333333333',
      magnetUri: 'magnet:?xt=urn:btih:3333333333333333333333333333333333333333',
      releaseName: '[Same Group] Author-only English Dub',
      seeders: 1,
      sourceId: 'other-source',
      provider: 'Other Provider',
      isDubbed: true,
    );
    const unrelated = ReleaseCandidate(
      infoHash: '4444444444444444444444444444444444444444',
      magnetUri: 'magnet:?xt=urn:btih:4444444444444444444444444444444444444444',
      releaseName: '[Unrelated] Global English Dub',
      seeders: 5000,
      sourceId: 'global-source',
      provider: 'Global Provider',
      isDubbed: true,
    );

    expect(
      compareAutoplayReleases(
        sameAuthor,
        unrelated,
        preferredProvider: 'Preferred Provider',
        preferredSourceId: 'same-source',
        preferredAuthor: 'Same Group',
        preferredAudio: PlaybackAudioPreference.dub,
      ),
      lessThan(0),
    );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tetotv/android_tv'),
          (call) async =>
              call.method == 'getDeviceProfile' ? <String, Object?>{} : null,
        );
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tetotv/android_tv'),
          null,
        );
  });

  testWidgets('shows resolver errors and debounces repeated activation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolveCalls = 0;
    final failResolution = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _FakeReleaseSource(),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolveCalls++;
            return _FailingResolver(failResolution.future);
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('Dubbed release'));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(find.text('More filters'), findsOneWidget);
    expect(find.text('QUALITY'), findsNothing);
    expect(find.text('BATCHES ON'), findsNothing);

    await tester.tap(find.text('More filters'));
    // Provider discovery is intentionally progressive and may keep its
    // loading indicator active while filters remain fully interactive.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('QUALITY'), findsOneWidget);
    expect(find.text('BATCHES ON'), findsOneWidget);

    // A held/duplicated remote-select event must not add the same magnet twice.
    await tester.tap(find.text('Dubbed release'));
    await tester.tap(find.text('Dubbed release'), warnIfMissed: false);
    await tester.pump();
    expect(resolveCalls, 1);
    failResolution.complete();
    await _pumpUntilFound(tester, find.text('Retry'));

    expect(
      find.textContaining('Could not start this stream: Release unavailable'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(resolveCalls, 2);
  });

  testWidgets('keeps the picker usable while another resolver is loading', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final slow = Completer<List<ReleaseCandidate>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            CompositeReleaseSource([
              const _FakeReleaseSource(),
              _CallbackReleaseSource('slow', () => slow.future),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Dubbed release'));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(
      find.textContaining('Available results can be selected now'),
      findsOneWidget,
    );

    final focusedControl = find
        .ancestor(
          of: find.text('Dubbed release'),
          matching: find.byType(FocusableActionDetector),
        )
        .first;
    final focusNode = tester
        .widget<FocusableActionDetector>(focusedControl)
        .focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    slow.complete(const [
      ReleaseCandidate(
        infoHash: '89abcdef0123456789abcdef0123456789abcdef',
        magnetUri:
            'magnet:?xt=urn:btih:89abcdef0123456789abcdef0123456789abcdef',
        releaseName: 'Higher quality release',
        seeders: 50,
        sourceId: 'slow',
        isDubbed: true,
        quality: '2160p',
        codec: 'H.264',
      ),
    ]);
    // Do not wait for unrelated web providers to finish; this test verifies
    // that the debrid list reorders safely while discovery is still active.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Dubbed release'), findsOneWidget);
    expect(find.text('Higher quality release'), findsOneWidget);
    expect(focusNode.hasFocus, isTrue);
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is FocusableActionDetector &&
              identical(widget.focusNode, focusNode),
        ),
        matching: find.text('Dubbed release'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'autoplay launches an immediate debrid result without waiting for web',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final never = Completer<void>();
      addTearDown(() {
        if (!never.isCompleted) never.complete();
      });
      final webAggregator = _NeverCompletingWebAggregator(never.future);
      var resolverCalls = 0;
      var playerBuilds = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) {
              playerBuilds++;
              return const Scaffold(body: Text('PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            webStreamAggregatorProvider.overrideWithValue(webAggregator),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('PLAYER OPENED'));
      expect(webAggregator.searchCalls, 1);
      expect(never.isCompleted, isFalse);
      expect(resolverCalls, 1);
      expect(playerBuilds, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        resolverCalls,
        1,
        reason: 'late source progress must not relaunch',
      );
      expect(playerBuilds, 1);
    },
  );

  testWidgets(
    'autoplay persistence handoff never exposes picker or text input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final saveStarted = Completer<void>();
      final allowSave = Completer<void>();
      addTearDown(() {
        if (!allowSave.isCompleted) allowSave.complete();
      });
      var resolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 424243,
                title: 'Slow Persistence Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('PERSISTED PLAYER OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator(const []),
            ),
            seriesPreferencesWriterProvider.overrideWithValue((_, _) async {
              if (!saveStarted.isCompleted) saveStarted.complete();
              await allowSave.future;
            }),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('Opening the selected stream…'));
      expect(saveStarted.isCompleted, isTrue);
      expect(resolverCalls, 0);
      expect(find.text('Choose your stream'), findsNothing);
      expect(find.byType(TvTextInput), findsNothing);
      expect(find.textContaining('Paste a magnet'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Opening the selected stream…'), findsOneWidget);
      expect(find.text('Choose your stream'), findsNothing);
      expect(find.byType(TvTextInput), findsNothing);

      allowSave.complete();
      await _pumpUntilFound(tester, find.text('PERSISTED PLAYER OPENED'));
      expect(resolverCalls, 1);
    },
  );

  testWidgets(
    'autoplay ranks all concurrent repositories before checking debrid cache',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slowSource = Completer<List<ReleaseCandidate>>();
      final neverWeb = Completer<void>();
      addTearDown(() {
        if (!slowSource.isCompleted) slowSource.complete(const []);
        if (!neverWeb.isCompleted) neverWeb.complete();
      });
      var resolverCalls = 0;
      PlaybackLaunch? opened;
      final source = CompositeReleaseSource([
        _CallbackReleaseSource(
          'fast',
          () async => const [
            ReleaseCandidate(
              infoHash: '1111111111111111111111111111111111111111',
              magnetUri:
                  'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
              releaseName: 'Fast repository result English Dub',
              seeders: 1,
              sourceId: 'fast',
              isDubbed: true,
              quality: '1080p',
              codec: 'H.264',
            ),
          ],
        ),
        _CallbackReleaseSource('slow', () => slowSource.future),
      ]);
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('RANKED PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(source),
            webStreamAggregatorProvider.overrideWithValue(
              _NeverCompletingWebAggregator(neverWeb.future),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Debrid 1/2'));
      expect(
        find.text('Fast repository result English Dub'),
        findsNothing,
        reason: 'autoplay discovery must not expose the manual source picker',
      );
      expect(resolverCalls, 0);
      slowSource.complete(const [
        ReleaseCandidate(
          infoHash: '2222222222222222222222222222222222222222',
          magnetUri:
              'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
          releaseName: 'Better ranked result English Dub',
          seeders: 100,
          sourceId: 'slow',
          isDubbed: true,
          quality: '1080p',
          codec: 'H.264',
        ),
      ]);
      await _pumpUntilFound(tester, find.text('RANKED PLAYER OPENED'));

      expect(resolverCalls, 1);
      expect(opened?.selectedRelease.infoHash, startsWith('2222'));
      expect(neverWeb.isCompleted, isFalse);
    },
  );

  testWidgets(
    'autoplay debrid failover keeps provider and author affinity order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const exact = ReleaseCandidate(
        infoHash: '1111111111111111111111111111111111111111',
        magnetUri:
            'magnet:?xt=urn:btih:1111111111111111111111111111111111111111',
        releaseName: '[Same Group] Show - 02 English Dub',
        seeders: 1,
        sourceId: 'source-a',
        provider: 'Same Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const providerOnly = ReleaseCandidate(
        infoHash: '2222222222222222222222222222222222222222',
        magnetUri:
            'magnet:?xt=urn:btih:2222222222222222222222222222222222222222',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 500,
        sourceId: 'source-a',
        provider: 'Same Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const global = ReleaseCandidate(
        infoHash: '3333333333333333333333333333333333333333',
        magnetUri:
            'magnet:?xt=urn:btih:3333333333333333333333333333333333333333',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 5000,
        sourceId: 'source-b',
        provider: 'Other Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      final attempted = <String>[];
      PlaybackLaunch? opened;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Same Provider',
              preferredAuthor: 'Same Group',
              episode: EpisodeReference(
                anilistMediaId: 525252,
                title: 'Affinity Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('AFFINITY PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _ListReleaseSource([global, providerOnly, exact]),
            ),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator(const []),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              return _SourceAwareResolver(source, (candidate) {
                attempted.add(candidate.infoHash);
                return attempted.length < 3
                    ? const DebridCacheMissException(DebridService.realDebrid)
                    : null;
              });
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('AFFINITY PLAYER OPENED'));
      expect(attempted, [
        exact.infoHash,
        providerOnly.infoHash,
        global.infoHash,
      ]);
      expect(opened?.selectedRelease, global);
    },
  );

  testWidgets(
    'provider-only preferred debrid release opens while another source is pending',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
        'streaming_web_enabled': 'false',
      });
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final never = Completer<List<ReleaseCandidate>>();
      addTearDown(() {
        if (!never.isCompleted) never.complete(const []);
      });
      const exact = ReleaseCandidate(
        infoHash: 'dddddddddddddddddddddddddddddddddddddddd',
        magnetUri:
            'magnet:?xt=urn:btih:dddddddddddddddddddddddddddddddddddddddd',
        releaseName: 'Show - 02 English Dub',
        seeders: 1,
        sourceId: 'fast-source',
        provider: 'Same Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      var resolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Same Provider',
              episode: EpisodeReference(
                anilistMediaId: 525254,
                title: 'Immediate Affinity Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('IMMEDIATE DEBRID OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              CompositeReleaseSource([
                const _ListReleaseSource([exact]),
                _CallbackReleaseSource('never', () => never.future),
              ]),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('IMMEDIATE DEBRID OPENED'));
      expect(resolverCalls, 1);
      expect(never.isCompleted, isFalse);
      never.complete(const []);
      await tester.pump();
    },
  );

  testWidgets(
    'stable source affinity opens early when the provider identity changed',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
        'streaming_web_enabled': 'false',
      });
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final never = Completer<List<ReleaseCandidate>>();
      addTearDown(() {
        if (!never.isCompleted) never.complete(const []);
      });
      const stableSource = ReleaseCandidate(
        infoHash: 'abababababababababababababababababababab',
        magnetUri:
            'magnet:?xt=urn:btih:abababababababababababababababababababab',
        releaseName: '[Same Group] Show - 02 English Dub',
        seeders: 1,
        sourceId: 'stable-source-id',
        provider: 'Renamed Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      var resolverCalls = 0;
      PlaybackLaunch? opened;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Previous Provider Name',
              preferredSourceId: 'stable-source-id',
              preferredAuthor: 'Same Group',
              episode: EpisodeReference(
                anilistMediaId: 525257,
                title: 'Stable Source Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('STABLE SOURCE OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              CompositeReleaseSource([
                const _ListReleaseSource([stableSource]),
                _CallbackReleaseSource('never', () => never.future),
              ]),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('STABLE SOURCE OPENED'));
      expect(resolverCalls, 1);
      expect(opened!.selectedRelease, stableSource);
      expect(never.isCompleted, isFalse);
      never.complete(const []);
      await tester.pump();
    },
  );

  testWidgets(
    'failed early affinity release waits and never retries before fallback',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
        'streaming_web_enabled': 'false',
      });
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slow = Completer<List<ReleaseCandidate>>();
      const exact = ReleaseCandidate(
        infoHash: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        magnetUri:
            'magnet:?xt=urn:btih:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        releaseName: '[Same Group] Show - 02 English Dub',
        seeders: 1,
        sourceId: 'fast-source',
        provider: 'Same Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const fallback = ReleaseCandidate(
        infoHash: 'ffffffffffffffffffffffffffffffffffffffff',
        magnetUri:
            'magnet:?xt=urn:btih:ffffffffffffffffffffffffffffffffffffffff',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 100,
        sourceId: 'slow-source',
        provider: 'Other Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      final attempted = <String>[];
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Same Provider',
              preferredAuthor: 'Same Group',
              episode: EpisodeReference(
                anilistMediaId: 525255,
                title: 'Progressive Fallback Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('PROGRESSIVE FALLBACK OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              CompositeReleaseSource([
                const _ListReleaseSource([exact]),
                _CallbackReleaseSource('slow-source', () => slow.future),
              ]),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              return _SourceAwareResolver(source, (candidate) {
                attempted.add(candidate.infoHash);
                return candidate.infoHash == exact.infoHash
                    ? const DebridCacheMissException(DebridService.realDebrid)
                    : null;
              });
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text('That release failed. Waiting for other sources…'),
      );
      slow.complete(const [fallback]);
      await _pumpUntilFound(tester, find.text('PROGRESSIVE FALLBACK OPENED'));
      expect(attempted, [exact.infoHash, fallback.infoHash]);
    },
  );

  testWidgets(
    'debrid launch carries deduped affinity releases and raw web alternatives',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const selected = ReleaseCandidate(
        infoHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        magnetUri:
            'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        releaseName: '[Current Group] Show - 02 English Dub',
        seeders: 10,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const duplicate = ReleaseCandidate(
        infoHash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        magnetUri:
            'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        releaseName: '[Current Group] Duplicate English Dub',
        seeders: 1,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '720p',
        codec: 'H.264',
      );
      const sameProvider = ReleaseCandidate(
        infoHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        magnetUri:
            'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 2,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const global = ReleaseCandidate(
        infoHash: 'cccccccccccccccccccccccccccccccccccccccc',
        magnetUri:
            'magnet:?xt=urn:btih:cccccccccccccccccccccccccccccccccccccccc',
        releaseName: '[Global] Show - 02 English Dub',
        seeders: 2000,
        sourceId: 'other-source',
        provider: 'Other Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      final currentUriWeb = WebStreamResult(
        providerId: 'same-uri',
        providerName: 'Same URI Provider',
        title: 'Current URI duplicate',
        uri: Uri.parse('https://debrid.example.com/episode.mkv'),
        quality: '4K',
        isDubbed: true,
      );
      final web1080 = _providerWebStream(
        providerId: 'web-1080',
        providerName: 'Web 1080',
        quality: '1080p',
      );
      final web720 = _providerWebStream(
        providerId: 'web-720',
        providerName: 'Web 720',
        quality: '720p',
      );
      final web720Duplicate = WebStreamResult(
        providerId: web720.providerId,
        providerName: 'Duplicate Web 720',
        title: 'Duplicate Web 720',
        uri: web720.uri,
        quality: web720.quality,
        isDubbed: true,
      );
      PlaybackLaunch? opened;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Current Provider',
              preferredAuthor: 'Current Group',
              episode: EpisodeReference(
                anilistMediaId: 525253,
                title: 'Alternative Order Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('ALTERNATIVES OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _ListReleaseSource([
                global,
                duplicate,
                sameProvider,
                selected,
              ]),
            ),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator([
                web720,
                currentUriWeb,
                web720Duplicate,
                web1080,
              ]),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(
              ({required service, required token, required source}) =>
                  const _ReadyResolver(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('ALTERNATIVES OPENED'));
      expect(opened!.selectedRelease.infoHash, selected.infoHash);
      expect(
        opened!.alternatives.map((release) => release.infoHash.toLowerCase()),
        [sameProvider.infoHash, global.infoHash],
      );
      expect(
        opened!.directAlternatives.map((alternative) => alternative.stream.uri),
        [web1080.uri, web720.uri],
      );
      expect(
        opened!.directAlternatives.map(
          (alternative) => alternative.stream.providerId,
        ),
        ['web-1080', 'web-720'],
      );
    },
  );

  testWidgets(
    'web launch carries affinity debrid alternatives and selected service',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        DebridService.torBox.tokenStorageKey: 'valid-torbox-token',
        'settings_selected_debrid_provider': DebridService.torBox.slug,
      });
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const exact = ReleaseCandidate(
        infoHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        magnetUri:
            'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        releaseName: '[Current Group] Show - 02 English Dub',
        seeders: 1,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const duplicate = ReleaseCandidate(
        infoHash: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        magnetUri:
            'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        releaseName: '[Current Group] Duplicate English Dub',
        seeders: 500,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const sameProvider = ReleaseCandidate(
        infoHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        magnetUri:
            'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        releaseName: '[Other Group] Show - 02 English Dub',
        seeders: 100,
        sourceId: 'current-source',
        provider: 'Current Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      const global = ReleaseCandidate(
        infoHash: 'cccccccccccccccccccccccccccccccccccccccc',
        magnetUri:
            'magnet:?xt=urn:btih:cccccccccccccccccccccccccccccccccccccccc',
        releaseName: '[Global] Show - 02 English Dub',
        seeders: 5000,
        sourceId: 'other-source',
        provider: 'Other Provider',
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      );
      final preferredWeb = _providerWebStream(
        providerId: 'preferred-web',
        providerName: 'Preferred Web',
        quality: '1080p',
      );
      final sourceSearched = Completer<void>();
      final allowPreflight = Completer<void>();
      PlaybackLaunch? opened;
      String? playerDebrid;
      var debridResolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredProvider: 'Current Provider',
              preferredAuthor: 'Current Group',
              preferredWebProviderId: 'preferred-web',
              episode: EpisodeReference(
                anilistMediaId: 525256,
                title: 'Cross Class Alternatives Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              playerDebrid = state.uri.queryParameters['debrid'];
              return const Scaffold(body: Text('WEB WITH DEBRID OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              _CallbackReleaseSource('debrid-alternatives', () async {
                if (!sourceSearched.isCompleted) sourceSearched.complete();
                return const [global, duplicate, sameProvider, exact];
              }),
            ),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator([preferredWeb]),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              await allowPreflight.future;
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              debridResolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await sourceSearched.future;
      allowPreflight.complete();
      await _pumpUntilFound(tester, find.text('WEB WITH DEBRID OPENED'));
      expect(opened!.stream.isWebStream, isTrue);
      expect(playerDebrid, DebridService.torBox.slug);
      expect(debridResolverCalls, 0);
      expect(
        opened!.alternatives.map((release) => release.infoHash.toLowerCase()),
        [exact.infoHash, sameProvider.infoHash, global.infoHash],
      );
    },
  );

  testWidgets(
    'web autoplay uses highest quality when preferred language is unavailable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _NoopAddonStore();
      final webAggregator = _FixedWebAggregator([
        _webStream('480p'),
        _webStream('1080p'),
      ]);
      Uri? preflightUri;
      PlaybackLaunch? launch;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 424242,
                title: 'Sub-only Show',
                episode: 1,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              launch = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('WEB PLAYER OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(store),
            webStreamAggregatorProvider.overrideWithValue(webAggregator),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              preflightUri = uri;
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('WEB PLAYER OPENED'));
      expect(preflightUri, Uri.parse('https://cdn.example.com/1080p.m3u8'));
      expect(launch!.stream.uri, preflightUri);
    },
  );

  testWidgets(
    'web autoplay waits for the preferred provider instead of opening an early result',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final other = _providerWebStream(
        providerId: 'other-provider',
        providerName: 'Other Provider',
        quality: '4K',
      );
      final preferred = _providerWebStream(
        providerId: 'preferred-provider',
        providerName: 'Preferred Provider',
        quality: '720p',
      );
      final sameProviderAlternative = _providerWebStream(
        providerId: 'preferred-provider',
        providerName: 'Preferred Provider',
        quality: '480p',
      );
      final preflighted = <Uri>[];
      PlaybackLaunch? opened;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'preferred-provider',
              episode: EpisodeReference(
                anilistMediaId: 535353,
                title: 'Preferred Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              opened = state.extra! as PlaybackLaunch;
              return const Scaffold(body: Text('PREFERRED WEB OPENED'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _ProgressiveWebAggregator(
                first: [other],
                completed: [other, preferred, sameProviderAlternative],
                gate: gate.future,
              ),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              preflighted.add(uri);
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Web 1/2'));
      expect(preflighted, isEmpty);
      expect(find.text(other.title), findsNothing);
      gate.complete();
      await _pumpUntilFound(tester, find.text('PREFERRED WEB OPENED'));
      expect(preflighted, [preferred.uri]);
      expect(
        opened!.directAlternatives.map(
          (alternative) => alternative.stream.providerId,
        ),
        ['preferred-provider', 'other-provider'],
      );
      expect(
        opened!.directAlternatives.map((alternative) => alternative.stream.uri),
        isNot(contains(preferred.uri)),
      );
    },
  );

  testWidgets(
    'preferred web discovery wait is bounded before opening another provider',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final fallback = _providerWebStream(
        providerId: 'available-provider',
        providerName: 'Available Provider',
        quality: '1080p',
      );
      final preflighted = <Uri>[];
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'provider-that-never-responds',
              episode: EpisodeReference(
                anilistMediaId: 535356,
                title: 'Bounded Preferred Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('BOUNDED WEB FALLBACK OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _ManyPendingWebAggregator(available: fallback, gate: gate.future),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              preflighted.add(uri);
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Web 1/20'));
      await tester.pump(const Duration(seconds: 11));
      expect(preflighted, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await _pumpUntilFound(tester, find.text('BOUNDED WEB FALLBACK OPENED'));
      expect(preflighted, [fallback.uri]);
      expect(gate.isCompleted, isFalse);
      gate.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'bounded preferred-provider fallback failure stays out of manual picker',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final fallback = _providerWebStream(
        providerId: 'rejected-provider',
        providerName: 'Rejected Provider',
        quality: '1080p',
      );
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'provider-that-never-responds',
              episode: EpisodeReference(
                anilistMediaId: 535357,
                title: 'Bounded Failed Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _ManyPendingWebAggregator(available: fallback, gate: gate.future),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              throw const FormatException('fallback rejected');
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Web 1/20'));
      await tester.pump(const Duration(seconds: 13));
      await _pumpUntilFound(tester, find.text('No playable stream found'));
      expect(find.text('Choose your stream'), findsNothing);
      expect(find.text(fallback.title), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      gate.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'exact preferred web provider opens while an unrelated debrid source is pending',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final never = Completer<List<ReleaseCandidate>>();
      addTearDown(() {
        if (!never.isCompleted) never.complete(const []);
      });
      final preferred = _providerWebStream(
        providerId: 'preferred-provider',
        providerName: 'Preferred Provider',
        quality: '1080p',
      );
      var debridResolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'preferred-provider',
              episode: EpisodeReference(
                anilistMediaId: 535354,
                title: 'Immediate Preferred Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('IMMEDIATE WEB OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              _CallbackReleaseSource('never', () => never.future),
            ),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator([preferred]),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              debridResolverCalls++;
              return const _ReadyResolver();
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('IMMEDIATE WEB OPENED'));
      expect(debridResolverCalls, 0);
      expect(never.isCompleted, isFalse);
      never.complete(const []);
      await tester.pump();
    },
  );

  testWidgets(
    'preferred web provider fast path never overrides preferred audio',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final preferredSub = _providerWebStream(
        providerId: 'preferred-provider',
        providerName: 'Preferred Provider',
        quality: '1080p',
        isDubbed: false,
      );
      final otherDub = _providerWebStream(
        providerId: 'dub-provider',
        providerName: 'Dub Provider',
        quality: '720p',
      );
      final preflighted = <Uri>[];
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'preferred-provider',
              episode: EpisodeReference(
                anilistMediaId: 535355,
                title: 'Audio Safe Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('AUDIO SAFE WEB OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _ProgressiveWebAggregator(
                first: [preferredSub],
                completed: [preferredSub, otherDub],
                gate: gate.future,
              ),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              preflighted.add(uri);
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Web 1/2'));
      expect(preflighted, isEmpty);
      gate.complete();
      await _pumpUntilFound(tester, find.text('AUDIO SAFE WEB OPENED'));
      expect(preflighted, [otherDub.uri]);
    },
  );

  testWidgets(
    'failed preferred web provider waits, then falls through without looping',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final preferred = _providerWebStream(
        providerId: 'preferred-provider',
        providerName: 'Preferred Provider',
        quality: '1080p',
      );
      final fallback = _providerWebStream(
        providerId: 'fallback-provider',
        providerName: 'Fallback Provider',
        quality: '720p',
      );
      final preflighted = <Uri>[];
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              preferredWebProviderId: 'preferred-provider',
              episode: EpisodeReference(
                anilistMediaId: 545454,
                title: 'Preferred Failure Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) =>
                const Scaffold(body: Text('WEB FALLBACK OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _ProgressiveWebAggregator(
                first: [preferred],
                completed: [preferred, fallback],
                gate: gate.future,
              ),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              preflighted.add(uri);
              if (uri == preferred.uri) {
                throw const FormatException('preferred stream rejected');
              }
              return ValidatedWebStream(
                uri: uri,
                headers: headers,
                contentType: 'application/vnd.apple.mpegurl',
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text('Waiting for the remaining web providers…'),
      );
      expect(preflighted, [preferred.uri]);
      gate.complete();
      await _pumpUntilFound(tester, find.text('WEB FALLBACK OPENED'));
      expect(preflighted, [preferred.uri, fallback.uri]);
    },
  );

  testWidgets('debrid autoplay exhaustion falls through to a web stream', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final web = _providerWebStream(
      providerId: 'web-fallback',
      providerName: 'Web Fallback',
      quality: '1080p',
    );
    var debridCalls = 0;
    final router = GoRouter(
      initialLocation: '/resolve',
      routes: [
        GoRoute(
          path: '/resolve',
          builder: (_, _) => const ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 555555,
              title: 'Debrid Fallback Show',
              episode: 2,
              autoPlay: true,
            ),
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (_, state) => Scaffold(
            body: Text(
              (state.extra! as PlaybackLaunch).stream.isWebStream
                  ? 'DEBRID TO WEB OPENED'
                  : 'WRONG STREAM',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _FakeReleaseSource(),
          ),
          addonStoreProvider.overrideWithValue(_NoopAddonStore()),
          webStreamAggregatorProvider.overrideWithValue(
            _FixedWebAggregator([web]),
          ),
          webStreamPreflightProvider.overrideWithValue((
            uri,
            headers, {
            subtitleUri,
          }) async {
            return ValidatedWebStream(
              uri: uri,
              headers: headers,
              contentType: 'application/vnd.apple.mpegurl',
            );
          }),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            debridCalls++;
            return const _ErrorResolver(
              DebridCacheMissException(DebridService.realDebrid),
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await _pumpUntilFound(tester, find.text('DEBRID TO WEB OPENED'));
    expect(debridCalls, 1);
  });

  testWidgets('late web preflight completion never reads a disposed ref', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preflight = Completer<ValidatedWebStream>();
    final stream = _webStream('1080p');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(null),
          addonStoreProvider.overrideWithValue(_NoopAddonStore()),
          webStreamAggregatorProvider.overrideWithValue(
            _FixedWebAggregator([stream]),
          ),
          webStreamPreflightProvider.overrideWithValue(
            (uri, headers, {subtitleUri}) => preflight.future,
          ),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 424243,
              title: 'Disposed Resolver',
              episode: 1,
              autoPlay: true,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.textContaining('Checking Provider'));
    // Simulate backing out while the provider preflight request is in flight.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    preflight.complete(
      ValidatedWebStream(
        uri: stream.uri,
        headers: stream.headers,
        contentType: 'application/vnd.apple.mpegurl',
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'autoplay no-result state offers Back and Retry without opening magnet input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _ListReleaseSource([]),
            ),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator(const []),
            ),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 565656,
                title: 'No Results Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('No playable stream found'));
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Magnet URI'), findsNothing);
      expect(find.text('Send to Real-Debrid'), findsNothing);
    },
  );

  testWidgets('terminal Retry forces a fresh web-provider session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recovered = _providerWebStream(
      providerId: 'retry-provider',
      providerName: 'Retry Provider',
      quality: '1080p',
    );
    final aggregator = _RefreshAwareWebAggregator(recovered);
    final router = GoRouter(
      initialLocation: '/resolve',
      routes: [
        GoRoute(
          path: '/resolve',
          builder: (_, _) => const ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 565657,
              title: 'Retry Show',
              episode: 2,
              autoPlay: true,
            ),
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (_, _) => const Scaffold(body: Text('REFRESHED WEB OPENED')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _ListReleaseSource([]),
          ),
          addonStoreProvider.overrideWithValue(_NoopAddonStore()),
          webStreamAggregatorProvider.overrideWithValue(aggregator),
          webStreamPreflightProvider.overrideWithValue((
            uri,
            headers, {
            subtitleUri,
          }) async {
            return ValidatedWebStream(
              uri: uri,
              headers: headers,
              contentType: 'application/vnd.apple.mpegurl',
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await _pumpUntilFound(tester, find.text('No playable stream found'));
    await tester.tap(find.text('Retry'));
    await _pumpUntilFound(tester, find.text('REFRESHED WEB OPENED'));
    expect(aggregator.refreshValues, [false, true]);
  });

  testWidgets(
    'debrid cache miss with Web disabled never opens the manual picker',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        DebridService.realDebrid.tokenStorageKey: 'valid-manual-token',
        'streaming_web_enabled': 'false',
      });
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              return const _ErrorResolver(
                DebridCacheMissException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 565658,
                title: 'No Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('No playable stream found'));
      expect(find.text('Choose your stream'), findsNothing);
      expect(find.text('Magnet URI'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'debrid exhaustion plus completed empty Web reaches terminal state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator(const []),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              return const _ErrorResolver(
                DebridCacheMissException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 565659,
                title: 'Empty Web Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('No playable stream found'));
      expect(find.text('Choose your stream'), findsNothing);
      expect(find.text('Magnet URI'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'exhausted debrid and web autoplay reaches a stable terminal state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final web = _providerWebStream(
        providerId: 'only-web',
        providerName: 'Only Web',
        quality: '1080p',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _FakeReleaseSource(),
            ),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator([web]),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) async {
              throw const FormatException('web stream rejected');
            }),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              return const _ErrorResolver(
                DebridCacheMissException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 575757,
                title: 'Everything Failed Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('No playable stream found'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No playable stream found'), findsOneWidget);
      expect(find.text('Trying another stream…'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Magnet URI'), findsNothing);
    },
  );

  testWidgets(
    'expired web autoplay budget reaches terminal without retry loop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = _providerWebStream(
        providerId: 'slow-provider',
        providerName: 'Slow Provider',
        quality: '1080p',
      );
      final remaining = _providerWebStream(
        providerId: 'remaining-provider',
        providerName: 'Remaining Provider',
        quality: '720p',
      );
      var now = DateTime.utc(2026, 8, 13);
      final preflight = Completer<ValidatedWebStream>();
      var preflightCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(null),
            addonStoreProvider.overrideWithValue(_NoopAddonStore()),
            webStreamAggregatorProvider.overrideWithValue(
              _FixedWebAggregator([first, remaining]),
            ),
            webStreamPreflightProvider.overrideWithValue((
              uri,
              headers, {
              subtitleUri,
            }) {
              preflightCalls++;
              return preflight.future;
            }),
          ],
          child: MaterialApp(
            home: ResolveEpisodeScreen(
              clock: () => now,
              episode: EpisodeReference(
                anilistMediaId: 585858,
                title: 'Budget Show',
                episode: 2,
                autoPlay: true,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.textContaining('Checking'));
      now = now.add(const Duration(seconds: 46));
      preflight.completeError(
        const FormatException('slow stream rejected'),
        StackTrace.current,
      );
      await tester.pump();
      await _pumpUntilFound(tester, find.text('No playable stream found'));
      await tester.pump(const Duration(seconds: 2));
      expect(preflightCalls, 1);
      expect(find.text('No playable stream found'), findsOneWidget);
      expect(find.text('Trying another stream…'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('web autoplay preflights at most eight unique candidates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final streams = [
      for (var index = 0; index < 9; index++)
        _providerWebStream(
          providerId: 'provider-$index',
          providerName: 'Provider $index',
          quality: '${1080 - index}p',
        ),
    ];
    var preflightCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(null),
          addonStoreProvider.overrideWithValue(_NoopAddonStore()),
          webStreamAggregatorProvider.overrideWithValue(
            _FixedWebAggregator(streams),
          ),
          webStreamPreflightProvider.overrideWithValue((
            uri,
            headers, {
            subtitleUri,
          }) async {
            preflightCalls++;
            throw const FormatException('stream rejected');
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 585859,
              title: 'Bounded Web Show',
              episode: 2,
              autoPlay: true,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('No playable stream found'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(preflightCalls, 8);
    expect(find.text('No playable stream found'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'release-specific failures continue through the fifth unique candidate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;
      final router = GoRouter(
        initialLocation: '/resolve',
        routes: [
          GoRoute(
            path: '/resolve',
            builder: (_, _) => const ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) => const Scaffold(body: Text('PLAYER OPENED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(5),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return resolverCalls == 5
                  ? const _ReadyResolver()
                  : _ErrorResolver(
                      RealDebridException.fromApi(code: 35, httpStatus: 403),
                    );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 5'));
      await tester.tap(find.text('Release 5'));
      await _pumpUntilFound(tester, find.text('PLAYER OPENED'));

      expect(resolverCalls, 5);
    },
  );

  testWidgets('release exhaustion reports the aggregate failure safely', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(3),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(
              RealDebridException.fromApi(code: 35, httpStatus: 403),
            );
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 3'));
    await tester.tap(find.text('Release 3'));
    await _pumpUntilFound(
      tester,
      find.textContaining('could not provide 3 different releases'),
    );

    expect(resolverCalls, 3);
    expect(find.textContaining('infringing_file'), findsNothing);
  });

  testWidgets(
    'uncached Real-Debrid releases report that no download was kept',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(3),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ErrorResolver(
                DebridCacheMissException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 3'));
      await tester.tap(find.text('Release 3'));
      await _pumpUntilFound(
        tester,
        find.textContaining('No instantly cached Real-Debrid stream was found'),
      );

      expect(resolverCalls, 3);
      expect(find.textContaining('did not leave an uncached'), findsOneWidget);
    },
  );

  testWidgets('terminal Real-Debrid authorization failure stops failover', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(5),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(
              RealDebridException.fromApi(code: 8, httpStatus: 401),
            );
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 5'));
    await tester.tap(find.text('Release 5'));
    await _pumpUntilFound(tester, find.textContaining('Reconnect it'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(resolverCalls, 1);
    expect(find.textContaining('infringing_file'), findsNothing);
  });

  testWidgets(
    'terminal debrid cleanup failure stops failover and names the dashboard',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resolverCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configuredReleaseSourceProvider.overrideWithValue(
              const _RankedReleaseSource(5),
            ),
            debridStreamResolverFactoryProvider.overrideWithValue(({
              required service,
              required token,
              required source,
            }) {
              resolverCalls++;
              return const _ErrorResolver(
                DebridCleanupFailureException(DebridService.realDebrid),
              );
            }),
          ],
          child: const MaterialApp(
            home: ResolveEpisodeScreen(
              episode: EpisodeReference(
                anilistMediaId: 42,
                title: 'Example Show',
                episode: 1,
              ),
            ),
          ),
        ),
      );

      await _pumpUntilFound(tester, find.text('Release 5'));
      await tester.tap(find.text('Release 5'));
      await _pumpUntilFound(
        tester,
        find.textContaining('Check your Real-Debrid dashboard'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(resolverCalls, 1);
      expect(find.textContaining('Automatic failover stopped'), findsOneWidget);
    },
  );

  testWidgets('Real-Debrid rate limiting does not fan out across releases', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var resolverCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configuredReleaseSourceProvider.overrideWithValue(
            const _RankedReleaseSource(5),
          ),
          debridStreamResolverFactoryProvider.overrideWithValue(({
            required service,
            required token,
            required source,
          }) {
            resolverCalls++;
            return _ErrorResolver(RealDebridException.fromApi(code: 34));
          }),
        ],
        child: const MaterialApp(
          home: ResolveEpisodeScreen(
            episode: EpisodeReference(
              anilistMediaId: 42,
              title: 'Example Show',
              episode: 1,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Release 5'));
    await tester.tap(find.text('Release 5'));
    await _pumpUntilFound(tester, find.textContaining('too many requests'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(resolverCalls, 1);
  });

  for (final testCase
      in <
        ({
          DebridService service,
          DebridProviderFailure error,
          String expectedMessage,
        })
      >[
        (
          service: DebridService.realDebrid,
          error: RealDebridException.fromApi(code: 8, httpStatus: 401),
          expectedMessage: 'Reconnect it',
        ),
        (
          service: DebridService.torBox,
          error: const TorBoxException(
            'TorBox token expired',
            code: 'AUTH_ERROR',
          ),
          expectedMessage: 'TorBox token expired',
        ),
        (
          service: DebridService.premiumize,
          error: const PremiumizeException(
            'Premiumize token expired',
            code: 'authentication_failed',
          ),
          expectedMessage: 'Premiumize token expired',
        ),
        (
          service: DebridService.allDebrid,
          error: const AllDebridException(
            'AllDebrid token expired',
            code: 'AUTH_BAD_APIKEY',
          ),
          expectedMessage: 'AllDebrid token expired',
        ),
      ]) {
    testWidgets(
      '${testCase.service.displayName} terminal provider errors stop Resolve '
      'candidate fan-out',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          testCase.service.tokenStorageKey: 'provider-token',
        });
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var resolverCalls = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              configuredReleaseSourceProvider.overrideWithValue(
                const _RankedReleaseSource(5),
              ),
              debridStreamResolverFactoryProvider.overrideWithValue(({
                required service,
                required token,
                required source,
              }) {
                expect(service, testCase.service);
                resolverCalls++;
                return _ErrorResolver(testCase.error);
              }),
            ],
            child: const MaterialApp(
              home: ResolveEpisodeScreen(
                episode: EpisodeReference(
                  anilistMediaId: 42,
                  title: 'Example Show',
                  episode: 1,
                ),
              ),
            ),
          ),
        );

        await _pumpUntilFound(tester, find.text('Release 5'));
        await tester.tap(find.text('Release 5'));
        await _pumpUntilFound(
          tester,
          find.textContaining(testCase.expectedMessage),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(resolverCalls, 1);
      },
    );
  }

  test(
    'stream filters distinguish language, quality, codec, HDR and batches',
    () {
      const release = ReleaseCandidate(
        infoHash: 'hash',
        magnetUri: 'magnet:?xt=urn:btih:hash',
        releaseName: 'Show S01 2160p HEVC HDR Dual Audio Batch',
        seeders: 50,
        sourceId: 'test',
        isDubbed: true,
        isBatch: true,
        isHdr: true,
        quality: '2160p',
        codec: 'HEVC',
      );

      expect(
        releaseMatchesStreamFilters(
          release,
          language: 'dub',
          quality: 'p2160',
          codec: 'hevc',
          hdr: 'hdr',
        ),
        isTrue,
      );
      expect(
        releaseMatchesStreamFilters(release, language: 'sub'),
        isTrue,
        reason: 'dual-audio files contain a usable original-language track',
      );
      expect(releaseMatchesStreamFilters(release, allowBatch: false), isFalse);
    },
  );

  test('preferred language is ranked before provider affinity on fallback', () {
    const dubbed = ReleaseCandidate(
      infoHash: 'dub',
      magnetUri: 'magnet:?xt=urn:btih:dub',
      releaseName: '[Other] Show 01 English Dub',
      seeders: 1,
      sourceId: 'other',
      isDubbed: true,
    );
    const subtitled = ReleaseCandidate(
      infoHash: 'sub',
      magnetUri: 'magnet:?xt=urn:btih:sub',
      releaseName: '[Preferred] Show 01',
      seeders: 500,
      sourceId: 'preferred',
      provider: 'Preferred provider',
    );

    expect(
      compareStreamReleases(
        dubbed,
        subtitled,
        preferredProvider: 'Preferred provider',
        preferredAudio: PlaybackAudioPreference.dub,
      ),
      lessThan(0),
    );
  });

  test('web qualities are ranked from highest to lowest', () {
    final streams = [
      _webStream('Auto'),
      _webStream('720p'),
      _webStream('4K UHD'),
      _webStream('1080p'),
    ]..sort(compareWebStreamsByQuality);

    expect(streams.map((item) => item.title), [
      '4K UHD',
      '1080p',
      '720p',
      'Auto',
    ]);
  });

  test('cached-only exhaustion message covers every debrid service', () {
    for (final service in DebridService.values) {
      final message = debridCacheExhaustedMessage(service, 3);
      expect(message, contains(service.displayName));
      expect(message, contains('3 releases'));
      expect(message, contains('did not leave an uncached cloud download'));
    }
  });
}

WebStreamResult _webStream(String quality) => WebStreamResult(
  providerId: quality,
  providerName: 'Provider',
  title: quality,
  uri: Uri.parse('https://cdn.example.com/$quality.m3u8'),
  quality: quality,
);

WebStreamResult _providerWebStream({
  required String providerId,
  required String providerName,
  required String quality,
  bool isDubbed = true,
}) => WebStreamResult(
  providerId: providerId,
  providerName: providerName,
  title: '$providerName $quality',
  uri: Uri.parse(
    'https://cdn.example.com/$providerId/${Uri.encodeComponent(quality)}.m3u8',
  ),
  quality: quality,
  isDubbed: isDubbed,
);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

class _FakeReleaseSource implements ReleaseSource {
  const _FakeReleaseSource();

  @override
  String get id => 'fake';

  @override
  Future<List<ReleaseCandidate>> search(
    EpisodeReference episode,
  ) async => const [
    ReleaseCandidate(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      magnetUri: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      releaseName: 'Dubbed release',
      seeders: 10,
      sourceId: 'fake',
      isDubbed: true,
      quality: '1080p',
      codec: 'H.264',
    ),
  ];
}

class _CallbackReleaseSource implements ReleaseSource {
  const _CallbackReleaseSource(this.id, this.callback);

  @override
  final String id;
  final Future<List<ReleaseCandidate>> Function() callback;

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) => callback();
}

class _ListReleaseSource implements ReleaseSource {
  const _ListReleaseSource(this.releases);

  final List<ReleaseCandidate> releases;

  @override
  String get id => 'list';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async =>
      releases;
}

class _RankedReleaseSource implements ReleaseSource {
  const _RankedReleaseSource(this.count);

  final int count;

  @override
  String get id => 'ranked';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async => [
    for (var index = 1; index <= count; index++)
      ReleaseCandidate(
        infoHash: index.toString().padLeft(40, '0'),
        magnetUri: 'magnet:?xt=urn:btih:${index.toString().padLeft(40, '0')}',
        releaseName: 'Release $index',
        seeders: index,
        sourceId: id,
        isDubbed: true,
        quality: '1080p',
        codec: 'H.264',
      ),
  ];
}

class _FailingResolver implements StreamResolver {
  const _FailingResolver(this.failWhenReleased);

  final Future<void> failWhenReleased;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    await failWhenReleased;
    throw StateError('Release unavailable');
  }
}

class _ReadyResolver implements StreamResolver {
  const _ReadyResolver();

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    yield StreamReady(
      uri: Uri.parse('https://debrid.example.com/episode.mkv'),
      displayName: 'Ready',
      debridService: DebridService.realDebrid,
    );
  }
}

class _SourceAwareResolver implements StreamResolver {
  const _SourceAwareResolver(this.source, this.errorForCandidate);

  final ReleaseSource source;
  final Object? Function(ReleaseCandidate candidate) errorForCandidate;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    final candidate = (await source.search(episode)).single;
    final error = errorForCandidate(candidate);
    if (error != null) throw error;
    yield StreamReady(
      uri: Uri.parse('https://debrid.example.com/${candidate.infoHash}.mkv'),
      displayName: candidate.releaseName,
      debridService: DebridService.realDebrid,
    );
  }
}

class _ErrorResolver implements StreamResolver {
  const _ErrorResolver(this.error);

  final Object error;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    throw error;
  }
}

class _NeverCompletingWebAggregator extends WebStreamAggregator {
  _NeverCompletingWebAggregator(this.never)
    : super(AddonStore(TetoTvDatabase.instance));

  final Future<void> never;
  int searchCalls = 0;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    searchCalls++;
    yield const WebStreamSearchProgress(
      totalProviders: 1,
      pendingProviderNames: ['Never finishes'],
    );
    await never;
  }
}

class _FixedWebAggregator extends WebStreamAggregator {
  _FixedWebAggregator(this.streams)
    : super(AddonStore(TetoTvDatabase.instance));

  final List<WebStreamResult> streams;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(streams: streams),
      completedProviders: 1,
      totalProviders: 1,
    );
  }
}

class _ProgressiveWebAggregator extends WebStreamAggregator {
  _ProgressiveWebAggregator({
    required this.first,
    required this.completed,
    required this.gate,
  }) : super(AddonStore(TetoTvDatabase.instance));

  final List<WebStreamResult> first;
  final List<WebStreamResult> completed;
  final Future<void> gate;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(streams: first),
      completedProviders: 1,
      totalProviders: 2,
      pendingProviderNames: const ['Remaining provider'],
    );
    await gate;
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(streams: completed),
      completedProviders: 2,
      totalProviders: 2,
    );
  }
}

class _ManyPendingWebAggregator extends WebStreamAggregator {
  _ManyPendingWebAggregator({required this.available, required this.gate})
    : super(AddonStore(TetoTvDatabase.instance));

  final WebStreamResult available;
  final Future<void> gate;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(streams: [available]),
      completedProviders: 1,
      totalProviders: 20,
      pendingProviderNames: const [
        'Preferred provider',
        'Provider 3',
        'Provider 4',
        'Provider 5',
        'Provider 6',
        'Provider 7',
        'Provider 8',
        'Provider 9',
        'Provider 10',
        'Provider 11',
        'Provider 12',
        'Provider 13',
        'Provider 14',
        'Provider 15',
        'Provider 16',
        'Provider 17',
        'Provider 18',
        'Provider 19',
        'Provider 20',
      ],
    );
    await gate;
  }
}

class _RefreshAwareWebAggregator extends WebStreamAggregator {
  _RefreshAwareWebAggregator(this.recovered)
    : super(AddonStore(TetoTvDatabase.instance));

  final WebStreamResult recovered;
  final List<bool> refreshValues = [];

  @override
  Stream<WebStreamSearchProgress> watchSearchIncrementally(
    EpisodeReference episode, {
    bool refresh = false,
  }) async* {
    refreshValues.add(refresh);
    yield WebStreamSearchProgress(
      aggregation: WebStreamAggregation(
        streams: refresh ? [recovered] : const [],
      ),
      completedProviders: 1,
      totalProviders: 1,
    );
  }
}

class _NoopAddonStore extends AddonStore {
  _NoopAddonStore() : super(TetoTvDatabase.instance);

  @override
  Future<void> recordProviderSuccess(String id) async {}

  @override
  Future<ProviderHealth> recordProviderFailure(String id, Object error) async =>
      ProviderHealth(providerId: id);
}
