import 'dart:async';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed provider does not hide another provider result', () async {
    const episode = EpisodeReference(
      anilistMediaId: 1,
      title: 'Test',
      episode: 2,
    );
    final result = await aggregateWebStreamingProviders([
      _FakeProvider('broken', 'Broken', () => throw StateError('offline')),
      _FakeProvider(
        'working',
        'Working',
        () async => [
          WebStreamResult(
            providerId: 'working',
            providerName: 'Working',
            title: '1080p',
            uri: Uri.parse('https://cdn.example.com/video.m3u8'),
          ),
        ],
      ),
    ], episode);

    expect(result.streams, hasLength(1));
    expect(result.streams.single.providerName, 'Working');
    expect(result.failures, hasLength(1));
    expect(result.failures.single.providerName, 'Broken');
  });

  test('duplicate stream URLs are collapsed across providers', () async {
    final stream = WebStreamResult(
      providerId: 'one',
      providerName: 'One',
      title: 'Auto',
      uri: Uri.parse('https://cdn.example.com/video.m3u8'),
    );
    final result = await aggregateWebStreamingProviders([
      _FakeProvider('one', 'One', () async => [stream]),
      _FakeProvider('two', 'Two', () async => [stream]),
    ], const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1));

    expect(result.streams, hasLength(1));
  });

  test('emits a working provider before a slower provider completes', () async {
    final slow = Completer<List<WebStreamResult>>();
    final progress = aggregateWebStreamingProvidersIncrementally([
      _FakeProvider('slow', 'Slow', () => slow.future),
      _FakeProvider(
        'fast',
        'Fast',
        () async => [
          WebStreamResult(
            providerId: 'fast',
            providerName: 'Fast',
            title: '1080p',
            uri: Uri.parse('https://cdn.example.com/fast.m3u8'),
          ),
        ],
      ),
    ], const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1));
    final iterator = StreamIterator(progress);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.completedProviders, 0);
    expect(
      iterator.current.pendingProviderNames,
      containsAll(['Slow', 'Fast']),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.aggregation.streams.single.providerName, 'Fast');
    expect(iterator.current.pendingProviderNames, ['Slow']);

    slow.complete(const []);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.isComplete, isTrue);
    await iterator.cancel();
  });

  test('times out a stalled provider without losing a valid result', () async {
    final result = await aggregateWebStreamingProviders(
      [
        _FakeProvider(
          'stalled',
          'Stalled',
          () => Completer<List<WebStreamResult>>().future,
        ),
        _FakeProvider(
          'working',
          'Working',
          () async => [
            WebStreamResult(
              providerId: 'working',
              providerName: 'Working',
              title: '720p',
              uri: Uri.parse('https://cdn.example.com/working.m3u8'),
            ),
          ],
        ),
      ],
      const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1),
      deadline: const Duration(milliseconds: 10),
    );

    expect(result.streams.single.providerName, 'Working');
    expect(result.failures.single.providerName, 'Stalled');
    expect(result.failures.single.message, contains('Timed out'));
  });

  test('never runs more providers than the configured worker limit', () async {
    var active = 0;
    var maximumActive = 0;
    final providers = [
      for (var index = 0; index < 7; index++)
        _FakeProvider('provider-$index', 'Provider $index', () async {
          active++;
          if (active > maximumActive) maximumActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return const [];
        }),
    ];

    await aggregateWebStreamingProviders(
      providers,
      const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1),
      maxConcurrentProviders: 2,
    );

    expect(maximumActive, 2);
  });

  test(
    'cancelling discovery stops active work and never starts queued jobs',
    () async {
      final activeStarted = Completer<void>();
      final activeCancelled = Completer<void>();
      var queuedStarts = 0;
      var recordedFailures = 0;
      final progress = aggregateWebStreamingProvidersIncrementally(
        [
          _CancellableProvider(
            'active',
            'Active',
            onStarted: activeStarted.complete,
            onCancelled: activeCancelled.complete,
          ),
          _FakeProvider('queued-1', 'Queued 1', () async {
            queuedStarts++;
            return const [];
          }),
          _FakeProvider('queued-2', 'Queued 2', () async {
            queuedStarts++;
            return const [];
          }),
        ],
        const EpisodeReference(anilistMediaId: 1, title: 'Test', episode: 1),
        deadline: const Duration(minutes: 1),
        maxConcurrentProviders: 1,
        onFailure: (_, _, _) => recordedFailures++,
      );
      final subscription = progress.listen((_) {});

      await activeStarted.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await activeCancelled.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(queuedStarts, 0);
      expect(
        recordedFailures,
        0,
        reason: 'cancellation is not a provider failure',
      );
    },
  );

  test('healthy providers are queued ahead of repeatedly failing ones', () {
    final addons = [
      _installedAddon('never-used'),
      _installedAddon('failing'),
      _installedAddon('successful'),
    ];
    final ordered = orderInstalledProvidersByHealth(addons, {
      'failing': const ProviderHealth(
        providerId: 'failing',
        consecutiveFailures: 3,
      ),
      'successful': ProviderHealth(
        providerId: 'successful',
        lastSuccessAt: DateTime.utc(2026, 8, 1),
      ),
    });

    expect(ordered.map((addon) => addon.manifest.id), [
      'successful',
      'never-used',
      'failing',
    ]);
  });

  test('resolver and player share one episode discovery session', () async {
    final release = Completer<void>();
    final aggregator = _CountingSharedAggregator(release.future);
    const episode = EpisodeReference(
      anilistMediaId: 77,
      title: 'Shared Search',
      episode: 4,
    );
    final resolver = StreamIterator(
      aggregator.watchSearchIncrementally(episode),
    );
    expect(await resolver.moveNext(), isTrue);
    expect(aggregator.searchCalls, 1);

    final player = StreamIterator(aggregator.watchSearchIncrementally(episode));
    expect(await player.moveNext(), isTrue);
    expect(aggregator.searchCalls, 1);
    expect(player.current.pendingProviderNames, ['Shared provider']);

    release.complete();
    expect(await resolver.moveNext(), isTrue);
    expect(await player.moveNext(), isTrue);
    expect(resolver.current.isComplete, isTrue);
    expect(player.current.isComplete, isTrue);
    await resolver.cancel();
    await player.cancel();
  });

  test(
    'shared discovery survives route handoff then cancels when abandoned',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<WebStreamSearchProgress>(
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
      addTearDown(source.close);
      final aggregator = _CancellableSharedAggregator(source.stream);
      const episode = EpisodeReference(
        anilistMediaId: 78,
        title: 'Graceful Handoff',
        episode: 2,
      );
      final resolver = StreamIterator(
        aggregator.watchSearchIncrementally(episode),
      );
      final firstProgress = resolver.moveNext();
      source.add(
        const WebStreamSearchProgress(
          totalProviders: 1,
          pendingProviderNames: ['Slow provider'],
        ),
      );
      expect(await firstProgress, isTrue);
      await resolver.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final player = StreamIterator(
        aggregator.watchSearchIncrementally(episode),
      );
      expect(await player.moveNext(), isTrue);
      expect(aggregator.searchCalls, 1);
      expect(cancelled.isCompleted, isFalse);

      await player.cancel();
      await cancelled.future.timeout(const Duration(seconds: 1));
    },
  );
}

