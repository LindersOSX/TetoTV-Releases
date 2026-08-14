import 'dart:async';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const defaultWebProviderDeadline = Duration(seconds: 20);
const defaultMaxConcurrentWebProviders = 2;

final webStreamAggregatorProvider = Provider<WebStreamAggregator>(
  (ref) => WebStreamAggregator(ref.watch(addonStoreProvider)),
);

class WebStreamSearchProgress {
  const WebStreamSearchProgress({
    this.aggregation = const WebStreamAggregation(),
    this.completedProviders = 0,
    this.totalProviders = 0,
    this.pendingProviderNames = const [],
  });

  final WebStreamAggregation aggregation;
  final int completedProviders;
  final int totalProviders;
  final List<String> pendingProviderNames;

  bool get isComplete => completedProviders >= totalProviders;
}

class WebStreamAggregator {
  WebStreamAggregator(
    this._store, {
    this.providerDeadline = defaultWebProviderDeadline,
    this.maxConcurrentProviders = defaultMaxConcurrentWebProviders,
    this.sharedSessionGrace = const Duration(seconds: 2),
  });

  final AddonStore _store;
  final Duration providerDeadline;
  final int maxConcurrentProviders;
  final Duration sharedSessionGrace;
  final Map<String, _SharedWebSearchSession> _sharedSessions = {};

  /// Replays and shares one provider search per episode across resolver and
  /// player routes. A route replacement therefore transfers observation of
  /// the existing bounded worker pool instead of starting another QuickJS
  /// wave while the old route is winding down.
  Stream<WebStreamSearchProgress> watchSearchIncrementally(
    EpisodeReference episode, {
    bool refresh = false,
  }) {
    final key = _episodeSearchKey(episode);
    final existing = _sharedSessions[key];
    final expired =
        existing != null &&
        existing.isComplete &&
        DateTime.now().difference(existing.startedAt) >
            const Duration(minutes: 2);
    final shouldReplace =
        existing == null ||
        existing.wasAbandoned ||
        expired ||
        (refresh && existing.isComplete);
    final session = shouldReplace
        ? _startSharedSession(key, episode)
        : existing;
    return session.stream;
  }

  _SharedWebSearchSession _startSharedSession(
    String key,
    EpisodeReference episode,
  ) {
    final session = _SharedWebSearchSession(
      zeroListenerGrace: sharedSessionGrace,
    );
    _sharedSessions[key] = session;
    unawaited(
      session.run(searchIncrementally(episode)).whenComplete(_pruneSessions),
    );
    return session;
  }

  void _pruneSessions() {
    if (_sharedSessions.length <= 8) return;
    final completed =
        _sharedSessions.entries
            .where((entry) => entry.value.isComplete)
            .toList()
          ..sort(
            (left, right) =>
                left.value.startedAt.compareTo(right.value.startedAt),
          );
    for (final entry in completed) {
      if (_sharedSessions.length <= 8) break;
      _sharedSessions.remove(entry.key);
    }
  }

  Future<WebStreamAggregation> search(EpisodeReference episode) async {
    var result = const WebStreamAggregation();
    await for (final progress in searchIncrementally(episode)) {
      result = progress.aggregation;
    }
    return result;
  }

  Stream<WebStreamSearchProgress> searchIncrementally(
    EpisodeReference episode,
  ) async* {
    final health = await _store.providerHealth();
    final addons = orderInstalledProvidersByHealth(
      (await _store.installedAddons())
          .where(
            (addon) =>
                addon.enabled &&
                addon.manifest.isCompatible &&
                !(health[addon.manifest.id]?.isQuarantined ?? false),
          )
          .toList(growable: false),
      health,
    );
    final providers = addons.map(SeanimeJavascriptProvider.new).toList();
    yield* aggregateWebStreamingProvidersIncrementally(
      providers,
      episode,
      deadline: providerDeadline,
      maxConcurrentProviders: maxConcurrentProviders,
      onSuccess: (provider, streams) async {
        if (streams.isNotEmpty) {
          await _store.recordProviderSuccess(provider.id);
        }
      },
      onFailure: (provider, error, noMatch) async {
        if (noMatch) return;
        await _store.recordProviderFailure(provider.id, error);
        await _store.database.recordDiagnosticEvent(
          category: 'provider',
          message: '${provider.name}: $error',
        );
      },
    );
  }
}

String _episodeSearchKey(EpisodeReference episode) => [
  episode.anilistMediaId,
  episode.malMediaId ?? 0,
  episode.episode,
  episode.year ?? 0,
  episode.title.trim().toLowerCase(),
].join(':');

class _SharedWebSearchSession {
  _SharedWebSearchSession({required this.zeroListenerGrace});

  final startedAt = DateTime.now();
  final Duration zeroListenerGrace;
  final StreamController<WebStreamSearchProgress> _updates =
      StreamController<WebStreamSearchProgress>.broadcast(sync: true);
  WebStreamSearchProgress? _latest;
  StreamSubscription<WebStreamSearchProgress>? _sourceSubscription;
  Timer? _zeroListenerTimer;
  Completer<void>? _completion;
  int _listenerCount = 0;
  bool isComplete = false;
  bool wasAbandoned = false;

