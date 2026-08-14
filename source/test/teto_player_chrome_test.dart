import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/features/player/presentation/teto_player_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared player chrome keeps every feature control available', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: TetoPlayerChrome(
            engineKey: 'test',
            title: 'A test anime • Episode 3',
            streamLabel: 'Web stream',
            engineLabel: 'MPV',
            position: const Duration(minutes: 3),
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 30,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('CC'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Back 10s'), findsNothing);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Forward 30s'), findsNothing);
    expect(find.bySemanticsLabel('Back 10s'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Forward 30s'), findsOneWidget);
    expect(find.text('03:00  /  24:00'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(
      find.byKey(const ValueKey('player-progress-scrubber')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('player-control-Back 10s'))),
      const Size.square(40),
    );
    expect(
      (tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('test-bottom-player-chrome')),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      const Color(0xD6080808),
    );
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(const ValueKey('player-control-Options')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      const Color(0x8F242429),
    );
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(const ValueKey('player-control-Pause')),
                  )
                  .decoration!
              as BoxDecoration)
          .color,
      AppColors.accent,
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('test-player-progress-bar')),
    );
    expect(progress.color, AppColors.accentBright);
    expect(progress.backgroundColor, Colors.white.withValues(alpha: .24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('icon-only transport controls keep their D-pad actions', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    var rewindCount = 0;
    var playPauseCount = 0;
    var forwardCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'transport-actions',
            title: 'Episode',
            streamLabel: 'Stream',
            position: Duration.zero,
            duration: const Duration(minutes: 24),
            isPlaying: false,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 30,
            onRewind: () => rewindCount++,
            onPlayPause: () => playPauseCount++,
            onForward: () => forwardCount++,
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    playFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(playPauseCount, 1);
    expect(rewindCount, 1);
    expect(forwardCount, 1);
    expect(find.text('Back 10s'), findsNothing);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Forward 30s'), findsNothing);
    expect(find.bySemanticsLabel('Back 10s'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(find.bySemanticsLabel('Forward 30s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip segment is a separate translucent overlay', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TetoSkipSegmentOverlay(
              label: 'Skip Intro',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('player-skip-segment-overlay')),
      findsOneWidget,
    );
    expect(find.text('Skip Intro'), findsOneWidget);
  });

  testWidgets('shared chrome consumes every Theme Studio HUD color role', (
    tester,
  ) async {
    final palette = AppThemePalette.fromSeeds(
      background: const Color(0xFF07131F),
      surface: const Color(0xFF1B3045),
      accent: const Color(0xFF2DAA68),
      primaryText: const Color(0xFFF2E7D5),
      mutedText: const Color(0xFF91A5B8),
    );
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkFor(palette),
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'themed',
            title: 'Themed episode',
            streamLabel: 'Stream',
            position: const Duration(minutes: 2),
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('themed-bottom-player-chrome')),
    );
    final panelDecoration = panel.decoration as BoxDecoration;
    expect(
      panelDecoration.color,
      Color.lerp(
        palette.background,
        palette.surface,
        .62,
      )!.withValues(alpha: .84),
    );
    expect(
      panelDecoration.border!.top.color,
      palette.accent.withValues(alpha: .78),
    );

    final normalControl = tester.widget<Container>(
      find.byKey(const ValueKey('player-control-Options')),
    );
    expect(
      (normalControl.decoration! as BoxDecoration).color,
      palette.selectableSurface.withValues(alpha: .56),
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('themed-player-progress-bar')),
    );
    expect(progress.color, palette.accentBright);
    expect(
      progress.backgroundColor,
      palette.primaryText.withValues(alpha: .24),
    );
    expect(
      tester.widget<Text>(find.text('Options')).style?.color,
      palette.primaryText,
    );
    expect(
      tester.widget<Text>(find.textContaining('D-pad controls')).style?.color,
      palette.mutedText,
    );

    playFocus.requestFocus();
    await tester.pumpAndSettle();
    final focusedChrome = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('player-control-Pause')),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final focusDecoration = focusedChrome.decoration as BoxDecoration;
    final focusForeground = focusedChrome.foregroundDecoration as BoxDecoration;
    expect(focusForeground.border!.top.color, palette.focusRing);
    expect(
      focusDecoration.boxShadow!.map((shadow) => shadow.color),
      contains(palette.focusGlow),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared chrome remains usable at narrow phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'phone',
            title: 'A very long anime episode title that must not overflow',
            streamLabel: 'A very long marketplace provider name',
            position: const Duration(minutes: 1),
            duration: const Duration(minutes: 24),
            isPlaying: false,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onSources: () {},
            onOptions: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    playFocus.requestFocus();
    await tester.pump();
    for (var move = 0; move < 8; move++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 120));
    }
    final optionsRect = tester.getRect(
      find.widgetWithText(TetoPlayerControl, 'Options'),
    );
    expect(optionsRect.left, greaterThanOrEqualTo(0));
    expect(optionsRect.right, lessThanOrEqualTo(320));
    expect(tester.binding.focusManager.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D-pad Down dismisses the visible player HUD immediately', (
    tester,
  ) async {
    final playFocus = FocusNode();
    addTearDown(playFocus.dispose);
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TetoPlayerChrome(
            engineKey: 'dismiss',
            title: 'Episode',
            streamLabel: 'Web stream',
            position: Duration.zero,
            duration: const Duration(minutes: 24),
            isPlaying: true,
            playFocusNode: playFocus,
            seekBackSeconds: 10,
            seekForwardSeconds: 10,
            onRewind: () {},
            onPlayPause: () {},
            onForward: () {},
            onAudio: () {},
            onSubtitles: () {},
            onCaptionSize: () {},
            onPicture: () {},
            onFixVideo: () {},
            onOptions: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    playFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(dismissed, isTrue);
  });

  for (final testCase in <({Size viewport, double textScale})>[
    (viewport: const Size(640, 360), textScale: 2.5),
    (viewport: const Size(720, 480), textScale: 2.0),
  ]) {
    testWidgets(
      'edge pills stay contained at ${testCase.viewport.width.toInt()}x'
      '${testCase.viewport.height.toInt()} and ${testCase.textScale}x text',
      (tester) async {
        tester.view.physicalSize = testCase.viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playFocus = FocusNode();
        addTearDown(playFocus.dispose);
        var optionsActivated = false;
        var rewindActivated = false;

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(testCase.textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: TetoPlayerChrome(
                engineKey: 'large-text',
                title: 'Episode',
                streamLabel: 'Stream',
                position: Duration.zero,
                duration: const Duration(minutes: 24),
                isPlaying: true,
                playFocusNode: playFocus,
                seekBackSeconds: 10,
                seekForwardSeconds: 10,
                onRewind: () => rewindActivated = true,
                onPlayPause: () {},
                onForward: () {},
                onAudio: () {},
                onSubtitles: () {},
                onCaptionSize: () {},
                onPicture: () {},
                onFixVideo: () {},
                onSources: () {},
                onOptions: () => optionsActivated = true,
                onDismiss: () {},
              ),
            ),
          ),
        );

        playFocus.requestFocus();
        await tester.pump();
        for (var move = 0; move < 8; move++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 120));
        }
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();

        final control = find.widgetWithText(TetoPlayerControl, 'Options');
        final controlRect = tester.getRect(control);
        final textRect = tester.getRect(
          find.descendant(of: control, matching: find.text('Options')),
        );
        final iconRect = tester.getRect(
          find.descendant(
            of: control,
            matching: find.byIcon(Icons.tune_rounded),
          ),
        );
        final viewportRect = Offset.zero & testCase.viewport;
        final panelRect = tester.getRect(
          find.byKey(const ValueKey('large-text-bottom-player-chrome')),
        );
        expect(viewportRect.contains(controlRect.topLeft), isTrue);
        expect(viewportRect.contains(controlRect.bottomRight), isTrue);
        // The trailing gutter also contains TvFocusable's scaled focus glow
        // inside the HUD card, not just inside the physical display.
        expect(controlRect.right + 14, lessThanOrEqualTo(panelRect.right));
        expect(controlRect.contains(textRect.topLeft), isTrue);
        expect(controlRect.contains(textRect.bottomRight), isTrue);
        expect(controlRect.contains(iconRect.topLeft), isTrue);
        expect(controlRect.contains(iconRect.bottomRight), isTrue);
        expect(optionsActivated, isTrue);
        final scrollable = Scrollable.of(
          tester.binding.focusManager.primaryFocus!.context!,
        );
        expect(
          scrollable.position.pixels,
          closeTo(scrollable.position.maxScrollExtent, 0.01),
        );

        // Traverse all the way back from the trailing edge. This mirrors the
        // real remote-control path and catches a leading-edge regression that
        // a fresh, already-left-aligned HUD would hide.
        for (var move = 0; move < 9; move++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump(const Duration(milliseconds: 120));
        }
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();

        final rewindControl = find.byKey(
          const ValueKey('player-control-Back 10s'),
        );
        final rewindRect = tester.getRect(rewindControl);
        final rewindIconRect = tester.getRect(
          find.descendant(
            of: rewindControl,
            matching: find.byIcon(Icons.replay_rounded),
          ),
        );
        expect(rewindRect.left - 14, greaterThanOrEqualTo(panelRect.left));
        expect(tester.getSize(rewindControl), const Size.square(40));
        expect(rewindRect.width, closeTo(41, .01));
        expect(rewindRect.height, closeTo(41, .01));
        expect(find.text('Back 10s'), findsNothing);
        expect(find.bySemanticsLabel('Back 10s'), findsOneWidget);
        expect(rewindRect.contains(rewindIconRect.topLeft), isTrue);
        expect(rewindRect.contains(rewindIconRect.bottomRight), isTrue);
        expect(rewindActivated, isTrue);
        expect(
          scrollable.position.pixels,
          closeTo(scrollable.position.minScrollExtent, 0.01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