class _CountingSharedAggregator extends WebStreamAggregator {
  _CountingSharedAggregator(this.release)
    : super(AddonStore(TetoTvDatabase.instance));

  final Future<void> release;
  int searchCalls = 0;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    searchCalls++;
    yield const WebStreamSearchProgress(
      totalProviders: 1,
      pendingProviderNames: ['Shared provider'],
    );
    await release;
    yield const WebStreamSearchProgress(
      completedProviders: 1,
      totalProviders: 1,
    );
  }
}

class _CancellableSharedAggregator extends WebStreamAggregator {
  _CancellableSharedAggregator(this.source)
    : super(
        AddonStore(TetoTvDatabase.instance),
        sharedSessionGrace: const Duration(milliseconds: 50),
      );

  final Stream<WebStreamSearchProgress> source;
  int searchCalls = 0;

  @override
  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) {
    searchCalls++;
    return source;
  }
}

InstalledStreamingAddon _installedAddon(String id) {
  final manifest = MarketplaceAddon.tryParse({
    'id': id,
    'name': id,
    'manifestURI': 'https://example.com/$id/manifest.json',
    'payloadURI': 'https://example.com/$id/provider.js',
    'type': 'onlinestream-provider',
    'language': 'javascript',
  }, repositoryUrl: 'https://example.com/marketplace.json')!;
  return InstalledStreamingAddon(
    manifest: manifest,
    payload: 'class Provider {}',
    enabled: true,
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeProvider implements WebStreamingProvider {
  const _FakeProvider(this.id, this.name, this.callback);

  @override
  final String id;
  @override
  final String name;
  final Future<List<WebStreamResult>> Function() callback;

  @override
  Future<List<WebStreamResult>> streams(
    EpisodeReference episode, {
    WebProviderCancellation? cancellation,
  }) => callback();
}

class _CancellableProvider implements WebStreamingProvider {
  const _CancellableProvider(
    this.id,
    this.name, {
    required this.onStarted,
    required this.onCancelled,
  });

  @override
  final String id;
  @override
  final String name;
  final void Function() onStarted;
  final void Function() onCancelled;

  @override
  Future<List<WebStreamResult>> streams(
    EpisodeReference episode, {
    WebProviderCancellation? cancellation,
  }) {
    onStarted();
    cancellation!.addListener(onCancelled);
    return Completer<List<WebStreamResult>>().future;
  }
}