  Stream<WebStreamSearchProgress> get stream => Stream.multi((listener) {
    _listenerCount++;
    _zeroListenerTimer?.cancel();
    _zeroListenerTimer = null;
    final latest = _latest;
    if (latest != null) listener.add(latest);
    final subscription = _updates.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = () async {
      await subscription.cancel();
      if (_listenerCount > 0) _listenerCount--;
      _scheduleAbandonedCancellation();
    };
  });

  Future<void> run(Stream<WebStreamSearchProgress> source) {
    final completion = _completion = Completer<void>();
    _sourceSubscription = source.listen(
      (progress) {
        _latest = progress;
        if (!_updates.isClosed) _updates.add(progress);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_updates.isClosed) _updates.addError(error, stackTrace);
      },
      onDone: _finish,
    );
    _scheduleAbandonedCancellation();
    return completion.future;
  }

  void _scheduleAbandonedCancellation() {
    if (isComplete || _listenerCount != 0 || _sourceSubscription == null) {
      return;
    }
    _zeroListenerTimer?.cancel();
    _zeroListenerTimer = Timer(zeroListenerGrace, () async {
      if (isComplete || _listenerCount != 0) return;
      wasAbandoned = true;
      await _sourceSubscription?.cancel();
      await _finish();
    });
  }

  Future<void> _finish() async {
    if (isComplete) return;
    isComplete = true;
    _zeroListenerTimer?.cancel();
    _zeroListenerTimer = null;
    if (!_updates.isClosed) await _updates.close();
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
  }
}

List<InstalledStreamingAddon> orderInstalledProvidersByHealth(
  List<InstalledStreamingAddon> addons,
  Map<String, ProviderHealth> health,
) {
  final indexed = addons.indexed
      .map((item) => (index: item.$1, addon: item.$2))
      .toList();
  indexed.sort((left, right) {
    final leftHealth = health[left.addon.manifest.id];
    final rightHealth = health[right.addon.manifest.id];
    final bucket = _providerHealthBucket(
      leftHealth,
    ).compareTo(_providerHealthBucket(rightHealth));
    if (bucket != 0) return bucket;
    if (leftHealth?.lastSuccessAt != null &&
        rightHealth?.lastSuccessAt != null) {
      final recent = rightHealth!.lastSuccessAt!.compareTo(
        leftHealth!.lastSuccessAt!,
      );
      if (recent != 0) return recent;
    }
    final failures = (leftHealth?.consecutiveFailures ?? 0).compareTo(
      rightHealth?.consecutiveFailures ?? 0,
    );
    return failures != 0 ? failures : left.index.compareTo(right.index);
  });
  return indexed.map((item) => item.addon).toList(growable: false);
}

int _providerHealthBucket(ProviderHealth? health) {
  if (health?.lastSuccessAt != null && health!.consecutiveFailures == 0) {
    return 0;
  }
  if (health == null) return 1;
  if (health.consecutiveFailures == 0) return 2;
  return 3;
}

typedef WebProviderSuccessCallback =
    FutureOr<void> Function(
      WebStreamingProvider provider,
      List<WebStreamResult> streams,
    );
typedef WebProviderFailureCallback =
    FutureOr<void> Function(
      WebStreamingProvider provider,
      Object error,
      bool noMatch,
    );

