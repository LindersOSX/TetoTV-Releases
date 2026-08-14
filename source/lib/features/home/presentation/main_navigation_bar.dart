import 'dart:math' as math;

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum MainNavigationDestination { home, myList, discover, calendar }

/// Keeps primary navigation stable while presenting linked tracker information
/// as a lightweight, informational part of the same row. The tracker summary
/// intentionally never participates in remote focus traversal.
class MainNavigationBar extends ConsumerWidget {
  const MainNavigationBar({
    required this.active,
    required this.preferences,
    this.onHomePressed,
    this.homeFocusNode,
    this.autofocusActive = false,
    super.key,
  });

  final MainNavigationDestination active;
  final SettingsPreferences preferences;
  final VoidCallback? onHomePressed;
  final FocusNode? homeFocusNode;
  final bool autofocusActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final profiles = [
      for (final provider in TrackingProvider.values)
        ?accounts.profiles[provider],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final normalTvLayout = width >= 700;
        final showWordmark = width >= 900;
        final showFullProfile = profiles.isNotEmpty && width >= 900;
        final showCompactProfile =
            profiles.isNotEmpty && width >= 380 && !showFullProfile;
        final showEveryProfile = profiles.length > 1 && width >= 1400;
        // Header height depends only on width, never on asynchronously loaded
        // account data, so linking/loading a tracker cannot shift the screen.
        final headerHeight = width >= 760 ? 96.0 : 62.0;

        return SizedBox(
          key: const ValueKey('main-navigation'),
          width: double.infinity,
          height: headerHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showWordmark) ...[
                const _TetoTvWordmark(),
                const SizedBox(width: 8),
              ],
              if (preferences.showSearch) ...[
                _NavigationAction(
                  key: const ValueKey('main-nav-search'),
                  icon: Icons.search_rounded,
                  label: 'Search',
                  compact: true,
                  onPressed: () => context.push('/search'),
                ),
                SizedBox(width: normalTvLayout ? 4 : 2),
              ],
              _NavigationAction(
                key: const ValueKey('main-nav-home'),
                icon: Icons.home_rounded,
                label: 'Home',
                compact: true,
                active: active == MainNavigationDestination.home,
                autofocus:
                    autofocusActive && active == MainNavigationDestination.home,
                focusNode: homeFocusNode,
                onPressed: onHomePressed ?? () => context.go('/'),
              ),
              if (preferences.showMyList) ...[
                SizedBox(width: normalTvLayout ? 4 : 2),
                _NavigationAction(
                  key: const ValueKey('main-nav-my-list'),
                  icon: Icons.video_library_rounded,
                  label: 'My List',
                  compact: false,
                  active: active == MainNavigationDestination.myList,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.myList,
                  onPressed: active == MainNavigationDestination.myList
                      ? () {}
                      : () => context.go('/my-list'),
                ),
              ],
              if (preferences.showDiscover) ...[
                SizedBox(width: normalTvLayout ? 4 : 2),
                _NavigationAction(
                  key: const ValueKey('main-nav-discover'),
                  icon: Icons.explore_rounded,
                  label: 'Discover',
                  compact: true,
                  active: active == MainNavigationDestination.discover,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.discover,
                  onPressed: active == MainNavigationDestination.discover
                      ? () {}
                      : () => context.go('/discover'),
                ),
              ],
              if (preferences.showCalendar) ...[
                SizedBox(width: normalTvLayout ? 4 : 2),
                _NavigationAction(
                  key: const ValueKey('main-nav-calendar'),
                  icon: Icons.calendar_month_rounded,
                  label: 'Calendar',
                  compact: true,
                  active: active == MainNavigationDestination.calendar,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.calendar,
                  onPressed: active == MainNavigationDestination.calendar
                      ? () {}
                      : () => context.go('/calendar'),
                ),
              ],
              SizedBox(width: normalTvLayout ? 4 : 2),
              _NavigationAction(
                key: const ValueKey('main-nav-settings'),
                icon: Icons.settings_rounded,
                label: 'Settings',
                compact: width < 1200,
                onPressed: () => context.push('/settings/accounts'),
              ),
              if (showFullProfile || showCompactProfile) ...[
                SizedBox(width: normalTvLayout ? 8 : 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, profileConstraints) {
                      final maximumWidth = showEveryProfile ? 830.0 : 410.0;
                      return Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: math.min(
                            profileConstraints.maxWidth,
                            showCompactProfile ? 190.0 : maximumWidth,
                          ),
                          height: showCompactProfile ? 34 : 58,
                          child: showFullProfile
                              ? _TrackerIdentitySummary(
                                  profiles: profiles,
                                  showEveryProfile: showEveryProfile,
                                )
                              : _CompactTrackerIdentitySummary(
                                  profiles: profiles,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TetoTvWordmark extends StatelessWidget {
  const _TetoTvWordmark();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w900,
      letterSpacing: -.45,
    );
    return Semantics(
      key: const ValueKey('main-nav-wordmark'),
      label: 'Teto TV',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Teto',
            key: const ValueKey('main-nav-wordmark-teto'),
            style: style.copyWith(color: context.appPalette.primaryText),
          ),
          const SizedBox(width: 4),
          Text(
            'TV',
            key: const ValueKey('main-nav-wordmark-tv'),
            style: style.copyWith(color: context.appPalette.accent),
          ),
        ],
      ),
    );
  }
}

