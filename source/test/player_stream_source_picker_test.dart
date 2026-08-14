import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/player/presentation/player_stream_source_picker.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source merge deduplicates by URI and sorts highest quality first', () {
    final low = _option('https://video.example/720.m3u8', '720p');
    final high = _option('https://video.example/1080.m3u8', '1080p');
    final duplicate = _option('https://video.example/720.m3u8', '4K');

    final merged = mergePlaybackStreamOptions([low], [high, duplicate]);

    expect(merged, hasLength(2));
    expect(merged.first.stream.uri, high.stream.uri);
    expect(merged.last.release.quality, '720p');
  });

  test('web recovery sees late direct sources before engine fallback', () {
    final current = _option('https://video.example/current.m3u8', '720p');
    final alternate = _option('https://video.example/alternate.m3u8', '1080p');

    expect(
      hasUntriedDirectWebStream(
        current: current.stream,
        options: [current, alternate],
      ),
      isTrue,
    );
    expect(
      hasUntriedDirectWebStream(
        current: current.stream,
        options: [current, alternate],
        failedUris: {alternate.stream.uri.toString()},
      ),
      isFalse,
    );
  });

  test('engine handoff preserves newly discovered source choices', () {
    final initial = _option('https://video.example/initial.m3u8', '720p');
    final discovered = _option('https://video.example/discovered.m3u8', '4K');

    final handoff = playbackStreamOptionsForHandoff(
      currentStream: initial.stream,
      currentRelease: initial.release,
      existing: [discovered],
    );

    expect(
      handoff.map((option) => option.stream.uri),
      containsAll([initial.stream.uri, discovered.stream.uri]),
    );
    expect(handoff.first.stream.uri, discovered.stream.uri);
  });

  test('validated redirect replaces raw URL and cannot loop recovery', () {
    final raw = _option('https://video.example/raw', '1080p');
    final redirected = _option('https://cdn.example/final.m3u8', '1080p');
    final fallback = _option('https://video.example/fallback.m3u8', '720p');

    final options = replaceValidatedPlaybackStreamOption(
      options: [raw, fallback, redirected],
      requestedUri: raw.stream.uri,
      validated: redirected,
    );

    expect(
      options.map((option) => option.stream.uri),
      containsAll([redirected.stream.uri, fallback.stream.uri]),
    );
    expect(
      options.map((option) => option.stream.uri),
      isNot(contains(raw.stream.uri)),
    );
    expect(
      validatedRedirectWasAlreadyAttempted(
        requestedUri: raw.stream.uri,
        validatedUri: redirected.stream.uri,
        attemptedUris: {redirected.stream.uri.toString()},
      ),
      isTrue,
    );
    expect(
      validatedRedirectWasAlreadyAttempted(
        requestedUri: fallback.stream.uri,
        validatedUri: fallback.stream.uri,
        attemptedUris: {fallback.stream.uri.toString()},
      ),
      isFalse,
    );
  });

  testWidgets('late higher-quality insertion preserves focused source', (
    tester,
  ) async {
    final progress = StreamController<WebStreamSearchProgress>();
    addTearDown(progress.close);
    final low = _option('https://video.example/720.m3u8', '720p');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerStreamSourcePicker(
            initialOptions: [low],
            selectedUri: low.stream.uri,
            onOptionsChanged: (_) {},
            discover: ({bool refresh = false}) => progress.stream,
          ),
        ),
      ),
    );
    await tester.pump();

    FocusableActionDetector detectorFor(PlaybackStreamOption option) =>
        tester.widget(
          find.descendant(
            of: find.byKey(
              ValueKey(
                'player-source-option-${playbackStreamOptionKey(option)}',
              ),
            ),
            matching: find.byType(FocusableActionDetector),
          ),
        );

    expect(detectorFor(low).focusNode?.hasFocus, isTrue);

    progress.add(
      WebStreamSearchProgress(
        aggregation: WebStreamAggregation(
          streams: [
            WebStreamResult(
              providerId: 'late',
              providerName: 'Late Provider',
              title: 'Episode 1 1080p',
              uri: Uri.https('video.example', '/1080.m3u8'),
              quality: '1080p',
            ),
          ],
        ),
        completedProviders: 1,
        totalProviders: 2,
        pendingProviderNames: const ['Another Provider'],
      ),
    );
    await tester.pump();

    expect(find.textContaining('1080p'), findsWidgets);
    expect(detectorFor(low).focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source picker follows a custom Theme Studio palette', (
    tester,
  ) async {
    final palette = AppThemePalette.fromSeeds(
      background: const Color(0xFF061522),
      surface: const Color(0xFF1A3548),
      accent: const Color(0xFF32A86B),
      primaryText: const Color(0xFFF2E5D2),
      mutedText: const Color(0xFF90A8BA),
    );
    final selected = _option('https://video.example/1080.m3u8', '1080p');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkFor(palette),
        home: Scaffold(
          body: PlayerStreamSourcePicker(
            initialOptions: [selected],
            selectedUri: selected.stream.uri,
            onOptionsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('player-source-picker-panel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(
      decoration.color,
      palette.surface.withValues(alpha: const Color(0xF5080808).a),
    );
    expect(decoration.border!.top.color, palette.accent.withValues(alpha: .75));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.video_library_rounded)).color,
      palette.accentBright,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('player-source-status')))
          .style
          ?.color,
      palette.mutedText,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color,
      palette.accentBright,
    );
    expect(tester.takeException(), isNull);
  });
}

PlaybackStreamOption _option(String uri, String quality) {
  final stream = StreamReady(
    uri: Uri.parse(uri),
    displayName: quality,
    providerId: quality,
    providerName: 'Provider $quality',
  );
  return PlaybackStreamOption(
    stream: stream,
    release: ReleaseCandidate(
      infoHash: uri,
      magnetUri: '',
      releaseName: 'Episode 1 $quality',
      seeders: 0,
      sourceId: 'web:$quality',
      quality: quality,
      provider: 'Provider $quality',
    ),
  );
}
