import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _debridProviderKey = 'settings_selected_debrid_provider';
const _trackingProviderKey = 'settings_selected_tracking_provider';
const _captionTextColorKey = 'appearance_caption_text_color';
const _captionBackgroundColorKey = 'appearance_caption_background_color';
const _captionTextSizeKey = 'appearance_caption_text_size';
const _thumbnailScaleKey = 'appearance_thumbnail_scale';
const _interfaceScaleKey = 'appearance_interface_scale';
const _contentDensityKey = 'appearance_content_density';
const _seekBackSecondsKey = 'player_seek_back_seconds';
const _seekForwardSecondsKey = 'player_seek_forward_seconds';
const _builtInKeyboardKey = 'input_use_built_in_keyboard';
const _debridStreamsEnabledKey = 'streaming_debrid_enabled';
const _webStreamsEnabledKey = 'streaming_web_enabled';
const _autoSkipIntrosKey = 'player_auto_skip_intros';
const _autoSkipOutrosKey = 'player_auto_skip_outros';
const _showFillerIndicatorsKey = 'player_show_filler_indicators';
const _homeLayoutKey = 'appearance_home_layout';
const _showSearchKey = 'navigation_show_search';
const _showMyListKey = 'navigation_show_my_list';
const _showDiscoverKey = 'navigation_show_discover';
const _showCalendarKey = 'navigation_show_calendar';
const _showHeroKey = 'home_show_featured_hero';
const _showPosterMetadataKey = 'home_show_poster_metadata';
const _showCardSubtitlesKey = 'home_show_card_subtitles';
const _trackerUpdateThresholdKey = 'tracking_episode_update_threshold';
const _interfaceModeKey = 'appearance_interface_mode';
const _navigationSoundsKey = 'audio_navigation_sounds';
const _clickSoundsKey = 'audio_click_sounds';
const _defaultLandingPageKey = 'navigation_default_landing_page';
const _preferredPlayerKey = 'player_preferred_engine';
const _preferredAudioKey = 'player_preferred_audio';
const _anonymousUsageCountKey = 'privacy_anonymous_usage_count';
const _anonymousCrashReportingKey = 'privacy_anonymous_crash_reporting';

/// AniList and MyAnimeList only accept a whole number of completed episodes.
/// This setting controls how much of the current episode must be watched before
/// TetoTV records that episode number on the connected trackers.
enum TrackerUpdateThreshold {
  halfway,
  threeQuarters,
  nearlyFinished,
  episodeEnd,
}

extension TrackerUpdateThresholdLabel on TrackerUpdateThreshold {
  String get displayName => switch (this) {
    TrackerUpdateThreshold.halfway => 'After 50%',
    TrackerUpdateThreshold.threeQuarters => 'After 75%',
    TrackerUpdateThreshold.nearlyFinished => 'After 90%',
    TrackerUpdateThreshold.episodeEnd => 'At episode end',
  };

  String get description => switch (this) {
    TrackerUpdateThreshold.halfway =>
      'Mark the episode watched once half of it has played.',
    TrackerUpdateThreshold.threeQuarters =>
      'Mark the episode watched after three quarters has played.',
    TrackerUpdateThreshold.nearlyFinished =>
      'Mark the episode watched near the end (recommended).',
    TrackerUpdateThreshold.episodeEnd =>
      'Only mark the episode watched after playback finishes.',
  };

  double get watchedFraction => switch (this) {
    TrackerUpdateThreshold.halfway => .5,
    TrackerUpdateThreshold.threeQuarters => .75,
    TrackerUpdateThreshold.nearlyFinished => .9,
    TrackerUpdateThreshold.episodeEnd => 1,
  };
}

bool trackerUpdateThresholdReached({
  required Duration position,
  required Duration duration,
  required TrackerUpdateThreshold threshold,
  bool playbackEnded = false,
}) {
  if (playbackEnded) return true;
  if (duration <= Duration.zero || position < Duration.zero) return false;
  if (threshold == TrackerUpdateThreshold.episodeEnd) return false;
  return position.inMilliseconds / duration.inMilliseconds >=
      threshold.watchedFraction;
}

enum HomeLayout { cinematic, compact }

extension HomeLayoutLabel on HomeLayout {
  String get displayName => switch (this) {
    HomeLayout.cinematic => 'Cinematic',
    HomeLayout.compact => 'Compact',
  };
}

