import 'dart:async';

import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/features/tracking/presentation/tracking_status_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _homeEasterEggTapTarget = 10;
  static const _homeEasterEggTapWindow = Duration(seconds: 5);
  static const _homeEasterEggDisplayDuration = Duration(seconds: 10);

  static const _connectTracking = [
    _ShelfItem(
      'Connect your tracker',
      'AniList or MAL',
      route: '/settings/accounts',
    ),
  ];

  final _heroFocus = FocusNode(debugLabel: 'home.watch-now');
  final _homeNavFocus = FocusNode(debugLabel: 'home.navigation.home');
  final _scrollController = ScrollController();
  bool _catalogFocusSettled = false;
  Timer? _heroTimer;
  Timer? _homeEasterEggTimer;
  late final AnimationController _homeEasterEggAnimation;
  late final Animation<double> _homeEasterEggFall;
  late final Animation<double> _homeEasterEggShake;
  int _heroIndex = 0;
  int _homeEasterEggTapCount = 0;
  DateTime? _homeEasterEggSequenceStartedAt;
  DateTime? _lastHomeActivation;
  bool _homeRefreshInProgress = false;
  bool _showHomeEasterEgg = false;

  @override
  void initState() {
    super.initState();
    _homeEasterEggAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    _homeEasterEggFall = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: -2.15,
          end: .075,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 56,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: .075,
          end: -.035,
        ).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 11,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -.035,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 11,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 22),
    ]).animate(_homeEasterEggAnimation);
    _homeEasterEggShake = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: .038), weight: 5),
      TweenSequenceItem(tween: Tween(begin: .038, end: -.032), weight: 6),
      TweenSequenceItem(tween: Tween(begin: -.032, end: .024), weight: 6),
      TweenSequenceItem(tween: Tween(begin: .024, end: -.015), weight: 6),
      TweenSequenceItem(tween: Tween(begin: -.015, end: .008), weight: 6),
      TweenSequenceItem(tween: Tween(begin: .008, end: 0.0), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 6),
    ]).animate(_homeEasterEggAnimation);
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final count = ref.read(trendingAnimeProvider).valueOrNull?.take(5).length;
      if (count == null || count < 2) return;
      final items = ref.read(trendingAnimeProvider).valueOrNull!;
      final nextIndex = ((_heroIndex % count) + 1) % count;
      final nextArtwork =
          items[nextIndex].bannerImageUrl ?? items[nextIndex].coverImageUrl;
      if (nextArtwork != null && nextArtwork.isNotEmpty) {
        NetworkArtwork.precache(context, nextArtwork, cacheWidth: 1280);
      }
      setState(() => _heroIndex = nextIndex);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusHero();
      unawaited(_runStartup());
    });
  }

  Future<void> _runStartup() async {
    final preferences = ref.read(settingsPreferencesProvider.notifier);
    await preferences.load();
    if (!mounted) return;
    final setup = ref.read(setupProgressProvider.notifier);
    await setup.load();
    if (!mounted) return;
    if (!ref.read(setupProgressProvider).completed) {
      await context.push('/setup');
      if (!mounted) return;
    }
    final landingRoute = preferences.takeInitialLandingRoute();
    // A release check can take tens of seconds on a slow or offline TV. Start
    // it in the background so the configured landing page is never held behind
    // network I/O. `_checkForUpdates` already stops UI work after disposal.
    unawaited(_checkForUpdates());
    if (landingRoute != null && mounted) context.go(landingRoute);
  }

  Future<void> _checkForUpdates() async {
    final updater = ref.read(appUpdateControllerProvider.notifier);
    await updater.checkForUpdates(automatic: true, launchInstaller: true);
    if (!mounted) return;
    final notes = await updater.takeInstalledReleaseNotes();
    if (!mounted || notes == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appPalette.surface,
        title: const Text('What\'s new in TetoTV'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 420),
          child: SingleChildScrollView(child: SelectableText(notes)),
        ),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _focusHero() {
    if (!mounted) return;
    if (_heroFocus.context != null) {
      _heroFocus.requestFocus();
    } else {
      _homeNavFocus.requestFocus();
    }
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _handleHomeActivation() {
    final now = DateTime.now();
    if (_recordHomeEasterEggActivation(now)) {
      _lastHomeActivation = null;
      _revealHomeEasterEgg();
      return;
    }
    final previous = _lastHomeActivation;
    _lastHomeActivation = now;
    if (previous == null ||
        now.difference(previous) > const Duration(milliseconds: 650)) {
      if (_scrollController.hasClients) {
        unawaited(
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    _lastHomeActivation = null;
    unawaited(_refreshHome());
  }

  bool _recordHomeEasterEggActivation(DateTime now) {
    final startedAt = _homeEasterEggSequenceStartedAt;
    if (startedAt == null ||
        now.difference(startedAt) > _homeEasterEggTapWindow) {
      _homeEasterEggSequenceStartedAt = now;
      _homeEasterEggTapCount = 1;
      return false;
    }
    _homeEasterEggTapCount++;
    if (_homeEasterEggTapCount < _homeEasterEggTapTarget) return false;
    _homeEasterEggTapCount = 0;
    _homeEasterEggSequenceStartedAt = null;
    return true;
  }

  void _revealHomeEasterEgg() {
    _homeEasterEggTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    if (!_showHomeEasterEgg) setState(() => _showHomeEasterEgg = true);
    _homeEasterEggAnimation.forward(from: 0);
    unawaited(
      AndroidTvBridge.instance.playHomeEasterEgg(
        maximumDuration: _homeEasterEggDisplayDuration,
      ),
    );
    _homeEasterEggTimer = Timer(_homeEasterEggDisplayDuration, () {
      if (!mounted) return;
      setState(() => _showHomeEasterEgg = false);
      unawaited(AndroidTvBridge.instance.stopHomeEasterEgg());
    });
  }

  Future<void> _refreshHome() async {
    if (_homeRefreshInProgress) return;
    _homeRefreshInProgress = true;
    ref.invalidate(trendingAnimeProvider);
    ref.invalidate(seasonalAnimeProvider);
    ref.invalidate(trackingHomeProvider);
    ref.invalidate(recentPlaybackProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refreshing Home…'),
        duration: Duration(milliseconds: 1200),
      ),
    );
    try {
      await Future.wait([
        ref.read(trendingAnimeProvider.future),
        ref.read(seasonalAnimeProvider.future),
        ref.read(trackingHomeProvider.future),
        ref.read(recentPlaybackProvider.future),
      ]);
      if (!mounted || _showHomeEasterEgg) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Home refreshed.'),
          duration: Duration(milliseconds: 1200),
        ),
      );
    } catch (_) {
      if (!mounted || _showHomeEasterEgg) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some Home shelves could not be refreshed.'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      _homeRefreshInProgress = false;
    }
  }

  Future<void> _removeFromLocalHistory(_ShelfItem item) async {
    final mediaId = item.historyMediaId ?? item.animeId;
    if (mediaId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: context.appPalette.surface,
        title: const Text('Remove from this TV?'),
        content: Text(
          'Remove “${item.title}” from local Watch History and Continue '
          'Watching? AniList and MAL will not be changed.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final database = ref.read(tetoTvDatabaseProvider);
    try {
      await database.removeLocalHistory(mediaId);
      await AndroidTvBridge.instance.removeWatchNext(mediaId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove local watch history.')),
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(recentPlaybackProvider);
    ref.invalidate(latestPlaybackProvider(mediaId));
    ref.invalidate(dismissedContinueWatchingProvider);
  }

  Future<void> _manageShelfItem(_ShelfItem item) async {
    final action = await showDialog<Object>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _HomeShowActionsDialog(item: item),
    );
    if (!mounted || action == null) return;
    if (action == _HomeShowAction.removeLocal) {
      await _removeFromLocalHistory(item);
      return;
    }
    if (action == _HomeShowAction.open) {
      final route =
          item.route ??
          (item.animeId == null
              ? Uri(
                  path: '/search',
                  queryParameters: {'q': item.title},
                ).toString()
              : '/anime/${item.animeId}');
      if (mounted) await context.push(route);
      return;
    }
    if (action is! TrackingListStatus) return;

    if (item.animeId == null && item.trackingItems.isNotEmpty) {
      var failures = 0;
      for (final tracked in item.trackingItems) {
        try {
          await ref
              .read(trackingStatusControllerProvider.notifier)
              .update(tracked, action);
        } catch (_) {
          failures++;
        }
      }
      if (!mounted) return;
      ref.invalidate(trackingHomeProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failures == 0
                ? '${item.title} moved to ${action.displayName}.'
                : 'Updated ${item.trackingItems.length - failures} of '
                      '${item.trackingItems.length} connected lists.',
          ),
          backgroundColor: failures == 0
              ? context.appPalette.accent
              : const Color(0xFF7D1E32),
        ),
      );
      return;
    }
    if (item.animeId == null) return;

    try {
      final result = await ref
          .read(trackingStatusControllerProvider.notifier)
          .updateCatalogStatus(
            anilistId: item.animeId!,
            malId: item.malMediaId,
            status: action,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPartial
                ? '${item.title} updated on ${result.updatedProviderNames}; '
                      'one linked tracker could not be updated.'
                : '${item.title} moved to ${action.displayName} on '
                      '${result.updatedProviderNames}.',
          ),
          backgroundColor: result.isPartial
              ? const Color(0xFF7D1E32)
              : context.appPalette.accent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : 'Could not update this show. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF7D1E32),
        ),
      );
    }
  }

  @override
  void dispose() {
    _heroFocus.dispose();
    _homeNavFocus.dispose();
    _scrollController.dispose();
    _heroTimer?.cancel();
    _homeEasterEggTimer?.cancel();
    _homeEasterEggAnimation.dispose();
    unawaited(AndroidTvBridge.instance.stopHomeEasterEgg());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trendingAnimeProvider, (_, next) {
      if (!_catalogFocusSettled && next.valueOrNull?.isNotEmpty == true) {
        _catalogFocusSettled = true;
        // The hero keeps the same focus node while its artwork loads. Do not
        // steal focus or jump to the top after the user has started navigating.
        if (_heroFocus.hasFocus || FocusManager.instance.primaryFocus == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_heroFocus.hasFocus ||
                FocusManager.instance.primaryFocus == null) {
              _focusHero();
            }
          });
        }
      }
    });

    final trendingAsync = ref.watch(trendingAnimeProvider);
    final seasonalAsync = ref.watch(seasonalAnimeProvider);
    final trending = trendingAsync.valueOrNull;
    final seasonal = seasonalAsync.valueOrNull;
    final tracking = ref.watch(trackingHomeProvider).valueOrNull;
    final localHistory = ref.watch(recentPlaybackProvider).valueOrNull;
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final enabledShelves = ref.watch(homeShelfPreferencesProvider);
    final shelfOrder = ref.watch(homeShelfOrderProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    final dismissedIds =
        ref.watch(dismissedContinueWatchingProvider).valueOrNull ??
        const <int>{};
    final heroItems =
        trending?.take(5).toList(growable: false) ?? const <AnimeSummary>[];
    final activeHeroIndex = heroItems.isEmpty
        ? 0
        : _heroIndex % heroItems.length;
    final hero = heroItems.isEmpty ? null : heroItems[activeHeroIndex];
    final seasonalItems = seasonal == null || seasonal.isEmpty
        ? const <_ShelfItem>[]
        : seasonal
              .map((anime) => _ShelfItem.fromAnime(anime, titlePreference))
              .toList(growable: false);
    final trendingItems = trending
        ?.skip(1)
        .map((anime) => _ShelfItem.fromAnime(anime, titlePreference))
        .toList(growable: false);
    final plannedItems = tracking?.planToWatch.isNotEmpty == true
        ? tracking!.planToWatch
              .map((item) => _ShelfItem.fromTracked(item, titlePreference))
              .toList(growable: false)
        : const <_ShelfItem>[];
    final completedItems = tracking?.completed
        .map((item) => _ShelfItem.fromTracked(item, titlePreference))
        .toList(growable: false);
    final historyItems = _historyShelfItems(
      localHistory: localHistory,
      tracking: tracking,
    );
    final watchingItems = _mergeContinueWatching(
      localHistory: localHistory,
      trackedWatching: tracking?.watching,
      dismissedIds: dismissedIds,
      titlePreference: titlePreference,
    );
    final followed = <HomeTrackedAnime>[
      ...?tracking?.watching,
      ...?tracking?.planToWatch,
    ];
    final airingItems = seasonal
        ?.where(
          (anime) =>
              anime.nextAiringEpisode != null &&
              _isTrackedAnime(anime, followed),
        )
        .take(20)
        .map(
          (anime) => _ShelfItem.fromAnime(anime, titlePreference).copyWith(
            subtitle: 'Episode ${anime.nextAiringEpisode} airing soon',
          ),
        )
        .toList(growable: false);
    final shelfSlivers = <Widget>[];
    for (final shelf in shelfOrder) {
      if (!enabledShelves.contains(shelf)) continue;
      switch (shelf) {
        case HomeShelf.tracking:
          shelfSlivers.add(
            SliverToBoxAdapter(
              child: _MediaShelf(
                title: shelf.displayName,
                items: watchingItems,
                preferences: preferences,
                onManage: _manageShelfItem,
              ),
            ),
          );
          break;
        case HomeShelf.history:
          if (historyItems != null && historyItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: historyItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
        case HomeShelf.recentlyReleased:
          if (seasonalAsync.isLoading) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelfSkeleton(
                  title: shelf.displayName,
                  preferences: preferences,
                ),
              ),
            );
          } else if (seasonalItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: seasonalItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
        case HomeShelf.trending:
          if (trendingItems != null && trendingItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: trendingItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
        case HomeShelf.planned:
          if (plannedItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: plannedItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
        case HomeShelf.airing:
          if (airingItems != null && airingItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: airingItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
        case HomeShelf.completed:
          if (completedItems != null && completedItems.isNotEmpty) {
            shelfSlivers.add(
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: shelf.displayName,
                  items: completedItems,
                  preferences: preferences,
                  onManage: _manageShelfItem,
                ),
              ),
            );
          }
          break;
      }
    }

    final responsivePadding = context.responsiveScreenPadding;
    final contentHorizontalPadding = EdgeInsets.only(
      left: responsivePadding.left,
      right: responsivePadding.right,
    );

    return Scaffold(
      backgroundColor: context.appPalette == AppThemePalette.defaults
          ? Colors.black
          : context.appPalette.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: contentHorizontalPadding,
                  sliver: SliverToBoxAdapter(
                    child: MainNavigationBar(
                      active: MainNavigationDestination.home,
                      preferences: preferences,
                      homeFocusNode: _homeNavFocus,
                      autofocusActive: !preferences.showHero,
                      onHomePressed: _handleHomeActivation,
                    ),
                  ),
                ),
                if (preferences.showHero)
                  SliverPadding(
                    padding: contentHorizontalPadding,
                    sliver: SliverToBoxAdapter(
                      child: _HeroPanel(
                        anime: hero,
                        isLoading: trendingAsync.isLoading,
                        focusNode: _heroFocus,
                        titlePreference: titlePreference,
                        preferences: preferences,
                        activeIndex: activeHeroIndex,
                        itemCount: heroItems.length,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: preferences.homeLayout == HomeLayout.compact
                        ? 10
                        : 18,
                  ),
                ),
                for (final shelfSliver in shelfSlivers)
                  SliverPadding(
                    padding: contentHorizontalPadding,
                    sliver: shelfSliver,
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 42)),
              ],
            ),
            if (_showHomeEasterEgg)
              Positioned.fill(
                child: IgnorePointer(
                  key: const ValueKey('home.easter-egg.ignore-pointer'),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedBuilder(
                      animation: _homeEasterEggAnimation,
                      builder: (context, child) => FractionalTranslation(
                        key: const ValueKey('home.easter-egg-motion'),
                        translation: Offset(
                          _homeEasterEggShake.value,
                          _homeEasterEggFall.value,
                        ),
                        child: child,
                      ),
                      child: FractionallySizedBox(
                        key: const ValueKey('home.easter-egg.region'),
                        heightFactor: 0.5,
                        widthFactor: 1,
                        alignment: Alignment.bottomCenter,
                        child: Image.asset(
                          'assets/easter_egg/teto_plush.png',
                          key: const ValueKey('home.easter-egg.image'),
                          alignment: Alignment.bottomCenter,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.focusNode,
    required this.titlePreference,
    required this.preferences,
    required this.isLoading,
    required this.activeIndex,
    required this.itemCount,
    this.anime,
  });

  final AnimeSummary? anime;
  final FocusNode focusNode;
  final TitleLanguagePreference titlePreference;
  final SettingsPreferences preferences;
  final bool isLoading;
  final int activeIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final route = anime == null ? '/search?q=Frieren' : '/anime/${anime!.id}';
    final compact = context.isCompactWidth;
    final dense = preferences.homeLayout == HomeLayout.compact;
    return Container(
      key: const ValueKey('home-hero'),
      height: dense ? (compact ? 270 : 224) : (compact ? 340 : 292),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: context.appPalette.surface),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF26050C), Color(0xFF080808)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: isLoading
                ? const ArtworkSkeleton(key: ValueKey('hero-loading'))
                : NetworkArtwork(
                    key: ValueKey('hero-art-${anime?.id ?? 0}'),
                    // AniList does not provide a wide banner for every title.
                    // A cover is still preferable to an apparently missing
                    // carousel background, and BoxFit.cover keeps it usable
                    // in the same hero frame.
                    url: anime?.bannerImageUrl ?? anime?.coverImageUrl,
                    cacheWidth: 1280,
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFA000000),
                  Color(0xC7000000),
                  Color(0x22000000),
                ],
                stops: [0, .50, 1],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xE6000000)],
                begin: Alignment.center,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 15 : 18,
              compact ? 18 : 22,
              compact ? 15 : 24,
              compact ? 16 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(text: 'FEATURED NOW'),
                const SizedBox(height: 8),
                SizedBox(
                  width: compact ? double.infinity : 620,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      key: ValueKey('hero-title-${anime?.id ?? 0}'),
                      anime?.displayTitle(titlePreference) ??
                          'Frieren: Beyond Journey’s End',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: compact ? 30 : 40,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: compact ? double.infinity : 610,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      key: ValueKey('hero-description-${anime?.id ?? 0}'),
                      anime?.description.isNotEmpty == true
                          ? anime!.description
                          : 'An elven mage retraces a legendary journey and '
                                'discovers what the brief lives of her friends meant.',
                      maxLines: dense ? 2 : (compact ? 5 : 4),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.appPalette.primaryText,
                        height: 1.32,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: compact ? 8 : 0,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _TvButton(
                      focusNode: focusNode,
                      autofocus: true,
                      icon: Icons.play_arrow_rounded,
                      label: 'Watch now',
                      onPressed: () => context.push(route),
                    ),
                    SizedBox(width: compact ? 2 : 16),
                    if (anime?.score case final score?)
                      _HeroMeta(
                        icon: Icons.star_rounded,
                        text: score.toStringAsFixed(1),
                      ),
                    if (anime?.format case final format?)
                      _HeroMeta(text: format.replaceAll('_', ' ')),
                    if (anime?.seasonYear case final year?)
                      _HeroMeta(text: '$year'),
                    if (anime?.durationMinutes case final minutes?)
                      _HeroMeta(text: '$minutes min'),
                    if (anime?.episodes case final episodes?)
                      _HeroMeta(text: '$episodes episodes'),
                  ],
                ),
              ],
            ),
          ),
          if (!compact && itemCount > 1)
            Positioned(
              right: 20,
              bottom: 18,
              child: Row(
                children: [
                  for (var index = 0; index < itemCount; index++)
                    _HeroDot(active: index == activeIndex),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: context.appPalette.accentBright),
            const SizedBox(width: 4),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: context.appPalette.primaryText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDot extends StatelessWidget {
  const _HeroDot({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 24 : 7,
      height: 7,
      margin: const EdgeInsets.only(left: 5),
      decoration: BoxDecoration(
        color: active ? context.appPalette.accentBright : Colors.white54,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _MediaShelf extends StatelessWidget {
  const _MediaShelf({
    required this.title,
    required this.items,
    required this.preferences,
    this.onManage,
  });

  final String title;
  final List<_ShelfItem> items;
  final SettingsPreferences preferences;
  final ValueChanged<_ShelfItem>? onManage;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompactWidth;
    final dense = preferences.homeLayout == HomeLayout.compact;
    final posterHeight = dense
        ? (compact ? 198.0 : 170.0)
        : (compact ? 238.0 : 205.0);
    final posterWidth = dense
        ? (compact ? 104.0 : 88.0)
        : (compact ? 126.0 : 106.0);
    final cardHeight = posterHeight * preferences.thumbnailScale;
    final artworkHeight =
        cardHeight - (preferences.showCardSubtitles ? 60.0 : 46.0);
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 9 * preferences.contentDensity.spacingScale),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  SizedBox(width: 10 * preferences.contentDensity.spacingScale),
              itemBuilder: (context, index) {
                final item = items[index];
                return _PosterCard(
                  item: item,
                  width: posterWidth * preferences.thumbnailScale,
                  artworkHeight: artworkHeight,
                  preferences: preferences,
                  onPressed: () => item.route != null
                      ? context.push(item.route!)
                      : item.animeId == null
                      ? context.push(
                          Uri(
                            path: '/search',
                            queryParameters: {'q': item.title},
                          ).toString(),
                        )
                      : context.push('/anime/${item.animeId}'),
                  onLongPress: onManage == null ? null : () => onManage!(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaShelfSkeleton extends StatelessWidget {
  const _MediaShelfSkeleton({required this.title, required this.preferences});

  final String title;
  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompactWidth;
    final dense = preferences.homeLayout == HomeLayout.compact;
    final posterHeight = dense
        ? (compact ? 198.0 : 170.0)
        : (compact ? 238.0 : 205.0);
    final posterWidth = dense
        ? (compact ? 104.0 : 88.0)
        : (compact ? 126.0 : 106.0);
    final width = posterWidth * preferences.thumbnailScale;
    final cardHeight = posterHeight * preferences.thumbnailScale;
    final artworkHeight =
        cardHeight - (preferences.showCardSubtitles ? 60.0 : 46.0);
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 9 * preferences.contentDensity.spacingScale),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 8,
              separatorBuilder: (_, _) =>
                  SizedBox(width: 10 * preferences.contentDensity.spacingScale),
              itemBuilder: (_, _) => SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: artworkHeight,
                      child: const ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        child: ArtworkSkeleton(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(
                      height: 24,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _SkeletonLine(widthFactor: .88),
                      ),
                    ),
                    if (preferences.showCardSubtitles) ...[
                      const SizedBox(height: 5),
                      const _SkeletonLine(widthFactor: .58),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: 7,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.width,
    required this.artworkHeight,
    required this.onPressed,
    required this.preferences,
    this.onLongPress,
  });

  final _ShelfItem item;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double width;
  final double artworkHeight;
  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TvFocusable(
        onPressed: onPressed,
        onLongPress: onLongPress,
        focusScale: 1.025,
        borderRadius: BorderRadius.circular(7),
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: ValueKey('home-artwork-${item.animeId ?? item.title}'),
                height: artworkHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.coverImageUrl == null)
                        ColoredBox(
                          color: context.appPalette.accent,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        )
                      else
                        NetworkArtwork(
                          url: item.coverImageUrl,
                          cacheWidth: 190,
                        ),
                      if (animeAiringStatusLabel(item.airingStatus) != null)
                        Positioned(
                          left: 5,
                          top: 5,
                          child: PosterAiringStatusBadge(
                            status: item.airingStatus,
                          ),
                        ),
                      if (preferences.showPosterMetadata &&
                          item.hasPosterMetadata)
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: PosterMetadataOverlay(
                            score: item.score,
                            releaseYear: item.releaseYear,
                            durationMinutes: item.durationMinutes,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appPalette.primaryText,
                      fontSize: 11,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (preferences.showCardSubtitles)
                SizedBox(
                  height: 14,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
                    child: Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appPalette.mutedText,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (item.progress != null) ...[
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  color: context.appPalette.accentBright,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(99),
      focusScale: 1.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: context.appPalette.accent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.appPalette.accentBright,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.6,
      ),
    );
  }
}

List<_ShelfItem> _mergeContinueWatching({
  required List<PlaybackCheckpoint>? localHistory,
  required List<HomeTrackedAnime>? trackedWatching,
  required Set<int> dismissedIds,
  required TitleLanguagePreference titlePreference,
}) {
  final merged = <_ShelfItem>[];
  final localAniListIds = <int>{};
  final localMalIds = <int>{};
  final localAniListIndexes = <int, int>{};
  final localMalIndexes = <int, int>{};

  // Recent local playback contains the most useful resume position, so it is
  // deliberately added first and wins whenever the tracker has the same media
  // ID. A local checkpoint must not hide unrelated titles from MAL or AniList.
  for (final checkpoint in localHistory ?? const <PlaybackCheckpoint>[]) {
    if (checkpoint.completed ||
        !localAniListIds.add(checkpoint.anilistMediaId)) {
      continue;
    }
    if (checkpoint.malMediaId case final malId?) localMalIds.add(malId);
    final index = merged.length;
    merged.add(_ShelfItem.fromCheckpoint(checkpoint));
    localAniListIndexes[checkpoint.anilistMediaId] = index;
    if (checkpoint.malMediaId case final malId?) {
      localMalIndexes[malId] = index;
    }
  }

  final seenTrackerIds = <String>{};
  for (final tracked in trackedWatching ?? const <HomeTrackedAnime>[]) {
    final aniListId = tracked.anilistId;
    if (aniListId != null && dismissedIds.contains(aniListId)) continue;

    final matchesLocal = switch (tracked.provider) {
      TrackingProvider.anilist => localAniListIds.contains(
        aniListId ?? tracked.tracked.mediaId,
      ),
      TrackingProvider.myAnimeList => localMalIds.contains(
        tracked.tracked.mediaId,
      ),
    };
    if (matchesLocal) {
      final index = switch (tracked.provider) {
        TrackingProvider.anilist =>
          localAniListIndexes[aniListId ?? tracked.tracked.mediaId],
        TrackingProvider.myAnimeList =>
          localMalIndexes[tracked.tracked.mediaId],
      };
      if (index != null) {
        merged[index] = merged[index].copyWith(
          trackingItems: [...merged[index].trackingItems, tracked],
        );
      }
      continue;
    }

    final trackerKey = '${tracked.provider.name}:${tracked.tracked.mediaId}';
    if (!seenTrackerIds.add(trackerKey)) continue;
    merged.add(_ShelfItem.fromTracked(tracked, titlePreference));
  }

  return merged.isEmpty ? _HomeScreenState._connectTracking : merged;
}

class _ShelfItem {
  const _ShelfItem(
    this.title,
    this.subtitle, {
    this.progress,
    this.animeId,
    this.coverImageUrl,
    this.route,
    this.score,
    this.releaseYear,
    this.durationMinutes,
    this.historyMediaId,
    this.airingStatus,
    this.malMediaId,
    this.trackingItems = const [],
  });

  final String title;
  final String subtitle;
  final double? progress;
  final int? animeId;
  final String? coverImageUrl;
  final String? route;
  final double? score;
  final int? releaseYear;
  final int? durationMinutes;
  final int? historyMediaId;
  final String? airingStatus;
  final int? malMediaId;
  final List<HomeTrackedAnime> trackingItems;

  bool get hasPosterMetadata =>
      score != null || releaseYear != null || durationMinutes != null;

  factory _ShelfItem.fromAnime(
    AnimeSummary anime,
    TitleLanguagePreference titlePreference,
  ) {
    return _ShelfItem(
      anime.displayTitle(titlePreference),
      anime.episodes == null ? '' : '${anime.episodes} episodes',
      animeId: anime.id,
      malMediaId: anime.idMal,
      coverImageUrl: anime.coverImageUrl,
      score: anime.score,
      releaseYear: anime.seasonYear,
      durationMinutes: anime.durationMinutes,
      airingStatus: anime.status,
    );
  }

  factory _ShelfItem.fromCheckpoint(PlaybackCheckpoint checkpoint) {
    return _ShelfItem(
      checkpoint.title,
      'Episode ${checkpoint.episode} • ${_shortDuration(checkpoint.position)}',
      progress: checkpoint.progress,
      animeId: checkpoint.anilistMediaId,
      coverImageUrl: checkpoint.coverImageUrl,
      historyMediaId: checkpoint.anilistMediaId,
      malMediaId: checkpoint.malMediaId,
    );
  }

  _ShelfItem copyWith({
    String? subtitle,
    List<HomeTrackedAnime>? trackingItems,
  }) => _ShelfItem(
    title,
    subtitle ?? this.subtitle,
    progress: progress,
    animeId: animeId,
    coverImageUrl: coverImageUrl,
    route: route,
    score: score,
    releaseYear: releaseYear,
    durationMinutes: durationMinutes,
    historyMediaId: historyMediaId,
    airingStatus: airingStatus,
    malMediaId: malMediaId,
    trackingItems: trackingItems ?? this.trackingItems,
  );

  factory _ShelfItem.fromTracked(
    HomeTrackedAnime item,
    TitleLanguagePreference titlePreference,
  ) {
    final tracked = item.tracked;
    final subtitle = switch (tracked.status) {
      TrackingListStatus.watching =>
        'Episode ${tracked.progress}'
            '${tracked.totalEpisodes == null ? '' : ' of ${tracked.totalEpisodes}'}',
      TrackingListStatus.planToWatch => 'Plan to watch',
      TrackingListStatus.completed =>
        tracked.totalEpisodes == null
            ? 'Completed'
            : '${tracked.totalEpisodes} episodes • Completed',
      TrackingListStatus.dropped => 'Dropped',
      TrackingListStatus.onHold => 'On hold',
    };
    return _ShelfItem(
      tracked.displayTitle(titlePreference),
      subtitle,
      progress: tracked.totalEpisodes == null || tracked.totalEpisodes == 0
          ? null
          : (tracked.progress / tracked.totalEpisodes!).clamp(0, 1),
      animeId: item.anilistId,
      malMediaId: item.provider == TrackingProvider.myAnimeList
          ? tracked.mediaId
          : null,
      coverImageUrl: item.coverImageUrl,
      route: item.anilistId == null
          ? Uri(
              path: '/search',
              queryParameters: {'q': tracked.title},
            ).toString()
          : null,
      airingStatus: tracked.airingStatus,
      trackingItems: [item],
    );
  }
}

enum _HomeShowAction { open, removeLocal }

class _HomeShowActionsDialog extends StatelessWidget {
  const _HomeShowActionsDialog({required this.item});

  final _ShelfItem item;

  @override
  Widget build(BuildContext context) {
    final current = item.trackingItems.isEmpty
        ? null
        : item.trackingItems.first.tracked.status;
    return AlertDialog(
      backgroundColor: context.appPalette.surface,
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.animeId != null || item.trackingItems.isNotEmpty) ...[
              Text(
                item.trackingItems.isEmpty
                    ? 'Add or update this show on your connected AniList and MAL accounts.'
                    : 'Update status on ${item.trackingItems.map((entry) => entry.provider.displayName).join(' and ')}',
                style: TextStyle(color: context.appPalette.mutedText),
              ),
              const SizedBox(height: 14),
              TrackingStatusOptions(
                current: current,
                onSelected: (status) => Navigator.of(context).pop(status),
              ),
            ] else
              Text(
                'Connect AniList or MAL to change this show\'s list status.',
                style: TextStyle(color: context.appPalette.mutedText),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: item.animeId == null && item.trackingItems.isEmpty,
          onPressed: () => Navigator.of(context).pop(_HomeShowAction.open),
          child: const Text('Open show'),
        ),
        if (item.historyMediaId != null)
          FilledButton.tonal(
            onPressed: () =>
                Navigator.of(context).pop(_HomeShowAction.removeLocal),
            child: const Text('Remove locally'),
          ),
      ],
    );
  }
}

List<_ShelfItem>? _historyShelfItems({
  required List<PlaybackCheckpoint>? localHistory,
  required TrackingHomeData? tracking,
}) {
  if (localHistory == null) return null;
  final tracked = <HomeTrackedAnime>[
    ...?tracking?.watching,
    ...?tracking?.planToWatch,
    ...?tracking?.completed,
  ];
  return [
    for (final checkpoint in localHistory)
      _ShelfItem.fromCheckpoint(checkpoint).copyWith(
        trackingItems: [
          for (final item in tracked)
            if ((item.provider == TrackingProvider.anilist &&
                    (item.anilistId ?? item.tracked.mediaId) ==
                        checkpoint.anilistMediaId) ||
                (item.provider == TrackingProvider.myAnimeList &&
                    checkpoint.malMediaId == item.tracked.mediaId))
              item,
        ],
      ),
  ];
}

bool _isTrackedAnime(AnimeSummary anime, List<HomeTrackedAnime> tracked) {
  final normalized = _normalizedAnimeTitle(anime.title);
  return tracked.any((item) {
    if (item.provider == TrackingProvider.anilist &&
        (item.anilistId ?? item.tracked.mediaId) == anime.id) {
      return true;
    }
    if (item.provider == TrackingProvider.myAnimeList &&
        anime.idMal == item.tracked.mediaId) {
      return true;
    }
    return _normalizedAnimeTitle(item.tracked.title) == normalized;
  });
}

String _normalizedAnimeTitle(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _shortDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
