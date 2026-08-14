import 'dart:typed_data';

import 'package:anime_tv/features/local_media/application/plex_controller.dart';
import 'package:anime_tv/features/local_media/data/plex_client.dart';
import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  test('connect validates Plex and persists only the secure session', () async {
    final client = _FakePlexClient();
    final controller = PlexController(storage, client);
    addTearDown(controller.dispose);

    await controller.connect(
      address: 'https://plex.example.com/base',
      token: _token,
    );

    expect(controller.state.busy, isFalse);
    expect(controller.state.connection?.serverName, 'Living Room Plex');
    expect(controller.state.libraries, hasLength(2));
    final saved = await storage.readAll();
    expect(saved['local_media_plex_access_token'], _token);
    expect(saved['local_media_plex_base_url'], 'https://plex.example.com/base');
    expect(saved['local_media_plex_client_identifier'], hasLength(48));
    expect(saved.values, isNot(contains('X-Plex-Token=$_token')));
  });

  test(
    'restores, browses libraries through episodes, and appends pages',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'local_media_plex_base_url': 'http://192.168.1.25:32400/plex',
        'local_media_plex_access_token': _token,
        'local_media_plex_client_identifier': _clientIdentifier,
        'local_media_plex_server_name': 'Living Room Plex',
        'local_media_plex_machine_identifier': 'machine-12345678',
        'local_media_plex_server_version': '1.41.4',
      });
      final client = _FakePlexClient();
      final controller = PlexController(storage, client);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.connection?.accessToken, _token);
      expect(controller.state.libraries, hasLength(2));

      await controller.openLibrary(client.librariesValue[1]);
      expect(controller.state.items.map((item) => item.title), [
        'Show One',
        'Show Two',
      ]);
      expect(controller.state.totalCount, 3);
      expect(controller.state.nextOffset, 2);

      await controller.loadMore();
      expect(client.libraryStarts, [0, 2]);
      expect(controller.state.items.map((item) => item.title), [
        'Show One',
        'Show Two',
        'Show Three',
      ]);

      await controller.openFolder(controller.state.items.first);
      expect(controller.state.items.single.type, PlexMediaType.season);
      await controller.openFolder(controller.state.items.single);
      final episode = controller.state.items.single;
      expect(episode.type, PlexMediaType.episode);
      expect(controller.playbackUri(episode).query, isEmpty);
      expect(controller.playbackHeaders()['X-Plex-Token'], _token);
      expect(controller.playbackHeaders(), isNot(contains('Accept')));

      await controller.goUp();
      expect(controller.state.items.single.type, PlexMediaType.season);
      await controller.goUp();
      expect(controller.state.items.first.type, PlexMediaType.show);
      await controller.goUp();
      expect(controller.state.locations, isEmpty);
      expect(controller.state.libraries, hasLength(2));
    },
  );

  test('empty malformed pages stop pagination instead of looping', () async {
    final client = _FakePlexClient(stalledPage: true);
    final controller = PlexController(storage, client);
    addTearDown(controller.dispose);
    await controller.connect(
      address: 'https://plex.example.com',
      token: _token,
    );

    await controller.openLibrary(client.librariesValue[1]);

    expect(controller.state.items, isEmpty);
    expect(controller.state.nextOffset, controller.state.totalCount);
    await controller.loadMore();
    expect(client.libraryStarts, [0]);
  });

  test(
    'disconnect removes the Plex token but preserves device identity',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'local_media_plex_base_url': 'http://192.168.1.25:32400/plex',
        'local_media_plex_access_token': _token,
        'local_media_plex_client_identifier': _clientIdentifier,
        'local_media_plex_server_name': 'Living Room Plex',
        'local_media_plex_machine_identifier': 'machine-12345678',
        'local_media_plex_server_version': '1.41.4',
      });
      final controller = PlexController(storage, _FakePlexClient());
      addTearDown(controller.dispose);

      await controller.disconnect();

      final saved = await storage.readAll();
      expect(saved['local_media_plex_access_token'], isNull);
      expect(saved['local_media_plex_base_url'], isNull);
      expect(saved['local_media_plex_client_identifier'], _clientIdentifier);
      expect(controller.state.connection, isNull);
    },
  );
}

