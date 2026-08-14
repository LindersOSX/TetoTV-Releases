import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anime_tv/features/marketplace/data/web_playback_proxy.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinnedPublicWebProxyUpstream', () {
    test('rejects a redirect to a private target before another hop', () async {
      final upstream = PinnedPublicWebProxyUpstream(
        targetValidator: (_) async {},
        hopFetcher: (request) async => _response(
          request,
          status: HttpStatus.found,
          headers: {
            HttpHeaders.locationHeader: ['https://127.0.0.1/private.mp4'],
          },
        ),
      );

      await expectLater(
        upstream.fetch(Uri.parse('https://video.example/start')),
        throwsFormatException,
      );
    });

    test('strips credentials when a redirect changes origin', () async {
      final requests = <WebProxyUpstreamRequest>[];
      final upstream = PinnedPublicWebProxyUpstream(
        targetValidator: (_) async {},
        hopFetcher: (request) async {
          requests.add(request);
          if (request.uri.host == 'provider.example') {
            return _response(
              request,
              status: HttpStatus.found,
              headers: {
                HttpHeaders.locationHeader: ['https://cdn.example/video.mp4'],
              },
            );
          }
          return _response(request, contentType: 'video/mp4', bytes: [1, 2, 3]);
        },
      );

      final response = await upstream.fetch(
        Uri.parse('https://provider.example/start'),
        headers: const {
          'Authorization': 'Bearer secret',
          'Cookie': 'session=secret',
          'Referer': 'https://provider.example/',
        },
      );
      await response.close();

      expect(requests, hasLength(2));
      expect(requests.first.headers, contains('Authorization'));
      expect(requests.last.headers, isNot(contains('Authorization')));
      expect(requests.last.headers, isNot(contains('Cookie')));
      expect(requests.last.headers['Referer'], 'https://provider.example/');
    });
  });

  group('WebPlaybackProxy', () {
    test('uses a 20 second preparation budget and a 32 GiB media cap', () {
      const limits = WebPlaybackProxyLimits();
      expect(limits.preparationTimeout, const Duration(seconds: 20));
      expect(limits.maximumProgressiveBytes, 32 * 1024 * 1024 * 1024);
    });

    test(
      'serves progressive media only through an opaque active lease',
      () async {
        final upstream = _fakeUpstream((request) async {
          return _response(
            request,
            contentType: 'video/mp4',
            bytes: [1, 2, 3, 4],
          );
        });
        final proxy = WebPlaybackProxy(upstream: upstream);
        addTearDown(proxy.close);

        final session = await proxy.prepare(
          uri: Uri.parse('https://cdn.example/video.mp4'),
        );
        expect(session.playbackUri.scheme, 'http');
        expect(session.playbackUri.host, '127.0.0.1');
        expect(proxy.isOwnedPlaybackProxyUri(session.playbackUri), isTrue);

        final retained = proxy.retainSessionForUri(session.playbackUri);
        expect(retained, isNotNull);
        await session.close();
        expect(proxy.isOwnedPlaybackProxyUri(retained!.playbackUri), isTrue);

        final response = await _localRequest(retained.playbackUri);
        expect(response.status, HttpStatus.ok);
        expect(response.body, [1, 2, 3, 4]);

        await retained.close();
        await retained.close();
        expect(proxy.isOwnedPlaybackProxyUri(retained.playbackUri), isFalse);
        expect((await _localRequest(retained.playbackUri)).status, 404);
      },
    );

    test(
      'expires retained capabilities but lets an active response drain',
      () async {
        var now = DateTime.utc(2026, 1, 1);
        final body = StreamController<List<int>>();
        final actualStarted = Completer<void>();
        final proxy = WebPlaybackProxy(
          limits: const WebPlaybackProxyLimits(
            sessionMaximumAge: Duration(seconds: 1),
          ),
          clock: () => now,
          upstream: _fakeUpstream((request) async {
            if (request.range?.startsWith('bytes=0-') == true) {
              return _response(request, contentType: 'video/mp4', bytes: [1]);
            }
            if (!actualStarted.isCompleted) actualStarted.complete();
            return WebProxyUpstreamResponse(
              statusCode: HttpStatus.ok,
              uri: request.uri,
              requestHeaders: request.headers,
              headers: const {
                HttpHeaders.contentTypeHeader: ['video/mp4'],
              },
              body: body.stream,
            );
          }),
        );
        addTearDown(() async {
          if (!body.isClosed) await body.close();
          await proxy.close();
        });
        final session = await proxy.prepare(
          uri: Uri.parse('https://cdn.example/video.mp4'),
        );
        final retained = proxy.retainSessionForUri(session.playbackUri)!;
        await session.close();

        final client = HttpClient();
        final request = await client.getUrl(retained.playbackUri);
        final responseFuture = request.close();
        await actualStarted.future;
        body.add([1]);
        final response = await responseFuture;
        final drained = response.drain<void>();

        now = now.add(const Duration(seconds: 2));
        expect(proxy.isOwnedPlaybackProxyUri(retained.playbackUri), isTrue);
        await retained.close();
        expect(proxy.isOwnedPlaybackProxyUri(retained.playbackUri), isFalse);
        await body.close();
        await drained;
        client.close(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(proxy.activeSessionCount, 0);
      },
    );

    test('maximum age revokes a retained capability when idle', () async {
      var now = DateTime.utc(2026, 1, 1);
      final proxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(
          sessionMaximumAge: Duration(seconds: 1),
        ),
        clock: () => now,
        upstream: _fakeUpstream(
          (request) async =>
              _response(request, contentType: 'video/mp4', bytes: [1]),
        ),
      );
      addTearDown(proxy.close);
      final session = await proxy.prepare(
        uri: Uri.parse('https://cdn.example/video.mp4'),
      );
      final retained = proxy.retainSessionForUri(session.playbackUri)!;
      await session.close();
      now = now.add(const Duration(seconds: 2));

      expect(proxy.isOwnedPlaybackProxyUri(retained.playbackUri), isFalse);
      expect(proxy.activeSessionCount, 0);
      await retained.close();
    });

    test(
      'rejects requests beyond the global and per-session concurrency cap',
      () async {
        final body = StreamController<List<int>>();
        final actualStarted = Completer<void>();
        final proxy = WebPlaybackProxy(
          limits: const WebPlaybackProxyLimits(
            maximumConcurrentRequests: 1,
            maximumSessionRequests: 1,
          ),
          upstream: _fakeUpstream((request) async {
            if (request.range?.startsWith('bytes=0-') == true) {
              return _response(request, contentType: 'video/mp4', bytes: [1]);
            }
            if (!actualStarted.isCompleted) actualStarted.complete();
            return WebProxyUpstreamResponse(
              statusCode: HttpStatus.ok,
              uri: request.uri,
              requestHeaders: request.headers,
              headers: const {
                HttpHeaders.contentTypeHeader: ['video/mp4'],
              },
              body: body.stream,
            );
          }),
        );
        addTearDown(() async {
          if (!body.isClosed) await body.close();
          await proxy.close();
        });
        final session = await proxy.prepare(
          uri: Uri.parse('https://cdn.example/video.mp4'),
        );
        final firstClient = HttpClient();
        final firstRequest = await firstClient.getUrl(session.playbackUri);
        final firstResponseFuture = firstRequest.close();
        await actualStarted.future;
        body.add([1]);
        final firstResponse = await firstResponseFuture;
        final firstDrain = firstResponse.drain<void>();

        expect(
          (await _localRequest(session.playbackUri)).status,
          HttpStatus.serviceUnavailable,
        );
        await body.close();
        await firstDrain;
        firstClient.close(force: true);
        await session.close();
      },
    );

    test('bounds total requests accepted by one capability session', () async {
      final proxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(maximumTotalSessionRequests: 1),
        upstream: _fakeUpstream(
          (request) async =>
              _response(request, contentType: 'video/mp4', bytes: [1]),
        ),
      );
      addTearDown(proxy.close);
      final session = await proxy.prepare(
        uri: Uri.parse('https://cdn.example/video.mp4'),
      );

      expect((await _localRequest(session.playbackUri)).status, HttpStatus.ok);
      expect(
        (await _localRequest(session.playbackUri)).status,
        HttpStatus.serviceUnavailable,
      );
      await session.close();
    });

    test(
      'rewrites a bounded static nested HLS graph to local tokens',
      () async {
        final root = Uri.parse('https://provider.example/master.m3u8');
        final nested = Uri.parse('https://provider.example/720.m3u8');
        final segment = Uri.parse('https://provider.example/segment.ts');
        final upstream = _fakeUpstream((request) async {
          if (request.uri == root) {
            return _textResponse(
              request,
              '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n720.m3u8\n',
            );
          }
          if (request.uri == nested) {
            return _textResponse(
              request,
              '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\n'
              'segment.ts\n#EXT-X-ENDLIST\n',
            );
          }
          expect(request.uri, segment);
          return _response(
            request,
            contentType: 'video/mp2t',
            bytes: [7, 8, 9],
          );
        });
        final proxy = WebPlaybackProxy(upstream: upstream);
        addTearDown(proxy.close);

        final session = await proxy.prepare(uri: root);
        final master = utf8.decode(
          (await _localRequest(session.playbackUri)).body,
        );
        final nestedLocal = Uri.parse(
          master.split('\n').firstWhere((line) => line.startsWith('http://')),
        );
        expect(proxy.isOwnedPlaybackProxyUri(nestedLocal), isTrue);
        final media = utf8.decode((await _localRequest(nestedLocal)).body);
        final segmentLocal = Uri.parse(
          media.split('\n').firstWhere((line) => line.startsWith('http://')),
        );
        expect((await _localRequest(segmentLocal)).body, [7, 8, 9]);
        await session.close();
      },
    );

    test('rejects private nested HLS references and live playlists', () async {
      Future<void> expectRejected(String manifest) async {
        final upstream = _fakeUpstream(
          (request) async => _textResponse(request, manifest),
        );
        final proxy = WebPlaybackProxy(upstream: upstream);
        addTearDown(proxy.close);
        await expectLater(
          proxy.prepare(uri: Uri.parse('https://cdn.example/root.m3u8')),
          throwsFormatException,
        );
      }

      await expectRejected(
        '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\n'
        'https://127.0.0.1/private.ts\n#EXT-X-ENDLIST\n',
      );
      await expectRejected(
        '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts\n',
      );
    });

    test('revalidates DNS before an actual media request', () async {
      var validations = 0;
      final upstream = PinnedPublicWebProxyUpstream(
        targetValidator: (_) async {
          validations++;
          if (validations > 1) {
            throw const FormatException('Host rebound to a private address.');
          }
        },
        hopFetcher: (request) async =>
            _response(request, contentType: 'video/mp4', bytes: [1, 2, 3]),
      );
      final proxy = WebPlaybackProxy(upstream: upstream);
      addTearDown(proxy.close);
      final session = await proxy.prepare(
        uri: Uri.parse('https://cdn.example/video.mp4'),
      );

      expect((await _localRequest(session.playbackUri)).status, 502);
      expect(validations, 2);
      await session.close();
    });

    test('forwards a single Range and If-Range validator', () async {
      WebProxyUpstreamRequest? playbackRequest;
      final upstream = _fakeUpstream((request) async {
        if (request.range == 'bytes=10-19') playbackRequest = request;
        return _response(
          request,
          status: request.range == null || request.range!.startsWith('bytes=0-')
              ? HttpStatus.ok
              : HttpStatus.partialContent,
          contentType: 'video/mp4',
          headers: request.range == 'bytes=10-19'
              ? {
                  HttpHeaders.contentRangeHeader: ['bytes 10-19/100'],
                  HttpHeaders.acceptRangesHeader: ['bytes'],
                }
              : const {},
          bytes: request.range == 'bytes=10-19'
              ? List<int>.filled(10, 4)
              : [1, 2, 3],
        );
      });
      final proxy = WebPlaybackProxy(upstream: upstream);
      addTearDown(proxy.close);
      final session = await proxy.prepare(
        uri: Uri.parse('https://cdn.example/video.mp4'),
      );

      final response = await _localRequest(
        session.playbackUri,
        headers: const {
          HttpHeaders.rangeHeader: 'bytes=10-19',
          HttpHeaders.ifRangeHeader: '"version-1"',
        },
      );
      expect(response.status, HttpStatus.partialContent);
      expect(playbackRequest?.range, 'bytes=10-19');
      expect(playbackRequest?.ifRange, '"version-1"');
      await session.close();
    });

    test(
      'rejects guessed, malformed, and traversal capability paths',
      () async {
        final proxy = WebPlaybackProxy(
          upstream: _fakeUpstream(
            (request) async =>
                _response(request, contentType: 'video/mp4', bytes: [1]),
          ),
        );
        addTearDown(proxy.close);
        final session = await proxy.prepare(
          uri: Uri.parse('https://cdn.example/video.mp4'),
        );
        final segments = session.playbackUri.pathSegments;
        final guessed = session.playbackUri.replace(
          pathSegments: [
            ...segments.take(3),
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          ],
        );
        final malformed = session.playbackUri.replace(path: '/anything');
        final traversal = session.playbackUri.replace(
          path: '/tetotv-web/v1/${segments[2]}/../${segments[3]}',
        );

        expect((await _localRequest(guessed)).status, 404);
        expect((await _localRequest(malformed)).status, 404);
        expect((await _localRequest(traversal)).status, 404);
        await session.close();
      },
    );

    test('enforces manifest reference and progressive size caps', () async {
      final hlsProxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(maximumManifestReferences: 1),
        upstream: _fakeUpstream(
          (request) async => _textResponse(
            request,
            '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:5,\na.ts\n'
            '#EXTINF:5,\nb.ts\n#EXT-X-ENDLIST\n',
          ),
        ),
      );
      addTearDown(hlsProxy.close);
      await expectLater(
        hlsProxy.prepare(uri: Uri.parse('https://cdn.example/root.m3u8')),
        throwsFormatException,
      );

      const maximum = 8;
      final mediaProxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(maximumProgressiveBytes: maximum),
        upstream: _fakeUpstream((request) async {
          if (request.range?.startsWith('bytes=0-') == true) {
            return _response(
              request,
              contentType: 'video/mp4',
              bytes: [1, 2, 3],
            );
          }
          return _response(
            request,
            contentType: 'video/mp4',
            headers: {
              HttpHeaders.contentLengthHeader: ['${maximum + 1}'],
            },
          );
        }),
      );
      addTearDown(mediaProxy.close);
      final session = await mediaProxy.prepare(
        uri: Uri.parse('https://cdn.example/video.mp4'),
      );
      expect((await _localRequest(session.playbackUri)).status, 502);
      await session.close();

      final rangedMediaProxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(maximumProgressiveBytes: maximum),
        upstream: _fakeUpstream((request) async {
          if (request.range?.startsWith('bytes=0-') == true &&
              request.range != 'bytes=0-0') {
            return _response(
              request,
              contentType: 'video/mp4',
              bytes: [1, 2, 3],
            );
          }
          return _response(
            request,
            status: HttpStatus.partialContent,
            contentType: 'video/mp4',
            headers: {
              HttpHeaders.contentLengthHeader: ['1'],
              HttpHeaders.contentRangeHeader: ['bytes 0-0/${maximum + 1}'],
            },
            bytes: [1],
          );
        }),
      );
      addTearDown(rangedMediaProxy.close);
      final rangedSession = await rangedMediaProxy.prepare(
        uri: Uri.parse('https://cdn.example/ranged-video.mp4'),
      );
      expect(
        (await _localRequest(
          rangedSession.playbackUri,
          headers: const {HttpHeaders.rangeHeader: 'bytes=0-0'},
        )).status,
        502,
      );
      await rangedSession.close();
    });

    test('times out one shared preparation budget', () async {
      final proxy = WebPlaybackProxy(
        limits: const WebPlaybackProxyLimits(
          preparationTimeout: Duration(milliseconds: 10),
        ),
        upstream: PinnedPublicWebProxyUpstream(
          limits: const WebPlaybackProxyLimits(
            preparationTimeout: Duration(milliseconds: 10),
          ),
          targetValidator: (_) =>
              Future<void>.delayed(const Duration(milliseconds: 100)),
          hopFetcher: (request) async =>
              _response(request, contentType: 'video/mp4', bytes: [1]),
        ),
      );
      addTearDown(proxy.close);

      await expectLater(
        proxy.prepare(uri: Uri.parse('https://slow.example/video.mp4')),
        throwsFormatException,
      );
      expect(proxy.activeSessionCount, 0);
    });

    test(
      'proxies supported subtitles and reports rejected subtitles',
      () async {
        final stream = Uri.parse('https://cdn.example/video.mp4');
        final goodSubtitle = Uri.parse('https://cdn.example/subtitle.vtt');
        final badSubtitle = Uri.parse('https://cdn.example/subtitle.html');
        final unavailableSubtitle = Uri.parse(
          'https://cdn.example/unavailable.vtt',
        );
        final upstream = _fakeUpstream((request) async {
          if (request.uri == stream) {
            return _response(
              request,
              contentType: 'video/mp4',
              bytes: [1, 2, 3],
            );
          }
          if (request.uri == goodSubtitle) {
            return _response(
              request,
              contentType: 'text/vtt',
              bytes: utf8.encode('WEBVTT\n\n00:00.000 --> 00:01.000\nHello'),
            );
          }
          if (request.uri == unavailableSubtitle) {
            throw StateError('subtitle host unavailable');
          }
          expect(request.uri, badSubtitle);
          return _response(
            request,
            contentType: 'text/html',
            bytes: utf8.encode('<!doctype html>login'),
          );
        });
        final proxy = WebPlaybackProxy(upstream: upstream);
        addTearDown(proxy.close);

        // Use the injectable proxy directly so no global loopback server leaks
        // between tests.
        final validated = await WebStreamValidator(
          proxy: proxy,
        ).validate(stream, const {}, subtitleUri: goodSubtitle);
        expect(validated.subtitleUri, isNotNull);
        expect(validated.subtitleContentType, 'text/vtt');
        expect(validated.subtitleRejected, isFalse);
        expect(
          utf8.decode((await _localRequest(validated.subtitleUri!)).body),
          contains('WEBVTT'),
        );
        await validated.session?.close();

        final rejected = await WebStreamValidator(
          proxy: proxy,
        ).validate(stream, const {}, subtitleUri: badSubtitle);
        expect(rejected.subtitleUri, isNull);
        expect(rejected.subtitleRejected, isTrue);
        await rejected.session?.close();

        final unavailable = await WebStreamValidator(
          proxy: proxy,
        ).validate(stream, const {}, subtitleUri: unavailableSubtitle);
        expect(unavailable.subtitleUri, isNull);
        expect(unavailable.subtitleRejected, isTrue);
        await unavailable.session?.close();
      },
    );
  });
}

