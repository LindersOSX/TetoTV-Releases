import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:dio/dio.dart';

/// Read-only catalog fallback used when AniList temporarily suspends its API.
///
/// Kitsu results are only exposed when they include an AniList mapping. This
/// keeps the rest of TetoTV on real AniList and MyAnimeList identifiers for
/// details, tracking, playback history, and release resolution.
class KitsuCatalogFallback {
  KitsuCatalogFallback({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://kitsu.io/api/edge/',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/vnd.api+json'},
            ),
          );

  static const _pageSize = 20;
  static const _blockedCategoryTerms = <String>{
    'adult',
    'boys love',
    'ecchi',
    'erotica',
    'explicit sex',
    'girls love',
    'hentai',
    'lolicon',
    'nudity',
    'pornography',
    'sexual content',
    'shotacon',
    'yaoi',
    'yuri',
  };

  final Dio _dio;

  Future<List<AnimeSummary>> search(String term, {int page = 1}) async {
    final body = await _get(
      'anime',
      queryParameters: {
        'filter[text]': term,
        'page[limit]': _pageSize,
        'page[offset]': (page - 1).clamp(0, 9999) * _pageSize,
        'include': 'mappings,categories',
      },
    );
    final included = _includedResources(body);
    final unique = <int, AnimeSummary>{};
    for (final resource in _resourceList(body['data'])) {
      final anime = _mapAnime(resource, included);
      if (anime != null) unique.putIfAbsent(anime.id, () => anime);
    }
    return List.unmodifiable(unique.values);
  }

