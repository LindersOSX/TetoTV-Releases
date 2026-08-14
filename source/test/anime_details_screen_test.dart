import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/anime_details_screen.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completed local episodes immediately advance details progress', () {
    expect(
      effectiveCompletedEpisodeProgress(
        trackedProgress: 3,
        localEpisode: 5,
        localCompleted: true,
      ),
      5,
    );
    expect(
      effectiveCompletedEpisodeProgress(
        trackedProgress: 7,
        localEpisode: 5,
        localCompleted: true,
      ),
      7,
    );
    expect(
      effectiveCompletedEpisodeProgress(trackedProgress: 3, localEpisode: 5),
      3,
    );
  });

  testWidgets('details error state starts on Back', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith(
            (_, _) async => throw StateError('offline'),
          ),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    final detector = find.descendant(
      of: find.byType(TvFocusable).first,
      matching: find.byType(FocusableActionDetector),
    );
    expect(
      tester.widget<FocusableActionDetector>(detector).focusNode?.hasFocus,
      isTrue,
    );
    expect(find.text('Could not load anime'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode action layout fits a 1080p TV canvas', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const anime = AnimeSummary(
      id: 1,
      title: 'The Example Hero and the Long Adventure Title',
      description:
          'A detailed synopsis that explains the story, its characters, and '
          'the challenges they face across a long television season.',
      episodes: 24,
      score: 8.4,
      genres: ['Action', 'Adventure', 'Fantasy'],
      format: 'TV',
      status: 'RELEASING',
      durationMinutes: 24,
      relatedAnime: [
        RelatedAnime(
          relationType: 'SEQUEL',
          anime: AnimeSummary(
            id: 2,
            title: 'The Example Hero Season 2',
            description: '',
            episodes: 12,
            score: 8.1,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith((_, _) async => anime),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
          trackingListProvider(
            TrackingListStatus.planToWatch,
          ).overrideWith((_) async => const TrackingListResult(items: [])),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('Start watching'), findsOneWidget);
    expect(find.text('My List status'), findsOneWidget);
    expect(find.text('Episode 1 of 24'), findsOneWidget);
    expect(find.text('Related series'), findsOneWidget);
    expect(find.text('RELATED'), findsNothing);
    expect(find.text('The Example Hero Season 2'), findsNothing);
    expect(find.text('Episodes'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AspectRatio && (widget.aspectRatio - 2 / 3).abs() < .001,
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('episode-step-previous')),
        matching: find.byType(FocusableActionDetector),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('episode-step-next')),
        matching: find.byType(FocusableActionDetector),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('My List status'));
    await tester.pumpAndSettle();
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Watching'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode action layout scales up on a full HD TV canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const anime = AnimeSummary(
      id: 1,
      title: 'Black Torch',
      description:
          'A detailed synopsis that remains readable beside the poster and '
          'playback controls on a full resolution television layout.',
      episodes: 24,
      score: 7.8,
      genres: ['Action', 'Adventure', 'Fantasy'],
      format: 'TV',
      status: 'RELEASING',
      durationMinutes: 24,
      seasonYear: 2026,
      staff: [AnimePerson(id: 10, name: 'Example Director')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith((_, _) async => anime),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EPISODE 1 OF 24'), findsOneWidget);
    expect(find.text('Start watching'), findsOneWidget);
    expect(find.text('Play from beginning'), findsOneWidget);
    expect(find.text('Play selected'), findsOneWidget);
    expect(find.text('Cast & crew'), findsOneWidget);
    expect(find.text('2026'), findsWidgets);
    expect(find.text('24m'), findsWidgets);
    expect(find.text('7.8 / 10'), findsOneWidget);
    final posterCenter = tester.getCenter(
      find.byKey(const ValueKey('anime-details-poster')),
    );
    final infoCenter = tester.getCenter(
      find.byKey(const ValueKey('anime-details-info')),
    );
    final actionsCenter = tester.getCenter(
      find.byKey(const ValueKey('episode-actions-panel')),
    );
    expect((posterCenter.dy - actionsCenter.dy).abs(), lessThan(1));
    expect((infoCenter.dy - actionsCenter.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('future shows display an unreleased cover badge', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const anime = AnimeSummary(
      id: 11,
      title: 'Future Anime',
      description: 'This series has not premiered yet.',
      episodes: 12,
      score: null,
      status: 'NOT_YET_RELEASED',
      seasonYear: 2027,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animeDetailsProvider.overrideWith((_, _) async => anime),
          trackingHomeProvider.overrideWith(
            (_) async => const TrackingHomeData(
              watching: [],
              planToWatch: [],
              completed: [],
            ),
          ),
        ],
        child: const MaterialApp(home: AnimeDetailsScreen(animeId: 11)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('UNRELEASED'), findsOneWidget);
    expect(find.text('Not released yet'), findsOneWidget);
    expect(find.text('Start watching'), findsNothing);
    for (final key in const [
      'episode-action-resume',
      'episode-action-restart',
      'episode-action-selected',
      'episode-step-previous',
      'episode-step-next',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(FocusableActionDetector),
        ),
        findsNothing,
        reason: '$key must not become a D-pad focus stop before release',
      );
    }
    final backControl = tester.widget<FocusableActionDetector>(
      find
          .ancestor(
            of: find.text('Back'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    expect(backControl.focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(700, 600), Size(720, 600), Size(800, 600)]) {
    testWidgets(
      'episode actions remain responsive and focusable at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const anime = AnimeSummary(
          id: 21,
          title: 'Responsive Mid Width Anime With a Long Title',
          description:
              'A longer synopsis verifies that the information column remains '
              'readable without crowding the playback actions at tablet and '
              'small television widths.',
          episodes: 24,
          score: 8.7,
          genres: ['Action', 'Adventure', 'Fantasy'],
          format: 'TV',
          status: 'RELEASING',
          durationMinutes: 24,
          seasonYear: 2026,
          staff: [AnimePerson(id: 1, name: 'Director')],
          relatedAnime: [
            RelatedAnime(
              relationType: 'SEQUEL',
              anime: AnimeSummary(
                id: 22,
                title: 'Responsive Sequel',
                description: '',
                episodes: 12,
                score: 8,
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              animeDetailsProvider.overrideWith((_, _) async => anime),
              trackingHomeProvider.overrideWith(
                (_) async => const TrackingHomeData(
                  watching: [],
                  planToWatch: [],
                  completed: [],
                ),
              ),
            ],
            child: const MaterialApp(home: AnimeDetailsScreen(animeId: 21)),
          ),
        );
        await tester.pumpAndSettle();

        final posterRect = tester.getRect(
          find.byKey(const ValueKey('anime-details-poster')),
        );
        expect(posterRect.left, greaterThanOrEqualTo(0));
        expect(posterRect.top, greaterThanOrEqualTo(0));
        expect(posterRect.right, lessThanOrEqualTo(size.width));
        expect(posterRect.bottom, lessThanOrEqualTo(size.height));

        if (size.width < 800) {
          final backControl = tester.widget<FocusableActionDetector>(
            find
                .ancestor(
                  of: find.text('Back'),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          );
          expect(backControl.focusNode?.hasFocus, isTrue);
          await tester.ensureVisible(
            find.byKey(const ValueKey('episode-actions-panel')),
          );
          await tester.pump();
        } else {
          final resumeControl = tester.widget<FocusableActionDetector>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('episode-action-resume')),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          );
          expect(resumeControl.focusNode?.hasFocus, isTrue);
        }
        final actionsRect = tester.getRect(
          find.byKey(const ValueKey('episode-actions-panel')),
        );
        expect(actionsRect.left, greaterThanOrEqualTo(0));
        expect(actionsRect.top, greaterThanOrEqualTo(0));
        expect(actionsRect.right, lessThanOrEqualTo(size.width));
        expect(actionsRect.bottom, lessThanOrEqualTo(size.height));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in const [
    Size(390, 844),
    Size(412, 915),
    Size(768, 832),
    Size(1536, 2048),
    Size(844, 390),
  ]) {
    testWidgets(
      'episode action layout fits mobile ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const anime = AnimeSummary(
          id: 1,
          title: 'A Long Example Anime Title for a Small Mobile Screen',
          description:
              'A synopsis that remains readable while the compact page scrolls '
              'instead of forcing the television columns into a phone viewport.',
          episodes: 12,
          score: 8.2,
          genres: ['Action', 'Adventure', 'Fantasy'],
          format: 'TV',
          status: 'RELEASING',
          durationMinutes: 24,
          seasonYear: 2026,
          relatedAnime: [
            RelatedAnime(
              relationType: 'SEQUEL',
              anime: AnimeSummary(
                id: 2,
                title: 'Example Season Two',
                description: '',
                episodes: 12,
                score: 8,
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              animeDetailsProvider.overrideWith((_, _) async => anime),
              trackingHomeProvider.overrideWith(
                (_) async => const TrackingHomeData(
                  watching: [],
                  planToWatch: [],
                  completed: [],
                ),
              ),
            ],
            child: const MaterialApp(home: AnimeDetailsScreen(animeId: 1)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Start watching'), findsOneWidget);
        expect(find.text('Play from beginning'), findsOneWidget);
        expect(find.text('Play selected'), findsOneWidget);
        expect(find.text('Related series'), findsOneWidget);
        expect(find.text('EP 1 / 12'), findsOneWidget);
        final posterSize = tester.getSize(
          find.byKey(const ValueKey('anime-details-poster')),
        );
        expect(posterSize.width, inInclusiveRange(112, 320));
        if (size.width >= 1200) {
          expect(posterSize.width, greaterThanOrEqualTo(300));
        }
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('episode-actions-panel')))
              .dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('anime-details-poster')),
                )
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
