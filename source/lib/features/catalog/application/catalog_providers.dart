import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final catalogClientProvider = Provider<AniListCatalogClient>(
  (_) => AniListCatalogClient(),
);

final trendingAnimeProvider = FutureProvider<List<AnimeSummary>>(
  (ref) => ref.watch(catalogClientProvider).trending(),
);

final seasonalAnimeProvider = FutureProvider<List<AnimeSummary>>(
  (ref) => ref.watch(catalogClientProvider).seasonal(),
);

final animeDetailsProvider = FutureProvider.family<AnimeSummary, int>(
  (ref, id) => ref.watch(catalogClientProvider).details(id),
);

final franchiseProvider = FutureProvider.family<List<AnimeSummary>, int>(
  (ref, id) => ref.watch(catalogClientProvider).franchise(id),
);

final studioAnimeProvider = FutureProvider.family<List<AnimeSummary>, int>(
  (ref, id) => ref.watch(catalogClientProvider).studioAnime(id),
);

final staffAnimeProvider = FutureProvider.family<List<AnimeSummary>, int>(
  (ref, id) => ref.watch(catalogClientProvider).staffAnime(id),
);

final airingWeekProvider = FutureProvider<List<AiringScheduleEntry>>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  return ref
      .watch(catalogClientProvider)
      .airingSchedule(from: from, to: from.add(const Duration(days: 7)));
});

/// Returns search results for [query].
///
/// Invalidate this provider to trigger a fresh network request.
final searchAnimeProvider = FutureProvider.family<List<AnimeSummary>, String>((
  ref,
  query,
) {
  final trimmed = query.trim();
  if (trimmed.length < 2) return Future.value(const <AnimeSummary>[]);
  return ref.watch(catalogClientProvider).search(trimmed);
});
