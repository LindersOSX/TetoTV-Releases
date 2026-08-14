import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/features/tracking/presentation/my_list_screen.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts tracker data consistently for every supported field', () {
    final older = DateTime(2024, 1, 1);
    final newer = DateTime(2025, 1, 1);
    final items = [
      HomeTrackedAnime(
        tracked: TrackedAnime(
          mediaId: 1,
          title: 'Beta',
          status: TrackingListStatus.watching,
          progress: 1,
          score: 7,
          updatedAt: older,
          startDate: newer,
        ),
        provider: TrackingProvider.anilist,
        anilistId: 1,
        coverImageUrl: null,
      ),
      HomeTrackedAnime(
        tracked: TrackedAnime(
          mediaId: 2,
          title: 'Alpha',
          status: TrackingListStatus.watching,
          progress: 1,
          score: 9,
          updatedAt: newer,
          startDate: older,
        ),
        provider: TrackingProvider.myAnimeList,
        anilistId: null,
        coverImageUrl: null,
      ),
    ];

    expect(
      sortMyListItems(items, MyListSort.title).first.tracked.title,
      'Alpha',
    );
    expect(sortMyListItems(items, MyListSort.score).first.tracked.score, 9);
    expect(
      sortMyListItems(items, MyListSort.lastUpdated).first.tracked.updatedAt,
      newer,
    );
    expect(
      sortMyListItems(items, MyListSort.startDate).first.tracked.startDate,
      newer,
    );
  });

  testWidgets('shows all tracker status tabs', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
        ],
        child: const MaterialApp(home: TvShortcuts(child: MyListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    for (final status in TrackingListStatus.values) {
      expect(find.text(status.displayName), findsWidgets);
    }
    expect(find.text('Watching is empty'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    expect(find.text('Calendar'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    final activeMyList = find.ancestor(
      of: find.byIcon(Icons.video_library_rounded),
      matching: find.byType(TvFocusable),
    );
    final detector = find.descendant(
      of: activeMyList,
      matching: find.byType(FocusableActionDetector),
    );
    expect(
      tester.widget<FocusableActionDetector>(detector).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('shows linked tracker summaries in the global navigation row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = TrackingAccountProfile(
      provider: TrackingProvider.anilist,
      username: 'TetoFan',
      avatarUrl: 'https://img.anili.st/avatar.png',
      animeCount: 120,
      episodesWatched: 2400,
      minutesWatched: 48000,
      meanScore: 82.4,
    );
    const malProfile = TrackingAccountProfile(
      provider: TrackingProvider.myAnimeList,
      username: 'MALFan',
      meanScore: 8.1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(
                usernames: {
                  TrackingProvider.anilist: 'TetoFan',
                  TrackingProvider.myAnimeList: 'MALFan',
                },
                profiles: {
                  TrackingProvider.anilist: profile,
                  TrackingProvider.myAnimeList: malProfile,
                },
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('main-nav-profile-anilist'));
    expect(card, findsOneWidget);
    expect(tester.widget<Container>(card).decoration, isNull);
    expect(
      find.byKey(const ValueKey('main-nav-profile-summary')),
      findsOneWidget,
    );
    expect(find.text('TetoFan'), findsOneWidget);
    expect(find.text('MALFan'), findsNothing);
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('+1 MAL'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('main-nav-profile-additional')),
          )
          .decoration,
      isNull,
    );
    final anilistStats = find.byKey(
      const ValueKey('main-nav-profile-stats-anilist'),
    );
    expect(
      find.descendant(of: anilistStats, matching: find.text('120 titles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: anilistStats, matching: find.text('2400 episodes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: anilistStats, matching: find.text('800h watched')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: anilistStats, matching: find.text('Mean 82.4/100')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('main-nav-profile-stats-myanimelist')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(card).dy,
      lessThan(tester.getTopLeft(find.text('Watching').first).dy),
    );
    final artwork = tester.widget<NetworkArtwork>(
      find.descendant(of: card, matching: find.byType(NetworkArtwork)),
    );
    expect(artwork.url, 'https://img.anili.st/avatar.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked profiles stay labelled on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(
                usernames: {TrackingProvider.anilist: 'TetoFan'},
                profiles: {
                  TrackingProvider.anilist: TrackingAccountProfile(
                    provider: TrackingProvider.anilist,
                    username: 'TetoFan',
                    avatarUrl: 'https://img.anili.st/avatar.png',
                  ),
                },
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MainNavigationBar(
                  active: MainNavigationDestination.myList,
                  preferences: SettingsPreferences(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('main-nav-profile-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('AniList'), findsOneWidget);
    expect(find.textContaining('TetoFan'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('main-nav-profile-compact-shell')),
          )
          .decoration,
      isNull,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('main-nav-profile-summary')),
        matching: find.byType(NetworkArtwork),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tracker header fits every responsive breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(330, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profiles = {
      TrackingProvider.anilist: TrackingAccountProfile(
        provider: TrackingProvider.anilist,
        username: 'TetoFan',
        avatarUrl: 'https://img.anili.st/avatar.png',
        animeCount: 120,
        episodesWatched: 2400,
        minutesWatched: 48000,
        meanScore: 82.4,
      ),
      TrackingProvider.myAnimeList: TrackingAccountProfile(
        provider: TrackingProvider.myAnimeList,
        username: 'MALFan',
        animeCount: 94,
        meanScore: 8.1,
      ),
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(profiles: profiles),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MainNavigationBar(
                  active: MainNavigationDestination.home,
                  preferences: SettingsPreferences(),
                ),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );

    for (final width in <double>[330, 430, 820, 960, 1200]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pump();

      final navigation = find.byKey(const ValueKey('main-navigation'));
      final calendar = find.byKey(const ValueKey('main-nav-calendar'));
      final settings = find.byKey(const ValueKey('main-nav-settings'));
      expect(settings, findsOneWidget, reason: 'width $width');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('main-nav-my-list')),
          matching: find.text('My List'),
        ),
        findsOneWidget,
        reason: 'My List must stay visibly labelled at width $width',
      );
      expect(
        tester.getRect(settings).left - tester.getRect(calendar).right,
        inInclusiveRange(2, 4),
        reason: 'Settings must sit immediately after Calendar at width $width',
      );
      expect(
        tester.getSize(navigation).height,
        width >= 760 ? 96 : 62,
        reason: 'Header geometry must remain fixed at width $width',
      );
      final profile = find.byKey(const ValueKey('main-nav-profile-summary'));
      if (width == 330) {
        expect(profile, findsNothing);
      } else {
        expect(profile, findsOneWidget, reason: 'width $width');
        expect(
          tester.getRect(profile).left,
          greaterThanOrEqualTo(tester.getRect(settings).right),
          reason: 'Profile must fill the space after Settings at width $width',
        );
        expect(
          tester.getRect(profile).right,
          closeTo(tester.getRect(navigation).right, .01),
          reason: 'Profile must use the right-side gap at width $width',
        );
        expect(
          tester.getCenter(profile).dy,
          closeTo(tester.getCenter(settings).dy, .01),
          reason: 'Profile and navigation share one row at width $width',
        );
      }
      if (width == 820) {
        expect(find.textContaining('+1 MAL'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('main-nav-profile-myanimelist')),
          findsNothing,
        );
      }
      if (width == 960 || width == 1200) {
        expect(find.text('+1 MAL'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('main-nav-profile-myanimelist')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('1080p TV header shows avatar identity and useful stats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingAccountsControllerProvider.overrideWith(
            (_) => _StaticTrackingAccountsController(
              const TrackingAccountsState(
                profiles: {
                  TrackingProvider.anilist: TrackingAccountProfile(
                    provider: TrackingProvider.anilist,
                    username: 'LivingRoomFan',
                    avatarUrl: 'https://img.anili.st/avatar.png',
                    animeCount: 71,
                    episodesWatched: 804,
                    minutesWatched: 24120,
                    meanScore: 78.6,
                  ),
                },
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MainNavigationBar(
                  active: MainNavigationDestination.home,
                  preferences: SettingsPreferences(),
                ),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final profile = find.byKey(const ValueKey('main-nav-profile-summary'));
    final calendar = find.byKey(const ValueKey('main-nav-calendar'));
    final settings = find.byKey(const ValueKey('main-nav-settings'));
    final navigation = find.byKey(const ValueKey('main-navigation'));
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('LivingRoomFan'), findsOneWidget);
    expect(
      find.descendant(of: profile, matching: find.byType(NetworkArtwork)),
      findsOneWidget,
    );
    final stats = find.byKey(const ValueKey('main-nav-profile-stats-anilist'));
    expect(
      find.descendant(of: stats, matching: find.text('71 titles')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stats, matching: find.text('804 episodes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stats, matching: find.text('402h watched')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stats, matching: find.text('Mean 78.6/100')),
      findsOneWidget,
    );
    expect(tester.getSize(profile).width, inInclusiveRange(360, 410));
    expect(tester.getSize(profile).height, 58);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('main-nav-profile-avatar-anilist')),
      ),
      const Size(44, 44),
    );
    final profileContainer = tester.widget<Container>(
      find.byKey(const ValueKey('main-nav-profile-anilist')),
    );
    expect(profileContainer.decoration, isNull);
    final avatarDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('main-nav-profile-avatar-anilist')),
                )
                .decoration!
            as BoxDecoration;
    expect(avatarDecoration.border, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('main-nav-my-list')),
        matching: find.text('My List'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(settings).left - tester.getRect(calendar).right,
      inInclusiveRange(2, 4),
    );
    expect(tester.getSize(navigation).height, 96);
    expect(
      tester.getCenter(profile).dy,
      closeTo(tester.getCenter(settings).dy, .01),
    );
    expect(
      tester.getRect(profile).left,
      greaterThanOrEqualTo(tester.getRect(settings).right),
    );
    expect(
      tester.getRect(profile).right,
      closeTo(tester.getRect(navigation).right, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV wordmark uses live Theme Studio text and accent colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final palette = AppThemePalette.fromSeeds(
      background: const Color(0xFF101820),
      surface: const Color(0xFF182632),
      accent: const Color(0xFF23B58F),
      primaryText: const Color(0xFFF3EEDC),
      mutedText: const Color(0xFF9CAAB2),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkFor(palette),
          home: const Scaffold(
            body: Column(
              children: [
                MainNavigationBar(
                  active: MainNavigationDestination.home,
                  preferences: SettingsPreferences(),
                ),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('main-nav-wordmark')), findsOneWidget);
    expect(find.text('Teto'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('TetoTV'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('main-nav-wordmark-teto')))
          .style
          ?.color,
      palette.primaryText,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('main-nav-wordmark-tv')))
          .style
          ?.color,
      palette.accent,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('main-nav-my-list')),
        matching: find.text('My List'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile insertion keeps Settings focus and D-pad order stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final accounts = _StaticTrackingAccountsController(
      const TrackingAccountsState(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingAccountsControllerProvider.overrideWith((_) => accounts),
        ],
        child: const MaterialApp(
          home: TvShortcuts(
            child: Scaffold(
              body: Column(
                children: [
                  MainNavigationBar(
                    active: MainNavigationDestination.home,
                    preferences: SettingsPreferences(),
                  ),
                  Expanded(
                    child: SizedBox(key: ValueKey('header-layout-content')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    FocusableActionDetector settingsDetector() =>
        tester.widget<FocusableActionDetector>(
          find.descendant(
            of: find.byKey(const ValueKey('main-nav-settings')),
            matching: find.byType(FocusableActionDetector),
          ),
        );

    settingsDetector().focusNode!.requestFocus();
    await tester.pump();
    expect(settingsDetector().focusNode!.hasFocus, isTrue);
    final navigationBefore = tester.getRect(
      find.byKey(const ValueKey('main-navigation')),
    );
    final contentTopBefore = tester
        .getRect(find.byKey(const ValueKey('header-layout-content')))
        .top;
    final wordmarkBefore = tester.getRect(
      find.byKey(const ValueKey('main-nav-wordmark')),
    );
    final myListBefore = tester.getRect(
      find.byKey(const ValueKey('main-nav-my-list')),
    );
    final settingsBefore = tester.getRect(
      find.byKey(const ValueKey('main-nav-settings')),
    );

    accounts.replace(
      const TrackingAccountsState(
        profiles: {
          TrackingProvider.anilist: TrackingAccountProfile(
            provider: TrackingProvider.anilist,
            username: 'TetoFan',
            animeCount: 120,
          ),
        },
      ),
    );
    await tester.pump();
    expect(settingsDetector().focusNode!.hasFocus, isTrue);
    expect(
      tester.getRect(find.byKey(const ValueKey('main-navigation'))),
      navigationBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('header-layout-content'))).top,
      contentTopBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-wordmark'))),
      wordmarkBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-my-list'))),
      myListBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-settings'))),
      settingsBefore,
    );

    final profileSummary = find.byKey(
      const ValueKey('main-nav-profile-summary'),
    );
    expect(
      find.descendant(of: profileSummary, matching: find.byType(TvFocusable)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: profileSummary,
        matching: find.byType(FocusableActionDetector),
      ),
      findsNothing,
    );
    final semantics = tester.widget<Semantics>(profileSummary);
    expect(semantics.properties.button, isNot(true));
    expect(semantics.properties.onTap, isNull);
    expect(semantics.excludeSemantics, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final calendarDetector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byKey(const ValueKey('main-nav-calendar')),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    expect(calendarDetector.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(settingsDetector().focusNode!.hasFocus, isTrue);

    accounts.replace(const TrackingAccountsState());
    await tester.pump();
    expect(
      find.byKey(const ValueKey('main-nav-profile-summary')),
      findsNothing,
    );
    expect(settingsDetector().focusNode!.hasFocus, isTrue);
    expect(
      tester.getRect(find.byKey(const ValueKey('main-navigation'))),
      navigationBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('header-layout-content'))).top,
      contentTopBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-wordmark'))),
      wordmarkBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-my-list'))),
      myListBefore,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('main-nav-settings'))),
      settingsBefore,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focusing and pressing primary navigation keeps padding stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TvShortcuts(
            child: Scaffold(
              body: Column(
                children: [
                  MainNavigationBar(
                    active: MainNavigationDestination.myList,
                    preferences: SettingsPreferences(),
                  ),
                  Expanded(
                    child: SizedBox(key: ValueKey('stable-nav-content')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final navigation = find.byKey(const ValueKey('main-navigation'));
    final content = find.byKey(const ValueKey('stable-nav-content'));
    final myListDetector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byKey(const ValueKey('main-nav-my-list')),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    final navigationBefore = tester.getRect(navigation);
    final contentTopBefore = tester.getRect(content).top;

    myListDetector.focusNode!.requestFocus();
    await tester.pump();
    expect(tester.getRect(navigation), navigationBefore);
    expect(tester.getRect(content).top, contentTopBefore);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tester.getRect(navigation), navigationBefore);
    expect(tester.getRect(content).top, contentTopBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh reloads the active list and home tracking shelves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var listLoads = 0;
    var homeLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith((
            _,
          ) async {
            listLoads++;
            return const TrackingListResult(items: []);
          }),
          trackingHomeProvider.overrideWith((_) async {
            homeLoads++;
            return const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            );
          }),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(listLoads, 1);
    expect(homeLoads, 0);

    await tester.tap(find.byKey(const Key('my-list-refresh')));
    await tester.pumpAndSettle();

    expect(listLoads, 2);
    expect(homeLoads, 1);
    expect(
      find.text('Refresh complete. Showing available connected tracker data.'),
      findsOneWidget,
    );
  });

  test('tracking result distinguishes partial and complete failures', () {
    final partial = TrackingListResult(
      items: const [],
      attempted: const {TrackingProvider.anilist, TrackingProvider.myAnimeList},
      failures: {TrackingProvider.myAnimeList: StateError('offline')},
    );
    final failed = TrackingListResult(
      items: const [],
      attempted: const {TrackingProvider.anilist, TrackingProvider.myAnimeList},
      failures: {
        TrackingProvider.anilist: StateError('offline'),
        TrackingProvider.myAnimeList: StateError('offline'),
      },
    );

    expect(partial.hasFailures, isTrue);
    expect(partial.allAttemptedFailed, isFalse);
    expect(failed.allAttemptedFailed, isTrue);
  });

  testWidgets('keeps partial tracker results visible with a warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = HomeTrackedAnime(
      tracked: const TrackedAnime(
        mediaId: 7,
        title: 'Available show',
        status: TrackingListStatus.watching,
        progress: 3,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 7,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith(
            (_) async => TrackingListResult(
              items: [item],
              attempted: const {
                TrackingProvider.anilist,
                TrackingProvider.myAnimeList,
              },
              failures: {TrackingProvider.myAnimeList: StateError('offline')},
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available show'), findsOneWidget);
    expect(find.textContaining('MAL could not be refreshed'), findsOneWidget);
    expect(find.text('Watching is empty'), findsNothing);
  });

  testWidgets('failed refresh keeps the previous tracker cards visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    final item = HomeTrackedAnime(
      tracked: const TrackedAnime(
        mediaId: 9,
        title: 'Previously loaded show',
        status: TrackingListStatus.watching,
        progress: 4,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 9,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(TrackingListStatus.watching).overrideWith((
            _,
          ) async {
            loads++;
            if (loads == 1) {
              return TrackingListResult(
                items: [item],
                attempted: const {TrackingProvider.anilist},
              );
            }
            return TrackingListResult(
              items: const [],
              attempted: const {TrackingProvider.anilist},
              failures: {TrackingProvider.anilist: StateError('offline')},
            );
          }),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Previously loaded show'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my-list-refresh')));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('Previously loaded show'), findsOneWidget);
    expect(find.textContaining('Showing the previous results'), findsOneWidget);
    expect(find.textContaining('Could not refresh AniList'), findsOneWidget);
  });

  testWidgets('a planned title can be removed instead of marked Dropped', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      TrackingProvider.anilist.tokenStorageKey: 'anilist-token',
    });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RemovingRepository();
    const planned = HomeTrackedAnime(
      tracked: TrackedAnime(
        mediaId: 77,
        title: 'Maybe Later',
        status: TrackingListStatus.planToWatch,
        progress: 0,
      ),
      provider: TrackingProvider.anilist,
      anilistId: 77,
      coverImageUrl: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingListProvider(
            TrackingListStatus.watching,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
          trackingListProvider(TrackingListStatus.planToWatch).overrideWith(
            (_) async => const TrackingListResult(items: [planned]),
          ),
          trackingRepositoryFactoryProvider.overrideWithValue(
            (_, _) => repository,
          ),
        ],
        child: const MaterialApp(home: MyListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Planning').first);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Maybe Later'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from Planning'), findsOneWidget);
    expect(find.text('Dropped'), findsWidgets);
    await tester.tap(find.text('Remove from Planning'));
    await tester.pumpAndSettle();

    expect(repository.removals, [77]);
    expect(find.textContaining('removed from AniList'), findsOneWidget);
  });
}

class _RemovingRepository implements TrackingRepository {
  final removals = <int>[];

  @override
  Future<int?> currentProgress(int mediaId) async => null;

  @override
  Future<List<TrackedAnime>> list(TrackingListStatus status) async => const [];

  @override
  Future<void> removeFromList({required int mediaId}) async {
    removals.add(mediaId);
  }

  @override
  Future<void> updateProgress({
    required int mediaId,
    required int completedEpisodes,
  }) async {}

  @override
  Future<void> updateStatus({
    required int mediaId,
    required TrackingListStatus status,
  }) async {}
}

class _StaticTrackingAccountsController extends TrackingAccountsController {
  _StaticTrackingAccountsController(TrackingAccountsState initial)
    : super(
        _TrackingAccountsRef(),
        TrackingTokenService(const FlutterSecureStorage()),
      ) {
    state = initial;
  }

  @override
  Future<void> load() async {}

  void replace(TrackingAccountsState next) => state = next;
}

class _TrackingAccountsRef extends Fake implements Ref {}
