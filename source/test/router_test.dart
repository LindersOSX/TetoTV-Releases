import 'package:anime_tv/app/router.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('route integers accept only positive decimal values', () {
    expect(positiveRouteInt('42'), 42);
    expect(positiveRouteInt('001'), 1);

    expect(positiveRouteInt(null), isNull);
    expect(positiveRouteInt(''), isNull);
    expect(positiveRouteInt('not-a-number'), isNull);
    expect(positiveRouteInt('0'), isNull);
    expect(positiveRouteInt('-1'), isNull);
  });

  test('legal disclosures have internal settings routes', () {
    final paths = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toSet();

    expect(paths, contains('/settings/privacy'));
    expect(paths, contains('/settings/notices'));
  });

  test('typed player routes allow only declared cross-class fallbacks', () {
    const episode = EpisodeReference(
      anilistMediaId: 1,
      title: 'Test show',
      episode: 2,
    );
    final release = ReleaseCandidate(
      infoHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      magnetUri: 'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      releaseName: '[Group] Test show - 02',
      seeders: 10,
      sourceId: 'source',
    );
    final fallback = ReleaseCandidate(
      infoHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      magnetUri: 'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      releaseName: '[Group] Test show - 02 alternate',
      seeders: 8,
      sourceId: 'source',
    );
    final web = StreamReady(
      uri: Uri.parse('https://video.example/episode-2.m3u8'),
      displayName: 'Web stream',
      providerId: 'web-provider',
    );
    final webOnly = PlaybackLaunch(
      stream: web,
      episode: episode,
      selectedRelease: release,
    );
    final webWithDebridFallback = PlaybackLaunch(
      stream: web,
      episode: episode,
      selectedRelease: release,
      alternatives: [fallback],
    );

    expect(
      isValidTypedPlayerLaunch(
        source: web.uri.toString(),
        service: null,
        resolved: webOnly,
      ),
      isTrue,
    );
    expect(
      isValidTypedPlayerLaunch(
        source: web.uri.toString(),
        service: DebridService.torBox,
        resolved: webOnly,
      ),
      isFalse,
    );
    expect(
      isValidTypedPlayerLaunch(
        source: web.uri.toString(),
        service: DebridService.torBox,
        resolved: webWithDebridFallback,
      ),
      isTrue,
    );
    expect(
      isValidTypedPlayerLaunch(
        source: 'https://attacker.example/not-the-launch.m3u8',
        service: DebridService.torBox,
        resolved: webWithDebridFallback,
      ),
      isFalse,
    );
  });

  test('player route accepts only active app-issued loopback capabilities', () {
    final issued = Uri.parse(
      'http://127.0.0.1:43123/tetotv-web/v1/'
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    );
    expect(
      isAllowedTypedPlayerSource(
        issued.toString(),
        ownsProxyUri: (uri) => uri == issued,
      ),
      isTrue,
    );
    expect(
      isAllowedTypedPlayerSource(
        issued
            .replace(pathSegments: [...issued.pathSegments.take(3), 'guess'])
            .toString(),
        ownsProxyUri: (_) => false,
      ),
      isFalse,
    );
    expect(
      isAllowedTypedPlayerSource(
        'http://127.0.0.1:43123/video.mp4',
        ownsProxyUri: (_) => false,
      ),
      isFalse,
    );
    expect(
      isAllowedTypedPlayerSource(
        'http://192.168.1.20/video.mp4',
        ownsProxyUri: (uri) => uri == issued,
      ),
      isFalse,
    );
    expect(isAllowedTypedPlayerSource('https://cdn.example/video.mp4'), isTrue);
    expect(isAllowedTypedPlayerSource('http://cdn.example/video.mp4'), isFalse);
  });
}
