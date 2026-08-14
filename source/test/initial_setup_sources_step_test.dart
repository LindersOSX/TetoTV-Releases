import 'dart:async';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:anime_tv/features/discord/application/discord_account_link_resolver.dart';
import 'package:anime_tv/features/marketplace/application/source_pairing_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/domain/source_pairing.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:anime_tv/features/settings/presentation/initial_setup_screen.dart';
import 'package:anime_tv/features/settings/application/device_setup_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('setup saves audio and automatic skip preferences', (
    tester,
  ) async {
    await _pumpSetup(tester, const Size(1280, 720));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Preferred anime audio'), findsOneWidget);
    expect(find.text('Automatic intro and outro skipping'), findsOneWidget);

    await tester.ensureVisible(find.text('Subtitled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subtitled'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip intros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip intros'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Skip outros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip outros'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(InitialSetupScreen)),
    );
    final preferences = container.read(settingsPreferencesProvider);
    expect(preferences.preferredAudio, PlaybackAudioPreference.sub);
    expect(preferences.autoSkipIntros, isTrue);
    expect(preferences.autoSkipOutros, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fresh setup defaults to TetoTV keyboard and saves D-pad choice',
    (tester) async {
      await _pumpSetup(tester, const Size(1280, 720));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Text input keyboard'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InitialSetupScreen)),
      );
      expect(
        container.read(settingsPreferencesProvider).useBuiltInKeyboard,
        isTrue,
      );

      await tester.ensureVisible(find.text('Device keyboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device keyboard'));
      await tester.pumpAndSettle();

      expect(
        container.read(settingsPreferencesProvider).useBuiltInKeyboard,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('setup asks before enabling anonymous choices or Discord', (
    tester,
  ) async {
    final discord = await _pumpSetup(tester, const Size(1280, 720));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy and Discord'), findsOneWidget);
    expect(find.text('Keep off'), findsOneWidget);
    expect(find.text('Enable live count'), findsOneWidget);
    expect(find.text('Do not send'), findsOneWidget);
    expect(find.text('Allow error reports'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InitialSetupScreen)),
    );
    expect(
      container.read(settingsPreferencesProvider).anonymousUsageCountEnabled,
      isFalse,
    );
    expect(
      container
          .read(settingsPreferencesProvider)
          .anonymousCrashReportingEnabled,
      isFalse,
    );

    await tester.tap(find.text('Enable live count'));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsPreferencesProvider).anonymousUsageCountEnabled,
      isTrue,
    );

    await tester.tap(find.text('Allow error reports'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(settingsPreferencesProvider)
          .anonymousCrashReportingEnabled,
      isTrue,
    );

    await tester.tap(find.text('Link Discord (optional)'));
    await tester.pumpAndSettle();
    expect(discord.authenticateCalls, 1);
    expect(find.text('Discord linked and enabled'), findsOneWidget);
  });

  testWidgets('TV setup opens device pairing without launching a browser', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/setup',
      routes: [
        GoRoute(
          path: '/setup',
          builder: (context, state) => const InitialSetupScreen(),
        ),
        GoRoute(
          path: '/pair/discord',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('TV DISCORD PAIRING'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    final discord = await _pumpSetup(
      tester,
      const Size(1280, 720),
      isTelevision: true,
      router: router,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link Discord (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('TV DISCORD PAIRING'), findsOneWidget);
    expect(discord.authenticateCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup repairs a stale Fire TV flag before Discord linking', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/setup',
      routes: [
        GoRoute(
          path: '/setup',
          builder: (context, state) => const InitialSetupScreen(),
        ),
        GoRoute(
          path: '/pair/discord',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('TV DISCORD PAIRING'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    final discord = await _pumpSetup(
      tester,
      const Size(1280, 720),
      isTelevision: false,
      nativeCategory: AndroidDeviceCategory.television,
      router: router,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link Discord (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('TV DISCORD PAIRING'), findsOneWidget);
    expect(discord.authenticateCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV setup places Sources between Debrid and tracking', (
    tester,
  ) async {
    await _pumpSetup(tester, const Size(1280, 720));

    // Skip setup starts focused. Down enters the persistent Continue action;
    // focus then stays there while each page advances.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    for (var index = 0; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    _expectSourcesStep(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add sources with phone'));
    await tester.pumpAndSettle();
    expect(find.byType(SourcePairingDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Connect an anime list'), findsOneWidget);
  });

  testWidgets('Sources setup step fits a narrow phone without overflow', (
    tester,
  ) async {
    await _pumpSetup(tester, const Size(390, 844));
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    _expectSourcesStep(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<_SetupDiscordPlatform> _pumpSetup(
  WidgetTester tester,
  Size size, {
  bool isTelevision = false,
  AndroidDeviceCategory? nativeCategory,
  GoRouter? router,
}) async {
  FlutterSecureStorage.setMockInitialValues({
    userTorrentSourceManifestsStorageKey:
        '["https://one.example/manifest.json",'
        '"https://two.example/manifest.json",'
        '"https://three.example/manifest.json"]',
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final marketplace = _StaticMarketplaceController(
    MarketplaceState(
      repositories: [
        AddonRepository(
          url: 'https://one.example/marketplace.json',
          updatedAt: DateTime(2026),
        ),
        AddonRepository(
          url: 'https://two.example/marketplace.json',
          updatedAt: DateTime(2026),
        ),
      ],
      loading: false,
    ),
  );
  final pairing = _StaticSourcePairingController();
  final deviceSetup = _StaticDeviceSetupController();
  final discord = _SetupDiscordPlatform();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceControllerProvider.overrideWith((_) => marketplace),
        sourcePairingControllerProvider.overrideWith((_) => pairing),
        deviceSetupProvider.overrideWith((_) => deviceSetup),
        discordPresencePlatformProvider.overrideWithValue(discord),
        isTelevisionProvider.overrideWithValue(isTelevision),
        discordAccountLinkResolverProvider.overrideWithValue(
          DiscordAccountLinkResolver(
            () async =>
                nativeCategory ??
                (isTelevision
                    ? AndroidDeviceCategory.television
                    : AndroidDeviceCategory.mobile),
          ),
        ),
      ],
      child: router == null
          ? const MaterialApp(home: InitialSetupScreen())
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return discord;
}

void _expectSourcesStep(WidgetTester tester) {
  expect(find.text('Add streaming sources'), findsOneWidget);
  expect(find.textContaining('does not bundle or recommend'), findsOneWidget);
  expect(find.text('2'), findsOneWidget);
  expect(find.text('Marketplace repositories'), findsOneWidget);
  expect(find.text('3'), findsOneWidget);
  expect(find.text('Torrent source manifests'), findsOneWidget);
  expect(find.text('Add sources with phone'), findsOneWidget);
  expect(find.text('Open Marketplace manually'), findsOneWidget);
  expect(find.text('Skip setup'), findsOneWidget);
  expect(find.text('Back'), findsOneWidget);
  expect(find.text('Continue'), findsOneWidget);
}

class _StaticMarketplaceController extends MarketplaceController {
  _StaticMarketplaceController(MarketplaceState initial)
    : this._(AddonStore(TetoTvDatabase.instance), initial);

  _StaticMarketplaceController._(AddonStore store, MarketplaceState initial)
    : super(store, MarketplaceClient(store)) {
    state = initial;
  }

  @override
  Future<void> load() async {}
}

class _StaticSourcePairingController extends SourcePairingController {
  _StaticSourcePairingController()
    : super(
        () async => null,
        (_) => throw UnimplementedError(),
        (_) async => const SourceImportSummary(),
      );

  @override
  Future<void> start() async {
    state = const SourcePairingState(
      stage: SourcePairingStage.failed,
      message: 'Pairing fixture',
    );
  }
}

class _StaticDeviceSetupController extends DeviceSetupController {
  _StaticDeviceSetupController() : super(const FlutterSecureStorage()) {
    state = DeviceSetupState(
      report: buildDeviceCalibrationReport(const TvDeviceProfile.unknown()),
    );
  }

  @override
  Future<void> scan() async {}
}

class _SetupDiscordPlatform implements DiscordPresencePlatform {
  int authenticateCalls = 0;

  @override
  Stream<DiscordBridgeEvent> get events => const Stream.empty();

  @override
  Future<DiscordTokenBundle> authenticate() async {
    authenticateCalls++;
    return DiscordTokenBundle(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      tokenType: 0,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      scopes: 'openid sdk.social_layer_presence',
    );
  }

  @override
  Future<void> cancelAuthentication() async {}

  @override
  Future<void> connect(DiscordTokenBundle token) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<DiscordTokenBundle> refreshToken(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<bool> revoke(String token) async => true;

  @override
  Future<Map<Object?, Object?>> sdkInfo() async => {
    'available': true,
    'status': 'disconnected',
    'version': '1.10.18369',
  };
}
