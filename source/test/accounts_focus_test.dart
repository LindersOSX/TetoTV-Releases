import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/presentation/accounts_screen.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const androidChannel = MethodChannel('dev.tetotv/android_tv');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  testWidgets('D-pad reaches Home shelves and switches to streaming', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TvShortcuts(child: AccountsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'accounts.back');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.area.customize',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.shelf.tracking',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.shelf.history',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.provider',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );
  });

  for (final layout in <(String, Size)>[
    ('TV', const Size(1280, 720)),
    ('phone', const Size(390, 844)),
  ]) {
    testWidgets(
      'Local Media entry stays hidden outside Developer Mode on ${layout.$1}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = layout.$2;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: AccountsScreen())),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Streaming'));
        await tester.pumpAndSettle();

        expect(find.text('Local media, Jellyfin & Plex'), findsNothing);
        expect(find.text('Open media'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Home shelves remain visible without a dropdown', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home section'), findsNothing);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Watch history'), findsOneWidget);
    expect(find.text('Recently released'), findsOneWidget);
    expect(find.text('Trending now'), findsOneWidget);
    expect(find.text('Plan to watch'), findsOneWidget);
    expect(find.text('Airing soon'), findsOneWidget);
    expect(find.text('Recently completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings uses the saved Theme Studio palette', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final palette = AppThemePalette.fromSeeds(
      background: const Color(0xFF102030),
      surface: const Color(0xFF203040),
      accent: const Color(0xFF00CC88),
      primaryText: const Color(0xFFF0FAFF),
      mutedText: const Color(0xFFA0B8C8),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkFor(palette),
          home: const AccountsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      palette.background,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == palette.accent,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == palette.surface,
      ),
      findsWidgets,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Choose what appears on Home and move favorites toward the top.',
            ),
          )
          .style
          ?.color,
      palette.mutedText,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home shelf rows toggle visibility and reorder in place', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue watching'));
    await tester.pumpAndSettle();
    expect(
      container.read(homeShelfPreferencesProvider),
      isNot(contains(HomeShelf.tracking)),
    );
    expect(find.text('HIDDEN'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Move Watch history up'));
    await tester.pumpAndSettle();
    expect(
      container.read(homeShelfOrderProvider).take(2),
      orderedEquals([HomeShelf.history, HomeShelf.tracking]),
    );
    expect(find.text('Home section'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad traverses all seven visible Home shelf rows in order', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TvShortcuts(child: AccountsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    for (final shelf in HomeShelf.values) {
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.shelf.${shelf.name}',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.customization.first',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad reaches the bottom AniList save action on a TV canvas', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optional private-repository token'), findsNothing);
    expect(find.text('Read-only GitHub token'), findsNothing);

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.anilist.save',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('title language toggle is reachable from the header', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.title-language',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Titles: Romaji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider selector only shows the chosen debrid configuration', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('TorBox API token'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('Connect by QR'), findsOneWidget);
    expect(find.text('Debrid provider'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Advanced: personal token'), findsNothing);
    expect(find.text('TorBox API token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad reaches automatic and manual update controls', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.automatic',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.check',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.setup',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.automatic',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.check',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord-presence',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord-qr',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.donation-qr',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.donate',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.clear-cache',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.reset-app',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.privacy',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.legal',
    );
    expect(find.text('Third-party notices'), findsOneWidget);
    expect(
      find.textContaining('AI-assisted development tools'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ten System activations unlock persistent update channels', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
          if (call.method == 'getAppVersion') {
            return <String, Object?>{
              'versionName': '1.0.0',
              'versionCode': 10000,
            };
          }
          return null;
        });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    for (var index = 0; index < 3; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.area.system',
    );
    for (var index = 0; index < 10; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final storage = const FlutterSecureStorage();
      for (var attempt = 0; attempt < 50; attempt++) {
        if (await storage.read(key: developerModeStorageKey) == 'true') return;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    });
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountsScreen)),
    );
    expect(container.read(appUpdateControllerProvider).developerMode, isTrue);
    expect(find.text('Developer mode'), findsOneWidget);
    expect(find.text('Update channel'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Load release history'), findsOneWidget);
    expect(find.textContaining('Beta key'), findsNothing);
    expect(find.textContaining('Installed version:'), findsOneWidget);
    expect(find.textContaining('Build:'), findsOneWidget);
    expect(
      await const FlutterSecureStorage().read(key: developerModeStorageKey),
      'true',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy Beta key is removed and key controls stay hidden', (
    tester,
  ) async {
    const betaKey = 'beta_test_access_key_0123456789abcdef';
    FlutterSecureStorage.setMockInitialValues({
      developerModeStorageKey: 'true',
      'beta_update_access_key': betaKey,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
          if (call.method == 'getAppVersion') {
            return <String, Object?>{
              'versionName': '1.0.0',
              'versionCode': 410001,
            };
          }
          return null;
        });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    for (var index = 0; index < 3; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Load release history'), findsOneWidget);
    expect(find.textContaining('Beta key'), findsNothing);
    expect(find.text(betaKey), findsNothing);
    expect(find.textContaining(betaKey), findsNothing);
    expect(
      await const FlutterSecureStorage().read(key: 'beta_update_access_key'),
      isNull,
    );
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.updates.release-history',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('System settings expose a remote-selectable Discord invite QR', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(find.byType(QrImageView, skipOffstage: false), findsNWidgets(2));
    expect(
      find.text('https://discord.gg/juC6k7d4WY', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('https://ko-fi.com/lindowsosx', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Discord Rich Presence', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('Double-click or press OK twice to copy', skipOffstage: false),
      findsNWidgets(2),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord-presence',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord-qr',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.discord',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.donation-qr',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.system.donate',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Discord Rich Presence actions align with update actions', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    final updateActions = find.byKey(
      const ValueKey('app-update-actions'),
      skipOffstage: false,
    );
    final discordActions = find.byKey(
      const ValueKey('discord-presence-actions'),
      skipOffstage: false,
    );
    expect(updateActions, findsOneWidget);
    expect(discordActions, findsOneWidget);

    await tester.ensureVisible(discordActions);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(discordActions).right,
      closeTo(tester.getRect(updateActions).right, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Storage actions fit phones and Clear cache preserves app data', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? method;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
          method = call.method;
          if (call.method == 'clearAppCache') return 1536;
          return null;
        });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    final clear = find.byKey(
      const ValueKey('storage-clear-cache'),
      skipOffstage: false,
    );
    final reset = find.byKey(
      const ValueKey('storage-reset-app'),
      skipOffstage: false,
    );
    expect(clear, findsOneWidget);
    expect(reset, findsOneWidget);
    expect(
      tester.getTopLeft(reset).dy,
      greaterThan(tester.getTopLeft(clear).dy),
      reason: 'Storage actions stack on a narrow phone without clipping.',
    );

    await tester.scrollUntilVisible(
      clear,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(method, 'clearAppCache');
    expect(find.text('Cleared 1.5 KB of temporary files.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reset requires two confirmations with safe cancel focus', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var resetCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
          if (call.method == 'resetApplicationData') {
            resetCalls++;
            return true;
          }
          return null;
        });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    final resetAction = find.byKey(
      const ValueKey('storage-reset-app'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      resetAction,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(resetAction);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-warning-dialog')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-warning-dialog')), findsNothing);
    expect(resetCalls, 0, reason: 'Enter activates the focused safe action.');
    await tester.tap(resetAction);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-warning-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-final-dialog')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-final-dialog')), findsNothing);
    expect(resetCalls, 0, reason: 'The second dialog also defaults to cancel.');
    await tester.tap(resetAction);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-warning-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-final-confirm')));
    await tester.pumpAndSettle();
    expect(resetCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected debrid traversal only targets visible controls', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      developerModeStorageKey: 'true',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
          if (call.method == 'getAppVersion') {
            return <String, Object?>{
              'versionName': '1.0.1',
              'versionCode': 410002,
            };
          }
          return null;
        });
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          realDebridSettingsControllerProvider.overrideWith(
            (_) => _ConnectedRealDebridController(),
          ),
        ],
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.debrid',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.debrid.connect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.local-media',
    );
    expect(find.text('Open media'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'accounts.streaming.local-media',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('organized settings sections fit a narrow mobile screen', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('APPEARANCE & NAVIGATION'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountsScreen)),
    );
    expect(
      container
          .read(settingsPreferencesProvider)
          .anonymousCrashReportingEnabled,
      isFalse,
    );
    final scaffold = find.byType(Scaffold).first;
    expect(tester.getTopLeft(scaffold), Offset.zero);
    expect(tester.getSize(scaffold), const Size(390, 844));
    expect(
      tester.widget<SafeArea>(find.byType(SafeArea).first).minimum,
      const EdgeInsets.symmetric(horizontal: 16),
      reason:
          'Settings controls need a responsive side inset on narrow screens.',
    );
    expect(tester.takeException(), isNull);

    final crashToggle = find.textContaining('Anonymous error reports');
    expect(crashToggle, findsOneWidget);
    await tester.ensureVisible(crashToggle);
    await tester.pumpAndSettle();
    await tester.tap(crashToggle);
    await tester.pumpAndSettle();
    expect(
      container
          .read(settingsPreferencesProvider)
          .anonymousCrashReportingEnabled,
      isTrue,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('filler labels setting is TV-focusable and updates globally', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TvShortcuts(child: AccountsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final enabledLabel = find.text('Show filler episode labels ON');
    expect(enabledLabel, findsOneWidget);
    await tester.ensureVisible(enabledLabel);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: enabledLabel, matching: find.byType(TvFocusable)),
      findsOneWidget,
    );

    await tester.tap(enabledLabel);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountsScreen)),
    );
    expect(
      container.read(settingsPreferencesProvider).showFillerIndicators,
      isFalse,
    );
    expect(find.text('Show filler episode labels OFF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device keyboard does not open while D-pad traverses token to Marketplace',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'input_use_built_in_keyboard': 'false',
      });
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AccountsScreen())),
      );
      await tester.pumpAndSettle();

      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.torbox.token',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.streaming.marketplace',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'accounts.torbox.token',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ConnectedRealDebridController extends RealDebridSettingsController {
  _ConnectedRealDebridController()
    : super(const FlutterSecureStorage(), (_) => throw UnimplementedError()) {
    state = const RealDebridSettingsState(
      hasSavedToken: true,
      account: RealDebridAccount(
        id: 1,
        username: 'connected-user',
        type: 'premium',
      ),
    );
  }

  @override
  Future<void> load() async {}
}
