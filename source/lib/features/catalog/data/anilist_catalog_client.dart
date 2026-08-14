import 'dart:convert';

import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/data/kitsu_catalog_fallback.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:dio/dio.dart';

class AniListCatalogClient {
  AniListCatalogClient({Dio? dio, Dio? kitsuDio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://graphql.anilist.co',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ),
          ),
      _kitsu = KitsuCatalogFallback(dio: kitsuDio);

  final Dio _dio;
  final KitsuCatalogFallback _kitsu;

  Future<List<AnimeSummary>> trending({int page = 1}) async {
    const query = r'''
      query TrendingAnime($page: Int!) {
        Page(page: $page, perPage: 20) {
          media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {
            id
            idMal
            title { userPreferred english romaji }
            description(asHtml: false)
            episodes
            averageScore
            genres
            coverImage { extraLarge }
            bannerImage
            format
            status
            season
            seasonYear
            duration
            synonyms
            nextAiringEpisode { episode }
          }
        }
      }
    ''';

    return _mediaPage(query, {'page': page});
  }

  Future<List<AnimeSummary>> seasonal({DateTime? now, int page = 1}) async {
    final date = now ?? DateTime.now();
    final season = switch (date.month) {
      <= 3 => 'WINTER',
      <= 6 => 'SPRING',
      <= 9 => 'SUMMER',
      _ => 'FALL',
    };
    const query = r'''
      query SeasonalAnime(
        $page: Int!,
        $season: MediaSeason!,
        $year: Int!
      ) {
        Page(page: $page, perPage: 20) {
          media(
            type: ANIME,
            season: $season,
            seasonYear: $year,
            sort: POPULARITY_DESC,
            isAdult: false
          ) {
            id
            idMal
            title { userPreferred english romaji }
            description(asHtml: false)
            episodes
            averageScore
            genres
            coverImage { extraLarge }
            bannerImage
            format
            status
            season
            seasonYear
            duration
            synonyms
            nextAiringEpisode { episode }
          }
        }
      }
    ''';
    return _mediaPage(query, {
      'page': page,
      'season': season,
      'year': date.year,
    });
  }

  Future<List<AnimeSummary>> search(String term, {int page = 1}) async {
    const query = r'''
      query SearchAnime($page: Int!, $search: String!) {
        Page(page: $page, perPage: 20) {
          media(
            type: ANIME,
            search: $search,
            sort: SEARCH_MATCH,
            isAdult: false
          ) {
            id
            idMal
            title { userPreferred english romaji }
            description(asHtml: false)
            episodes
            averageScore
            genres
            coverImage { extraLarge }
            bannerImage
            format
            status
            season
            seasonYear
            duration
            synonyms
            nextAiringEpisode { episode }
          }
        }
      }
    ''';
    try {
      return await _mediaPage(query, {
        'page': page,
        'search': term,
      }, useStaleOnError: false);
    } catch (anilistError) {
      try {
        return await _kitsu.search(term, page: page);
      } catch (_) {
        throw StateError(
          'Anime search is temporarily unavailable. Please try again shortly. '
          'AniList error: ${_friendlyError(anilistError)}',
        );
      }
    }
  }

  Future<AnimeSummary> details(int id) async {
    const query = r'''
      query AnimeDetails($id: Int!) {
        Media(id: $id, type: ANIME) {
          id
          idMal
          title { userPreferred english romaji }
          description(asHtml: false)
          episodes
          averageScore
          genres
          coverImage { extraLarge }
          bannerImage
          format
          status
          season
          seasonYear
          duration
          synonyms
          nextAiringEpisode { episode }
          studios(isMain: true) { nodes { id name } }
          staff(perPage: 10, sort: RELEVANCE) {
            nodes { id name { full } image { large } }
          }
          characters(perPage: 12, sort: ROLE) {
            edges {
              role
              node { id name { full } image { large } }
              voiceActors(language: ENGLISH, sort: RELEVANCE) {
                id name { full } image { large }
              }
            }
          }
          relations {
            edges {
              relationType
              node {
                id
                idMal
                type
                title { userPreferred english romaji }
                description(asHtml: false)
                episodes
                averageScore
                genres
                coverImage { extraLarge }
                bannerImage
                format
                status
                season
                seasonYear
                duration
                synonyms
                nextAiringEpisode { episode }
              }
            }
          }
        }
      }
    ''';
    try {
      final data = await _graphQl(query, {'id': id});
      final media = data['Media'] as Map<String, dynamic>?;
      if (media == null) throw StateError('Anime not found.');
      return _mapAnime(media);
    } catch (_) {
      return _kitsu.detailsForAniListId(id);
    }
  }

  Future<List<AnimeSummary>> discover(
    CatalogFilters filters, {
    int page = 1,
  }) async {
    const query = r'''
      query DiscoverAnime(
        $page: Int!, $search: String, $genre: String, $tag: String,
        $format: MediaFormat,
        $status: MediaStatus, $season: MediaSeason, $year: Int,
        $minimumScore: Int, $isAdult: Boolean, $sort: [MediaSort!]
      ) {
        Page(page: $page, perPage: 30) {
          media(
            type: ANIME, search: $search, isAdult: $isAdult,
            genre: $genre, tag: $tag, format: $format,
            status: $status, season: $season, seasonYear: $year,
            averageScore_greater: $minimumScore, sort: $sort
          ) {
            id idMal title { userPreferred english romaji }
            description(asHtml: false) episodes averageScore genres
            coverImage { extraLarge } bannerImage format status season
            seasonYear duration synonyms nextAiringEpisode { episode }
          }
        }
      }
    ''';
    final variables = <String, dynamic>{
      'isAdult': filters.includeAdult,
      'sort': [filters.sort],
    };
    void addIfPresent(String key, Object? value) {
      if (value != null) variables[key] = value;
    }

    final search = filters.search?.trim();
    addIfPresent('search', search == null || search.isEmpty ? null : search);
    addIfPresent('genre', filters.genre);
    addIfPresent('tag', filters.tag);
    addIfPresent('format', filters.format);
    addIfPresent('status', filters.status);
    addIfPresent('season', filters.season);
    addIfPresent('year', filters.year);
    addIfPresent('minimumScore', filters.minimumScore);
    try {
      return await _discoverPages(query, variables, logicalPage: page);
    } on StateError catch (error) {
      // AniList occasionally rejects an otherwise valid filter request with
      // "Illegal operation and value combination" when a sort is combined
      // with other media arguments. Retry the same filters without a server
      // sort instead of leaving Discover unusable. The small returned page is
      // then sorted locally to retain the user's requested ordering.
      if (!_isIllegalDiscoverCombination(error)) rethrow;
      final retryVariables = Map<String, dynamic>.from(variables)
        ..remove('sort');
      final results = await _discoverPages(
        query,
        retryVariables,
        logicalPage: page,
      );
      return _sortDiscoverResults(results, filters.sort);
    }
  }

  Future<List<AnimeSummary>> _discoverPages(
    String query,
    Map<String, dynamic> variables, {
    required int logicalPage,
  }) async {
    // Two 30-item pages produce ten rows on the standard TV grid. Keep both
    // requests in one Future so a filter refresh can never render a partial
    // page or combine results belonging to different filter selections.
    final firstApiPage = logicalPage * 2 - 1;
    final pages = await Future.wait([
      for (final page in [firstApiPage, firstApiPage + 1])
        _mediaPage(query, {...variables, 'page': page}, useStaleOnError: false),
    ]);
    final uniqueById = <int, AnimeSummary>{};
    for (final page in pages) {
      for (final anime in page) {
        // A boundary duplicate keeps its page-one position and payload.
        uniqueById.putIfAbsent(anime.id, () => anime);
      }
    }
    return uniqueById.values.toList(growable: false);
  }

  Future<List<AiringScheduleEntry>> airingSchedule({
    required DateTime from,
    required DateTime to,
  }) async {
    const query = r'''
      query AiringCalendar($page: Int!, $from: Int!, $to: Int!) {
        Page(page: $page, perPage: 50) {
          pageInfo { hasNextPage }
          airingSchedules(
            airingAt_greater: $from, airingAt_lesser: $to, sort: TIME
          ) {
            episode airingAt
            media {
              id idMal title { userPreferred english romaji }
              description(asHtml: false) episodes averageScore genres
              coverImage { extraLarge } bannerImage format status season
              seasonYear duration synonyms nextAiringEpisode { episode }
            }
          }
        }
      }
    ''';
    final entries = <AiringScheduleEntry>[];
    var pageNumber = 1;
    var hasNextPage = true;
    // A week normally spans several AniList pages. Fetching only page one
    // made the followed-only calendar appear empty whenever a user's show was
    // outside the first 50 global airings.
    while (hasNextPage && pageNumber <= 20) {
      final data = await _graphQl(query, {
        'page': pageNumber,
        'from': from.millisecondsSinceEpoch ~/ 1000,
        'to': to.millisecondsSinceEpoch ~/ 1000,
      });
      final page = data['Page'] as Map<String, dynamic>?;
      final schedules = page?['airingSchedules'] as List<dynamic>? ?? const [];
      entries.addAll(
        schedules.whereType<Map<String, dynamic>>().map((item) {
          return AiringScheduleEntry(
            anime: _mapAnime(item['media'] as Map<String, dynamic>),
            episode: item['episode'] as int,
            airingAt: DateTime.fromMillisecondsSinceEpoch(
              (item['airingAt'] as int) * 1000,
            ),
          );
        }),
      );
      final pageInfo = page?['pageInfo'] as Map<String, dynamic>?;
      hasNextPage = pageInfo?['hasNextPage'] == true;
      pageNumber++;
    }
    return entries;
  }

  Future<List<AnimeSummary>> studioAnime(int studioId) async {
    const query = r'''
      query StudioAnime($id: Int!) {
        Studio(id: $id) {
          media(page: 1, perPage: 30, sort: POPULARITY_DESC, isMain: true) {
            nodes {
              id idMal title { userPreferred english romaji }
              description(asHtml: false) episodes averageScore genres
              coverImage { extraLarge } bannerImage format status season
              seasonYear duration synonyms nextAiringEpisode { episode }
            }
          }
        }
      }
    ''';
    final data = await _graphQl(query, {'id': studioId});
    final studio = data['Studio'] as Map<String, dynamic>?;
    final media = studio?['media'] as Map<String, dynamic>?;
    return (media?['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_mapAnime)
        .toList(growable: false);
  }

  Future<List<AnimeSummary>> staffAnime(int staffId) async {
    const query = r'''
      query StaffAnime($id: Int!) {
        Staff(id: $id) {
          staffMedia(page: 1, perPage: 30, type: ANIME, sort: POPULARITY_DESC) {
            nodes {
              id idMal title { userPreferred english romaji }
              description(asHtml: false) episodes averageScore genres
              coverImage { extraLarge } bannerImage format status season
              seasonYear duration synonyms nextAiringEpisode { episode }
            }
          }
        }
      }
    ''';
    final data = await _graphQl(query, {'id': staffId});
    final staff = data['Staff'] as Map<String, dynamic>?;
    final media = staff?['staffMedia'] as Map<String, dynamic>?;
    return (media?['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_mapAnime)
        .toList(growable: false);
  }

  Future<List<AnimeSummary>> franchise(int mediaId) async {
    final root = await details(mediaId);
    final values = <int, AnimeSummary>{root.id: root};
    for (final relation in root.relatedAnime) {
      values[relation.anime.id] = relation.anime;
    }
    final directIds = root.relatedAnime
        .where(
          (item) =>
              const ['SEQUEL', 'PREQUEL', 'PARENT'].contains(item.relationType),
        )
        .map((item) => item.anime.id)
        .take(8);
    final expanded = await Future.wait(directIds.map(details));
    for (final anime in expanded) {
      values[anime.id] = anime;
      for (final relation in anime.relatedAnime) {
        if (const [
          'SEQUEL',
          'PREQUEL',
          'PARENT',
        ].contains(relation.relationType)) {
          values[relation.anime.id] = relation.anime;
        }
      }
    }
    final result = values.values.toList();
    result.sort((a, b) {
      final year = (a.seasonYear ?? 9999).compareTo(b.seasonYear ?? 9999);
      if (year != 0) return year;
      return a.id.compareTo(b.id);
    });
    return result;
  }

  Future<List<AnimeSummary>> _mediaPage(
    String query,
    Map<String, dynamic> variables, {
    bool useStaleOnError = true,
  }) async {
    final data = await _graphQl(
      query,
      variables,
      useStaleOnError: useStaleOnError,
    );
    final pageData = data['Page'] as Map<String, dynamic>?;
    final media = pageData?['media'] as List<dynamic>? ?? const [];
    return media
        .whereType<Map<String, dynamic>>()
        .map(_mapAnime)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _graphQl(
    String query,
    Map<String, dynamic> variables, {
    bool useStaleOnError = true,
  }) async {
    final cacheKey =
        'anilist:${jsonEncode({'query': query, 'variables': variables})}';
    try {
      final cached = await TetoTvDatabase.instance.cachedJson(cacheKey);
      if (cached != null) return cached;
    } catch (_) {
      // Unit tests and unsupported platforms may not provide sqflite.
    }
    Map<String, dynamic> body;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '',
        data: {'query': query, 'variables': variables},
      );
      body = response.data ?? const {};
    } on DioException catch (error, stackTrace) {
      if (useStaleOnError) {
        try {
          final stale = await TetoTvDatabase.instance.cachedJson(
            cacheKey,
            allowExpired: true,
          );
          if (stale != null) return stale;
        } catch (_) {
          // Preserve the original network error below.
        }
      }
      final message = _graphQlErrorMessage(error.response?.data);
      if (message != null) {
        Error.throwWithStackTrace(StateError(message), stackTrace);
      }
      rethrow;
    } catch (_) {
      if (useStaleOnError) {
        try {
          final stale = await TetoTvDatabase.instance.cachedJson(
            cacheKey,
            allowExpired: true,
          );
          if (stale != null) return stale;
        } catch (_) {
          // Preserve the original network error below.
        }
      }
      rethrow;
    }
    if (body['errors'] case final List<dynamic> errors when errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map<String, dynamic>
          ? first['message'] as String?
          : null;
      throw StateError(message ?? 'AniList request failed.');
    }
    final data = body['data'] as Map<String, dynamic>? ?? const {};
    try {
      await TetoTvDatabase.instance.cacheJson(cacheKey, data);
    } catch (_) {
      // Catalog caching is a best-effort performance optimization.
    }
    return data;
  }

  AnimeSummary _mapAnime(Map<String, dynamic> item) {
    final title = item['title'] as Map<String, dynamic>?;
    final cover = item['coverImage'] as Map<String, dynamic>?;
    final score = item['averageScore'] as num?;
    final airing = item['nextAiringEpisode'] as Map<String, dynamic>?;
    final titleEnglish = title?['english'] as String?;
    final titleRomaji = title?['romaji'] as String?;
    final userPreferred = title?['userPreferred'] as String?;
    return AnimeSummary(
      id: item['id'] as int,
      idMal: item['idMal'] as int?,
      title: _firstTitle([titleEnglish, titleRomaji, userPreferred]),
      titleEnglish: titleEnglish,
      titleRomaji: titleRomaji,
      description: _plainText(item['description'] as String? ?? ''),
      episodes: item['episodes'] as int?,
      score: score == null ? null : score.toDouble() / 10,
      coverImageUrl: cover?['extraLarge'] as String?,
      bannerImageUrl: item['bannerImage'] as String?,
      genres: (item['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      synonyms: (item['synonyms'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      format: item['format'] as String?,
      status: item['status'] as String?,
      season: item['season'] as String?,
      seasonYear: item['seasonYear'] as int?,
      durationMinutes: item['duration'] as int?,
      nextAiringEpisode: airing?['episode'] as int?,
      relatedAnime: _mapRelations(item['relations']),
      studios: _mapStudios(item['studios']),
      staff: _mapStaff(item['staff']),
      characters: _mapCharacters(item['characters']),
    );
  }

  List<AnimeStudio> _mapStudios(dynamic data) {
    if (data is! Map<String, dynamic>) return const [];
    return (data['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (item) =>
              AnimeStudio(id: item['id'] as int, name: item['name'] as String),
        )
        .toList(growable: false);
  }

  AnimePerson _mapPerson(Map<String, dynamic> item) {
    final name = item['name'] as Map<String, dynamic>?;
    final image = item['image'] as Map<String, dynamic>?;
    return AnimePerson(
      id: item['id'] as int,
      name: name?['full'] as String? ?? 'Unknown',
      imageUrl: image?['large'] as String?,
    );
  }

  List<AnimePerson> _mapStaff(dynamic data) {
    if (data is! Map<String, dynamic>) return const [];
    return (data['nodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_mapPerson)
        .toList(growable: false);
  }

  List<AnimeCharacter> _mapCharacters(dynamic data) {
    if (data is! Map<String, dynamic>) return const [];
    return (data['edges'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((edge) {
          final node = edge['node'] as Map<String, dynamic>;
          final name = node['name'] as Map<String, dynamic>?;
          final image = node['image'] as Map<String, dynamic>?;
          final voices = (edge['voiceActors'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          return AnimeCharacter(
            id: node['id'] as int,
            name: name?['full'] as String? ?? 'Unknown',
            imageUrl: image?['large'] as String?,
            role: edge['role'] as String?,
            voiceActor: voices.isEmpty ? null : _mapPerson(voices.first),
          );
        })
        .toList(growable: false);
  }

  List<RelatedAnime> _mapRelations(dynamic data) {
    if (data is! Map<String, dynamic>) return const [];
    final edges = data['edges'];
    if (edges is! List) return const [];
    final related = edges
        .whereType<Map<String, dynamic>>()
        .map((edge) {
          final node = edge['node'];
          if (node is! Map<String, dynamic> || node['type'] != 'ANIME') {
            return null;
          }
          return RelatedAnime(
            anime: _mapAnime(node),
            relationType:
                edge['relationType']?.toString().replaceAll('_', ' ') ??
                'RELATED',
          );
        })
        .whereType<RelatedAnime>()
        .toList();
    related.sort((a, b) {
      final relation = _relationPriority(
        a.relationType,
      ).compareTo(_relationPriority(b.relationType));
      if (relation != 0) return relation;
      final year = (a.anime.seasonYear ?? 9999).compareTo(
        b.anime.seasonYear ?? 9999,
      );
      if (year != 0) return year;
      return a.anime.title.toLowerCase().compareTo(b.anime.title.toLowerCase());
    });
    return List.unmodifiable(related);
  }

  int _relationPriority(String relationType) => switch (relationType) {
    'SEQUEL' => 0,
    'PREQUEL' => 1,
    'PARENT' => 2,
    'SIDE STORY' => 3,
    'SPIN OFF' => 4,
    'SOURCE' || 'ADAPTATION' => 5,
    'ALTERNATIVE' => 6,
    'SUMMARY' => 7,
    'CHARACTER' => 8,
    _ => 9,
  };

  String _firstTitle(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return 'Untitled';
  }

  String? _graphQlErrorMessage(dynamic body) {
    if (body is! Map) return null;
    final errors = body['errors'];
    if (errors is! List || errors.isEmpty) return null;
    final first = errors.first;
    if (first is! Map) return null;
    final message = first['message']?.toString().trim();
    return message == null || message.isEmpty ? null : message;
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is DioException) {
      return _graphQlErrorMessage(error.response?.data) ??
          'the service could not be reached';
    }
    return 'the service could not be reached';
  }

  String _plainText(String value) {
    return value
        .replaceAll(RegExp('<br\\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .trim();
  }
}

bool _isIllegalDiscoverCombination(StateError error) {
  final message = error.message.toString().toLowerCase();
  return message.contains('illegal operation') &&
      message.contains('value combination');
}

List<AnimeSummary> _sortDiscoverResults(
  List<AnimeSummary> values,
  String sort,
) {
  final results = List<AnimeSummary>.of(values);
  int compareNullableNum(num? left, num? right, {required bool descending}) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return descending ? right.compareTo(left) : left.compareTo(right);
  }

  switch (sort) {
    case 'SCORE_DESC':
      results.sort(
        (a, b) => compareNullableNum(a.score, b.score, descending: true),
      );
      break;
    case 'START_DATE_DESC':
      results.sort(
        (a, b) =>
            compareNullableNum(a.seasonYear, b.seasonYear, descending: true),
      );
      break;
    case 'TITLE_ENGLISH':
      results.sort(
        (a, b) => (a.titleEnglish ?? a.title).toLowerCase().compareTo(
          (b.titleEnglish ?? b.title).toLowerCase(),
        ),
      );
      break;
    default:
      // Popularity, trending, and favourites do not exist on AnimeSummary.
      // Preserve AniList's fallback order for those choices.
      break;
  }
  return results;
}
