import 'dart:async';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/discord/application/discord_account_link_resolver.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:anime_tv/features/settings/application/all_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/device_setup_controller.dart';
import 'package:anime_tv/features/settings/application/premiumize_settings_controller.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  static const _stepCount = 8;
  final _pages = PageController();
  int _step = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _setStep(int step) async {
    final next = step.clamp(0, _stepCount - 1);
    final shouldScan =
        next == 2 && ref.read(deviceSetupProvider).report == null;
    final deviceSetup = shouldScan
        ? ref.read(deviceSetupProvider.notifier)
        : null;
    setState(() => _step = next);
    await _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    if (shouldScan) unawaited(deviceSetup!.scan());
  }

  Future<void> _finish() async {
    final deviceSetup = ref.read(deviceSetupProvider.notifier);
    final setupProgress = ref.read(setupProgressProvider.notifier);
    final hasDeviceReport = ref.read(deviceSetupProvider).report != null;
    if (hasDeviceReport) await deviceSetup.markCompleted();
    await setupProgress.complete();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(settingsPreferencesProvider);
    return Scaffold(
      backgroundColor: context.appPalette.background,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Image.asset(
                    'assets/branding/tetotv_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Set up TetoTV',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                _SetupButton(
                  label: 'Skip setup',
                  icon: Icons.skip_next_rounded,
                  autofocus: true,
                  onPressed: _finish,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SetupProgress(step: _step, count: _stepCount),
            const SizedBox(height: 12),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const _WelcomeStep(),
                  _CustomizationStep(preferences: preferences),
                  _PrivacyCommunityStep(preferences: preferences),
                  const _DeviceStep(),
                  const _DebridStep(),
                  const _SourcesStep(),
                  const _TrackingStep(),
                  const _FinishedStep(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_step > 0)
                  _SetupButton(
                    label: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => _setStep(_step - 1),
                  ),
                const Spacer(),
                _SetupButton(
                  label: _step == _stepCount - 1 ? 'Finish' : 'Continue',
                  icon: _step == _stepCount - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  primary: true,
                  onPressed: _step == _stepCount - 1
                      ? _finish
                      : () => _setStep(_step + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) => _SetupPage(
    icon: Icons.auto_awesome_rounded,
    title: 'Welcome to TetoTV',
    subtitle:
        'This short walkthrough configures the interface, checks playback compatibility, and connects your services.',
    child: const Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _FeaturePill(Icons.tv_rounded, 'TV and mobile layouts'),
        _FeaturePill(Icons.high_quality_rounded, 'Device-aware playback'),
        _FeaturePill(Icons.cloud_done_rounded, 'Debrid streaming'),
        _FeaturePill(Icons.sync_rounded, 'Anime tracking'),
      ],
    ),
  );
}

class _CustomizationStep extends ConsumerWidget {
  const _CustomizationStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsPreferencesProvider.notifier);
    return _SetupPage(
      icon: Icons.tune_rounded,
      title: 'Make it yours',
      subtitle:
          'Choose a spacious cinematic Home or a denser layout, then keep only the shortcuts you use.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Home layout',
            children: [
              for (final layout in HomeLayout.values)
                _SetupChoice(
                  label: layout.displayName,
                  selected: preferences.homeLayout == layout,
                  onPressed: () => controller.setHomeLayout(layout),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Top navigation',
            children: [
              _SetupChoice(
                label: 'My List',
                selected: preferences.showMyList,
                onPressed: () =>
                    controller.setShowMyList(!preferences.showMyList),
              ),
              _SetupChoice(
                label: 'Discover',
                selected: preferences.showDiscover,
                onPressed: () =>
                    controller.setShowDiscover(!preferences.showDiscover),
              ),
              _SetupChoice(
                label: 'Calendar',
                selected: preferences.showCalendar,
                onPressed: () =>
                    controller.setShowCalendar(!preferences.showCalendar),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Home details',
            children: [
              _SetupChoice(
                label: 'Featured hero',
                selected: preferences.showHero,
                onPressed: () => controller.setShowHero(!preferences.showHero),
              ),
              _SetupChoice(
                label: 'Poster badges',
                selected: preferences.showPosterMetadata,
                onPressed: () => controller.setShowPosterMetadata(
                  !preferences.showPosterMetadata,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Text input keyboard',
            children: [
              _SetupChoice(
                label: 'TetoTV keyboard',
                selected: preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(true),
              ),
              _SetupChoice(
                label: 'Device keyboard',
                selected: !preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Preferred anime audio',
            children: [
              for (final audio in PlaybackAudioPreference.values)
                _SetupChoice(
                  label: audio.displayName,
                  selected: preferences.preferredAudio == audio,
                  onPressed: () => controller.setPreferredAudio(audio),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Automatic intro and outro skipping',
            children: [
              _SetupChoice(
                label: 'Skip intros',
                selected: preferences.autoSkipIntros,
                onPressed: () =>
                    controller.setAutoSkipIntros(!preferences.autoSkipIntros),
              ),
              _SetupChoice(
                label: 'Skip outros',
                selected: preferences.autoSkipOutros,
                onPressed: () =>
                    controller.setAutoSkipOutros(!preferences.autoSkipOutros),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Automatic skipping only runs when reliable timestamps are available. You can always use the on-screen skip button instead.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCommunityStep extends ConsumerWidget {
  const _PrivacyCommunityStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsPreferencesProvider.notifier);
    final isTelevision = ref.watch(isTelevisionProvider);
    final discord = ref.watch(discordPresenceControllerProvider);
    final discordController = ref.read(
      discordPresenceControllerProvider.notifier,
    );
    final discordLabel = discord.busy
        ? 'Connecting Discord'
        : !discord.loaded
        ? 'Checking Discord'
        : !discord.available
        ? 'Discord unavailable on this device'
        : discord.linked
        ? discord.enabled
              ? 'Discord linked and enabled'
              : 'Discord linked but disabled'
        : 'Link Discord (optional)';
    return _SetupPage(
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy and Discord',
      subtitle:
          'Every choice is optional and starts off. You can change it later in Settings.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Show this session in the anonymous live viewer count?',
            children: [
              _SetupChoice(
                label: 'Keep off',
                selected: !preferences.anonymousUsageCountEnabled,
                onPressed: () => settings.setAnonymousUsageCountEnabled(false),
              ),
              _SetupChoice(
                label: 'Enable live count',
                selected: preferences.anonymousUsageCountEnabled,
                onPressed: () => settings.setAnonymousUsageCountEnabled(true),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Only active/streaming state is counted. No show, episode, account, device ID, source, or URL is sent.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 18),
          _SetupChoiceRow(
            label:
                'Send anonymous crash and error reports to help improve TetoTV?',
            children: [
              _SetupChoice(
                label: 'Do not send',
                selected: !preferences.anonymousCrashReportingEnabled,
                onPressed: () =>
                    settings.setAnonymousCrashReportingEnabled(false),
              ),
              _SetupChoice(
                label: 'Allow error reports',
                selected: preferences.anonymousCrashReportingEnabled,
                onPressed: () =>
                    settings.setAnonymousCrashReportingEnabled(true),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Reports include the app/build, error type and time, Android version, CPU architecture, device class, and a redacted technical trace. They never include the show, episode, account, device ID, source, or URL.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 18),
          if (discord.busy || !discord.loaded || !discord.available)
            _FeaturePill(Icons.forum_rounded, discordLabel)
          else
            _SetupButton(
              label: discordLabel,
              icon: discord.linked ? Icons.check_rounded : Icons.forum_rounded,
              primary: !discord.linked,
              onPressed: discord.linked
                  ? () => discordController.setEnabled(!discord.enabled)
                  : () async {
                      final resolver = ref.read(
                        discordAccountLinkResolverProvider,
                      );
                      final flow = await resolver.resolve(
                        startupTelevision: isTelevision,
                      );
                      if (!context.mounted) return;
                      if (flow == DiscordAccountLinkFlow.deviceQr) {
                        await context.push('/pair/discord');
                      } else {
                        await discordController.linkAccount();
                      }
                    },
            ),
          const SizedBox(height: 9),
          Text(
            'Discord Rich Presence can show what you are watching. TetoTV never sees or stores your Discord password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          if (discord.error case final error?) ...[
            const SizedBox(height: 9),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appPalette.accentBright),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceStep extends ConsumerWidget {
  const _DeviceStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceSetupProvider);
    final report = state.report;
    return _SetupPage(
      icon: Icons.memory_rounded,
      title: 'Playback compatibility',
      subtitle:
          'TetoTV checks the device’s hardware decoders, HDR display, audio output, and anime subtitle renderer.',
      child: state.loading
          ? Padding(
              padding: const EdgeInsets.all(26),
              child: CircularProgressIndicator(
                color: context.appPalette.accentBright,
              ),
            )
          : state.error != null
          ? Column(
              children: [
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                _SetupButton(
                  label: 'Scan again',
                  icon: Icons.refresh_rounded,
                  onPressed: () =>
                      ref.read(deviceSetupProvider.notifier).scan(),
                ),
              ],
            )
          : report == null
          ? _SetupButton(
              label: 'Run scan',
              icon: Icons.play_arrow_rounded,
              primary: true,
              onPressed: () => ref.read(deviceSetupProvider.notifier).scan(),
            )
          : Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final check in report.checks)
                      _CapabilityPill(check: check),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  report.recommendation,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.appPalette.secondaryAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DebridStep extends ConsumerWidget {
  const _DebridStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final realDebrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final allDebrid = ref.watch(allDebridSettingsControllerProvider);
    final premiumize = ref.watch(premiumizeSettingsControllerProvider);
    final selectedConnected = switch (preferences.debridProvider) {
      DebridService.realDebrid => realDebrid.hasSavedToken,
      DebridService.torBox => torBox.hasSavedToken,
      DebridService.allDebrid => allDebrid.hasSavedToken,
      DebridService.premiumize => premiumize.hasSavedToken,
    };
    return _SetupPage(
      icon: Icons.cloud_done_rounded,
      title: 'Choose your debrid service',
      subtitle:
          'TetoTV only sends supported releases through the debrid provider you select.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Provider',
            children: [
              for (final service in DebridService.values)
                _SetupChoice(
                  label: service.displayName,
                  selected: preferences.debridProvider == service,
                  onPressed: () => ref
                      .read(settingsPreferencesProvider.notifier)
                      .setDebridProvider(service),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SetupButton(
            label: selectedConnected
                ? '${preferences.debridProvider.displayName} connected'
                : 'Connect ${preferences.debridProvider.displayName}',
            icon: selectedConnected
                ? Icons.check_rounded
                : Icons.qr_code_rounded,
            primary: !selectedConnected,
            onPressed: () => context.push(switch (preferences.debridProvider) {
              DebridService.realDebrid => '/pair/realdebrid',
              DebridService.torBox => '/pair/torbox',
              DebridService.allDebrid => '/pair/alldebrid',
              DebridService.premiumize => '/pair/premiumize',
            }),
          ),
        ],
      ),
    );
  }
}

class _SourcesStep extends ConsumerWidget {
  const _SourcesStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marketplace = ref.watch(marketplaceControllerProvider);
    final torrentSources = ref.watch(userTorrentSourcesControllerProvider);
    final repositoryCount = marketplace.repositories.length;
    final manifestCount = torrentSources.manifestUrls.length;
    return _SetupPage(
      icon: Icons.add_link_rounded,
      title: 'Add streaming sources',
      subtitle:
          'TetoTV does not bundle or recommend streaming sources. Add only Marketplace repositories and Torrent source manifests you trust and are authorized to use.',
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _SourceCount(
                icon: Icons.extension_rounded,
                count: repositoryCount,
                label: repositoryCount == 1
                    ? 'Marketplace repository'
                    : 'Marketplace repositories',
              ),
              _SourceCount(
                icon: Icons.cloud_download_outlined,
                count: manifestCount,
                label: manifestCount == 1
                    ? 'Torrent source manifest'
                    : 'Torrent source manifests',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _SetupButton(
                label: 'Add sources with phone',
                icon: Icons.phone_android_rounded,
                primary: true,
                onPressed: () => showSourcePairingDialog(context),
              ),
              _SetupButton(
                label: 'Open Marketplace manually',
                icon: Icons.tune_rounded,
                onPressed: () => context.push('/settings/marketplace'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'This step is optional. You can add or remove sources later in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _TrackingStep extends ConsumerWidget {
  const _TrackingStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final connected = accounts.isConnected(preferences.trackingProvider);
    return _SetupPage(
      icon: Icons.sync_alt_rounded,
      title: 'Connect an anime list',
      subtitle:
          'Choose the service that should populate My List and receive episode progress. You can change it later.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Tracking service',
            children: [
              for (final provider in TrackingProvider.values)
                _SetupChoice(
                  label: provider.displayName,
                  selected: preferences.trackingProvider == provider,
                  onPressed: () => ref
                      .read(settingsPreferencesProvider.notifier)
                      .setTrackingProvider(provider),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SetupButton(
            label: connected
                ? '${preferences.trackingProvider.displayName} connected'
                : 'Connect ${preferences.trackingProvider.displayName}',
            icon: connected ? Icons.check_rounded : Icons.qr_code_rounded,
            primary: !connected,
            onPressed: () => context.push(
              preferences.trackingProvider == TrackingProvider.anilist
                  ? '/pair/anilist'
                  : '/pair/myanimelist',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Connecting is optional. TetoTV can still browse and play without an anime-list account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _SourceCount extends StatelessWidget {
  const _SourceCount({
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.appPalette.secondaryAccent),
        const SizedBox(width: 7),
        Text(
          '$count',
          style: TextStyle(
            color: context.appPalette.accentBright,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _FinishedStep extends StatelessWidget {
  const _FinishedStep();

  @override
  Widget build(BuildContext context) => const _SetupPage(
    icon: Icons.check_circle_rounded,
    title: 'TetoTV is ready',
    subtitle:
        'Your choices are saved on this device. Everything in this walkthrough remains available under Settings → System.',
    child: _FeaturePill(Icons.play_arrow_rounded, 'Start watching'),
  );
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.isCompactWidth ? 18 : 28),
          decoration: BoxDecoration(
            color: context.appPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(
            children: [
              Icon(icon, color: context.appPalette.accentBright, size: 48),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appPalette.mutedText),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < count; index++) ...[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 4,
            decoration: BoxDecoration(
              color: index <= step
                  ? context.appPalette.accentBright
                  : Colors.white12,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        if (index != count - 1) const SizedBox(width: 5),
      ],
    ],
  );
}

class _SetupChoiceRow extends StatelessWidget {
  const _SetupChoiceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: children,
      ),
    ],
  );
}

class _SetupChoice extends StatelessWidget {
  const _SetupChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 40,
      padding: EdgeInsets.symmetric(
        horizontal: context.isCompactWidth ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: selected
            ? context.appPalette.accent
            : context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? context.appPalette.accentBright : Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(selected ? Icons.check_rounded : Icons.add_rounded, size: 17),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.appPalette.secondaryAccent),
        const SizedBox(width: 7),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.check});

  final CapabilityCheck check;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: check.supported
          ? const Color(0xFF143526)
          : context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          check.supported ? Icons.check_rounded : Icons.info_outline_rounded,
          size: 16,
        ),
        const SizedBox(width: 5),
        Text(
          check.label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _SetupButton extends StatelessWidget {
  const _SetupButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: primary
            ? context.appPalette.accent
            : context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: primary ? Colors.white : null),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primary ? Colors.white : null,
                fontSize: context.isCompactWidth ? 12 : null,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
