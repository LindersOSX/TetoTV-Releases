import 'dart:convert';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/local_media/application/local_media_controller.dart';
import 'package:anime_tv/features/local_media/application/plex_controller.dart';
import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:anime_tv/features/local_media/data/plex_client.dart';
import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:anime_tv/features/local_media/presentation/local_media_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  const androidChannel = MethodChannel('dev.tetotv/android_tv');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  testWidgets(
    'Plex browse uses bounded byte artwork and sends token only as playback header',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Map<Object?, Object?>? playerArguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (call) async {
            if (call.method == 'startNativePlayer') {
              playerArguments = (call.arguments as Map)
                  .cast<Object?, Object?>();
              return <String, Object?>{
                'status': 'exit',
                'positionMs': 0,
                'durationMs': 0,
              };
            }
            return null;
          });

      final localController = LocalMediaController(
        storage,
        JellyfinClient(),
        AndroidTvBridge.instance,
      );
      await localController.load();
      final plexClient = _ScreenPlexClient();
      final plexController = PlexController(storage, plexClient);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        FlutterSecureStorage.setMockInitialValues({});
      });
      await plexController.connect(
        address: 'https://plex.example.com/base',
        token: _token,
      );
      await plexController.openLibrary(plexClient.library);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localMediaControllerProvider.overrideWith((_) => localController),
            plexControllerProvider.overrideWith((_) => plexController),
          ],
          child: const MaterialApp(home: LocalMediaScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final outerScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('plex-item-movie-1')),
        250,
        scrollable: outerScroll,
      );
      await tester.pumpAndSettle();

      expect(find.text('Movie One'), findsOneWidget);
      expect(plexClient.loadedImages, [
        Uri.parse(
          'https://plex.example.com/base/library/metadata/movie-1/thumb/1',
        ),
      ]);
      final plexImages = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byKey(const ValueKey('plex-item-movie-1')),
              matching: find.byType(Image),
            ),
          )
          .toList();
      expect(plexImages, hasLength(1));
      expect(_isMemoryImage(plexImages.single.image), isTrue);
      final networkImages = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => _networkImage(image.image))
          .whereType<NetworkImage>();
      expect(
        networkImages.every((image) => image.headers?['X-Plex-Token'] == null),
        isTrue,
      );

      await tester.tap(find.text('Movie One'));
      await tester.pumpAndSettle();

      expect(playerArguments, isNotNull);
      expect(
        playerArguments!['source'],
        'https://plex.example.com/base/library/parts/600/file.mkv',
      );
      expect(playerArguments!['source'].toString(), isNot(contains(_token)));
      final headers = (playerArguments!['headers'] as Map)
          .cast<String, String>();
      expect(headers['X-Plex-Token'], _token);
      expect(headers, isNot(contains('Accept')));
      expect(playerArguments!['trustedLocalSource'], isTrue);
      expect(playerArguments, isNot(contains('artworkUrl')));
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

NetworkImage? _networkImage(ImageProvider provider) => switch (provider) {
  NetworkImage value => value,
  ResizeImage value => _networkImage(value.imageProvider),
  _ => null,
};

bool _isMemoryImage(ImageProvider provider) => switch (provider) {
  MemoryImage _ => true,
  ResizeImage value => _isMemoryImage(value.imageProvider),
  _ => false,
};

const _token = 'plex-access-token-123456';

class _ScreenPlexClient extends PlexClient {
  final loadedImages = <Uri>[];

  final library = const PlexLibrary(
    key: '1',
    title: 'Movies',
    type: PlexMediaType.movie,
  );

  @override
  Future<PlexServerIdentity> serverIdentity(PlexConnection connection) async =>
      const PlexServerIdentity(
        name: 'Living Room Plex',
        machineIdentifier: 'machine-12345678',
        version: '1.41.4',
      );

  @override
  Future<List<PlexLibrary>> libraries(PlexConnection connection) async => [
    library,
  ];

  @override
  Future<PlexPage<PlexMediaItem>> libraryItems(
    PlexConnection connection,
    PlexLibrary library, {
    int start = 0,
    int size = 100,
  }) async => const PlexPage(
    items: [
      PlexMediaItem(
        ratingKey: 'movie-1',
        key: '/library/metadata/movie-1',
        title: 'Movie One',
        type: PlexMediaType.movie,
        year: 2026,
        thumb: '/library/metadata/movie-1/thumb/1',
        parts: [PlexMediaPart(key: '/library/parts/600/file.mkv')],
      ),
    ],
    totalCount: 1,
    offset: 0,
    nextOffset: 1,
  );

  @override
  Future<Uint8List> imageBytes(PlexConnection connection, Uri uri) async {
    loadedImages.add(uri);
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  }
}
