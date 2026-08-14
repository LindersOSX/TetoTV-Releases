import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all Flutter player presentation surfaces use Theme Studio palette', () {
    for (final path in [
      'lib/features/player/presentation/tv_player_screen.dart',
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
      'lib/features/player/presentation/player_control_overlay.dart',
      'lib/features/player/presentation/player_stream_source_picker.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('AppColors.')), reason: path);
      expect(source, contains('context.appPalette'), reason: path);
    }
  });

  test(
    'Flutter and Media3 keep transport icons and labeled actions in order',
    () {
      final flutterChrome = File(
        'lib/features/player/presentation/teto_player_chrome.dart',
      ).readAsStringSync();
      final nativeChrome = File(
        'android/app/src/main/res/layout/tetotv_player_controls.xml',
      ).readAsStringSync();
      final nativeStrings = File(
        'android/app/src/main/res/values/strings.xml',
      ).readAsStringSync();

      _expectInOrder(flutterChrome, const [
        "label: 'Back \${seekBackSeconds}s'",
        'iconOnly: true',
        "label: isPlaying ? 'Pause' : 'Play'",
        'iconOnly: true',
        "label: 'Forward \${seekForwardSeconds}s'",
        'iconOnly: true',
        "label: 'Audio'",
        "label: 'CC'",
        "label: 'Size'",
        "label: 'Picture'",
        "label: 'Player'",
        "label: 'Sources'",
        "label: 'Options'",
      ]);
      _expectInOrder(nativeChrome, const [
        '@id/exo_rew',
        '@id/exo_play_pause',
        '@id/exo_ffwd',
        '@+id/tetotv_audio_tracks',
        '@+id/tetotv_caption_tracks',
        '@+id/tetotv_caption_size',
        '@+id/tetotv_picture_mode',
        '@+id/tetotv_fix_video',
        '@+id/tetotv_player_sources',
        '@+id/tetotv_player_options',
      ]);

      for (final label in [
        '>Audio<',
        '>CC<',
        '>Size<',
        '>Picture<',
        '>Player<',
        '>Sources<',
        '>Options<',
      ]) {
        expect(nativeStrings, contains(label));
      }

      expect(flutterChrome, contains('Semantics(label: label, button: true'));
      for (final transportLabelId in [
        'tetotv_rewind_label',
        'tetotv_play_pause_label',
        'tetotv_fast_forward_label',
      ]) {
        expect(nativeChrome, isNot(contains(transportLabelId)));
      }
      for (final accessibilityLabel in [
        '@string/tetotv_player_rewind',
        '@string/tetotv_player_play',
        '@string/tetotv_player_fast_forward',
      ]) {
        expect(nativeChrome, contains(accessibilityLabel));
      }
    },
  );

  test('all HUDs reveal the final controls instead of clipping focus', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    expect(flutterChrome, contains('Scrollable.ensureVisible('));
    expect(
      flutterChrome,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtEnd'),
    );
    expect(nativeChrome, contains('android:clipChildren="false"'));
    expect(nativeChrome, contains('@+id/tetotv_sources_control'));
    expect(nativeChrome, contains('@drawable/tetotv_ic_sources'));
    expect(media3, contains('container.requestRectangleOnScreen('));
    expect(media3, contains('STATUS_NEXT_STREAM'));
    expect(media3, contains('EXTRA_HAS_DIRECT_SOURCES'));
  });

  test('all player engines keep five-second hide and Down dismissal', () {
    final flutterPolicy = File(
      'lib/features/player/presentation/player_control_overlay.dart',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    expect(
      flutterPolicy,
      contains('playerControlsIdleTimeout = Duration(seconds: 5)'),
    );
    expect(media3, contains('CONTROLLER_HIDE_TIMEOUT_MS = 5_000L'));
    expect(media3, contains('KeyEvent.KEYCODE_DPAD_DOWN'));
    expect(media3, contains('playerView.hideController()'));
    expect(media3, contains('controllerAutoShow = false'));
    expect(
      media3,
      isNot(contains('controllerAutoShow = !isTelevisionDevice()')),
    );
  });

  test('MPV and VLC render the exact same shared chrome', () {
    final mpv = File(
      'lib/features/player/presentation/tv_player_screen.dart',
    ).readAsStringSync();
    final vlc = File(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    ).readAsStringSync();

    expect(mpv, contains("engineKey: 'mpv'"));
    expect(vlc, contains("engineKey: 'vlc'"));
    expect(mpv, contains('TetoPlayerChrome('));
    expect(vlc, contains('TetoPlayerChrome('));
    expect(mpv, contains('onCaptionSize: _openCaptionSizePicker'));
    expect(vlc, contains('unawaited(_openCaptionSizePicker())'));
    expect(mpv, isNot(contains('onCaptionSize: _openPlaybackMenu')));
    expect(
      vlc,
      isNot(contains('onCaptionSize: () => unawaited(_openOptions())')),
    );
    for (final callback in [
      'onCaptionSize:',
      'onPicture:',
      'onFixVideo:',
      'onSources:',
      'onOptions:',
      'onDismiss:',
    ]) {
      expect(mpv, contains(callback));
      expect(vlc, contains(callback));
    }
  });

  test('VLC and Media3 retain MPV picture and skip shortcuts', () {
    final vlc = File(
      'lib/features/player/presentation/vlc_tv_player_screen.dart',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    for (final token in [
      'LogicalKeyboardKey.keyI && _canSkip',
      'LogicalKeyboardKey.keyA',
      'LogicalKeyboardKey.gameButtonX',
    ]) {
      expect(vlc, contains(token));
    }
    for (final token in [
      'KeyEvent.KEYCODE_I',
      'KeyEvent.KEYCODE_A',
      'KeyEvent.KEYCODE_BUTTON_X',
    ]) {
      expect(media3, contains(token));
    }
  });

  test('Media3 shortcut cleanup and buffering intent stay coherent', () {
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();

    final dispatchStart = media3.indexOf('override fun dispatchKeyEvent');
    final dispatchEnd = media3.indexOf(
      '/** Keyboard/gamepad shortcuts',
      dispatchStart,
    );
    final dispatch = media3.substring(dispatchStart, dispatchEnd);
    final cleanup = dispatch.indexOf('consumedNavigationKeyUp?.let');
    final modalGuard = dispatch.indexOf('exitDialog?.isShowing == true');
    expect(cleanup, greaterThanOrEqualTo(0));
    expect(cleanup, lessThan(modalGuard));
    expect(
      dispatch,
      contains('if (event.keyCode !in MODAL_CHROME_SHORTCUT_KEYS)'),
    );
    for (final dialogKey in [
      'KEYCODE_S',
      'KEYCODE_C',
      'KEYCODE_M',
      'KEYCODE_MENU',
      'KEYCODE_BUTTON_Y',
    ]) {
      expect(media3, contains(dialogKey));
    }
    expect(media3, contains('consumedNavigationKeyUp = null'));
    expect(
      media3,
      contains(
        'player.playWhenReady && player.playbackState != Player.STATE_ENDED',
      ),
    );
    expect(
      media3,
      contains(
        'KeyEvent.KEYCODE_K -> if (isPlaybackIntended()) player.pause() '
        'else player.play()',
      ),
    );
    expect(media3, contains('playing = isPlaybackIntended()'));
  });

  test('Media3 restores the prior read-only progress bar', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final nativePlayer = File(
      'android/app/src/main/res/layout/activity_media3_player.xml',
    ).readAsStringSync();
    final compactDimensions = File(
      'android/app/src/main/res/values/player_hud_dimensions.xml',
    ).readAsStringSync();
    final regularDimensions = File(
      'android/app/src/main/res/values-w720dp-h480dp/'
      'player_hud_dimensions.xml',
    ).readAsStringSync();
    final timeBar = RegExp(
      r'<androidx\.media3\.ui\.DefaultTimeBar[\s\S]*?/>',
    ).firstMatch(nativeChrome)?.group(0);

    expect(timeBar, isNotNull);
    expect(timeBar, contains('android:layout_height="32dp"'));
    expect(
      timeBar,
      contains(
        'android:layout_marginTop='
        '"@dimen/tetotv_player_progress_touch_margin_top"',
      ),
    );
    expect(
      timeBar,
      contains('app:bar_height="@dimen/tetotv_player_progress_bar_height"'),
    );
    expect(timeBar, contains('app:touch_target_height="32dp"'));
    expect(timeBar, contains('android:focusable="false"'));
    expect(timeBar, contains('android:clickable="false"'));
    expect(timeBar, contains('android:longClickable="false"'));
    expect(timeBar, contains('android:importantForAccessibility="no"'));
    expect(timeBar, contains('app:scrubber_disabled_size="0dp"'));
    expect(timeBar, contains('app:scrubber_dragged_size="0dp"'));
    expect(timeBar, contains('app:scrubber_enabled_size="0dp"'));
    expect(nativePlayer, contains('app:time_bar_scrubbing_enabled="false"'));
    for (final token in ['>3dp<', '>1dp<', '>-9dp<']) {
      expect(compactDimensions, contains(token));
    }
    for (final token in ['>4dp<', '>4dp<', '>-5dp<']) {
      expect(regularDimensions, contains(token));
    }
    expect(flutterChrome, isNot(contains('PlayerScrubController')));
    expect(flutterChrome, isNot(contains('onSeek')));
    expect(flutterChrome, isNot(contains('player-progress-scrubber')));
  });

  test('Media3 resource geometry and palette mirror the MPV master HUD', () {
    final flutterChrome = File(
      'lib/features/player/presentation/teto_player_chrome.dart',
    ).readAsStringSync();
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final nativeStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final card = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_card_background.xml',
    ).readAsStringSync();
    final badge = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_badge_background.xml',
    ).readAsStringSync();
    final normalControl = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_pill_background.xml',
    ).readAsStringSync();
    final primaryControl = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_primary_background.xml',
    ).readAsStringSync();
    final scrim = File(
      'android/app/src/main/res/drawable/tetotv_player_controls_scrim.xml',
    ).readAsStringSync();

    // Lock the shared MPV/VLC source of truth first.
    for (final token in [
      'constraints: const BoxConstraints(maxWidth: 1280)',
      'horizontalInset = compact ? 12.0 : 28.0',
      'bottomInset = compact ? 10.0 : 24.0',
      'const Color _defaultPlayerChromePanel = Color(0xD6080808)',
      'const Color _defaultPlayerControlSurface = Color(0x8F242429)',
      'final palette = context.appPalette',
      'color: _playerChromePanelColor(palette)',
      'color: primary ? palette.accent : _playerControlSurfaceColor(palette)',
      'height: 40',
      'minHeight: compact ? 3 : 4',
    ]) {
      expect(flutterChrome, contains(token));
    }

    // Media3 keeps the same non-compact geometry and typography.
    for (final token in [
      'android:layout_marginStart="28dp"',
      'android:layout_marginBottom="24dp"',
      'android:paddingStart="18dp"',
      'android:paddingTop="14dp"',
      'android:paddingBottom="12dp"',
      'android:layout_height="wrap_content"',
      'android:textSize="24sp"',
      'android:layout_height="40dp"',
      'android:layout_marginTop="10dp"',
      'app:bar_height="@dimen/tetotv_player_progress_bar_height"',
      'app:played_color="#FFFF496A"',
      'app:unplayed_color="#3DFFFFFF"',
      'android:textColor="#FFB7AEB1"',
    ]) {
      expect(nativeChrome, contains(token));
    }
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlPill">[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlIcon"[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerBadge"[\s\S]*?'
        r'<item name="android:layout_height">wrap_content</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    for (final token in ['#D6080808', '16dp', '1.4dp', '#C7E52B50']) {
      expect(card, contains(token));
    }
    for (final token in ['#33E52B50', '#59E52B50']) {
      expect(badge, contains(token));
    }
    expect(normalControl, contains('#8F242429'));
    expect(normalControl, isNot(contains('#FF3A3A40')));
    expect(primaryControl, contains('#FFE52B50'));
    expect(scrim, contains('#00000000'));
    expect(scrim, isNot(contains('<gradient')));
  });

  test(
    'Media3 keeps track controls focusable so unavailable pickers explain',
    () {
      final media3 = File(
        'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
        'Media3PlayerActivity.kt',
      ).readAsStringSync();

      expect(media3, contains('audioTrackButton.isEnabled = true'));
      expect(media3, contains('captionTrackButton.isEnabled = true'));
      expect(
        media3,
        contains('setChromeControlAvailable(audioControlContainer, true)'),
      );
      expect(
        media3,
        contains('setChromeControlAvailable(captionControlContainer, true)'),
      );
      expect(media3, contains('R.string.tetotv_player_no_audio_tracks'));
      expect(media3, contains('R.string.tetotv_player_no_caption_tracks'));
      expect(media3, contains('Player.COMMAND_SEEK_BACK'));
      expect(media3, contains('Player.COMMAND_SEEK_FORWARD'));
    },
  );

  test('native pill surfaces defer accessibility to labeled icon controls', () {
    final nativeStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();

    expect(
      nativeStyles,
      contains('<item name="android:importantForAccessibility">no</item>'),
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlPill">[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
    expect(
      RegExp(
        r'<style name="TetoTVPlayerControlIcon"[\s\S]*?'
        r'<item name="android:layout_height">40dp</item>',
      ).hasMatch(nativeStyles),
      isTrue,
    );
  });

  test('Media3 uses app-owned rounded icons and Teto focus treatment', () {
    final nativeChrome = File(
      'android/app/src/main/res/layout/tetotv_player_controls.xml',
    ).readAsStringSync();
    final normalFocus = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_pill_background.xml',
    ).readAsStringSync();
    final primaryFocus = File(
      'android/app/src/main/res/drawable/'
      'tetotv_player_control_primary_background.xml',
    ).readAsStringSync();
    final media3 = File(
      'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
      'Media3PlayerActivity.kt',
    ).readAsStringSync();
    final nativeHudSource = '$nativeChrome\n$media3';

    expect(nativeChrome, isNot(contains('@android:drawable/ic_menu_')));
    for (final icon in [
      'replay_rounded',
      'play_arrow_rounded',
      'pause_rounded',
      'forward_rounded',
      'picture',
      'player',
      'options',
    ]) {
      expect(nativeHudSource, contains('tetotv_ic_$icon'));
      final vector = File(
        'android/app/src/main/res/drawable/tetotv_ic_$icon.xml',
      ).readAsStringSync();
      expect(vector, contains('<vector'));
      expect(vector, contains('glyph used by Flutter'));
    }
    for (final focusDrawable in [normalFocus, primaryFocus]) {
      expect(focusDrawable, contains('android:state_activated="true"'));
      expect(focusDrawable, contains('android:width="3dp"'));
      expect(focusDrawable, contains('android:color="#FFFF5C78"'));
      expect(focusDrawable, contains('android:color="#E6000000"'));
      expect(focusDrawable, isNot(contains('android:color="#FFFFFFFF"')));
    }
    expect(media3, contains('control.setOnFocusChangeListener'));
    expect(
      media3,
      contains('setChromeControlHighlighted(container, hasFocus)'),
    );
    expect(media3, contains('CHROME_FOCUS_SCALE = 1.025f'));
    expect(media3, contains('CHROME_FOCUS_ANIMATION_MS = 80L'));
    expect(media3, contains('PathInterpolator(0.215f, 0.61f, 0.355f, 1f)'));
  });
}

void _expectInOrder(String source, List<String> tokens) {
  var previous = -1;
  for (final token in tokens) {
    final index = source.indexOf(token, previous + 1);
    expect(
      index,
      greaterThan(previous),
      reason: 'Missing/out of order: $token',
    );
    previous = index;
  }
}
