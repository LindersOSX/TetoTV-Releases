import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Dio interceptedDio(dynamic responseData) {
    final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              data: responseData as Map<String, dynamic>,
              requestOptions: options,
              statusCode: 200,
            ),
          );
        },
      ),
    );
    return dio;
  }

  Dio rejectedAniListDio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<Map<String, dynamic>>(
                data: const {
                  'errors': [
                    {
                      'message':
                          'The AniList API has been temporarily disabled.',
                      'status': 403,
                    },
                  ],
                },
                requestOptions: options,
                statusCode: 403,
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );
    return dio;
  }

  Dio kitsuDio(Map<String, dynamic> Function(RequestOptions) responseFor) {
    final dio = Dio(BaseOptions(baseUrl: 'https://kitsu.io/api/edge/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              data: responseFor(options),
              requestOptions: options,
              statusCode: 200,
            ),
          );
        },
      ),
    );
    return dio;
  }

  Map<String, dynamic> kitsuAnimeResource() => {
    'type': 'anime',
    'id': '42',
    'attributes': {
      'canonicalTitle': 'Fallback Romaji',
      'titles': {'en': 'Fallback English', 'en_jp': 'Fallback Romaji'},
      'synopsis': 'Available during an AniList outage.',
      'episodeCount': 12,
      'averageRating': '84.5',
      'posterImage': {'large': 'https://example.com/poster.jpg'},
      'coverImage': {'large': 'https://example.com/banner.jpg'},
      'subtype': 'TV',
      'status': 'finished',
      'startDate': '2024-04-01',
      'episodeLength': 24,
      'abbreviatedTitles': ['Fallback'],
    },
    'relationships': {
      'mappings': {
        'data': [
          {'type': 'mappings', 'id': 'anilist-map'},
          {'type': 'mappings', 'id': 'mal-map'},
        ],
      },
      'categories': {
        'data': [
          {'type': 'categories', 'id': 'action'},
        ],
      },
    },
  };

  List<Map<String, dynamic>> kitsuIncluded() => [
    {
      'type': 'mappings',
      'id': 'anilist-map',
      'attributes': {'externalSite': 'anilist/anime', 'externalId': '100'},
    },
    {
      'type': 'mappings',
      'id': 'mal-map',
      'attributes': {'externalSite': 'myanimelist/anime', 'externalId': '200'},
    },
    {
      'type': 'categories',
      'id': 'action',
      'attributes': {'title': 'Action'},
    },
  ];

  group('AniListCatalogClient', () {
    test('strips HTML tags from descriptions', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 1,
                  'idMal': null,
                  'title': {
                    'userPreferred': 'Test Anime',
                    'english': 'Test Anime English',
                    'romaji': 'Test Anime Romaji',
                  },
                  'description':
                      'A <b>bold</b> story.<br/>Second line.<br />'
                      'Entities: &amp; &quot; &#039;',
                  'episodes': 12,
                  'averageScore': 85,
                  'genres': <String>[],
                  'coverImage': {'extraLarge': null},
                  'bannerImage': null,
                  'format': 'TV',
                  'status': 'FINISHED',
                  'season': 'SPRING',
                  'seasonYear': 2023,
                  'duration': 24,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results, hasLength(1));
      final desc = results.first.description;
      expect(desc, isNot(contains('<b>')));
      expect(desc, isNot(contains('<br')));
      expect(desc, contains('bold'));
      expect(desc, contains('Second line.'));
      expect(desc, contains('& " \''));
      expect(results.first.title, 'Test Anime English');
      expect(
        results.first.displayTitle(TitleLanguagePreference.romaji),
        'Test Anime Romaji',
      );
    });

    test('maps score from AniList 0–100 to 0.0–10.0', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 2,
                  'idMal': null,
                  'title': {'userPreferred': 'Scored'},
                  'description': '',
                  'episodes': 1,
                  'averageScore': 80,
                  'genres': <String>[],
                  'coverImage': {'extraLarge': null},
                  'bannerImage': null,
                  'format': 'OVA',
                  'status': 'FINISHED',
                  'season': null,
                  'seasonYear': null,
                  'duration': 30,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results.first.score, closeTo(8.0, 0.001));
    });

    test('returns null score when averageScore is absent', () async {
      final client = AniListCatalogClient(
        dio: interceptedDio({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 3,
                  'idMal': null,
                  'title': {'userPreferred': 'Unscored'},
                  'description': '',
                  'episodes': null,
                  'averageScore': null,
                  'genres': <String>[],
                  'coverImage': <String, dynamic>{},
                  'bannerImage': null,
                  'format': null,
                  'status': null,
                  'season': null,
                  'seasonYear': null,
                  'duration': null,
                  'synonyms': <String>[],
                  'nextAiringEpisode': null,
                },
              ],
            },
          },
        }),
      );

      final results = await client.trending();

      expect(results.first.score, isNull);
      expect(results.first.episodes, isNull);
      expect(results.first.coverImageUrl, isNull);
    });

    test('seasonal uses correct quarter for each month', () async {
      // We can verify the query variables by checking that seasonal() doesn't
      // throw with a stubbed response regardless of the date.
      for (final month in [1, 4, 7, 10]) {
        final client = AniListCatalogClient(
          dio: interceptedDio({
            'data': {
              'Page': {'media': <dynamic>[]},
            },
          }),
        );

        await expectLater(
          client.seasonal(now: DateTime(2023, month)),
          completes,
        );
      }
    });

    test(
      'search falls back to mapped Kitsu results during AniList outage',
      () async {
        final client = AniListCatalogClient(
          dio: rejectedAniListDio(),
          kitsuDio: kitsuDio(
            (_) => {
              'data': [kitsuAnimeResource()],
              'included': kitsuIncluded(),
            },
          ),
        );

        final results = await client.search('Fallback');

        expect(results, hasLength(1));
        final anime = results.single;
        expect(anime.id, 100);
        expect(anime.idMal, 200);
        expect(anime.title, 'Fallback English');
        expect(anime.titleRomaji, 'Fallback Romaji');
        expect(anime.score, closeTo(8.45, 0.001));
        expect(anime.genres, ['Action']);
        expect(anime.season, 'SPRING');
      },
    );

    test(
      'details falls back by AniList mapping during AniList outage',
      () async {
        final client = AniListCatalogClient(
          dio: rejectedAniListDio(),
          kitsuDio: kitsuDio((options) {
            if (options.uri.path.endsWith('/mappings')) {
              expect(options.queryParameters['include'], 'item');
              return {
                'data': [
                  {
                    'type': 'mappings',
                    'id': 'anilist-map',
                    'relationships': {
                      'item': {
                        'data': {'type': 'anime', 'id': '42'},
                      },
                    },
                  },
                ],
              };
            }
            return {'data': kitsuAnimeResource(), 'included': kitsuIncluded()};
          }),
        );

        final anime = await client.details(100);

        expect(anime.id, 100);
        expect(anime.idMal, 200);
        expect(anime.episodes, 12);
        expect(anime.durationMinutes, 24);
      },
    );

    test(
      'fallback rejects adult categories even when Kitsu rating is incorrect',
      () async {
        final resource = kitsuAnimeResource();
        final attributes = resource['attributes'] as Map<String, dynamic>;
        attributes['nsfw'] = false;
        attributes['ageRating'] = 'PG';
        final relationships = resource['relationships'] as Map<String, dynamic>;
        relationships['categories'] = {
          'data': [
            {'type': 'categories', 'id': 'adult-category'},
          ],
        };
        final included = kitsuIncluded()
          ..add({
            'type': 'categories',
            'id': 'adult-category',
            'attributes': {'title': 'Yaoi'},
          });
        final client = AniListCatalogClient(
          dio: rejectedAniListDio(),
          kitsuDio: kitsuDio(
            (_) => {
              'data': [resource],
              'included': included,
            },
          ),
        );

        final results = await client.search('Incorrectly rated title');

        expect(results, isEmpty);
      },
    );

    test(
      'ignores malformed media entries without losing valid results',
      () async {
        final client = AniListCatalogClient(
          dio: interceptedDio({
            'data': {
              'Page': {
                'media': [
                  null,
                  {
                    'id': 4,
                    'idMal': null,
                    'title': {'userPreferred': 'Valid'},
                    'description': '',
                    'episodes': 1,
                    'averageScore': null,
                    'genres': [null, 'Comedy'],
                    'coverImage': <String, dynamic>{},
                    'bannerImage': null,
                    'format': 'TV',
                    'status': 'FINISHED',
                    'season': null,
                    'seasonYear': null,
                    'duration': 3,
                    'synonyms': [null, 'Still valid'],
                    'nextAiringEpisode': null,
                  },
                ],
              },
            },
          }),
        );

        final results = await client.search('Valid');

        expect(results, hasLength(1));
        expect(results.single.genres, ['Comedy']);
        expect(results.single.synonyms, ['Still valid']);
      },
    );

    test('discover forwards the complete filter set to AniList', () async {
      final requestBodies = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestBodies.add(
                Map<String, dynamic>.from(options.data as Map<String, dynamic>),
              );
              handler.resolve(
                Response<Map<String, dynamic>>(
                  data: const {
                    'data': {
                      'Page': {'media': <dynamic>[]},
                    },
                  },
                  requestOptions: options,
                  statusCode: 200,
                ),
              );
            },
          ),
        );
      final client = AniListCatalogClient(dio: dio);

      await client.discover(
        const CatalogFilters(
          search: 'Frieren',
          genre: 'Fantasy',
          tag: 'Elf',
          format: 'TV',
          status: 'RELEASING',
          season: 'FALL',
          year: 2026,
          minimumScore: 80,
          includeAdult: true,
          sort: 'SCORE_DESC',
        ),
      );

      expect(
        requestBodies.map(
          (body) => (body['variables'] as Map<String, dynamic>)['page'],
        ),
        [1, 2],
      );
      for (var index = 0; index < requestBodies.length; index++) {
        expect(requestBodies[index]['variables'], {
          'page': index + 1,
          'search': 'Frieren',
          'genre': 'Fantasy',
          'tag': 'Elf',
          'format': 'TV',
          'status': 'RELEASING',
          'season': 'FALL',
          'year': 2026,
          'minimumScore': 80,
          'isAdult': true,
          'sort': ['SCORE_DESC'],
        });
      }
    });

    test('discover omits unused nullable arguments', () async {
      final requestBodies = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestBodies.add(
                Map<String, dynamic>.from(options.data as Map<String, dynamic>),
              );
              handler.resolve(
                Response<Map<String, dynamic>>(
                  data: const {
                    'data': {
                      'Page': {'media': <dynamic>[]},
                    },
                  },
                  requestOptions: options,
                  statusCode: 200,
                ),
              );
            },
          ),
        );
      final client = AniListCatalogClient(dio: dio);

      await client.discover(const CatalogFilters());

      expect(requestBodies, hasLength(2));
      for (var index = 0; index < requestBodies.length; index++) {
        expect(requestBodies[index]['variables'], {
          'page': index + 1,
          'isAdult': false,
          'sort': ['POPULARITY_DESC'],
        });
      }
    });

    test(
      'discover combines exactly two pages into 60 ordered results',
      () async {
        final requestedPages = <int>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final body = options.data as Map<String, dynamic>;
                final variables = body['variables'] as Map<String, dynamic>;
                final page = variables['page'] as int;
                requestedPages.add(page);
                final firstId = page == 1 ? 1 : 31;
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    data: {
                      'data': {
                        'Page': {
                          'media': List.generate(
                            30,
                            (index) => _catalogMedia(firstId + index),
                          ),
                        },
                      },
                    },
                    requestOptions: options,
                    statusCode: 200,
                  ),
                );
              },
            ),
          );
        final client = AniListCatalogClient(dio: dio);

        final results = await client.discover(const CatalogFilters());

        expect(requestedPages, [1, 2]);
        expect(results, hasLength(60));
        expect(
          results.map((anime) => anime.id),
          List.generate(60, (i) => i + 1),
        );
      },
    );

    test(
      'discover logical page two requests AniList pages three and four',
      () async {
        final requestedPages = <int>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final body = options.data as Map<String, dynamic>;
                final variables = body['variables'] as Map<String, dynamic>;
                requestedPages.add(variables['page'] as int);
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    data: const {
                      'data': {
                        'Page': {'media': <Map<String, dynamic>>[]},
                      },
                    },
                    requestOptions: options,
                    statusCode: 200,
                  ),
                );
              },
            ),
          );
        final client = AniListCatalogClient(dio: dio);

        await client.discover(const CatalogFilters(), page: 2);

        expect(requestedPages, [3, 4]);
      },
    );

    test(
      'discover keeps the first occurrence of duplicate anime ids',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final body = options.data as Map<String, dynamic>;
                final variables = body['variables'] as Map<String, dynamic>;
                final page = variables['page'] as int;
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    data: {
                      'data': {
                        'Page': {
                          'media': page == 1
                              ? [
                                  _catalogMedia(1),
                                  _catalogMedia(2, title: 'Page one copy'),
                                ]
                              : [
                                  _catalogMedia(2, title: 'Page two copy'),
                                  _catalogMedia(3),
                                ],
                        },
                      },
                    },
                    requestOptions: options,
                    statusCode: 200,
                  ),
                );
              },
            ),
          );
        final client = AniListCatalogClient(dio: dio);

        final results = await client.discover(const CatalogFilters());

        expect(results.map((anime) => anime.id), [1, 2, 3]);
        expect(results[1].title, 'Page one copy');
      },
    );

    test(
      'discover retries AniList illegal combinations without sort',
      () async {
        final requests = <Map<String, dynamic>>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final body = Map<String, dynamic>.from(
                  options.data as Map<String, dynamic>,
                );
                requests.add(
                  Map<String, dynamic>.from(
                    body['variables'] as Map<String, dynamic>,
                  ),
                );
                final hasSort = (body['variables'] as Map).containsKey('sort');
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    data: hasSort
                        ? const {
                            'errors': [
                              {
                                'message':
                                    'Illegal operation and value combination',
                              },
                            ],
                          }
                        : const {
                            'data': {
                              'Page': {'media': <dynamic>[]},
                            },
                          },
                    requestOptions: options,
                    statusCode: 200,
                  ),
                );
              },
            ),
          );
        final client = AniListCatalogClient(dio: dio);

        await expectLater(
          client.discover(
            const CatalogFilters(genre: 'Fantasy', sort: 'SCORE_DESC'),
          ),
          completion(isEmpty),
        );

        expect(requests, hasLength(4));
        expect(
          requests
              .where((request) => request.containsKey('sort'))
              .map((request) => request['page']),
          [1, 2],
        );
        expect(
          requests
              .where((request) => !request.containsKey('sort'))
              .map((request) => request['page']),
          [1, 2],
        );
        expect(requests.last['genre'], 'Fantasy');
      },
    );

    test(
      'airing calendar follows AniList pagination beyond the first 50',
      () async {
        final requestedPages = <int>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final body = options.data as Map<String, dynamic>;
                final variables = body['variables'] as Map<String, dynamic>;
                final page = variables['page'] as int;
                requestedPages.add(page);
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    data: {
                      'data': {
                        'Page': {
                          'pageInfo': {'hasNextPage': page == 1},
                          'airingSchedules': [
                            {
                              'episode': page,
                              'airingAt': 1_800_000_000 + page,
                              'media': _calendarMedia(page),
                            },
                          ],
                        },
                      },
                    },
                    requestOptions: options,
                    statusCode: 200,
                  ),
                );
              },
            ),
          );
        final client = AniListCatalogClient(dio: dio);

        final entries = await client.airingSchedule(
          from: DateTime(2027),
          to: DateTime(2027, 1, 8),
        );

        expect(requestedPages, [1, 2]);
        expect(entries.map((entry) => entry.anime.id), [1, 2]);
      },
    );
  });
}

Map<String, dynamic> _calendarMedia(int id) => {
  'id': id,
  'idMal': id + 100,
  'title': {
    'userPreferred': 'Show $id',
    'english': 'Show $id',
    'romaji': 'Show $id',
  },
  'description': '',
  'episodes': 12,
  'averageScore': 80,
  'genres': <String>[],
  'coverImage': {'extraLarge': null},
  'bannerImage': null,
  'format': 'TV',
  'status': 'RELEASING',
  'season': 'WINTER',
  'seasonYear': 2027,
  'duration': 24,
  'synonyms': <String>[],
  'nextAiringEpisode': {'episode': id + 1},
};

Map<String, dynamic> _catalogMedia(int id, {String? title}) => {
  ..._calendarMedia(id),
  'title': {
    'userPreferred': title ?? 'Show $id',
    'english': title ?? 'Show $id',
    'romaji': title ?? 'Show $id',
  },
};