/// Controls whether TetoTV uses its 10-foot canvas or the denser handheld
/// canvas. Automatic keeps the current device-aware behavior for existing
/// installs, while the explicit options are useful on unusual Android boxes
/// and large foldable phones.
enum InterfaceMode { automatic, television, phone }

extension InterfaceModeLabel on InterfaceMode {
  String get displayName => switch (this) {
    InterfaceMode.automatic => 'Automatic',
    InterfaceMode.television => 'TV',
    InterfaceMode.phone => 'Phone',
  };

  String get description => switch (this) {
    InterfaceMode.automatic => 'Match this device',
    InterfaceMode.television => '10-foot layout',
    InterfaceMode.phone => 'Denser handheld layout',
  };
}

enum LandingPage { home, search, myList, discover, calendar }

extension LandingPageLabel on LandingPage {
  String get displayName => switch (this) {
    LandingPage.home => 'Home',
    LandingPage.search => 'Search',
    LandingPage.myList => 'My List',
    LandingPage.discover => 'Discover',
    LandingPage.calendar => 'Calendar',
  };

  String get route => switch (this) {
    LandingPage.home => '/',
    LandingPage.search => '/search',
    LandingPage.myList => '/my-list',
    LandingPage.discover => '/discover',
    LandingPage.calendar => '/calendar',
  };
}

enum ContentDensity { compact, standard, comfortable }

extension ContentDensityLabel on ContentDensity {
  String get displayName => switch (this) {
    ContentDensity.compact => 'Compact',
    ContentDensity.standard => 'Standard',
    ContentDensity.comfortable => 'Comfortable',
  };

  double get spacingScale => switch (this) {
    ContentDensity.compact => .88,
    ContentDensity.standard => 1,
    ContentDensity.comfortable => 1.12,
  };
}

enum PreferredPlayer { automatic, media3, mpv, vlc }

extension PreferredPlayerLabel on PreferredPlayer {
  String get displayName => switch (this) {
    PreferredPlayer.automatic => 'Automatic',
    PreferredPlayer.media3 => 'Media3',
    PreferredPlayer.mpv => 'MPV',
    PreferredPlayer.vlc => 'VLC',
  };

  String get description => switch (this) {
    PreferredPlayer.automatic => 'Best engine for this device and stream',
    PreferredPlayer.media3 => 'Native Android hardware player',
    PreferredPlayer.mpv => 'Best subtitle and web-stream compatibility',
    PreferredPlayer.vlc => 'Alternate compatibility player',
  };
}

class SettingsPreferences {
  const SettingsPreferences({
    this.debridProvider = DebridService.realDebrid,
    this.trackingProvider = TrackingProvider.anilist,
    this.captionTextColor = 0xFFFFFFFF,
    this.captionBackgroundColor = 0x00000000,
    this.captionTextSize = 34,
    this.thumbnailScale = 1,
    this.interfaceScale = 1,
    this.contentDensity = ContentDensity.standard,
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 10,
    // Fresh installs start with TetoTV's D-pad keyboard. First-time setup asks
    // explicitly, and existing installations keep their saved/migrated choice.
    this.useBuiltInKeyboard = true,
    this.debridStreamsEnabled = true,
    this.webStreamsEnabled = true,
    this.autoSkipIntros = false,
    this.autoSkipOutros = false,
    this.showFillerIndicators = true,
    this.homeLayout = HomeLayout.cinematic,
    this.showSearch = true,
    this.showMyList = true,
    this.showDiscover = true,
    this.showCalendar = true,
    this.showHero = true,
    this.showPosterMetadata = true,
    this.showCardSubtitles = true,
    this.trackerUpdateThreshold = TrackerUpdateThreshold.nearlyFinished,
    this.interfaceMode = InterfaceMode.automatic,
    this.navigationSounds = true,
    this.clickSounds = true,
    this.defaultLandingPage = LandingPage.home,
    this.preferredPlayer = PreferredPlayer.automatic,
    this.preferredAudio = PlaybackAudioPreference.dub,
    this.anonymousUsageCountEnabled = false,
    this.anonymousCrashReportingEnabled = false,
    this.loaded = false,
  });