PinnedPublicWebProxyUpstream _fakeUpstream(WebProxyHopFetcher fetcher) =>
    PinnedPublicWebProxyUpstream(
      targetValidator: (_) async {},
      hopFetcher: fetcher,
    );

WebProxyUpstreamResponse _textResponse(
  WebProxyUpstreamRequest request,
  String text,
) => _response(
  request,
  contentType: 'application/vnd.apple.mpegurl',
  bytes: utf8.encode(text),
);

WebProxyUpstreamResponse _response(
  WebProxyUpstreamRequest request, {
  int status = HttpStatus.ok,
  String contentType = '',
  Map<String, List<String>> headers = const {},
  List<int> bytes = const [],
}) {
  final merged = <String, List<String>>{
    for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    if (contentType.isNotEmpty) HttpHeaders.contentTypeHeader: [contentType],
    if (!headers.keys.any(
      (name) => name.toLowerCase() == HttpHeaders.contentLengthHeader,
    ))
      HttpHeaders.contentLengthHeader: ['${bytes.length}'],
  };
  return WebProxyUpstreamResponse(
    statusCode: status,
    uri: request.uri,
    requestHeaders: request.headers,
    headers: merged,
    body: Stream.value(bytes),
  );
}

Future<_LocalResponse> _localRequest(
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return _LocalResponse(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

class _LocalResponse {
  const _LocalResponse(this.status, this.body);

  final int status;
  final List<int> body;
}