class _TrackerIdentitySummary extends StatelessWidget {
  const _TrackerIdentitySummary({
    required this.profiles,
    required this.showEveryProfile,
  });

  final List<TrackingAccountProfile> profiles;
  final bool showEveryProfile;

  @override
  Widget build(BuildContext context) {
    final label = profiles
        .map(
          (profile) => '${profile.username} on ${profile.provider.displayName}',
        )
        .join(', ');
    final visibleProfiles = showEveryProfile
        ? profiles
        : profiles.take(1).toList(growable: false);
    final hiddenProfiles = showEveryProfile
        ? const <TrackingAccountProfile>[]
        : profiles.skip(1).toList(growable: false);
    return ExcludeFocus(
      child: Semantics(
        key: const ValueKey('main-nav-profile-summary'),
        container: true,
        label: 'Linked tracker profiles: $label',
        excludeSemantics: true,
        child: Row(
          children: [
            for (var index = 0; index < visibleProfiles.length; index++) ...[
              Expanded(
                child: _FullTrackerProfile(
                  profile: visibleProfiles[index],
                  additionalProfiles: index == 0
                      ? hiddenProfiles
                      : const <TrackingAccountProfile>[],
                ),
              ),
              if (index != visibleProfiles.length - 1)
                const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _FullTrackerProfile extends StatelessWidget {
  const _FullTrackerProfile({
    required this.profile,
    required this.additionalProfiles,
  });

  final TrackingAccountProfile profile;
  final List<TrackingAccountProfile> additionalProfiles;

  @override
  Widget build(BuildContext context) {
    final slug = profile.provider.slug;
    return Container(
      key: ValueKey('main-nav-profile-$slug'),
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          _ProfileAvatar(profile: profile, size: 44),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appPalette.primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ProviderBadge(provider: profile.provider, compact: true),
                    if (additionalProfiles.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      _LinkedProfilesIndicator(
                        profiles: additionalProfiles,
                        compact: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  key: ValueKey('main-nav-profile-stats-$slug'),
                  children: [
                    Expanded(
                      child: _ProfileStat(
                        key: ValueKey('main-nav-profile-stat-$slug-titles'),
                        icon: Icons.video_library_outlined,
                        text: profile.animeCount == null
                            ? '— titles'
                            : '${_readableCount(profile.animeCount!)} titles',
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        key: ValueKey('main-nav-profile-stat-$slug-episodes'),
                        icon: Icons.play_circle_outline_rounded,
                        text: profile.episodesWatched == null
                            ? '— episodes'
                            : '${_readableCount(profile.episodesWatched!)} episodes',
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        key: ValueKey('main-nav-profile-stat-$slug-time'),
                        icon: Icons.schedule_rounded,
                        text: profile.minutesWatched == null
                            ? '— watched'
                            : _watchedDuration(profile.minutesWatched!),
                      ),
                    ),
                    Expanded(
                      child: _ProfileStat(
                        key: ValueKey('main-nav-profile-stat-$slug-mean'),
                        icon: Icons.star_rounded,
                        text: profile.meanScore == null
                            ? 'Mean —/${profile.provider == TrackingProvider.anilist ? 100 : 10}'
                            : 'Mean ${profile.meanScore!.toStringAsFixed(1)}/${profile.provider == TrackingProvider.anilist ? 100 : 10}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: context.appPalette.mutedText),
          const SizedBox(width: 3),
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTrackerIdentitySummary extends StatelessWidget {
  const _CompactTrackerIdentitySummary({required this.profiles});

  final List<TrackingAccountProfile> profiles;

  @override
  Widget build(BuildContext context) {
    final label = profiles
        .map(
          (profile) => '${profile.username} on ${profile.provider.displayName}',
        )
        .join(', ');
    return ExcludeFocus(
      child: Semantics(
        key: const ValueKey('main-nav-profile-summary'),
        container: true,
        label: 'Linked tracker profiles: $label',
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('main-nav-profile-compact-shell'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 120) {
                final additional = profiles.length > 1
                    ? ' +${profiles.length - 1} ${profiles.skip(1).map((profile) => profile.provider.displayName).join('/')}'
                    : '';
                return Container(
                  key: ValueKey(
                    'main-nav-profile-${profiles.first.provider.slug}',
                  ),
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${profiles.first.provider.displayName}: ${profiles.first.username}$additional',
                      maxLines: 1,
                      style: TextStyle(
                        color: context.appPalette.primaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _CompactProfileIdentity(profile: profiles.first),
                  ),
                  if (profiles.length > 1) ...[
                    const SizedBox(width: 5),
                    _LinkedProfilesIndicator(
                      profiles: profiles.skip(1).toList(growable: false),
                      compact: true,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompactProfileIdentity extends StatelessWidget {
  const _CompactProfileIdentity({required this.profile});

  final TrackingAccountProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('main-nav-profile-${profile.provider.slug}'),
      children: [
        _ProviderBadge(provider: profile.provider, compact: true),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            profile.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.appPalette.primaryText,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkedProfilesIndicator extends StatelessWidget {
  const _LinkedProfilesIndicator({
    required this.profiles,
    this.compact = false,
  });

  final List<TrackingAccountProfile> profiles;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final providers = profiles
        .map((profile) => profile.provider.displayName)
        .join('/');
    return Container(
      key: const ValueKey('main-nav-profile-additional'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 2 : 3,
      ),
      child: Text(
        compact
            ? '+${profiles.length} $providers'
            : '+${profiles.length} linked · $providers',
        maxLines: 1,
        style: TextStyle(
          color: context.appPalette.mutedText,
          fontSize: compact ? 7.5 : 8.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider, this.compact = false});

  final TrackingProvider provider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: context.appPalette.accent.withValues(alpha: .24),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        provider.displayName,
        style: TextStyle(
          color: context.appPalette.accentBright,
          fontSize: compact ? 8 : 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _readableCount(int value) {
  if (value < 10000) return '$value';
  if (value < 1000000) {
    final digits = value >= 100000 ? 0 : 1;
    return '${(value / 1000).toStringAsFixed(digits)}K';
  }
  final digits = value >= 10000000 ? 0 : 1;
  return '${(value / 1000000).toStringAsFixed(digits)}M';
}

String _watchedDuration(int minutes) {
  if (minutes < 60) return '${minutes}m watched';
  return '${(minutes / 60).round()}h watched';
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.size});

  final TrackingAccountProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('main-nav-profile-avatar-${profile.provider.slug}'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appPalette.surfaceRaised,
      ),
      child: NetworkArtwork(
        url: profile.avatarUrl,
        cacheWidth: (size * 2).round(),
        icon: Icons.person_rounded,
      ),
    );
  }
}

class _NavigationAction extends StatelessWidget {
  const _NavigationAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.compact = false,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool compact;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? label : '',
      child: TvFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(7),
        focusScale: 1.02,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 11,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: active
                ? context.appPalette.accent.withValues(alpha: .13)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active
                    ? context.appPalette.accentBright
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active
                    ? context.appPalette.accentBright
                    : context.appPalette.primaryText,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
