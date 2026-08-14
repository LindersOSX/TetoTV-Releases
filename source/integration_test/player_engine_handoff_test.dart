import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'MPV and VLC repeatedly hand off the decoder without late surface callbacks',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _EngineHandoffHarness(),
          ),
        ),
      );

      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('mpv-bottom-player-chrome'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 2));

      for (var roundTrip = 0; roundTrip < 2; roundTrip++) {
        final vlcHandoff = roundTrip * 2 + 1;
        final mpvHandoff = vlcHandoff + 1;

        await _choosePlayer(tester, 'VLC');
        await _pumpUntil(
          tester,
          () => find
              .byKey(ValueKey('engine-vlc-$vlcHandoff'), skipOffstage: false)
              .evaluate()
              .isNotEmpty,
        );
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('vlc-playback-advancing'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'MPV surface detach must finish before VLC takes ownership',
        );

        await _choosePlayer(tester, 'MPV');
        await _pumpUntil(
          tester,
          () => find
              .byKey(ValueKey('engine-mpv-$mpvHandoff'), skipOffstage: false)
              .evaluate()
              .isNotEmpty,
        );
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('mpv-bottom-player-chrome'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'VLC-to-MPV handoff must not revive the released MPV player',
        );
      }

      expect(
        find.byKey(
          const ValueKey('handoff-position-valid'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  for (final engine in _SmokeEngine.values) {
    testWidgets(
      '${engine.name.toUpperCase()} Exit releases playback before popping',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: _PlayerExitHarness(engine: engine),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('open-exit-player')));
        await tester.pump();
        await _pumpUntil(
          tester,
          () => engine == _SmokeEngine.mpv
              ? find
                    .byKey(const ValueKey('mpv-bottom-player-chrome'))
                    .evaluate()
                    .isNotEmpty
              : find
                    .byKey(const ValueKey('vlc-playback-advancing'))
                    .evaluate()
                    .isNotEmpty,
        );

        await tester.binding.handlePopRoute();
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('player-exit-dialog'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('player-exit-confirm')));
        // A repeated Back while decoder release is in progress must join the
        // same terminal action and never pop the route below the player.
        await tester.binding.handlePopRoute();
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('exit-player-home'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('exit-harness-root')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _choosePlayer(WidgetTester tester, String label) async {
  final playerControl = find.text('Player');
  await _pumpUntil(tester, () => playerControl.evaluate().isNotEmpty);
  await tester.ensureVisible(playerControl.first);
  await tester.pumpAndSettle();
  await tester.tap(playerControl.first);
  await _pumpUntil(
    tester,
    () => find.text('Choose player').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 5),
  );
  expect(find.text('Choose player'), findsOneWidget);
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for the player smoke-test condition.');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

enum _SmokeEngine { mpv, vlc }

class _PlayerExitHarness extends StatelessWidget {
  const _PlayerExitHarness({required this.engine});

  final _SmokeEngine engine;

  static const _source = 'asset:///assets/videos/vlc_smoke.mp4';
  static const _release = ReleaseCandidate(
    infoHash: '0123456789012345678901234567890123456789',
    magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
    releaseName: 'TetoTV exit smoke stream',
    seeders: 1,
    sourceId: 'exit-smoke-test',
    codec: 'H.264',
  );
  static const _episode = EpisodeReference(
    anilistMediaId: 1,
    title: 'Exit smoke test',
    episode: 1,
  );

  PlaybackLaunch get _launch => PlaybackLaunch(
    stream: StreamReady(
      uri: Uri.parse(_source),
      displayName: 'Bundled exit smoke stream',
      debridService: DebridService.realDebrid,
    ),
    episode: _episode,
    selectedRelease: _release,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('exit-harness-root'),
    body: Center(
      child: FilledButton(
        key: const ValueKey('open-exit-player'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => engine == _SmokeEngine.mpv
                ? MpvTvPlayerScreen(
                    source: _source,
                    title: 'Exit smoke test',
                    debridService: DebridService.realDebrid,
                    launch: _launch,
                    anilistMediaId: _episode.anilistMediaId,
                    episode: _episode.episode,
                    onUseVlc: (_, _, _, _) {},
                    onStreamAdopted: (_, _) async {},
                  )
                : VlcTvPlayerScreen(
                    source: _source,
                    title: 'Exit smoke test',
                    debridService: DebridService.realDebrid,
                    launch: _launch,
                    anilistMediaId: _episode.anilistMediaId,
                    episode: _episode.episode,
                    onUseMpv: (_, _, _, _) {},
                    onStreamAdopted: (_, _) async {},
                  ),
          ),
        ),
        child: const Text('Open player'),
      ),
    ),
    bottomNavigationBar: const SizedBox(
      key: ValueKey('exit-player-home'),
      height: 1,
    ),
  );
}

class _EngineHandoffHarness extends StatefulWidget {
  const _EngineHandoffHarness();

  @override
  State<_EngineHandoffHarness> createState() => _EngineHandoffHarnessState();
}

class _EngineHandoffHarnessState extends State<_EngineHandoffHarness> {
  static const _source = 'asset:///assets/videos/vlc_smoke.mp4';
  static const _release = ReleaseCandidate(
    infoHash: '0123456789012345678901234567890123456789',
    magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
    releaseName: 'TetoTV engine handoff smoke stream',
    seeders: 1,
    sourceId: 'engine-handoff-test',
    codec: 'H.264',
  );
  static const _episode = EpisodeReference(
    anilistMediaId: 1,
    title: 'Engine handoff smoke test',
    episode: 1,
  );

  _SmokeEngine _engine = _SmokeEngine.mpv;
  Duration _resume = Duration.zero;
  int _handoffs = 0;

  PlaybackLaunch get _launch => PlaybackLaunch(
    stream: StreamReady(
      uri: Uri.parse(_source),
      displayName: 'Bundled smoke stream',
      debridService: DebridService.realDebrid,
    ),
    episode: _episode,
    selectedRelease: _release,
  );

  void _use(_SmokeEngine engine, Duration position) {
    setState(() {
      _engine = engine;
      _resume = position;
      _handoffs++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = _engine == _SmokeEngine.mpv
        ? MpvTvPlayerScreen(
            source: _source,
            title: 'Engine handoff smoke test',
            debridService: DebridService.realDebrid,
            launch: _launch,
            anilistMediaId: _episode.anilistMediaId,
            episode: _episode.episode,
            initialPosition: _resume,
            onUseVlc: (position, _, _, _) => _use(_SmokeEngine.vlc, position),
            onStreamAdopted: (_, _) async {},
            onSelectEngine: (selected, position, _, _, _) {
              if (selected == PreferredPlayer.vlc) {
                _use(_SmokeEngine.vlc, position);
              }
            },
          )
        : VlcTvPlayerScreen(
            source: _source,
            title: 'Engine handoff smoke test',
            debridService: DebridService.realDebrid,
            launch: _launch,
            anilistMediaId: _episode.anilistMediaId,
            episode: _episode.episode,
            initialPosition: _resume,
            onUseMpv: (position, _, _, _) => _use(_SmokeEngine.mpv, position),
            onStreamAdopted: (_, _) async {},
            onSelectEngine: (selected, position, _, _, _) {
              if (selected == PreferredPlayer.mpv) {
                _use(_SmokeEngine.mpv, position);
              }
            },
          );
    return Stack(
      children: [
        player,
        Offstage(
          child: Column(
            children: [
              if (_handoffs > 0)
                SizedBox(key: ValueKey('engine-${_engine.name}-$_handoffs')),
              if (_handoffs >= 2 && _resume > const Duration(seconds: 1))
                const SizedBox(key: ValueKey('handoff-position-valid')),
            ],
          ),
        ),
      ],
    );
  }
}
