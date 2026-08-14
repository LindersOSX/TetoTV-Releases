import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'libVLC compatibility player renders and advances on Android TV',
    (tester) async {
      const source = 'asset:///assets/videos/vlc_smoke.mp4';
      const release = ReleaseCandidate(
        infoHash: '0123456789012345678901234567890123456789',
        magnetUri:
            'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
        releaseName: 'TetoTV VLC compatibility smoke stream',
        seeders: 1,
        sourceId: 'integration-test',
        codec: 'H.264',
      );
      const episode = EpisodeReference(
        anilistMediaId: 1,
        title: 'VLC compatibility smoke test',
        episode: 1,
      );
      final launch = PlaybackLaunch(
        stream: StreamReady(
          uri: Uri.parse(source),
          displayName: 'VLC smoke stream',
          debridService: DebridService.realDebrid,
        ),
        episode: episode,
        selectedRelease: release,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: VlcTvPlayerScreen(
              source: source,
              title: 'VLC compatibility smoke test',
              debridService: DebridService.realDebrid,
              launch: launch,
              onUseMpv: (_, _, _, _) {},
              onStreamAdopted: (_, _) async {},
            ),
          ),
        ),
      );

      for (var second = 0; second < 30; second++) {
        await tester.pump(const Duration(seconds: 1));
        if (find
            .byKey(const ValueKey('vlc-playback-advancing'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      expect(
        find.byKey(const ValueKey('vlc-player-initialized')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('vlc-playback-advancing')),
        findsOneWidget,
      );
      expect(find.textContaining('VLC compatibility'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
