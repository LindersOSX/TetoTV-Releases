import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/home/presentation/main_navigation_bar.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AiringCalendarScreen extends ConsumerWidget {
  const AiringCalendarScreen({super.key});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(airingWeekProvider);
    final tracking = ref.watch(trackingHomeProvider);
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    return Scaffold(
      backgroundColor: context.appPalette == AppThemePalette.defaults
          ? Colors.black
          : context.appPalette.background,
      body: SafeArea(
        minimum: context.responsiveScreenPadding.copyWith(top: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MainNavigationBar(
              active: MainNavigationDestination.calendar,
              preferences: preferences,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TvFocusable(
                  autofocus: true,
                  onPressed: context.pop,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Airing calendar',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                if (!context.isCompactWidth)
                  Text(
                    'Times use your device timezone',
                    style: TextStyle(color: context.appPalette.mutedText),
                  ),
                const SizedBox(width: 10),
                TvFocusable(
                  onPressed: () {
                    ref.invalidate(airingWeekProvider);
                    ref.invalidate(trackingHomeProvider);
                  },
                  borderRadius: BorderRadius.circular(9),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Refresh'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: schedule.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: context.appPalette.accentBright,
                  ),
                ),
                error: (error, _) =>
                    Center(child: Text('Could not load schedule: $error')),
                data: (entries) {
                  if (tracking.isLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: context.appPalette.accentBright,
                      ),
                    );
                  }
                  if (tracking.hasError) {
                    return Center(
                      child: Text(
                        'Your AniList or MAL calendar could not be loaded. '
                        'Check the tracker connection in Settings, then select Refresh.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.appPalette.mutedText),
                      ),
                    );
                  }
                  final followed = <HomeTrackedAnime>[
                    ...?tracking.valueOrNull?.watching,
                    ...?tracking.valueOrNull?.planToWatch,
                  ];
                  final visibleEntries = entries
                      .where((entry) => _isFollowed(entry.anime, followed))
                      .toList(growable: false);
                  if (visibleEntries.isEmpty) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: Text(
                          'No followed shows are airing this week. Add a show '
                          'to Watching or Planning on AniList or MAL, then '
                          'refresh your list.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.appPalette.mutedText),
                        ),
                      ),
                    );
                  }
                  final days = <DateTime, List<AiringScheduleEntry>>{};
                  for (final entry in visibleEntries) {
                    final local = entry.airingAt.toLocal();
                    final day = DateTime(local.year, local.month, local.day);
                    (days[day] ??= []).add(entry);
                  }
                  return ListView(
                    children: [
                      for (final group in days.entries) ...[
                        Text(
                          '${_weekdays[group.key.weekday - 1]}  ${group.key.month}/${group.key.day}',
                          style: TextStyle(
                            color: context.appPalette.accentBright,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 108,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: group.value.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 9),
                            itemBuilder: (context, index) {
                              final entry = group.value[index];
                              final time = TimeOfDay.fromDateTime(
                                entry.airingAt.toLocal(),
                              ).format(context);
                              return SizedBox(
                                width: 270,
                                child: ColoredBox(
                                  color: const Color(0xFF141414),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TvFocusable(
                                          onPressed: () => context.push(
                                            '/anime/${entry.anime.id}',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 68,
                                                child: NetworkArtwork(
                                                  url:
                                                      entry.anime.coverImageUrl,
                                                  cacheWidth: 140,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      entry.anime.displayTitle(
                                                        titlePreference,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      '$time • Episode ${entry.episode}',
                                                      style: TextStyle(
                                                        color: context
                                                            .appPalette
                                                            .mutedText,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 38,
                                        child: TvFocusable(
                                          onPressed: () async {
                                            final saved = await AndroidTvBridge
                                                .instance
                                                .scheduleReminder(
                                                  mediaId: entry.anime.id,
                                                  episode: entry.episode,
                                                  title: entry.anime
                                                      .displayTitle(
                                                        titlePreference,
                                                      ),
                                                  airingAt: entry.airingAt,
                                                );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  saved
                                                      ? 'Reminder set for 10 minutes before airtime.'
                                                      : 'This airing is too soon for a reminder.',
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons
                                                  .notifications_active_outlined,
                                              size: 19,
                                              color: context
                                                  .appPalette
                                                  .accentBright,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isFollowed(AnimeSummary anime, List<HomeTrackedAnime> followed) {
  final normalized = _normalizedTitle(anime.title);
  return followed.any((item) {
    if (item.provider == TrackingProvider.anilist &&
        (item.anilistId ?? item.tracked.mediaId) == anime.id) {
      return true;
    }
    if (item.provider == TrackingProvider.myAnimeList &&
        anime.idMal == item.tracked.mediaId) {
      return true;
    }
    return _normalizedTitle(item.tracked.title) == normalized;
  });
}

String _normalizedTitle(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
