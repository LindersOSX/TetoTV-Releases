import 'dart:async';

import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stream source and keyboard preferences persist', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = SettingsPreferencesController(storage);

    await controller.setDebridStreamsEnabled(false);
    await controller.setWebStreamsEnabled(false);
    await controller.setUseBuiltInKeyboard(false);
    await controller.setAutoSkipIntros(true);
    await controller.setAutoSkipOutros(true);
    await controller.setShowFillerIndicators(false);
    await controller.setHomeLayout(HomeLayout.compact);
    await controller.setShowMyList(false);
    await controller.setShowDiscover(false);
    await controller.setShowCalendar(false);
    await controller.setShowHero(false);
    await controller.setShowPosterMetadata(false);
    await controller.setShowCardSubtitles(false);
    await controller.setTrackerUpdateThreshold(TrackerUpdateThreshold.halfway);
    await controller.setInterfaceMode(InterfaceMode.phone);
    await controller.setInterfaceScale(.8);
    await controller.setNavigationSounds(false);
    await controller.setClickSounds(false);
    await controller.setPreferredPlayer(PreferredPlayer.vlc);
    await controller.setPreferredAudio(PlaybackAudioPreference.sub);
    await controller.setDefaultLandingPage(LandingPage.myList);
    await controller.setAnonymousUsageCountEnabled(false);
    await controller.setAnonymousCrashReportingEnabled(true);

    final restored = SettingsPreferencesController(storage);
    await restored.load();
    expect(restored.state.debridStreamsEnabled, isFalse);
    expect(restored.state.webStreamsEnabled, isFalse);
    expect(restored.state.useBuiltInKeyboard, isFalse);
    expect(restored.state.autoSkipIntros, isTrue);
    expect(restored.state.autoSkipOutros, isTrue);
    expect(restored.state.showFillerIndicators, isFalse);
    expect(restored.state.homeLayout, HomeLayout.compact);
    expect(restored.state.showMyList, isFalse);
    expect(restored.state.showDiscover, isFalse);
    expect(restored.state.showCalendar, isFalse);
    expect(restored.state.showHero, isFalse);
    expect(restored.state.showPosterMetadata, isFalse);
    expect(restored.state.showCardSubtitles, isFalse);
    expect(
      restored.state.trackerUpdateThreshold,
      TrackerUpdateThreshold.halfway,
    );
    expect(restored.state.interfaceMode, InterfaceMode.phone);
    expect(restored.state.interfaceScale, .8);
    expect(restored.state.navigationSounds, isFalse);
    expect(restored.state.clickSounds, isFalse);
    expect(restored.state.preferredPlayer, PreferredPlayer.vlc);
    expect(restored.state.preferredAudio, PlaybackAudioPreference.sub);
    expect(restored.state.defaultLandingPage, LandingPage.myList);
    expect(restored.state.anonymousUsageCountEnabled, isFalse);
    expect(restored.state.anonymousCrashReportingEnabled, isTrue);
    expect(restored.state.loaded, isTrue);
  });

  test('fresh installs keep anonymous reporting off by default', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );
    await controller.load();

    expect(controller.state.debridStreamsEnabled, isTrue);
    expect(controller.state.webStreamsEnabled, isTrue);
    expect(controller.state.useBuiltInKeyboard, isTrue);
    expect(controller.state.autoSkipIntros, isFalse);
    expect(controller.state.autoSkipOutros, isFalse);
    expect(controller.state.showFillerIndicators, isTrue);
    expect(controller.state.homeLayout, HomeLayout.cinematic);
    expect(controller.state.interfaceMode, InterfaceMode.automatic);
    expect(controller.state.navigationSounds, isTrue);
    expect(controller.state.clickSounds, isTrue);
    expect(controller.state.defaultLandingPage, LandingPage.home);
    expect(controller.state.showMyList, isTrue);
    expect(controller.state.showDiscover, isTrue);
    expect(controller.state.showCalendar, isTrue);
    expect(controller.state.anonymousUsageCountEnabled, isFalse);
    expect(controller.state.anonymousCrashReportingEnabled, isFalse);
    expect(controller.state.preferredAudio, PlaybackAudioPreference.dub);
    expect(controller.state.loaded, isTrue);
    expect(
      controller.state.trackerUpdateThreshold,
      TrackerUpdateThreshold.nearlyFinished,
    );
  });

  test(
    'completed legacy installs without a keyboard choice keep device input',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        initialSetupCompletedStorageKey: 'true',
      });
      final controller = SettingsPreferencesController(
        const FlutterSecureStorage(),
      );

      await controller.load();

      expect(controller.state.useBuiltInKeyboard, isFalse);
    },
  );

  test('legacy installs migrate to visible filler indicators', () async {
    FlutterSecureStorage.setMockInitialValues({
      initialSetupCompletedStorageKey: 'true',
      'player_auto_skip_intros': 'true',
    });
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );

    await controller.load();

    expect(controller.state.showFillerIndicators, isTrue);
  });

  test('reset appearance restores visible filler indicators', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = SettingsPreferencesController(storage);

    await controller.setShowFillerIndicators(false);
    expect(controller.state.showFillerIndicators, isFalse);
    await controller.resetAppearance();
    expect(controller.state.showFillerIndicators, isTrue);

    final restored = SettingsPreferencesController(storage);
    await restored.load();
    expect(restored.state.showFillerIndicators, isTrue);
  });

  test('explicit built-in keyboard choice is preserved', () async {
    FlutterSecureStorage.setMockInitialValues({
      'input_use_built_in_keyboard': 'true',
    });
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );

    await controller.load();

    expect(controller.state.useBuiltInKeyboard, isTrue);
  });

  test('explicit device keyboard choice is preserved', () async {
    FlutterSecureStorage.setMockInitialValues({
      'input_use_built_in_keyboard': 'false',
      initialSetupCompletedStorageKey: 'true',
    });
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );

    await controller.load();

    expect(controller.state.useBuiltInKeyboard, isFalse);
  });

  test('anonymous live counting persists only after explicit opt in', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = SettingsPreferencesController(storage);

    await controller.setAnonymousUsageCountEnabled(true);
    final restored = SettingsPreferencesController(storage);
    await restored.load();

    expect(restored.state.anonymousUsageCountEnabled, isTrue);
  });

  test(
    'anonymous crash reporting persists only after explicit opt in',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final controller = SettingsPreferencesController(storage);

      expect(controller.state.anonymousCrashReportingEnabled, isFalse);
      await controller.setAnonymousCrashReportingEnabled(true);
      final restored = SettingsPreferencesController(storage);
      await restored.load();

      expect(restored.state.anonymousCrashReportingEnabled, isTrue);
    },
  );

  test('hidden navigation route cannot remain the landing page', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );

    await controller.setDefaultLandingPage(LandingPage.search);
    expect(controller.state.defaultLandingPage, LandingPage.search);
    await controller.setShowSearch(false);

    expect(controller.state.showSearch, isFalse);
    expect(controller.state.defaultLandingPage, LandingPage.home);
    expect(controller.takeInitialLandingRoute(), isNull);
  });

  test('configured landing page is consumed only once per launch', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
    );
    await controller.setDefaultLandingPage(LandingPage.calendar);

    expect(controller.takeInitialLandingRoute(), '/calendar');
    expect(controller.takeInitialLandingRoute(), isNull);
  });

  test('one failed storage read does not discard other preferences', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SettingsPreferencesController(
      const FlutterSecureStorage(),
      readValue: (key) async {
        if (key == 'appearance_caption_text_size') {
          throw StateError('one encrypted value is unavailable');
        }
        return const {
          'streaming_web_enabled': 'false',
          'audio_navigation_sounds': 'false',
          'navigation_default_landing_page': 'search',
        }[key];
      },
    );

    await controller.load();

    expect(controller.state.captionTextSize, 34);
    expect(controller.state.webStreamsEnabled, isFalse);
    expect(controller.state.navigationSounds, isFalse);
    expect(controller.state.defaultLandingPage, LandingPage.search);
  });

  test(
    'startup load is single-flight and preserves an early mutation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final gate = Completer<void>();
      var reads = 0;
      final controller = SettingsPreferencesController(
        const FlutterSecureStorage(),
        readValue: (key) async {
          reads++;
          await gate.future;
          return const {
            'streaming_web_enabled': 'false',
            'audio_navigation_sounds': 'false',
          }[key];
        },
      );

      final firstLoad = controller.load();
      final duplicateLoad = controller.load();
      await controller.setWebStreamsEnabled(true);
      gate.complete();
      await Future.wait([firstLoad, duplicateLoad]);

      expect(reads, 34, reason: 'duplicate startup loads must be coalesced');
      expect(controller.state.webStreamsEnabled, isTrue);
      expect(controller.state.navigationSounds, isFalse);
    },
  );

  test(
    'serializes rapid writes so the newest preference persists last',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final firstWriteGate = Completer<void>();
      final writes = <String>[];
      final controller = SettingsPreferencesController(
        const FlutterSecureStorage(),
        writeValue: (key, value) async {
          writes.add(value);
          if (value == '0.8') await firstWriteGate.future;
        },
      );

      final first = controller.setInterfaceScale(.8);
      await Future<void>.delayed(Duration.zero);
      final second = controller.setInterfaceScale(1.2);
      await Future<void>.delayed(Duration.zero);

      expect(writes, ['0.8']);
      expect(controller.state.interfaceScale, 1.2);
      firstWriteGate.complete();
      await Future.wait([first, second]);
      expect(writes, ['0.8', '1.2']);
    },
  );

  test('tracker threshold only completes a whole episode when crossed', () {
    const duration = Duration(minutes: 24);

    expect(
      trackerUpdateThresholdReached(
        position: const Duration(minutes: 11),
        duration: duration,
        threshold: TrackerUpdateThreshold.halfway,
      ),
      isFalse,
    );
    expect(
      trackerUpdateThresholdReached(
        position: const Duration(minutes: 12),
        duration: duration,
        threshold: TrackerUpdateThreshold.halfway,
      ),
      isTrue,
    );
    expect(
      trackerUpdateThresholdReached(
        position: duration,
        duration: duration,
        threshold: TrackerUpdateThreshold.episodeEnd,
      ),
      isFalse,
    );
    expect(
      trackerUpdateThresholdReached(
        position: duration,
        duration: duration,
        threshold: TrackerUpdateThreshold.episodeEnd,
        playbackEnded: true,
      ),
      isTrue,
    );
  });
}