  final DebridService debridProvider;
  final TrackingProvider trackingProvider;
  final int captionTextColor;
  final int captionBackgroundColor;
  final double captionTextSize;
  final double thumbnailScale;
  final double interfaceScale;
  final ContentDensity contentDensity;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final bool useBuiltInKeyboard;
  final bool debridStreamsEnabled;
  final bool webStreamsEnabled;
  final bool autoSkipIntros;
  final bool autoSkipOutros;
  final bool showFillerIndicators;
  final HomeLayout homeLayout;
  final bool showSearch;
  final bool showMyList;
  final bool showDiscover;
  final bool showCalendar;
  final bool showHero;
  final bool showPosterMetadata;
  final bool showCardSubtitles;
  final TrackerUpdateThreshold trackerUpdateThreshold;
  final InterfaceMode interfaceMode;
  final bool navigationSounds;
  final bool clickSounds;
  final LandingPage defaultLandingPage;
  final PreferredPlayer preferredPlayer;
  final PlaybackAudioPreference preferredAudio;
  final bool anonymousUsageCountEnabled;
  final bool anonymousCrashReportingEnabled;
  final bool loaded;

  SettingsPreferences copyWith({
    DebridService? debridProvider,
    TrackingProvider? trackingProvider,
    int? captionTextColor,
    int? captionBackgroundColor,
    double? captionTextSize,
    double? thumbnailScale,
    double? interfaceScale,
    ContentDensity? contentDensity,
    int? seekBackSeconds,
    int? seekForwardSeconds,
    bool? useBuiltInKeyboard,
    bool? debridStreamsEnabled,
    bool? webStreamsEnabled,
    bool? autoSkipIntros,
    bool? autoSkipOutros,
    bool? showFillerIndicators,
    HomeLayout? homeLayout,
    bool? showSearch,
    bool? showMyList,
    bool? showDiscover,
    bool? showCalendar,
    bool? showHero,
    bool? showPosterMetadata,
    bool? showCardSubtitles,
    TrackerUpdateThreshold? trackerUpdateThreshold,
    InterfaceMode? interfaceMode,
    bool? navigationSounds,
    bool? clickSounds,
    LandingPage? defaultLandingPage,
    PreferredPlayer? preferredPlayer,
    PlaybackAudioPreference? preferredAudio,
    bool? anonymousUsageCountEnabled,
    bool? anonymousCrashReportingEnabled,
    bool? loaded,
  }) => SettingsPreferences(
    debridProvider: debridProvider ?? this.debridProvider,
    trackingProvider: trackingProvider ?? this.trackingProvider,
    captionTextColor: captionTextColor ?? this.captionTextColor,
    captionBackgroundColor:
        captionBackgroundColor ?? this.captionBackgroundColor,
    captionTextSize: captionTextSize ?? this.captionTextSize,
    thumbnailScale: thumbnailScale ?? this.thumbnailScale,
    interfaceScale: interfaceScale ?? this.interfaceScale,
    contentDensity: contentDensity ?? this.contentDensity,
    seekBackSeconds: seekBackSeconds ?? this.seekBackSeconds,
    seekForwardSeconds: seekForwardSeconds ?? this.seekForwardSeconds,
    useBuiltInKeyboard: useBuiltInKeyboard ?? this.useBuiltInKeyboard,
    debridStreamsEnabled: debridStreamsEnabled ?? this.debridStreamsEnabled,
    webStreamsEnabled: webStreamsEnabled ?? this.webStreamsEnabled,
    autoSkipIntros: autoSkipIntros ?? this.autoSkipIntros,
    autoSkipOutros: autoSkipOutros ?? this.autoSkipOutros,
    showFillerIndicators: showFillerIndicators ?? this.showFillerIndicators,
    homeLayout: homeLayout ?? this.homeLayout,
    showSearch: showSearch ?? this.showSearch,
    showMyList: showMyList ?? this.showMyList,
    showDiscover: showDiscover ?? this.showDiscover,
    showCalendar: showCalendar ?? this.showCalendar,
    showHero: showHero ?? this.showHero,
    showPosterMetadata: showPosterMetadata ?? this.showPosterMetadata,
    showCardSubtitles: showCardSubtitles ?? this.showCardSubtitles,
    trackerUpdateThreshold:
        trackerUpdateThreshold ?? this.trackerUpdateThreshold,
    interfaceMode: interfaceMode ?? this.interfaceMode,
    navigationSounds: navigationSounds ?? this.navigationSounds,
    clickSounds: clickSounds ?? this.clickSounds,
    defaultLandingPage: defaultLandingPage ?? this.defaultLandingPage,
    preferredPlayer: preferredPlayer ?? this.preferredPlayer,
    preferredAudio: preferredAudio ?? this.preferredAudio,
    anonymousUsageCountEnabled:
        anonymousUsageCountEnabled ?? this.anonymousUsageCountEnabled,
    anonymousCrashReportingEnabled:
        anonymousCrashReportingEnabled ?? this.anonymousCrashReportingEnabled,
    loaded: loaded ?? this.loaded,
  );
}

