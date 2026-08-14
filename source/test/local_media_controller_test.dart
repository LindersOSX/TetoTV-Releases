import 'dart:convert';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/local_media/application/local_media_controller.dart';
import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('local document contract accepts only provider-backed content URIs', () {
    final document = LocalMediaDocument.fromMap(const {
      'uri': 'content://com.android.providers.media/video/42',
      'name': ' USB video.mkv ',
      'mimeType': 'video/x-matroska',
      'size': 4096,
      'persistedReadPermission': true,
    });

    expect(document.name, 'USB video.mkv');
    expect(document.size, 4096);
    expect(document.persistedReadPermission, isTrue);
    for (final value in const [
      'file:///storage/emulated/0/video.mkv',
      'https://media.example/video.mkv',
      'content:opaque-value',
      'content:///missing-authority/video/42',
      'content://user:password@provider/video/42',
      'content://provider/video/42#fragment',
    ]) {
      expect(
        () => LocalMediaDocument.fromMap({'uri': value, 'name': 'video'}),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('picker persists only grants Android confirms are durable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('dev.tetotv/android_tv');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    var persisted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickLocalVideo');
      return <String, Object?>{
        'uri': 'content://usb.provider/video/42',
        'name': 'USB video.mkv',
        'mimeType': 'video/x-matroska',
        'size': 4096,
        'persistedReadPermission': persisted,
      };
    });
    final controller = LocalMediaController(
      storage,
      JellyfinClient(_stubDio((request) => _json(request, const {}))),
      AndroidTvBridge.instance,
    );

    final sessionOnly = await controller.pickLocalVideo();
    expect(sessionOnly?.persistedReadPermission, isFalse);
    expect(await storage.read(key: 'local_media_recent_document'), isNull);
    expect(controller.state.message, contains('only until TetoTV closes'));

    persisted = true;
    final durable = await controller.pickLocalVideo();
    expect(durable?.persistedReadPermission, isTrue);
    final saved =
        jsonDecode((await storage.read(key: 'local_media_recent_document'))!)
            as Map<String, dynamic>;
    expect(saved['uri'], 'content://usb.provider/video/42');
    expect(saved['persistedReadPermission'], isTrue);
  });

  test('connect persists a token but never the submitted password', () async {
    final requests = <RequestOptions>[];
    final controller = LocalMediaController(
      storage,
      JellyfinClient(
        _stubDio((request) {
          requests.add(request);
          if (request.uri.path.endsWith('/System/Info/Public')) {
            return _json(request, {
              'ServerName': 'Living Room',
              'Version': '10.10.7',
              'Id': 'server-id-12345678',
            });
          }
          if (request.uri.path.endsWith('/Users/AuthenticateByName')) {
            return _json(request, {
              'AccessToken': 'saved-access-token-1234567890',
              'User': {'Id': 'user-id-12345678', 'Name': 'Viewer'},
            });
          }
          return _json(request, {
            'Items': [
              {
                'Id': 'movie-id-12345678',
                'Name': 'Local Movie',
                'Type': 'Movie',
              },
            ],
            'TotalRecordCount': 1,
          });
        }),
      ),
      AndroidTvBridge.instance,
    );

    await controller.connect(
      address: '192.168.1.25:8096/jellyfin',
      username: 'Viewer',
      password: 'never-save-this-password',
    );

    expect(controller.state.busy, isFalse);
    expect(controller.state.connection?.serverName, 'Living Room');
    expect(controller.state.items.single.name, 'Local Movie');
    expect(requests.map((request) => request.uri.path), [
      '/jellyfin/System/Info/Public',
      '/jellyfin/Users/AuthenticateByName',
      '/jellyfin/Items',
    ]);
    final persisted = await storage.readAll();
    expect(
      persisted['local_media_jellyfin_access_token'],
      'saved-access-token-1234567890',
    );
    expect(persisted['local_media_jellyfin_username'], 'Viewer');
    expect(persisted.keys, isNot(contains('local_media_jellyfin_password')));
    expect(persisted.values, isNot(contains('never-save-this-password')));
  });

  test('load restores the session and refreshes its root library', () async {
    FlutterSecureStorage.setMockInitialValues({
      'local_media_jellyfin_base_url': 'http://192.168.1.25:8096/jellyfin',
      'local_media_jellyfin_server_name': 'Living Room',
      'local_media_jellyfin_server_version': '10.10.7',
      'local_media_jellyfin_user_id': 'user-id-12345678',
      'local_media_jellyfin_username': 'Viewer',
      'local_media_jellyfin_access_token': 'saved-access-token-1234567890',
      'local_media_jellyfin_device_id': 'device-id-12345678',
      'local_media_recent_document': jsonEncode({
        'uri': 'content://com.android.providers.media/video/42',
        'name': 'USB video.mkv',
        'mimeType': 'video/x-matroska',
        'size': 1024,
        'persistedReadPermission': true,
      }),
    });
    RequestOptions? request;
    final controller = LocalMediaController(
      storage,
      JellyfinClient(
        _stubDio((value) {
          request = value;
          return _json(value, {
            'Items': [
              {
                'Id': 'folder-id-12345678',
                'Name': 'Shows',
                'Type': 'CollectionFolder',
              },
            ],
            'TotalRecordCount': 1,
          });
        }),
      ),
      AndroidTvBridge.instance,
    );

    await controller.load();

    expect(controller.state.loaded, isTrue);
    expect(controller.state.busy, isFalse);
    expect(controller.state.connection?.username, 'Viewer');
    expect(controller.state.recentLocalDocument?.name, 'USB video.mkv');
    expect(controller.state.items.single.name, 'Shows');
    expect(request?.uri.path, '/jellyfin/Items');
    expect(
      request?.headers['Authorization'],
      contains('Token="saved-access-token-1234567890"'),
    );
  });

  test(
    'load more appends the next Jellyfin page without replacing prior items',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'local_media_jellyfin_base_url': 'http://192.168.1.25:8096/jellyfin',
        'local_media_jellyfin_server_name': 'Living Room',
        'local_media_jellyfin_server_version': '10.10.7',
        'local_media_jellyfin_user_id': 'user-id-12345678',
        'local_media_jellyfin_username': 'Viewer',
        'local_media_jellyfin_access_token': 'saved-access-token-1234567890',
        'local_media_jellyfin_device_id': 'device-id-12345678',
      });
      final requestedStartIndexes = <String?>[];
      final controller = LocalMediaController(
        storage,
        JellyfinClient(
          _stubDio((request) {
            final startIndex = request.uri.queryParameters['startIndex'];
            requestedStartIndexes.add(startIndex);
            final offset = int.tryParse(startIndex ?? '') ?? 0;
            final count = offset == 0 ? 100 : 1;
            return _json(request, {
              'Items': [
                for (var index = 0; index < count; index++)
                  {
                    'Id':
                        'movie-id-${(offset + index).toString().padLeft(8, '0')}',
                    'Name': 'Movie ${offset + index}',
                    'Type': 'Movie',
                  },
              ],
              'TotalRecordCount': 101,
            });
          }),
        ),
        AndroidTvBridge.instance,
      );

      await controller.load();
      expect(controller.state.items, hasLength(100));
      expect(controller.state.totalCount, 101);

      await controller.loadMore();

      expect(requestedStartIndexes, ['0', '100']);
      expect(controller.state.items, hasLength(101));
      expect(controller.state.items.first.name, 'Movie 0');
      expect(controller.state.items.last.name, 'Movie 100');

      await controller.loadMore();
      expect(requestedStartIndexes, hasLength(2));
    },
  );

  test(
    'invalid saved server and document values are discarded safely',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'local_media_jellyfin_base_url': 'http://public.example.com:8096',
        'local_media_jellyfin_user_id': 'user-id-12345678',
        'local_media_jellyfin_username': 'Viewer',
        'local_media_jellyfin_access_token': 'saved-access-token-1234567890',
        'local_media_jellyfin_device_id': 'device-id-12345678',
        'local_media_recent_document': jsonEncode({
          'uri': 'file:///storage/emulated/0/private.mkv',
          'name': 'Unsafe path',
        }),
      });
      var requestCount = 0;
      final controller = LocalMediaController(
        storage,
        JellyfinClient(
          _stubDio((request) {
            requestCount++;
            return _json(request, const {});
          }),
        ),
        AndroidTvBridge.instance,
      );

      await controller.load();

      expect(controller.state.loaded, isTrue);
      expect(controller.state.connection, isNull);
      expect(controller.state.recentLocalDocument, isNull);
      expect(requestCount, 0);
    },
  );

  test(
    'resume checkpoints do not expose a media URL or token in storage keys',
    () async {
      final controller = LocalMediaController(
        storage,
        JellyfinClient(_stubDio((request) => _json(request, const {}))),
        AndroidTvBridge.instance,
      );
      final source = Uri.parse(
        'https://media.example.com/video.mkv?api_key=secret-token',
      );

      await controller.saveResumePosition(source, const Duration(seconds: 4));
      expect(await controller.resumePosition(source), Duration.zero);

      await controller.saveResumePosition(source, const Duration(minutes: 15));
      expect(
        await controller.resumePosition(source),
        const Duration(minutes: 15),
      );
      final persisted = await storage.readAll();
      final resumeKeys = persisted.keys
          .where((key) => key.startsWith('local_media_resume_'))
          .toList();
      expect(resumeKeys, hasLength(1));
      expect(resumeKeys.single, isNot(contains('media.example.com')));
      expect(resumeKeys.single, isNot(contains('secret-token')));
    },
  );

  test('corrupt negative resume checkpoints clamp to the beginning', () async {
    final controller = LocalMediaController(
      storage,
      JellyfinClient(_stubDio((request) => _json(request, const {}))),
      AndroidTvBridge.instance,
    );
    final source = Uri.parse('content://media/video/42');
    FlutterSecureStorage.setMockInitialValues({
      'local_media_resume_${controller.checkpointId(source)}': '-45000',
    });

    expect(await controller.resumePosition(source), Duration.zero);
  });

  test(
    'disconnect removes the account token while preserving device identity',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'local_media_jellyfin_base_url': 'http://192.168.1.25:8096/jellyfin',
        'local_media_jellyfin_server_name': 'Living Room',
        'local_media_jellyfin_server_version': '10.10.7',
        'local_media_jellyfin_user_id': 'user-id-12345678',
        'local_media_jellyfin_username': 'Viewer',
        'local_media_jellyfin_access_token': 'saved-access-token-1234567890',
        'local_media_jellyfin_device_id': 'device-id-12345678',
      });
      final controller = LocalMediaController(
        storage,
        JellyfinClient(_stubDio((request) => _json(request, const {}))),
        AndroidTvBridge.instance,
      );

      await controller.disconnect();

      final persisted = await storage.readAll();
      expect(persisted['local_media_jellyfin_access_token'], isNull);
      expect(persisted['local_media_jellyfin_user_id'], isNull);
      expect(persisted['local_media_jellyfin_device_id'], 'device-id-12345678');
      expect(controller.state.connection, isNull);
    },
  );
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
) => Response<ResponseBody>(
  requestOptions: request,
  statusCode: 200,
  data: ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: const {
      Headers.contentTypeHeader: ['application/json'],
    },
  ),
);