  Future<AnimeSummary> detailsForAniListId(int anilistId) async {
    if (anilistId <= 0) throw StateError('Invalid AniList media ID.');
    final lookup = await _get(
      'mappings',
      queryParameters: {
        'filter[externalSite]': 'anilist/anime',
        'filter[externalId]': '$anilistId',
        'include': 'item',
      },
    );
    final mappings = _resourceList(lookup['data']);
    if (mappings.isEmpty) {
      throw StateError('This anime is not available in the backup catalog.');
    }
    final item = _map(mappings.first['relationships'])?['item'];
    final itemData = _map(_map(item)?['data']);
    final kitsuId = itemData?['id']?.toString();
    if (kitsuId == null || kitsuId.isEmpty) {
      throw StateError('The backup catalog returned an incomplete mapping.');
    }

    final body = await _get(
      'anime/$kitsuId',
      queryParameters: const {'include': 'mappings,categories'},
    );
    final resource = _map(body['data']);
    final anime = resource == null
        ? null
        : _mapAnime(
            resource,
            _includedResources(body),
            knownAniListId: anilistId,
          );
    if (anime == null) {
      throw StateError('The backup catalog returned incomplete anime data.');
    }
    return anime;
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final query = queryParameters ?? const <String, dynamic>{};
    final cacheKey =
        'kitsu:${Uri(path: path, queryParameters: query.map((key, value) => MapEntry(key, '$value')))}';
    try {
      final cached = await TetoTvDatabase.instance.cachedJson(cacheKey);
      if (cached != null) return cached;
    } catch (_) {
      // Tests and unsupported platforms may not provide sqflite.
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );
      final body = response.data ?? const <String, dynamic>{};
      try {
        await TetoTvDatabase.instance.cacheJson(cacheKey, body);
      } catch (_) {
        // Catalog caching is a best-effort performance optimization.
      }
      return body;
    } catch (_) {
      try {
        final stale = await TetoTvDatabase.instance.cachedJson(
          cacheKey,
          allowExpired: true,
        );
        if (stale != null) return stale;
      } catch (_) {
        // Preserve the original network error below.
      }
      rethrow;
    }
  }

  AnimeSummary? _mapAnime(
    Map<String, dynamic> resource,
    Map<String, Map<String, dynamic>> included, {
    int? knownAniListId,
  }) {
    if (resource['type'] != 'anime') return null;
    final attributes = _map(resource['attributes']);
    if (attributes == null) return null;
    final mappings = _related(resource, 'mappings', included);
    final anilistId = knownAniListId ?? _externalId(mappings, 'anilist/anime');
    if (anilistId == null || anilistId <= 0) return null;
    final malId = _externalId(mappings, 'myanimelist/anime');

    final titles = _map(attributes['titles']);
    final english = _firstText([titles?['en'], attributes['canonicalTitle']]);
    final romaji = _firstText([titles?['en_jp'], attributes['canonicalTitle']]);
    final title = _firstText([english, romaji, attributes['canonicalTitle']]);
    if (title == null) return null;

    final startDate = DateTime.tryParse(
      attributes['startDate']?.toString() ?? '',
    );
    final rating = double.tryParse(
      attributes['averageRating']?.toString() ?? '',
    );
    final categories = _related(resource, 'categories', included)
        .map((item) => _map(item['attributes'])?['title']?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (_isBlockedContent(attributes, categories)) return null;
    final synonyms = <String>{
      for (final value in _stringList(attributes['abbreviatedTitles'])) value,
      ?english,
      ?romaji,
    }..remove(title);

    return AnimeSummary(
      id: anilistId,
      idMal: malId,
      title: title,
      titleEnglish: english,
      titleRomaji: romaji,
      description: _plainText(
        attributes['synopsis']?.toString() ??
            attributes['description']?.toString() ??
            '',
      ),
      episodes: _integer(attributes['episodeCount']),
      score: rating == null ? null : rating / 10,
      coverImageUrl: _imageUrl(attributes['posterImage']),
      bannerImageUrl: _imageUrl(attributes['coverImage']),
      genres: categories,
      synonyms: List.unmodifiable(synonyms),
      format: attributes['subtype']?.toString().toUpperCase(),
      status: _status(attributes['status']?.toString()),
      season: _season(startDate),
      seasonYear: startDate?.year,
      durationMinutes: _integer(attributes['episodeLength']),
    );
  }

  Map<String, Map<String, dynamic>> _includedResources(
    Map<String, dynamic> body,
  ) {
    return {
      for (final resource in _resourceList(body['included']))
        '${resource['type']}:${resource['id']}': resource,
    };
  }

  List<Map<String, dynamic>> _related(
    Map<String, dynamic> resource,
    String relationship,
    Map<String, Map<String, dynamic>> included,
  ) {
    final relationships = _map(resource['relationships']);
    final relation = _map(relationships?[relationship]);
    final references = _resourceList(relation?['data']);
    return references
        .map((item) => included['${item['type']}:${item['id']}'])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  int? _externalId(Iterable<Map<String, dynamic>> mappings, String site) {
    for (final mapping in mappings) {
      final attributes = _map(mapping['attributes']);
      if (attributes?['externalSite'] == site) {
        return int.tryParse(attributes?['externalId']?.toString() ?? '');
      }
    }
    return null;
  }

  bool _isBlockedContent(
    Map<String, dynamic> attributes,
    Iterable<String> categories,
  ) {
    if (attributes['nsfw'] == true ||
        attributes['ageRating']?.toString().toUpperCase() == 'R18') {
      return true;
    }
    final ratingGuide = _normalizeSafetyText(
      attributes['ageRatingGuide']?.toString() ?? '',
    );
    if (ratingGuide.contains('adult') ||
        ratingGuide.contains('explicit') ||
        ratingGuide.contains('18 only')) {
      return true;
    }
    return categories
        .map(_normalizeSafetyText)
        .any(_blockedCategoryTerms.contains);
  }

  String _normalizeSafetyText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String? _imageUrl(dynamic value) {
    final image = _map(value);
    return _firstText([image?['large'], image?['original'], image?['medium']]);
  }

  String? _firstText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  int? _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  List<String> _stringList(dynamic value) => value is List
      ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
      : const [];

  String? _status(String? value) => switch (value?.toLowerCase()) {
    'current' => 'RELEASING',
    'finished' => 'FINISHED',
    'tba' || 'unreleased' || 'upcoming' => 'NOT_YET_RELEASED',
    final status? when status.isNotEmpty => status.toUpperCase(),
    _ => null,
  };

  String? _season(DateTime? value) {
    if (value == null) return null;
    return switch (value.month) {
      >= 1 && <= 3 => 'WINTER',
      >= 4 && <= 6 => 'SPRING',
      >= 7 && <= 9 => 'SUMMER',
      _ => 'FALL',
    };
  }

  Map<String, dynamic>? _map(dynamic value) => value is Map<String, dynamic>
      ? value
      : value is Map
      ? value.map((key, item) => MapEntry('$key', item))
      : null;

  List<Map<String, dynamic>> _resourceList(dynamic value) {
    if (value is Map) {
      final item = _map(value);
      return item == null ? const [] : [item];
    }
    if (value is! List) return const [];
    return value.map(_map).whereType<Map<String, dynamic>>().toList();
  }

  String _plainText(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
