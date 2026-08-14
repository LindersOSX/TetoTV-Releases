import 'dart:convert';

import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:anime_tv/features/local_media/domain/jellyfin_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jellyfin server address policy', () {
    test('normalizes a private server address and preserves its base path', () {
      expect(
        normalizeJellyfinServerUri(' 192.168.1.25:8096/jellyfin/// '),
        Uri.parse('http://192.168.1.25:8096/jellyfin'),
      );
      expect(
        normalizeJellyfinServerUri('HTTPS://Media.Example.COM/jellyfin/'),
        Uri.parse('https://media.example.com/jellyfin'),
      );
      expect(
        normalizeJellyfinServerUri('http://[fd12:3456::7]:8096/'),
        Uri.parse('http://[fd12:3456::7]:8096'),
      );
    });

    test(
      'rejects credentials, URL state, unsupported schemes, and public HTTP',
      () {
        for (final value in const [
          '',
          'ftp://192.168.1.25/video',
          'http://user:password@192.168.1.25:8096',
          'http://192.168.1.25:8096?token=secret',
          'http://192.168.1.25:8096/#fragment',
          'http://8.8.8.8:8096',
          'http://example.com:8096',
          'http://192.168.1.25:0',
          'http://192.168.1.25:not-a-port',
          'http://192.168.1.25:70000',
        ]) {
          expect(normalizeJellyfinServerUri(value), isNull, reason: value);
        }
      },
    );

    test(
      'recognizes private IP boundaries without trusting public addresses',
      () {
        for (final host in const [
          'localhost',
          '10.0.0.1',
          '172.16.0.1',
          '172.31.255.254',
          '192.168.50.2',
          '127.0.0.1',
          '169.254.1.2',
          'fd12:3456::7',
          'fe80::1',
        ]) {
          expect(isPrivateJellyfinHost(host), isTrue, reason: host);
        }
        for (final host in const [
          '8.8.8.8',
          '172.15.255.255',
          '172.32.0.1',
          '192.167.1.1',
          'example.com',
          'jellyfin',
          'jellyfin.local',
          '224.0.0.1',
          'ff02::1',
        ]) {
          expect(isPrivateJellyfinHost(host), isFalse, reason: host);
        }
      },
    );
  });

  group('Jellyfin client requests', () {
    test(
      'authenticates without exposing the password in a URL or auth header',
      () async {
        final requests = <RequestOptions>[];
        final client = JellyfinClient(
          _stubDio((request) {
            requests.add(request);
            if (request.uri.path.endsWith('/System/Info/Public')) {
              return _json(request, {
                'ServerName': 'Living Room',
                'Version': '10.10.7',
                'Id': 'server-12345678',
              });
            }
            return _json(request, {
              'AccessToken': 'access-token-1234567890',
              'User': {'Id': 'user-id-12345678', 'Name': 'Viewer'},
            });
          }),
        );

        final connection = await client.authenticate(
          baseUri: Uri.parse('http://192.168.1.25:8096/jellyfin'),
          username: ' Viewer ',
          password: 'correct horse battery staple',
          deviceId: 'device"id\r\nInjected: value',
        );

        expect(connection.serverName, 'Living Room');
        expect(connection.username, 'Viewer');
        expect(requests, hasLength(2));
        expect(requests[0].uri.path, '/jellyfin/System/Info/Public');
        expect(requests[0].headers['Authorization'], isNull);
        expect(requests[1].method, 'POST');
        expect(requests[1].uri.path, '/jellyfin/Users/AuthenticateByName');
        expect(requests[1].uri.toString(), isNot(contains('correct horse')));
        expect(requests[1].data, {
          'Username': 'Viewer',
          'Pw': 'correct horse battery staple',
        });
        final authorization = requests[1].headers['Authorization'] as String;
        expect(authorization, startsWith('MediaBrowser '));
        expect(
          authorization,
          contains(r'DeviceId="device\"idInjected: value"'),
        );
        expect(authorization, isNot(contains('\r')));
        expect(authorization, isNot(contains('\n')));
        expect(authorization, isNot(contains('correct horse')));
        expect(authorization, isNot(contains('Token=')));
      },
    );

    test('never follows a redirect carrying a saved session token', () async {
      final requests = <RequestOptions>[];
      final client = JellyfinClient(
        _stubDio((request) {
          requests.add(request);
          return _raw(
            requestOptions: request,
            statusCode: 302,
            headers: Headers.fromMap({
              'location': ['https://attacker.example/collect'],
            }),
            data: const {},
          );
        }),
      );

      await expectLater(
        client.items(_connection()),
        throwsA(
          isA<JellyfinException>().having(
            (error) => error.message,
            'message',
            contains('redirected'),
          ),
        ),
      );

      expect(requests, hasLength(1));
      expect(requests.single.uri.host, '192.168.1.25');
      expect(requests.single.followRedirects, isFalse);
      expect(
        requests.single.headers['Authorization'],
        contains('Token="access-token-1234567890"'),
      );
    });

    test(
      'lists bounded media and keeps the token out of generated URLs',
      () async {
        RequestOptions? captured;
        final client = JellyfinClient(
          _stubDio((request) {
            captured = request;
            return _json(request, {
              'Items': [
                {
                  'Id': 'episode-id-12345678',
                  'Name': 'A New Start',
                  'Type': 'Episode',
                  'SeriesName': 'Example Series',
                  'ParentIndexNumber': 2,
                  'IndexNumber': 3,
                  'RunTimeTicks': 14_400_000_000,
                  'ImageTags': {'Primary': 'image-tag-123'},
                  'MediaSources': [
                    {'Id': 'source/id?value', 'Container': 'mkv'},
                  ],
                },
                {'Id': 'short', 'Name': 'Rejected', 'Type': 'Movie'},
              ],
              'TotalRecordCount': 2,
            });
          }),
        );

        final page = await client.items(
          _connection(),
          parentId: 'folder-id-12345678',
          startIndex: 100,
        );

        expect(page.items, hasLength(1));
        expect(page.items.single.name, 'A New Start');
        expect(page.items.single.episodeNumber, 3);
        expect(captured?.uri.path, '/jellyfin/Items');
        expect(captured?.uri.queryParameters['parentId'], 'folder-id-12345678');
        expect(captured?.uri.queryParameters['startIndex'], '100');
        expect(captured?.uri.queryParameters['limit'], '100');
        expect(captured?.headers['Authorization'], contains('Token='));

        final stream = client.streamUri(_connection(), page.items.single);
        final image = client.imageUri(_connection(), page.items.single);
        expect(stream.path, '/jellyfin/Videos/episode-id-12345678/stream');
        expect(stream.queryParameters['mediaSourceId'], 'source/id?value');
        expect(stream.queryParameters, isNot(contains('api_key')));
        expect(stream.toString(), isNot(contains('access-token')));
        expect(
          image?.path,
          '/jellyfin/Items/episode-id-12345678/Images/Primary',
        );
        expect(image.toString(), isNot(contains('access-token')));
      },
    );

    test(
      'ignores malformed optional numeric fields instead of losing the library',
      () async {
        final client = JellyfinClient(
          _stubDio(
            (request) => _json(request, {
              'Items': [
                {
                  'Id': 'episode-id-12345678',
                  'Name': 'Malformed Metadata',
                  'Type': 'Episode',
                  'ParentIndexNumber': 'not-a-number',
                  'IndexNumber': '3',
                  'RunTimeTicks': 'unknown',
                },
              ],
              'TotalRecordCount': 1,
            }),
          ),
        );

        final page = await client.items(_connection());

        expect(page.items, hasLength(1));
        expect(page.items.single.seasonNumber, isNull);
        expect(page.items.single.episodeNumber, 3);
        expect(page.items.single.runTimeTicks, isNull);
      },
    );

    test(
      'rejects oversized decoded responses even without Content-Length',
      () async {
        final client = JellyfinClient(
          _stubDio(
            (request) => _json(request, {
              'ServerName': 'Jellyfin',
              'Version': '10.10.7',
              'Id': 'server-12345678',
              'padding': List<String>.filled(4 * 1024 * 1024 + 1, 'x').join(),
            }),
          ),
        );

        await expectLater(
          client.publicInfo(Uri.parse('https://media.example.com')),
          throwsA(
            isA<JellyfinException>().having(
              (error) => error.message,
              'message',
              contains('too much data'),
            ),
          ),
        );
      },
    );

    test('maps unauthorized responses to a bounded account error', () async {
      final client = JellyfinClient(
        _stubDio(
          (request) =>
              _raw(requestOptions: request, statusCode: 401, data: const {}),
        ),
      );

      await expectLater(
        client.items(_connection()),
        throwsA(
          isA<JellyfinException>().having(
            (error) => error.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });

    test(
      'logs out with the saved token and accepts an empty 204 response',
      () async {
        RequestOptions? captured;
        final client = JellyfinClient(
          _stubDio((request) {
            captured = request;
            return _raw(
              requestOptions: request,
              statusCode: 204,
              data: const {},
            );
          }),
        );

        await client.logout(_connection());

        expect(captured?.method, 'POST');
        expect(captured?.uri.path, '/jellyfin/Sessions/Logout');
        expect(
          captured?.headers['Authorization'],
          contains('Token="access-token-1234567890"'),
        );
      },
    );
  });
}

Dio _stubDio(Response<dynamic> Function(RequestOptions request) responder) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(responder(request)),
    ),
  );
  return dio;
}

Response<ResponseBody> _json(
  RequestOptions request,
  Map<String, dynamic> data,
) => _raw(requestOptions: request, statusCode: 200, data: data);

Response<ResponseBody> _raw({
  required RequestOptions requestOptions,
  required int statusCode,
  required Map<String, dynamic> data,
  Headers? headers,
}) => Response<ResponseBody>(
  requestOptions: requestOptions,
  statusCode: statusCode,
  headers: headers ?? Headers(),
  data: ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: const {
      Headers.contentTypeHeader: ['application/json'],
    },
  ),
);

JellyfinConnection _connection() => JellyfinConnection(
  baseUri: Uri.parse('http://192.168.1.25:8096/jellyfin'),
  serverName: 'Living Room',
  serverVersion: '10.10.7',
  userId: 'user-id-12345678',
  username: 'Viewer',
  accessToken: 'access-token-1234567890',
  deviceId: 'device-id-12345678',
);