/// Searches providers through a small worker pool and emits an accumulated
/// result whenever one finishes. Each provider has its own deadline, so one
/// abandoned or incompatible add-on cannot hold the entire stream picker open
/// or create an unbounded wave of QuickJS runtimes on low-memory TV devices.
Stream<WebStreamSearchProgress> aggregateWebStreamingProvidersIncrementally(
  List<WebStreamingProvider> providers,
  EpisodeReference episode, {
  Duration deadline = defaultWebProviderDeadline,
  int maxConcurrentProviders = defaultMaxConcurrentWebProviders,
  WebProviderSuccessCallback? onSuccess,
  WebProviderFailureCallback? onFailure,
}) {
  final available = List<WebStreamingProvider>.unmodifiable(providers);
  final cancellation = WebProviderCancellation();
  late final StreamController<WebStreamSearchProgress> controller;
  var started = false;

  Future<void> run() async {
    try {
      if (available.isEmpty) {
        if (!cancellation.isCancelled) {
          controller.add(const WebStreamSearchProgress());
        }
        return;
      }

      final concurrency = maxConcurrentProviders.clamp(1, available.length);
      final active = <int, Future<_IndexedWebProviderOutcome>>{};
      final completedIndexes = <int>{};
      var nextIndex = 0;

      void fillWorkers() {
        while (!cancellation.isCancelled &&
            active.length < concurrency &&
            nextIndex < available.length) {
          final index = nextIndex++;
          active[index] = _searchWebProvider(
            available[index],
            episode,
            deadline,
            cancellation: cancellation,
            onSuccess: onSuccess,
            onFailure: onFailure,
          ).then((outcome) => (index: index, outcome: outcome));
        }
      }

      fillWorkers();
      final outcomes = <_WebProviderOutcome>[];
      if (!cancellation.isCancelled) {
        controller.add(
          WebStreamSearchProgress(
            totalProviders: available.length,
            pendingProviderNames: _pendingWebProviderNames(
              completedIndexes,
              available,
            ),
          ),
        );
      }

      while (active.isNotEmpty && !cancellation.isCancelled) {
        final completed = await Future.any(active.values);
        if (cancellation.isCancelled) break;
        active.remove(completed.index);
        completedIndexes.add(completed.index);
        final outcome = completed.outcome;
        if (!outcome.cancelled) outcomes.add(outcome);
        fillWorkers();
        if (cancellation.isCancelled) break;
        controller.add(
          WebStreamSearchProgress(
            aggregation: mergeWebProviderOutcomes(
              outcomes
                  .map((item) => (streams: item.streams, failure: item.failure))
                  .toList(growable: false),
            ),
            completedProviders: outcomes.length,
            totalProviders: available.length,
            pendingProviderNames: _pendingWebProviderNames(
              completedIndexes,
              available,
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!cancellation.isCancelled && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  controller = StreamController<WebStreamSearchProgress>(
    sync: true,
    onListen: () {
      if (started) return;
      started = true;
      unawaited(run());
    },
    onCancel: cancellation.cancel,
  );
  return controller.stream;
}

typedef _IndexedWebProviderOutcome = ({int index, _WebProviderOutcome outcome});

List<String> _pendingWebProviderNames(
  Set<int> completedIndexes,
  List<WebStreamingProvider> providers,
) => [
  for (var index = 0; index < providers.length; index++)
    if (!completedIndexes.contains(index)) providers[index].name,
];

Future<_WebProviderOutcome> _searchWebProvider(
  WebStreamingProvider provider,
  EpisodeReference episode,
  Duration deadline, {
  required WebProviderCancellation cancellation,
  WebProviderSuccessCallback? onSuccess,
  WebProviderFailureCallback? onFailure,
}) async {
  try {
    cancellation.throwIfCancelled();
    final streams = await Future.any<List<WebStreamResult>>([
      provider.streams(episode, cancellation: cancellation),
      cancellation.whenCancelled.then<List<WebStreamResult>>(
        (_) => throw const WebProviderSearchCancelled(),
      ),
    ]).timeout(deadline);
    cancellation.throwIfCancelled();
    try {
      await onSuccess?.call(provider, streams);
    } catch (_) {
      // Health bookkeeping must not hide a provider's usable streams.
    }
    return _WebProviderOutcome(providerId: provider.id, streams: streams);
  } catch (error) {
    if (error is WebProviderSearchCancelled || cancellation.isCancelled) {
      return _WebProviderOutcome(providerId: provider.id, cancelled: true);
    }
    final noMatch = isSeanimeProviderNoMatch(error);
    try {
      await onFailure?.call(provider, error, noMatch);
    } catch (_) {
      // Diagnostics are best effort and must never block discovery.
    }
    return _WebProviderOutcome(
      providerId: provider.id,
      failure: WebProviderFailure(
        providerName: provider.name,
        message: noMatch
            ? 'No matching title or episode from this provider.'
            : error is TimeoutException
            ? 'Timed out after ${deadline.inSeconds} seconds.'
            : _shortMessage(error),
      ),
    );
  }
}

WebStreamAggregation mergeWebProviderOutcomes(
  List<({List<WebStreamResult> streams, WebProviderFailure? failure})> outcomes,
) {
  final unique = <String, WebStreamResult>{};
  final failures = <WebProviderFailure>[];
  for (final outcome in outcomes) {
    if (outcome.failure != null) failures.add(outcome.failure!);
    for (final stream in outcome.streams) {
      unique.putIfAbsent(stream.uri.toString(), () => stream);
    }
  }
  final streams = unique.values.toList()
    ..sort((a, b) {
      final provider = a.providerName.compareTo(b.providerName);
      return provider != 0 ? provider : a.title.compareTo(b.title);
    });
  return WebStreamAggregation(streams: streams, failures: failures);
}

Future<WebStreamAggregation> aggregateWebStreamingProviders(
  List<WebStreamingProvider> providers,
  EpisodeReference episode, {
  Duration deadline = defaultWebProviderDeadline,
  int maxConcurrentProviders = defaultMaxConcurrentWebProviders,
}) async {
  var result = const WebStreamAggregation();
  await for (final progress in aggregateWebStreamingProvidersIncrementally(
    providers,
    episode,
    deadline: deadline,
    maxConcurrentProviders: maxConcurrentProviders,
  )) {
    result = progress.aggregation;
  }
  return result;
}

String _shortMessage(Object error) {
  final value = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return value.length > 160 ? '${value.substring(0, 160)}…' : value;
}

class _WebProviderOutcome {
  const _WebProviderOutcome({
    required this.providerId,
    this.streams = const [],
    this.failure,
    this.cancelled = false,
  });

  final String providerId;
  final List<WebStreamResult> streams;
  final WebProviderFailure? failure;
  final bool cancelled;
}
