import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native Media3 Back Exit returns to the series without relaunching playback',
    (tester) async {
      var engineSwitches = 0;
      final router = GoRouter(
        initialLocation: '/player',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: Center(
                child: Text('TetoTV Home', key: ValueKey('native-exit-home')),
              ),
            ),
          ),
          GoRoute(
            path: '/anime/:id',
            builder: (_, state) => Scaffold(
              body: Center(
                child: Text(
                  'Series ${state.pathParameters['id']}',
                  key: const ValueKey('native-exit-series'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/player',
            builder: (_, _) => NativeMedia3PlayerScreen(
              source: _source,
              title: 'Native exit route smoke test',
              debridService: DebridService.realDebrid,
              launch: _launch,
              onUseMpv: (_, _, _) => engineSwitches++,
              onUseVlc: (_, _, _) => engineSwitches++,
              onStreamAdopted: (_, _) async {},
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      );

      // The host-side smoke runner presses Back, moves focus to "Exit video",
      // and confirms it while Media3 owns the foreground Activity. This wait
      // covers the real native Activity result and the production Flutter
      // route handler that must return to the originating series.
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('native-exit-series'))
            .evaluate()
            .isNotEmpty,
      );
      expect(engineSwitches, 0);
      expect(tester.takeException(), isNull);

      // Catch a delayed duplicate result/relaunch after the series appears.
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('native-exit-series')), findsOneWidget);
      expect(engineSwitches, 0);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for native Media3 Exit to return to the series.');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const _source = 'asset:///assets/videos/vlc_smoke.mp4';

const _release = ReleaseCandidate(
  infoHash: '0123456789012345678901234567890123456789',
  magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
  releaseName: 'TetoTV native exit smoke stream',
  seeders: 1,
  sourceId: 'native-exit-smoke-test',
  codec: 'H.264',
);

const _episode = EpisodeReference(
  anilistMediaId: 1,
  title: 'Native exit smoke test',
  episode: 1,
);

final _launch = PlaybackLaunch(
  stream: StreamReady(
    uri: Uri.parse(_source),
    displayName: 'Bundled native exit smoke stream',
    debridService: DebridService.realDebrid,
  ),
  episode: _episode,
  selectedRelease: _release,
);
