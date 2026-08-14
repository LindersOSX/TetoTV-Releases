import 'dart:async';

import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

const defaultReleaseSourceDeadline = Duration(seconds: 20);

class ReleaseSourceFailure {
  const ReleaseSourceFailure({required this.sourceId, required this.message});

  final String sourceId;
  final String message;
}

class ReleaseSearchProgress {
  const ReleaseSearchProgress({
    this.candidates = const [],
    this.failures = const [],
    this.completedSources = 0,
    this.totalSources = 0,
    this.pendingSourceIds = const [],
  });

  final List<ReleaseCandidate> candidates;
  final List<ReleaseSourceFailure> failures;
  final int completedSources;
  final int totalSources;
  final List<String> pendingSourceIds;

  bool get isComplete => completedSources >= totalSources;
}

class CompositeReleaseSource implements ReleaseSource {
  const CompositeReleaseSource(this.sources);

  final List<ReleaseSource> sources;

  @override
  String get id => 'composite';

  Stream<ReleaseSearchProgress> searchIncrementally(
    EpisodeReference episode, {
    Duration deadline = defaultReleaseSourceDeadline,
  }) => searchReleaseSourcesIncrementally(sources, episode, deadline: deadline);

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async {
    var result = const <ReleaseCandidate>[];
    await for (final progress in searchIncrementally(episode)) {
      result = progress.candidates;
    }
    return result;
  }
}

/// Searches every release source concurrently and emits a new snapshot as each
/// source completes. A stalled resolver therefore cannot hide results already
/// returned by another resolver.
Stream<ReleaseSearchProgress> searchReleaseSourcesIncrementally(
  List<ReleaseSource> sources,
  EpisodeReference episode, {
  Duration deadline = defaultReleaseSourceDeadline,
}) async* {
  final available = List<ReleaseSource>.unmodifiable(sources);
  if (available.isEmpty) {
    yield const ReleaseSearchProgress();
    return;
  }

  final pending = <int, Future<_IndexedReleaseSourceOutcome>>{
    for (var index = 0; index < available.length; index++)
      index: _searchReleaseSource(
        available[index],
        episode,
        deadline,
      ).then((outcome) => (index: index, outcome: outcome)),
  };
  final outcomes = <_ReleaseSourceOutcome>[];
  yield ReleaseSearchProgress(
    totalSources: available.length,
    pendingSourceIds: _pendingReleaseSourceIds(pending.keys, available),
  );

  while (pending.isNotEmpty) {
    final completed = await Future.any(pending.values);
    pending.remove(completed.index);
    final outcome = completed.outcome;
    outcomes.add(outcome);
    final candidates = mergeReleaseCandidates(
      outcomes.expand((item) => item.candidates),
    );
    final failures = outcomes
        .where((item) => item.failure != null)
        .map((item) => item.failure!)
        .toList(growable: false);
    yield ReleaseSearchProgress(
      candidates: candidates,
      failures: failures,
      completedSources: outcomes.length,
      totalSources: available.length,
      pendingSourceIds: _pendingReleaseSourceIds(pending.keys, available),
    );
  }
}

typedef _IndexedReleaseSourceOutcome = ({
  int index,
  _ReleaseSourceOutcome outcome,
});

List<String> _pendingReleaseSourceIds(
  Iterable<int> indexes,
  List<ReleaseSource> sources,
) => indexes.map((index) => sources[index].id).toList(growable: false);

Future<_ReleaseSourceOutcome> _searchReleaseSource(
  ReleaseSource source,
  EpisodeReference episode,
  Duration deadline,
) async {
  try {
    final candidates = await source.search(episode).timeout(deadline);
    return _ReleaseSourceOutcome(sourceId: source.id, candidates: candidates);
  } catch (error) {
    final message = error is TimeoutException
        ? 'Timed out after ${deadline.inSeconds} seconds.'
        : _shortReleaseError(error);
    return _ReleaseSourceOutcome(
      sourceId: source.id,
      failure: ReleaseSourceFailure(sourceId: source.id, message: message),
    );
  }
}

List<ReleaseCandidate> mergeReleaseCandidates(
  Iterable<ReleaseCandidate> candidates,
) {
  final unique = <String, ReleaseCandidate>{};
  for (final candidate in candidates) {
    final hash = candidate.infoHash.toLowerCase();
    final existing = unique[hash];
    if (existing == null ||
        candidate.seeders > existing.seeders ||
        (candidate.provider != null && existing.provider == null)) {
      unique[hash] = candidate;
    }
  }

  final result = unique.values.toList();
  result.sort((a, b) {
    final resolution = _resolutionScore(
      b.quality,
    ).compareTo(_resolutionScore(a.quality));
    if (resolution != 0) return resolution;
    final codec = _codecScore(b.codec).compareTo(_codecScore(a.codec));
    if (codec != 0) return codec;
    return b.seeders.compareTo(a.seeders);
  });
  return result;
}

int _resolutionScore(String? quality) {
  if (quality == null) return 0;
  final value = quality.toLowerCase();
  if (value.contains('4k') || value.contains('2160')) return 4;
  if (value.contains('1080')) return 3;
  if (value.contains('720')) return 2;
  if (value.contains('480')) return 1;
  return 0;
}

int _codecScore(String? codec) {
  if (codec == null) return 0;
  final value = codec.toLowerCase();
  if (value.contains('hevc') ||
      value.contains('265') ||
      value.contains('av1')) {
    return 2;
  }
  if (value.contains('264') || value.contains('avc')) return 1;
  return 0;
}

String _shortReleaseError(Object error) {
  final value = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return value.length > 160 ? '${value.substring(0, 160)}…' : value;
}

class _ReleaseSourceOutcome {
  const _ReleaseSourceOutcome({
    required this.sourceId,
    this.candidates = const [],
    this.failure,
  });

  final String sourceId;
  final List<ReleaseCandidate> candidates;
  final ReleaseSourceFailure? failure;
}
