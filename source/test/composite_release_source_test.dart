import 'dart:async';

import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const episode = EpisodeReference(
    anilistMediaId: 1,
    title: 'Example',
    episode: 1,
  );

  test(
    'emits a fast release while another resolver is still pending',
    () async {
      final slow = Completer<List<ReleaseCandidate>>();
      final source = CompositeReleaseSource([
        _FakeReleaseSource('fast', () async => const [_release]),
        _FakeReleaseSource('slow', () => slow.future),
      ]);

      final iterator = StreamIterator(source.searchIncrementally(episode));
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.completedSources, 0);
      expect(iterator.current.pendingSourceIds, containsAll(['fast', 'slow']));

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.candidates, const [_release]);
      expect(iterator.current.completedSources, 1);
      expect(iterator.current.pendingSourceIds, ['slow']);

      slow.complete(const []);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.isComplete, isTrue);
      await iterator.cancel();
    },
  );

  test('a source deadline becomes an isolated failure', () async {
    final progress = await searchReleaseSourcesIncrementally(
      [
        _FakeReleaseSource(
          'stalled',
          () => Completer<List<ReleaseCandidate>>().future,
        ),
      ],
      episode,
      deadline: const Duration(milliseconds: 10),
    ).last;

    expect(progress.isComplete, isTrue);
    expect(progress.candidates, isEmpty);
    expect(progress.failures, hasLength(1));
    expect(progress.failures.single.sourceId, 'stalled');
    expect(progress.failures.single.message, contains('Timed out'));
  });
}

const _release = ReleaseCandidate(
  infoHash: '0123456789abcdef0123456789abcdef01234567',
  magnetUri: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
  releaseName: 'Fast release',
  seeders: 12,
  sourceId: 'fast',
  quality: '1080p',
);

class _FakeReleaseSource implements ReleaseSource {
  const _FakeReleaseSource(this.id, this.callback);

  @override
  final String id;
  final Future<List<ReleaseCandidate>> Function() callback;

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) => callback();
}
