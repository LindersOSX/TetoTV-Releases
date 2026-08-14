import 'package:anime_tv/features/player/presentation/vlc_tv_player_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _VlcSmokeApp()));
}

class _VlcSmokeApp extends StatelessWidget {
  const _VlcSmokeApp();

  @override
  Widget build(BuildContext context) {
    const source = 'asset:///assets/videos/vlc_smoke.mp4';
    const release = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: 'TetoTV VLC compatibility smoke stream',
      seeders: 1,
      sourceId: 'smoke-test',
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: VlcTvPlayerScreen(
        source: source,
        title: 'VLC compatibility smoke test',
        debridService: DebridService.realDebrid,
        launch: launch,
        onUseMpv: (_, _, _, _) {},
        onStreamAdopted: (_, _) async {},
      ),
    );
  }
}
