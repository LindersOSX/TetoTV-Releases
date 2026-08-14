import 'dart:isolate';

import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'packaged QuickJS addon runtime resolves a typed stream',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'fixture-provider',
        'name': 'Fixture Provider',
        'description': 'Packaged runtime test provider',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
            async search(input) {
              console.debug('fixture search', input.query);
              return [{id: 'show', title: input.query, subOrDub: 'sub'}];
            }
            async findEpisodes(id) { return [{id: 'episode', number: 3, url: 'episode'}]; }
            async findEpisodeServer(episode, server) {
              return {server, headers: {Referer: 'https://example.com/'}, videoSources: [
                {url: 'https://example.com/episode-3.m3u8', quality: '1080p', subtitles: [
                  {url: 'https://example.com/episode-3-en.vtt', language: 'English'}
                ]}
              ]};
            }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final results = await SeanimeJavascriptProvider(addon).streams(
        const EpisodeReference(
          anilistMediaId: 1,
          title: 'Fixture Anime',
          episode: 3,
        ),
      );

      expect(results, hasLength(1));
      expect(results.single.providerName, 'Fixture Provider');
      expect(results.single.uri.host, 'example.com');
      expect(results.single.quality, '1080p');
      expect(results.single.headers['Referer'], 'https://example.com/');
      expect(results.single.subtitleLanguage, 'English');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'packaged runtime matches Seanime selection and response contracts',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'compatibility-fixture-provider',
        'name': 'Compatibility Fixture Provider',
        'description': 'Hermetic Seanime API compatibility fixture',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
        'userConfig': {
          'requiredConfig': false,
          'fields': [
            {'name': 'baseUrl', 'default': 'https://example.com/catalog/'},
          ],
        },
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() {
              return {episodeServers: ['Fixture'], supportsDub: false};
            }

            async search(input) {
              if ($getUserPreference('baseUrl') !== 'https://example.com/catalog/') {
                throw new Error('user config defaults were not injected');
              }
              if (input.year !== 0 || input.media.status !== 'NOT_YET_RELEASED' ||
                  input.media.format !== 'TV' || input.media.episodeCount !== -1 ||
                  input.media.isAdult !== false || input.media.startDate !== undefined) {
                throw new Error('Seanime search/media defaults are incompatible');
              }
              const $ = LoadDoc(`
                <main>
                  <article class="card" data-id="matched">
                    <a class="title" href="shows/matched">${input.query}</a>
                  </article>
                  <article class="card" data-id="other">
                    <a class="title" href="shows/other">Another title</a>
                  </article>
                </main>
              `);
              if (typeof $('.card').length !== 'function' || $('.card').length() !== 2) {
                throw new Error('DocSelection.length must be a method');
              }
              const matches = [];
              $('.card').each((index, element) => {
                if (element.length() !== 1 || typeof element.find !== 'function') {
                  throw new Error('each callback must receive a DocSelection');
                }
                matches.push({
                  id: element.attr('data-id'),
                  title: element.find('.title').text(),
                  url: element.find('.title').attr('href'),
                  subOrDub: 'sub',
                });
              });
              return matches;
            }

            async findEpisodes() {
              const $ = LoadDoc(`
                <div class="stop">
                  <section class="pick">
                    <article><a class="episode" data-number="2" href="episode-2">Episode 2</a></article>
                  </section>
                </div>
              `);
              const selected = $('.episode');
              if (selected.parentsUntil('.stop').length() !== 2) {
                throw new Error('parentsUntil stop selector semantics are incompatible');
              }
              if (selected.parentsUntil('.pick', '.stop').length() !== 1) {
                throw new Error('parentsUntil filter/until semantics are incompatible');
              }
              const episodes = selected.map((index, element) => ({
                id: element.attr('href'),
                number: Number(element.attr('data-number')),
                url: element.attr('href'),
              }));
              if (!Array.isArray(episodes)) {
                throw new Error('DocSelection.map must return an array');
              }
              return episodes;
            }

            async findEpisodeServer(episode, server) {
              const response = __tetoCreateFetchResponse({
                status: 200,
                statusText: 'OK',
                method: 'POST',
                url: 'https://example.com/api/episode',
                headers: {'Content-Type': 'application/json'},
                rawHeaders: {'Content-Type': ['application/json']},
                cookies: {session: 'fixture-cookie'},
                redirected: true,
                contentType: 'application/json',
                contentLength: 11,
                body: '{"ok":true}',
              });
              if (typeof response.text() !== 'string' || response.text() !== '{"ok":true}') {
                throw new Error('FetchResponse.text must be synchronous');
              }
              if (!response.json().ok || response.cookies.session !== 'fixture-cookie') {
                throw new Error('FetchResponse JSON or cookies are incompatible');
              }
              if (response.headers['Content-Type'] !== 'application/json' ||
                  response.headers.get('content-type') !== 'application/json' ||
                  response.rawHeaders['Content-Type'][0] !== 'application/json' ||
                  response.method !== 'POST' || !response.redirected) {
                throw new Error('FetchResponse metadata is incompatible');
              }
              if (__tetoCreateFetchResponse({status: 200, body: '{'}).json() !== null) {
                throw new Error('invalid response JSON must match Seanime null behavior');
              }

              const stream = new URL('/videos/' + episode.id + '.m3u8', 'https://example.com/shows/title');
              stream.searchParams.set('token', 'fixture');
              return {
                server,
                videoSources: [{url: stream.toString(), quality: '720p'}],
              };
            }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final validatedTargets = <Uri>[];

      final results =
          await SeanimeJavascriptProvider(
            addon,
            validateResultTarget: (uri) async => validatedTargets.add(uri),
          ).streams(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Fixture Anime',
              episode: 2,
            ),
          );

      expect(results, hasLength(1));
      expect(
        results.single.uri.toString(),
        'https://example.com/videos/episode-2.m3u8?token=fixture',
      );
      expect(results.single.quality, '720p');
      expect(validatedTargets, [results.single.uri]);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'packaged runtime supports marketplace Buffer and CryptoJS base64 patterns',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'base64-compatibility-fixture-provider',
        'name': 'Base64 Compatibility Fixture Provider',
        'description': 'Hermetic marketplace core-global fixture',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() {
              return {episodeServers: ['Fixture'], supportsDub: false};
            }
            async search(input) {
              return [{id: 'show', title: input.query, subOrDub: 'sub'}];
            }
            async findEpisodes() {
              return [{id: 'episode', number: 1, url: 'episode'}];
            }
            async findEpisodeServer() {
              // AnimeUnity Mirror's exact fallback shape.
              const unity = Buffer.from('aHR0cHM6Ly9leGFtcGxlLmNvbS91bml0eS5tcDQ=', 'base64')
                .toString('utf-8');
              if (unity !== 'https://example.com/unity.mp4') {
                throw new Error('Buffer base64 compatibility failed');
              }

              // AnimeSaturn's exact CryptoJS byte iteration shape.
              const key = 'K';
              const encoded = 'Iz8/OzhxZGQuMyomOycuZSgkJmQ4Kj8+OSVlJjt/';
              const bytes = CryptoJS.enc.Base64.parse(encoded);
              let decoded = '';
              for (let index = 0; index < bytes.length; index++) {
                decoded += String.fromCharCode(bytes[index] ^ key.charCodeAt(index % key.length));
              }
              if (decoded !== 'https://example.com/saturn.mp4') {
                throw new Error('CryptoJS Base64 byte compatibility failed: ' + decoded);
              }
              // The decorated value must remain a usable CryptoJS WordArray.
              if (bytes.sigBytes !== bytes.length ||
                  CryptoJS.enc.Base64.stringify(bytes) !== encoded) {
                throw new Error('CryptoJS WordArray behavior was broken');
              }
              return {videoSources: [
                {url: unity, quality: '720p'},
                {url: decoded, quality: '1080p'},
              ]};
            }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final results =
          await SeanimeJavascriptProvider(
            addon,
            validateResultTarget: (_) async {},
          ).streams(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Base64 Fixture',
              episode: 1,
            ),
          );

      expect(results.map((result) => result.uri.toString()), [
        'https://example.com/unity.mp4',
        'https://example.com/saturn.mp4',
      ]);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'packaged QuickJS interrupts non-terminating scripts',
    (tester) async {
      final runtime = QuickJsRuntime2(timeout: 100);
      final stopwatch = Stopwatch()..start();
      try {
        final result = runtime.evaluate('for (;;) {}');
        stopwatch.stop();

        expect(result.isError, isTrue);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'The native interrupt handler must bound addon execution.',
        );
      } finally {
        runtime.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets(
    'stateful provider servers resolve serially in manifest order',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'stateful-server-fixture-provider',
        'name': 'Stateful Server Fixture Provider',
        'description': 'Detects overlapping server resolution',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            constructor() { this.headers = {}; }
            getSettings() {
              return {episodeServers: ['Alpha', 'Beta'], supportsDub: false};
            }
            async search(input) {
              return [{id: 'show', title: input.query, subOrDub: 'sub'}];
            }
            async findEpisodes() {
              return [{id: 'episode', number: 1, url: 'episode'}];
            }
            async findEpisodeServer(episode, server) {
              this.headers.Referer = 'https://' + server.toLowerCase() + '.example/';
              // Yield once. Concurrent calls on this Provider instance would
              // both observe Beta's mutated Referer after resuming.
              await Promise.resolve();
              return {
                server,
                headers: Object.assign({}, this.headers),
                videoSources: [{
                  url: 'https://example.com/' + server.toLowerCase() + '.mp4',
                  quality: '720p',
                }],
              };
            }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

      final results =
          await SeanimeJavascriptProvider(
            addon,
            validateResultTarget: (_) async {},
          ).streams(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Stateful Fixture',
              episode: 1,
            ),
          );

      expect(results.map((result) => result.title), [
        'Alpha / 720p',
        'Beta / 720p',
      ]);
      expect(results[0].headers['Referer'], 'https://alpha.example/');
      expect(results[1].headers['Referer'], 'https://beta.example/');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'AnimeUnity-style unawaited sleep paces work and remains cancellable',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'sleep-fixture-provider',
        'name': 'Sleep Fixture Provider',
        'description': 'Exercises the Seanime sleep compatibility bridge',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      InstalledStreamingAddon fixture(String sleepCall) =>
          InstalledStreamingAddon(
            manifest: manifest,
            payload:
                '''
              class Provider {
                getSettings() {
                  return {episodeServers: ['Fixture'], supportsDub: false};
                }
                async search(input) {
                  this.sleepStartedAt = Date.now();
                  \$sleep($sleepCall);
                  return [{id: 'show', title: input.query, subOrDub: 'sub'}];
                }
                async findEpisodes() {
                  if (Date.now() - this.sleepStartedAt < 140) {
                    throw new Error('unawaited sleep did not pace provider work');
                  }
                  return [{id: 'episode', number: 1, url: 'episode'}];
                }
                async findEpisodeServer() {
                  return {videoSources: [{
                    url: 'https://example.com/sleep-fixture.mp4',
                    quality: '720p',
                  }]};
                }
              }
            ''',
            enabled: true,
            installedAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          );

      final results =
          await SeanimeJavascriptProvider(
            fixture('180'),
            validateResultTarget: (_) async {},
          ).streams(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Sleep Fixture',
              episode: 1,
            ),
          );
      expect(results, hasLength(1));

      final cancellation = WebProviderCancellation();
      final stopwatch = Stopwatch()..start();
      final cancelledSearch =
          SeanimeJavascriptProvider(
            fixture('1000'),
            validateResultTarget: (_) async {},
          ).streams(
            const EpisodeReference(
              anilistMediaId: 1,
              title: 'Cancelled Sleep Fixture',
              episode: 1,
            ),
            cancellation: cancellation,
          );
      await Future<void>.delayed(const Duration(milliseconds: 75));
      cancellation.cancel();
      await expectLater(
        cancelledSearch,
        throwsA(isA<WebProviderSearchCancelled>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'packaged QuickJS reports recursive stack overflow without killing Dart',
    (tester) async {
      // Third-party providers run on Dart worker isolates. Those threads may
      // have much less native stack available than the main thread, so the
      // bridge must clamp QuickJS's logical stack budget to the current native
      // stack before entering JS.
      for (var attempt = 0; attempt < 3; attempt++) {
        final outcome = await Isolate.run(() {
          final runtime = QuickJsRuntime2(
            stackSize: 1024 * 1024,
            timeout: 1000,
          );
          try {
            final result = runtime.evaluate('''
              function recursiveProviderCall() {
                return recursiveProviderCall();
              }
              recursiveProviderCall();
            ''');
            return (isError: result.isError, message: result.stringResult);
          } finally {
            runtime.dispose();
          }
        });
        expect(outcome.isError, isTrue);
        expect(outcome.message.toLowerCase(), contains('stack overflow'));
      }
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'repeated provider cancellation disposes native runtimes gracefully',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'cancellation-fixture-provider',
        'name': 'Cancellation Fixture Provider',
        'description': 'Waits forever until the host cancels it',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final addon = InstalledStreamingAddon(
        manifest: manifest,
        payload: r'''
          class Provider {
            getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
            async search() { return await new Promise(() => {}); }
          }
        ''',
        enabled: true,
        installedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final provider = SeanimeJavascriptProvider(addon);

      for (var attempt = 0; attempt < 5; attempt++) {
        final cancellation = WebProviderCancellation();
        final search = provider.streams(
          const EpisodeReference(
            anilistMediaId: 1,
            title: 'Cancellation Fixture',
            episode: 1,
          ),
          cancellation: cancellation,
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        cancellation.cancel();
        await expectLater(
          search.timeout(const Duration(seconds: 3)),
          throwsA(isA<WebProviderSearchCancelled>()),
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'cancelling synchronous provider spin waits for native unwind',
    (tester) async {
      final manifest = MarketplaceAddon.tryParse({
        'id': 'spin-cancellation-fixture-provider',
        'name': 'Spin Cancellation Fixture Provider',
        'description': 'Exercises native interruption during cancellation',
        'author': 'TetoTV',
        'manifestURI': 'https://example.com/manifest.json',
        'payloadURI': 'https://example.com/provider.js',
        'version': '1.0.0',
        'type': 'onlinestream-provider',
        'language': 'javascript',
        'lang': 'en',
      }, repositoryUrl: 'https://example.com/catalog.json')!;
      final provider = SeanimeJavascriptProvider(
        InstalledStreamingAddon(
          manifest: manifest,
          payload: r'''
            class Provider {
              getSettings() { return {episodeServers: ['Fixture'], supportsDub: false}; }
              async search() { for (;;) {} }
            }
          ''',
          enabled: true,
          installedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final cancellation = WebProviderCancellation();
      final stopwatch = Stopwatch()..start();
      final search = provider.streams(
        const EpisodeReference(
          anilistMediaId: 1,
          title: 'Spin Cancellation Fixture',
          episode: 1,
        ),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      cancellation.cancel();

      await expectLater(
        search.timeout(const Duration(seconds: 9)),
        throwsA(isA<WebProviderSearchCancelled>()),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 9)));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
