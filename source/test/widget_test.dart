import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/core/layout/interface_scaling.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/home/presentation/home_screen.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses denser canvases as physical TV resolution increases', () {
    expect(tvCanvasWidthForPhysicalPixels(1920), 960);
    expect(tvCanvasWidthForPhysicalPixels(2560), 1280);
    expect(tvCanvasWidthForPhysicalPixels(3840), 1600);
  });

  testWidgets('renders the TV home shell', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const TetoTvApp(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('main-nav-wordmark')), findsOneWidget);
    expect(find.text('Teto'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Watch now'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('renders the home shell without overflow on a phone', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Continue watching'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double activating the in-app Home action refreshes shelves', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var trendingLoads = 0;
    var seasonalLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async {
            trendingLoads++;
            return const [];
          }),
          seasonalAnimeProvider.overrideWith((_) async {
            seasonalLoads++;
            return const [];
          }),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'home.navigation.home',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(trendingLoads, greaterThan(1));
    expect(seasonalLoads, greaterThan(1));
  });

  testWidgets(
    'ten rapid Home activations drop, shake, and hold for ten seconds',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingAnimeProvider.overrideWith((_) async => const []),
            seasonalAnimeProvider.overrideWith((_) async => const []),
            trackingHomeProvider.overrideWith(
              (_) async => const TrackingHomeData(
                watching: [],
                planToWatch: [],
                completed: [],
              ),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      final home = find.byIcon(Icons.home_rounded);
      for (var activation = 0; activation < 9; activation++) {
        await tester.tap(home);
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byKey(const ValueKey('home.easter-egg.image')), findsNothing);

      await tester.tap(home);
      await tester.pump();

      final image = find.byKey(const ValueKey('home.easter-egg.image'));
      final region = find.byKey(const ValueKey('home.easter-egg.region'));
      expect(image, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.widget<Image>(image).image,
        isA<AssetImage>().having(
          (asset) => asset.assetName,
          'asset name',
          'assets/easter_egg/teto_plush.png',
        ),
      );
      expect(tester.getSize(region), const Size(1280, 360));
      expect(tester.getBottomRight(region).dy, lessThan(0));
      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(const ValueKey('home.easter-egg.ignore-pointer')),
            )
            .ignoring,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 850));
      final impactMotion = tester.widget<FractionalTranslation>(
        find.byKey(const ValueKey('home.easter-egg-motion')),
      );
      expect(impactMotion.translation.dx.abs(), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getBottomRight(region).dy, 720);
      await tester.pump(const Duration(milliseconds: 8649));
      expect(image, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(image, findsNothing);
    },
  );

  testWidgets('Android bridge bounds the decoration audio to ten seconds', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('dev.tetotv/android_tv');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      await AndroidTvBridge.instance.playHomeEasterEgg();
      await AndroidTvBridge.instance.stopHomeEasterEgg();

      expect(calls.map((call) => call.method), [
        'playHomeEasterEgg',
        'stopHomeEasterEgg',
      ]);
      expect(
        (calls.first.arguments as Map<Object?, Object?>)['maximumDurationMs'],
        10000,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('holding an unwatched Home shelf card opens status actions', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const hero = AnimeSummary(
      id: 1,
      title: 'Featured title',
      description: '',
      episodes: 12,
      score: null,
    );
    const unwatched = AnimeSummary(
      id: 2,
      idMal: 22,
      title: 'Unwatched trending title',
      description: '',
      episodes: 12,
      score: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async => [hero, unwatched]),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Unwatched trending title'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Unwatched trending title'));
    await tester.pumpAndSettle();

    expect(find.text('Planning'), findsOneWidget);
    expect(
      find.text(
        'Add or update this show on your connected AniList and MAL accounts.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('featured carousel rotates the title and matching metadata', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const first = AnimeSummary(
      id: 1,
      title: 'First Trending Show',
      description: 'First description',
      episodes: 12,
      score: 7.1,
      seasonYear: 2025,
    );
    const second = AnimeSummary(
      id: 2,
      title: 'Second Trending Show',
      description: 'Second description',
      episodes: 24,
      score: 8.8,
      seasonYear: 2026,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async => [first, second]),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('First Trending Show'), findsOneWidget);
    expect(find.text('First description'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Second Trending Show'), findsWidgets);
    expect(find.text('Second description'), findsOneWidget);
    expect(find.text('First description'), findsNothing);
  });

  testWidgets('featured carousel uses cover art when a banner is missing', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const cover = 'https://example.test/fallback-cover.jpg';
    const hero = AnimeSummary(
      id: 71,
      title: 'Cover-only hero',
      description: 'Still has artwork',
      coverImageUrl: cover,
      episodes: null,
      score: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) async => const [hero]),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final artwork = tester.widget<NetworkArtwork>(
      find.byKey(const ValueKey('hero-art-71')),
    );
    expect(artwork.url, cover);
  });

  testWidgets('home artwork keeps a fixed height across title lengths', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const hero = AnimeSummary(
      id: 1,
      title: 'Hero',
      description: 'Hero',
      episodes: null,
      score: null,
    );
    const short = AnimeSummary(
      id: 2,
      title: 'Short',
      description: 'Short',
      episodes: null,
      score: null,
    );
    const long = AnimeSummary(
      id: 3,
      title: 'A much longer title that needs the reserved second line',
      description: 'Long',
      episodes: null,
      score: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith(
            (_) async => const [hero, short, long],
          ),
          seasonalAnimeProvider.overrideWith((_) async => const []),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final shortArtwork = find.byKey(const ValueKey('home-artwork-2'));
    final longArtwork = find.byKey(const ValueKey('home-artwork-3'));
    final heroPanel = find.byKey(const ValueKey('home-hero'));
    expect(shortArtwork, findsOneWidget);
    expect(longArtwork, findsOneWidget);
    expect(heroPanel, findsOneWidget);
    expect(tester.getTopLeft(find.byType(Scaffold).first), Offset.zero);
    expect(tester.getSize(find.byType(Scaffold).first).width, 1280);
    expect(tester.getTopLeft(heroPanel).dx, 34);
    expect(tester.getSize(heroPanel).width, 1212);
    expect(
      tester.getSize(shortArtwork).height,
      tester.getSize(longArtwork).height,
    );
  });

  testWidgets(
    'continue watching merges tracker titles with local resume precedence',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final checkpoint = PlaybackCheckpoint(
        anilistMediaId: 101,
        malMediaId: 202,
        episode: 4,
        title: 'Local resume wins',
        position: const Duration(minutes: 8),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime(2026, 8, 9),
      );
      const watching = [
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 101,
            title: 'AniList duplicate must be hidden',
            status: TrackingListStatus.watching,
            progress: 3,
          ),
          provider: TrackingProvider.anilist,
          anilistId: 101,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 202,
            title: 'MAL duplicate must be hidden',
            status: TrackingListStatus.watching,
            progress: 3,
          ),
          provider: TrackingProvider.myAnimeList,
          anilistId: null,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 303,
            title: 'Distinct AniList title remains',
            status: TrackingListStatus.watching,
            progress: 2,
          ),
          provider: TrackingProvider.anilist,
          anilistId: 303,
          coverImageUrl: null,
        ),
        HomeTrackedAnime(
          tracked: TrackedAnime(
            mediaId: 404,
            title: 'Distinct MAL title remains',
            status: TrackingListStatus.watching,
            progress: 1,
          ),
          provider: TrackingProvider.myAnimeList,
          anilistId: null,
          coverImageUrl: null,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingAnimeProvider.overrideWith((_) async => const []),
            seasonalAnimeProvider.overrideWith((_) async => const []),
            trackingHomeProvider.overrideWith(
              (_) async => const TrackingHomeData(
                watching: watching,
                planToWatch: [],
                completed: [],
              ),
            ),
            recentPlaybackProvider.overrideWith((_) async => [checkpoint]),
            dismissedContinueWatchingProvider.overrideWith(
              (_) async => const <int>{},
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Local resume wins'), findsWidgets);
      expect(find.text('AniList duplicate must be hidden'), findsNothing);
      expect(find.text('MAL duplicate must be hidden'), findsNothing);
      expect(find.text('Distinct AniList title remains'), findsOneWidget);
      expect(find.text('Distinct MAL title remains'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fresh installs open setup and can skip it', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trendingAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          seasonalAnimeProvider.overrideWith((_) => const <AnimeSummary>[]),
          trackingHomeProvider.overrideWith(
            (_) => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const TetoTvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up TetoTV'), findsOneWidget);
    expect(find.text('Skip setup'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Set up TetoTV'), findsNothing);
    expect(find.byKey(const ValueKey('main-nav-wordmark')), findsOneWidget);
    expect(find.text('Teto'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
  });
}