final settingsPreferencesProvider =
    StateNotifierProvider<SettingsPreferencesController, SettingsPreferences>((
      ref,
    ) {
      final controller = SettingsPreferencesController(
        ref.watch(secureStorageProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class SettingsPreferencesController extends StateNotifier<SettingsPreferences> {
  SettingsPreferencesController(
    this._storage, {
    this.readValue,
    this.writeValue,
    this.deleteValue,
  }) : super(const SettingsPreferences());

  final FlutterSecureStorage _storage;
  final Future<String?> Function(String key)? readValue;
  final Future<void> Function(String key, String value)? writeValue;
  final Future<void> Function(String key)? deleteValue;
  bool _initialLandingPageConsumed = false;
  Future<void>? _loadFuture;
  bool _initialLoadComplete = false;
  int _revision = 0;
  final Map<String, int> _keyRevisions = {};
  final Set<String> _preloadMutations = {};
  Future<void> _storageTail = Future<void>.value();

  /// Returns the configured non-Home route once per app process. This avoids
  /// redirecting again when the user intentionally navigates back to Home.
  String? takeInitialLandingRoute() {
    if (_initialLandingPageConsumed) return null;
    _initialLandingPageConsumed = true;
    final route = state.defaultLandingPage.route;
    return route == '/' ? null : route;
  }

  /// Coalesces simultaneous startup loads, restores each preference
  /// independently, and preserves any user choice made before encrypted
  /// storage finishes responding.
  Future<void> load() => _loadFuture ??= _load().whenComplete(() {
    _loadFuture = null;
  });

  Future<void> _load() async {
    final revisionAtStart = _revision;
    final wasInitialLoad = !_initialLoadComplete;
    final values = await Future.wait<Object?>([
      _safeRead(_debridProviderKey),
      _safeRead(_trackingProviderKey),
      _safeRead(_captionTextColorKey),
      _safeRead(_captionBackgroundColorKey),
      _safeRead(_captionTextSizeKey),
      _safeRead(_thumbnailScaleKey),
      _safeRead(_interfaceScaleKey),
      _safeRead(_contentDensityKey),
      _safeRead(_seekBackSecondsKey),
      _safeRead(_seekForwardSecondsKey),
      _safeRead(_builtInKeyboardKey),
      _safeRead(_debridStreamsEnabledKey),
      _safeRead(_webStreamsEnabledKey),
      _safeRead(_autoSkipIntrosKey),
      _safeRead(_autoSkipOutrosKey),
      _safeRead(_homeLayoutKey),
      _safeRead(_showSearchKey),
      _safeRead(_showMyListKey),
      _safeRead(_showDiscoverKey),
      _safeRead(_showCalendarKey),
      _safeRead(_showHeroKey),
      _safeRead(_showPosterMetadataKey),
      _safeRead(_showCardSubtitlesKey),
      _safeRead(_trackerUpdateThresholdKey),
      _safeRead(_interfaceModeKey),
      _safeRead(_navigationSoundsKey),
      _safeRead(_clickSoundsKey),
      _safeRead(_defaultLandingPageKey),
      _safeRead(_preferredPlayerKey),
      _safeRead(_anonymousUsageCountKey),
      _safeRead(_anonymousCrashReportingKey),
      _safeRead(_preferredAudioKey),
      _safeRead(initialSetupCompletedStorageKey),
      _safeRead(_showFillerIndicatorsKey),
    ]);

    bool canRestore(String key, int index) {
      if (identical(values[index], _preferenceReadFailed)) return false;
      if (wasInitialLoad && _preloadMutations.contains(key)) return false;
      return (_keyRevisions[key] ?? 0) <= revisionAtStart;
    }

    String? valueAt(int index) => values[index] as String?;
    var restored = state;
    if (canRestore(_debridProviderKey, 0)) {
      restored = restored.copyWith(
        debridProvider:
            DebridService.fromSlug(valueAt(0)) ?? DebridService.realDebrid,
      );
    }
    if (canRestore(_trackingProviderKey, 1)) {
      restored = restored.copyWith(
        trackingProvider: TrackingProvider.values.firstWhere(
          (provider) => provider.slug == valueAt(1),
          orElse: () => TrackingProvider.anilist,
        ),
      );
    }
    if (canRestore(_captionTextColorKey, 2)) {
      restored = restored.copyWith(
        captionTextColor: _parseInt(valueAt(2), 0xFFFFFFFF),
      );
    }
    if (canRestore(_captionBackgroundColorKey, 3)) {
      restored = restored.copyWith(
        captionBackgroundColor: _parseInt(valueAt(3), 0x00000000),
      );
    }
    if (canRestore(_captionTextSizeKey, 4)) {
      restored = restored.copyWith(
        captionTextSize: _parseDouble(valueAt(4), 34).clamp(18, 60),
      );
    }
    if (canRestore(_thumbnailScaleKey, 5)) {
      restored = restored.copyWith(
        thumbnailScale: _parseDouble(valueAt(5), 1).clamp(.8, 1.25),
      );
    }
    if (canRestore(_interfaceScaleKey, 6)) {
      restored = restored.copyWith(
        interfaceScale: _parseDouble(valueAt(6), 1).clamp(.8, 1.2),
      );
    }
    if (canRestore(_contentDensityKey, 7)) {
      restored = restored.copyWith(
        contentDensity: ContentDensity.values.firstWhere(
          (density) => density.name == valueAt(7),
          orElse: () => ContentDensity.standard,
        ),
      );
    }
    if (canRestore(_seekBackSecondsKey, 8)) {
      restored = restored.copyWith(seekBackSeconds: _seekValue(valueAt(8)));
    }
    if (canRestore(_seekForwardSecondsKey, 9)) {
      restored = restored.copyWith(seekForwardSeconds: _seekValue(valueAt(9)));
    }
    if (canRestore(_builtInKeyboardKey, 10)) {
      final savedKeyboard = valueAt(10);
      final completedLegacySetup =
          canRestore(initialSetupCompletedStorageKey, 32) &&
          valueAt(32) == 'true';
      // The previous release migrated an existing installation with no saved
      // keyboard key to device input. Keep that behavior once onboarding was
      // already completed, while a genuinely empty install gets the new
      // TetoTV-keyboard default and can choose on the Customize step.
      restored = restored.copyWith(
        useBuiltInKeyboard: savedKeyboard == null
            ? !completedLegacySetup
            : savedKeyboard == 'true',
      );
    }
    if (canRestore(_debridStreamsEnabledKey, 11)) {
      restored = restored.copyWith(
        debridStreamsEnabled: valueAt(11) != 'false',
      );
    }
    if (canRestore(_webStreamsEnabledKey, 12)) {
      restored = restored.copyWith(webStreamsEnabled: valueAt(12) != 'false');
    }
    if (canRestore(_autoSkipIntrosKey, 13)) {
      restored = restored.copyWith(autoSkipIntros: valueAt(13) == 'true');
    }
    if (canRestore(_autoSkipOutrosKey, 14)) {
      restored = restored.copyWith(autoSkipOutros: valueAt(14) == 'true');
    }
    if (canRestore(_homeLayoutKey, 15)) {
      restored = restored.copyWith(
        homeLayout: HomeLayout.values.firstWhere(
          (layout) => layout.name == valueAt(15),
          orElse: () => HomeLayout.cinematic,
        ),
      );
    }
    if (canRestore(_showSearchKey, 16)) {
      restored = restored.copyWith(showSearch: valueAt(16) != 'false');
    }
    if (canRestore(_showMyListKey, 17)) {
      restored = restored.copyWith(showMyList: valueAt(17) != 'false');
    }
    if (canRestore(_showDiscoverKey, 18)) {
      restored = restored.copyWith(showDiscover: valueAt(18) != 'false');
    }
    if (canRestore(_showCalendarKey, 19)) {
      restored = restored.copyWith(showCalendar: valueAt(19) != 'false');
    }
    if (canRestore(_showHeroKey, 20)) {
      restored = restored.copyWith(showHero: valueAt(20) != 'false');
    }
    if (canRestore(_showPosterMetadataKey, 21)) {
      restored = restored.copyWith(showPosterMetadata: valueAt(21) != 'false');
    }
    if (canRestore(_showCardSubtitlesKey, 22)) {
      restored = restored.copyWith(showCardSubtitles: valueAt(22) != 'false');
    }
    if (canRestore(_trackerUpdateThresholdKey, 23)) {
      restored = restored.copyWith(
        trackerUpdateThreshold: TrackerUpdateThreshold.values.firstWhere(
          (threshold) => threshold.name == valueAt(23),
          orElse: () => TrackerUpdateThreshold.nearlyFinished,
        ),
      );
    }
    if (canRestore(_interfaceModeKey, 24)) {
      restored = restored.copyWith(
        interfaceMode: InterfaceMode.values.firstWhere(
          (mode) => mode.name == valueAt(24),
          orElse: () => InterfaceMode.automatic,
        ),
      );
    }
    if (canRestore(_navigationSoundsKey, 25)) {
      restored = restored.copyWith(navigationSounds: valueAt(25) != 'false');
    }
    if (canRestore(_clickSoundsKey, 26)) {
      restored = restored.copyWith(clickSounds: valueAt(26) != 'false');
    }
    if (canRestore(_defaultLandingPageKey, 27)) {
      restored = restored.copyWith(
        defaultLandingPage: LandingPage.values.firstWhere(
          (page) => page.name == valueAt(27),
          orElse: () => LandingPage.home,
        ),
      );
    }
    if (canRestore(_preferredPlayerKey, 28)) {
      restored = restored.copyWith(
        preferredPlayer: PreferredPlayer.values.firstWhere(
          (player) => player.name == valueAt(28),
          orElse: () => PreferredPlayer.automatic,
        ),
      );
    }
    if (canRestore(_anonymousUsageCountKey, 29)) {
      restored = restored.copyWith(
        anonymousUsageCountEnabled: valueAt(29) == 'true',
      );
    }
    if (canRestore(_anonymousCrashReportingKey, 30)) {
      restored = restored.copyWith(
        anonymousCrashReportingEnabled: valueAt(30) == 'true',
      );
    }
    if (canRestore(_preferredAudioKey, 31)) {
      restored = restored.copyWith(
        preferredAudio: PlaybackAudioPreferenceLabel.fromStorage(valueAt(31)),
      );
    }
    if (canRestore(_showFillerIndicatorsKey, 33)) {
      // Existing installations have no saved value, so absence migrates to
      // the enabled default while an explicit opt-out remains permanent.
      restored = restored.copyWith(
        showFillerIndicators: valueAt(33) != 'false',
      );
    }
    state = restored.copyWith(loaded: true);
    _initialLoadComplete = true;
    _preloadMutations.clear();
  }

  Future<Object?> _safeRead(String key) async {
    try {
      return await (readValue?.call(key) ?? _storage.read(key: key));
    } catch (_) {
      return _preferenceReadFailed;
    }
  }

  void _markMutated(Iterable<String> keys) {
    final revision = ++_revision;
    for (final key in keys) {
      _keyRevisions[key] = revision;
      if (!_initialLoadComplete) _preloadMutations.add(key);
    }
  }

  Future<void> setDebridProvider(DebridService value) => _update(
    state.copyWith(debridProvider: value),
    {_debridProviderKey: value.slug},
  );

  Future<void> setTrackingProvider(TrackingProvider value) => _update(
    state.copyWith(trackingProvider: value),
    {_trackingProviderKey: value.slug},
  );

  Future<void> setCaptionTextColor(int value) => _update(
    state.copyWith(captionTextColor: value),
    {_captionTextColorKey: value.toString()},
  );

  Future<void> setCaptionBackgroundColor(int value) => _update(
    state.copyWith(captionBackgroundColor: value),
    {_captionBackgroundColorKey: value.toString()},
  );

  Future<void> setCaptionTextSize(double value) => _update(
    state.copyWith(captionTextSize: value),
    {_captionTextSizeKey: value.toString()},
  );

  Future<void> setThumbnailScale(double value) => _update(
    state.copyWith(thumbnailScale: value),
    {_thumbnailScaleKey: value.toString()},
  );

  Future<void> setInterfaceScale(double value) => _update(
    state.copyWith(interfaceScale: value),
    {_interfaceScaleKey: value.toString()},
  );

  Future<void> setContentDensity(ContentDensity value) => _update(
    state.copyWith(contentDensity: value),
    {_contentDensityKey: value.name},
  );

  Future<void> setSeekBackSeconds(int value) => _update(
    state.copyWith(seekBackSeconds: value),
    {_seekBackSecondsKey: value.toString()},
  );

  Future<void> setSeekForwardSeconds(int value) => _update(
    state.copyWith(seekForwardSeconds: value),
    {_seekForwardSecondsKey: value.toString()},
  );

  Future<void> setUseBuiltInKeyboard(bool value) => _update(
    state.copyWith(useBuiltInKeyboard: value),
    {_builtInKeyboardKey: value.toString()},
  );

  Future<void> setDebridStreamsEnabled(bool value) => _update(
    state.copyWith(debridStreamsEnabled: value),
    {_debridStreamsEnabledKey: value.toString()},
  );

  Future<void> setWebStreamsEnabled(bool value) => _update(
    state.copyWith(webStreamsEnabled: value),
    {_webStreamsEnabledKey: value.toString()},
  );

  Future<void> setAutoSkipIntros(bool value) => _update(
    state.copyWith(autoSkipIntros: value),
    {_autoSkipIntrosKey: value.toString()},
  );

  Future<void> setAutoSkipOutros(bool value) => _update(
    state.copyWith(autoSkipOutros: value),
    {_autoSkipOutrosKey: value.toString()},
  );

  Future<void> setShowFillerIndicators(bool value) => _update(
    state.copyWith(showFillerIndicators: value),
    {_showFillerIndicatorsKey: value.toString()},
  );

  Future<void> setHomeLayout(HomeLayout value) =>
      _update(state.copyWith(homeLayout: value), {_homeLayoutKey: value.name});

  Future<void> setShowSearch(bool value) => _setNavigationVisibility(
    visible: value,
    page: LandingPage.search,
    visibilityKey: _showSearchKey,
    next: state.copyWith(showSearch: value),
  );

  Future<void> setShowMyList(bool value) => _setNavigationVisibility(
    visible: value,
    page: LandingPage.myList,
    visibilityKey: _showMyListKey,
    next: state.copyWith(showMyList: value),
  );

  Future<void> setShowDiscover(bool value) => _setNavigationVisibility(
    visible: value,
    page: LandingPage.discover,
    visibilityKey: _showDiscoverKey,
    next: state.copyWith(showDiscover: value),
  );

  Future<void> setShowCalendar(bool value) => _setNavigationVisibility(
    visible: value,
    page: LandingPage.calendar,
    visibilityKey: _showCalendarKey,
    next: state.copyWith(showCalendar: value),
  );

  Future<void> setShowHero(bool value) => _update(
    state.copyWith(showHero: value),
    {_showHeroKey: value.toString()},
  );

  Future<void> setShowPosterMetadata(bool value) => _update(
    state.copyWith(showPosterMetadata: value),
    {_showPosterMetadataKey: value.toString()},
  );

  Future<void> setShowCardSubtitles(bool value) => _update(
    state.copyWith(showCardSubtitles: value),
    {_showCardSubtitlesKey: value.toString()},
  );

  Future<void> setTrackerUpdateThreshold(TrackerUpdateThreshold value) =>
      _update(state.copyWith(trackerUpdateThreshold: value), {
        _trackerUpdateThresholdKey: value.name,
      });

  Future<void> setInterfaceMode(InterfaceMode value) => _update(
    state.copyWith(interfaceMode: value),
    {_interfaceModeKey: value.name},
  );

  Future<void> setNavigationSounds(bool value) => _update(
    state.copyWith(navigationSounds: value),
    {_navigationSoundsKey: value.toString()},
  );

  Future<void> setClickSounds(bool value) => _update(
    state.copyWith(clickSounds: value),
    {_clickSoundsKey: value.toString()},
  );

  Future<void> setDefaultLandingPage(LandingPage value) => _update(
    state.copyWith(defaultLandingPage: value),
    {_defaultLandingPageKey: value.name},
  );

  Future<void> setPreferredPlayer(PreferredPlayer value) => _update(
    state.copyWith(preferredPlayer: value),
    {_preferredPlayerKey: value.name},
  );

  Future<void> setPreferredAudio(PlaybackAudioPreference value) => _update(
    state.copyWith(preferredAudio: value),
    {_preferredAudioKey: value.name},
  );

  Future<void> setAnonymousUsageCountEnabled(bool value) => _update(
    state.copyWith(anonymousUsageCountEnabled: value),
    {_anonymousUsageCountKey: value.toString()},
  );

  Future<void> setAnonymousCrashReportingEnabled(bool value) => _update(
    state.copyWith(anonymousCrashReportingEnabled: value, loaded: true),
    {_anonymousCrashReportingKey: value.toString()},
  );

  Future<void> resetCustomization() {
    const defaults = SettingsPreferences();
    const keys = [
      _homeLayoutKey,
      _showSearchKey,
      _showMyListKey,
      _showDiscoverKey,
      _showCalendarKey,
      _showHeroKey,
      _showPosterMetadataKey,
      _showCardSubtitlesKey,
      _navigationSoundsKey,
      _clickSoundsKey,
      _defaultLandingPageKey,
    ];
    _markMutated(keys);
    state = state.copyWith(
      homeLayout: defaults.homeLayout,
      showSearch: defaults.showSearch,
      showMyList: defaults.showMyList,
      showDiscover: defaults.showDiscover,
      showCalendar: defaults.showCalendar,
      showHero: defaults.showHero,
      showPosterMetadata: defaults.showPosterMetadata,
      showCardSubtitles: defaults.showCardSubtitles,
      navigationSounds: defaults.navigationSounds,
      clickSounds: defaults.clickSounds,
      defaultLandingPage: defaults.defaultLandingPage,
    );
    return _enqueueStorage(() async {
      for (final key in keys) {
        await _delete(key);
      }
    });
  }

  Future<void> resetAppearance() {
    const defaults = SettingsPreferences();
    const keys = [
      _captionTextColorKey,
      _captionBackgroundColorKey,
      _captionTextSizeKey,
      _thumbnailScaleKey,
      _interfaceScaleKey,
      _contentDensityKey,
      _interfaceModeKey,
      _seekBackSecondsKey,
      _seekForwardSecondsKey,
      _preferredPlayerKey,
      _preferredAudioKey,
      _showFillerIndicatorsKey,
    ];
    _markMutated(keys);
    state = state.copyWith(
      captionTextColor: defaults.captionTextColor,
      captionBackgroundColor: defaults.captionBackgroundColor,
      captionTextSize: defaults.captionTextSize,
      thumbnailScale: defaults.thumbnailScale,
      interfaceScale: defaults.interfaceScale,
      contentDensity: defaults.contentDensity,
      interfaceMode: defaults.interfaceMode,
      seekBackSeconds: defaults.seekBackSeconds,
      seekForwardSeconds: defaults.seekForwardSeconds,
      preferredPlayer: defaults.preferredPlayer,
      preferredAudio: defaults.preferredAudio,
      showFillerIndicators: defaults.showFillerIndicators,
    );
    return _enqueueStorage(() async {
      for (final key in keys) {
        await _delete(key);
      }
    });
  }

  Future<void> _update(SettingsPreferences next, Map<String, String> values) {
    _markMutated(values.keys);
    state = next;
    return _enqueueStorage(() async {
      for (final entry in values.entries) {
        await _write(entry.key, entry.value);
      }
    });
  }

  Future<void> _enqueueStorage(Future<void> Function() operation) {
    final previous = _storageTail;
    final request = () async {
      await previous;
      try {
        await operation();
      } catch (_) {
        // Keep the in-memory preference if platform storage is unavailable.
      }
    }();
    _storageTail = request;
    return request;
  }

  Future<void> _write(String key, String value) =>
      writeValue?.call(key, value) ?? _storage.write(key: key, value: value);

  Future<void> _delete(String key) =>
      deleteValue?.call(key) ?? _storage.delete(key: key);

  Future<void> _setNavigationVisibility({
    required bool visible,
    required LandingPage page,
    required String visibilityKey,
    required SettingsPreferences next,
  }) {
    final landingPage = !visible && state.defaultLandingPage == page
        ? LandingPage.home
        : state.defaultLandingPage;
    return _update(next.copyWith(defaultLandingPage: landingPage), {
      visibilityKey: visible.toString(),
      if (landingPage != state.defaultLandingPage)
        _defaultLandingPageKey: landingPage.name,
    });
  }
}

const _preferenceReadFailed = Object();

int _parseInt(String? value, int fallback) =>
    int.tryParse(value ?? '') ?? fallback;

double _parseDouble(String? value, double fallback) =>
    double.tryParse(value ?? '') ?? fallback;

int _seekValue(String? value) {
  const allowed = {5, 10, 15, 30, 60};
  final parsed = int.tryParse(value ?? '');
  return allowed.contains(parsed) ? parsed! : 10;
}