const _token = 'plex-access-token-123456';
const _clientIdentifier = 'tetotv-client-123456';

class _FakePlexClient extends PlexClient {
  _FakePlexClient({this.stalledPage = false});

  final bool stalledPage;
  final libraryStarts = <int>[];

  final librariesValue = const [
    PlexLibrary(key: '1', title: 'Movies', type: PlexMediaType.movie),
    PlexLibrary(key: '2', title: 'TV Shows', type: PlexMediaType.show),
  ];

  @override
  Future<PlexServerIdentity> serverIdentity(PlexConnection connection) async =>
      const PlexServerIdentity(
        name: 'Living Room Plex',
        machineIdentifier: 'machine-12345678',
        version: '1.41.4',
      );

  @override
  Future<List<PlexLibrary>> libraries(PlexConnection connection) async =>
      librariesValue;

  @override
  Future<PlexPage<PlexMediaItem>> libraryItems(
    PlexConnection connection,
    PlexLibrary library, {
    int start = 0,
    int size = 100,
  }) async {
    libraryStarts.add(start);
    if (stalledPage) {
      return const PlexPage(
        items: [],
        totalCount: 10,
        offset: 0,
        nextOffset: 0,
      );
    }
    if (library.isMovieLibrary) {
      return const PlexPage(
        items: [_movie],
        totalCount: 1,
        offset: 0,
        nextOffset: 1,
      );
    }
    return start == 0
        ? const PlexPage(
            items: [_showOne, _showTwo],
            totalCount: 3,
            offset: 0,
            nextOffset: 2,
          )
        : const PlexPage(
            items: [_showThree],
            totalCount: 3,
            offset: 2,
            nextOffset: 3,
          );
  }

  @override
  Future<PlexPage<PlexMediaItem>> children(
    PlexConnection connection,
    PlexMediaItem item, {
    int start = 0,
    int size = 100,
  }) async => item.type == PlexMediaType.show
      ? const PlexPage(
          items: [_season],
          totalCount: 1,
          offset: 0,
          nextOffset: 1,
        )
      : const PlexPage(
          items: [_episode],
          totalCount: 1,
          offset: 0,
          nextOffset: 1,
        );

  @override
  Uri playbackUri(
    PlexConnection connection,
    PlexMediaItem item, {
    PlexMediaPart? part,
  }) => Uri.parse('${connection.baseUri}/library/parts/500/file.mkv');

  @override
  Map<String, String> authenticatedHeaders(PlexConnection connection) => {
    'X-Plex-Client-Identifier': connection.clientIdentifier,
    'X-Plex-Token': connection.accessToken,
  };

  @override
  Future<Uint8List> imageBytes(PlexConnection connection, Uri uri) async =>
      Uint8List.fromList(const [1]);
}

const _showOne = PlexMediaItem(
  ratingKey: 'show-1',
  key: '/library/metadata/show-1/children',
  title: 'Show One',
  type: PlexMediaType.show,
);
const _showTwo = PlexMediaItem(
  ratingKey: 'show-2',
  key: '/library/metadata/show-2/children',
  title: 'Show Two',
  type: PlexMediaType.show,
);
const _showThree = PlexMediaItem(
  ratingKey: 'show-3',
  key: '/library/metadata/show-3/children',
  title: 'Show Three',
  type: PlexMediaType.show,
);
const _season = PlexMediaItem(
  ratingKey: 'season-1',
  key: '/library/metadata/season-1/children',
  title: 'Season 1',
  type: PlexMediaType.season,
);
const _episode = PlexMediaItem(
  ratingKey: 'episode-1',
  key: '/library/metadata/episode-1',
  title: 'Pilot',
  type: PlexMediaType.episode,
  grandparentTitle: 'Show One',
  parentIndex: 1,
  index: 1,
  parts: [PlexMediaPart(key: '/library/parts/500/file.mkv')],
);
const _movie = PlexMediaItem(
  ratingKey: 'movie-1',
  key: '/library/metadata/movie-1',
  title: 'Movie One',
  type: PlexMediaType.movie,
  parts: [PlexMediaPart(key: '/library/parts/600/file.mkv')],
);
