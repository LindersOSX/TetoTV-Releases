import 'package:anime_tv/app/router.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/diagnostics/anonymous_crash_reporter.dart';
import 'package:anime_tv/core/layout/interface_scaling.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/telemetry/anonymous_usage_reporter.dart';
import 'package:anime_tv/core/tv/interaction_sound_scope.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/theme_studio_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TetoTvApp extends ConsumerWidget {
  const TetoTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final appPalette = ref.watch(themeStudioControllerProvider).palette;
    final isTelevision = ref.watch(isTelevisionProvider);
    ref.watch(trackingOutboxFlushProvider);
    // Rich Presence is opt-in. Watching the controller only restores an
    // already-linked session; fresh installs do not contact Discord.
    ref.watch(discordPresenceControllerProvider);
    // Anonymous crash delivery is consent-gated and remains dormant until the
    // encrypted preference has loaded. Native crashes are retried next launch.
    ref.watch(anonymousCrashReporterProvider);
    // Development and widget-test sessions must not inflate community counts.
    // Production/profile APKs initialize the anonymous reporter normally.
    if (!kDebugMode) {
      ref.watch(anonymousUsageReporterProvider);
    }
    return MaterialApp.router(
      title: 'TetoTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkFor(appPalette),
      routerConfig: appRouter,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final content = InteractionSoundScope(
          navigationEnabled: preferences.navigationSounds,
          clickEnabled: preferences.clickSounds,
          child: TvShortcuts(child: child ?? const SizedBox.shrink()),
        );
        final scale = interfaceCanvasScale(
          logicalWidth: mq.size.width,
          physicalWidth: View.of(context).physicalSize.width,
          detectedTelevision: isTelevision,
          mode: preferences.interfaceMode,
          userScale: preferences.interfaceScale,
        );

        return InterfaceScaleViewport(
          mediaQuery: mq,
          scale: scale,
          child: content,
        );
      },
    );
  }
}
