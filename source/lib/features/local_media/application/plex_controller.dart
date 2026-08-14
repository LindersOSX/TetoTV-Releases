import 'dart:math';
import 'dart:typed_data';

import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/local_media/data/plex_client.dart';
import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _plexBaseUrlKey = 'local_media_plex_base_url';
const _plexAccessTokenKey = 'local_media_plex_access_token';
const _plexClientIdentifierKey = 'local_media_plex_client_identifier';
const _plexServerNameKey = 'local_media_plex_server_name';
const _plexMachineIdentifierKey = 'local_media_plex_machine_identifier';
const _plexServerVersionKey = 'local_media_plex_server_version';

final plexClientProvider = Provider<PlexClient>((_) => PlexClient());

final plexControllerProvider = StateNotifierProvider<PlexController, PlexState>(
  (ref) {
    final controller = PlexController(
      ref.watch(secureStorageProvider),
      ref.watch(plexClientProvider),
    );
    Future.microtask(controller.load);
    return controller;
  },
);

class PlexLocation {
  PlexLocation.library(PlexLibrary value)
    : library = value,
      item = null,
      label = value.title;

  PlexLocation.item(PlexMediaItem value)
    : item = value,
      library = null,
      label = value.title;

  final PlexLibrary? library;
  final PlexMediaItem? item;
  final String label;
}

class PlexState {
  const PlexState({
    this.loaded = false,
    this.busy = false,
    this.connection,
    this.libraries = const [],
    this.items = const [],
    this.locations = const [],
    this.totalCount = 0,
    this.nextOffset = 0,
    this.message,
  });

  final bool loaded;
  final bool busy;
  final PlexConnection? connection;
  final List<PlexLibrary> libraries;
  final List<PlexMediaItem> items;
  final List<PlexLocation> locations;
  final int totalCount;
  final int nextOffset;
  final String? message;

  PlexState copyWith({
    bool? loaded,
    bool? busy,
    Object? connection = _unset,
    List<PlexLibrary>? libraries,
    List<PlexMediaItem>? items,
    List<PlexLocation>? locations,
    int? totalCount,
    int? nextOffset,
    Object? message = _unset,
  }) => PlexState(
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    connection: identical(connection, _unset)
        ? this.connection
        : connection as PlexConnection?,
    libraries: libraries ?? this.libraries,
    items: items ?? this.items,
    locations: locations ?? this.locations,
    totalCount: totalCount ?? this.totalCount,
    nextOffset: nextOffset ?? this.nextOffset,
    message: identical(message, _unset) ? this.message : message as String?,
  );
}

const _unset = Object();

class PlexController extends StateNotifier<PlexState> {
  PlexController(this._storage, this._client) : super(const PlexState());

  final FlutterSecureStorage _storage;
  final PlexClient _client;
  int _generation = 0;
  bool _disposed = false;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final values = await Future.wait([
        _storage.read(key: _plexBaseUrlKey),
        _storage.read(key: _plexAccessTokenKey),
        _storage.read(key: _plexClientIdentifierKey),
        _storage.read(key: _plexServerNameKey),
        _storage.read(key: _plexMachineIdentifierKey),
        _storage.read(key: _plexServerVersionKey),
      ]);
      if (!_isCurrent(generation)) return;
      final baseUri = normalizePlexServerUri(values[0] ?? '');
      final token = values[1]?.trim() ?? '';
      final clientIdentifier = values[2]?.trim() ?? '';
      final connection =
          baseUri == null || token.length < 8 || clientIdentifier.length < 8
          ? null
          : PlexConnection(
              baseUri: baseUri,
              accessToken: token,
              clientIdentifier: clientIdentifier,
              serverName: values[3],
              machineIdentifier: values[4],
              serverVersion: values[5],
            );
      state = state.copyWith(
        loaded: true,
        connection: connection,
        message: null,
      );
      if (connection != null) await refreshLibraries();
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        loaded: true,
        message: 'Saved Plex settings could not be loaded.',
      );
    }
  }

  Future<void> connect({required String address, required String token}) async {
    if (_disposed || state.busy) return;
    final baseUri = normalizePlexServerUri(address);
    final cleanToken = token.trim();
    if (baseUri == null) {
      state = state.copyWith(
        message:
            'Use an HTTPS Plex address, or an HTTP address on your private network.',
      );
      return;
    }
    if (cleanToken.length < 8 || cleanToken.length > 4096) {
      state = state.copyWith(message: 'Enter a valid Plex access token.');
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(busy: true, message: 'Connecting to Plex…');
    try {
      final clientIdentifier = await _clientIdentifier();
      if (!_isCurrent(generation)) return;
      var connection = PlexConnection(
        baseUri: baseUri,
        accessToken: cleanToken,
        clientIdentifier: clientIdentifier,
      );
      final identity = await _client.serverIdentity(connection);
      if (!_isCurrent(generation)) return;
      connection = connection.copyWith(
        serverName: identity.name,
        machineIdentifier: identity.machineIdentifier,
        serverVersion: identity.version,
      );
      final libraries = await _client.libraries(connection);
      if (!_isCurrent(generation)) return;
      await _persist(connection);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        busy: false,
        connection: connection,
        libraries: libraries,
        items: const [],
        locations: const [],
        totalCount: libraries.length,
        nextOffset: libraries.length,
        message: 'Connected to ${identity.name}.',
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(message: _friendlyError(error));
    } finally {
      if (_isCurrent(generation)) state = state.copyWith(busy: false);
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    ++_generation;
    await Future.wait([
      for (final key in const [
        _plexBaseUrlKey,
        _plexAccessTokenKey,
        _plexServerNameKey,
        _plexMachineIdentifierKey,
        _plexServerVersionKey,
      ])
        _storage.delete(key: key),
    ]);
    state = state.copyWith(
      busy: false,
      connection: null,
      libraries: const [],
      items: const [],
      locations: const [],
      totalCount: 0,
      nextOffset: 0,
      message: 'Plex disconnected.',
    );
  }

  Future<void> refreshLibraries() async {
    final connection = state.connection;
    if (_disposed || connection == null || state.busy) return;
    final generation = ++_generation;
    state = state.copyWith(busy: true, message: 'Loading Plex libraries…');
    try {
      final libraries = await _client.libraries(connection);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        libraries: libraries,
        items: const [],
        locations: const [],
        totalCount: libraries.length,
        nextOffset: libraries.length,
        message: libraries.isEmpty
            ? 'No movie or TV libraries were found.'
            : null,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(message: _friendlyError(error));
    } finally {
      if (_isCurrent(generation)) state = state.copyWith(busy: false);
    }
  }

  Future<void> openLibrary(PlexLibrary library) =>
      _loadLocation(locations: [PlexLocation.library(library)], append: false);

  Future<void> refresh() => state.locations.isEmpty
      ? refreshLibraries()
      : _loadLocation(locations: state.locations, append: false);

  Future<void> openFolder(PlexMediaItem item) {
    if (!item.isFolder || state.locations.isEmpty) return Future.value();
    return _loadLocation(
      locations: [...state.locations, PlexLocation.item(item)],
      append: false,
    );
  }

  Future<void> goUp() {
    if (state.locations.isEmpty) return Future.value();
    if (state.locations.length == 1) return refreshLibraries();
    return _loadLocation(
      locations: state.locations.sublist(0, state.locations.length - 1),
      append: false,
    );
  }

  Future<void> loadMore() {
    if (state.locations.isEmpty || state.nextOffset >= state.totalCount) {
      return Future.value();
    }
    return _loadLocation(locations: state.locations, append: true);
  }

  Uri playbackUri(PlexMediaItem item) {
    final connection = state.connection;
    if (connection == null) {
      throw const PlexException('Connect Plex before playing media.');
    }
    return _client.playbackUri(connection, item);
  }

  Uri? imageUri(PlexMediaItem item) {
    final connection = state.connection;
    return connection == null ? null : _client.imageUri(connection, item);
  }

  Uri? libraryImageUri(PlexLibrary library) {
    final connection = state.connection;
    return connection == null
        ? null
        : _client.libraryImageUri(connection, library);
  }

  Map<String, String> playbackHeaders() {
    final connection = state.connection;
    return connection == null
        ? const {}
        : _client.authenticatedHeaders(connection);
  }

  Future<Uint8List> imageBytes(Uri uri) {
    final connection = state.connection;
    if (connection == null) {
      throw const PlexException('Connect Plex before loading artwork.');
    }
    return _client.imageBytes(connection, uri);
  }

  Future<void> _loadLocation({
    required List<PlexLocation> locations,
    required bool append,
  }) async {
    final connection = state.connection;
    if (_disposed || connection == null || state.busy || locations.isEmpty) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(busy: true, message: 'Loading Plex library…');
    try {
      final last = locations.last;
      final start = append ? state.nextOffset : 0;
      final page = last.library != null
          ? await _client.libraryItems(connection, last.library!, start: start)
          : await _client.children(connection, last.item!, start: start);
      if (!_isCurrent(generation)) return;
      final nextOffset =
          page.nextOffset <= start && page.totalCount > page.nextOffset
          ? page.totalCount
          : page.nextOffset;
      state = state.copyWith(
        items: append
            ? List.unmodifiable([...state.items, ...page.items])
            : page.items,
        locations: List.unmodifiable(locations),
        totalCount: page.totalCount,
        nextOffset: nextOffset,
        message: page.items.isEmpty ? 'This Plex folder is empty.' : null,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(message: _friendlyError(error));
    } finally {
      if (_isCurrent(generation)) state = state.copyWith(busy: false);
    }
  }

  Future<String> _clientIdentifier() async {
    final saved = await _storage.read(key: _plexClientIdentifierKey);
    if (saved?.isNotEmpty == true) return saved!;
    final random = Random.secure();
    final value = List<int>.generate(
      24,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _plexClientIdentifierKey, value: value);
    return value;
  }

  Future<void> _persist(PlexConnection connection) => Future.wait([
    _storage.write(key: _plexBaseUrlKey, value: connection.baseUri.toString()),
    _storage.write(key: _plexAccessTokenKey, value: connection.accessToken),
    _storage.write(
      key: _plexClientIdentifierKey,
      value: connection.clientIdentifier,
    ),
    _storage.write(
      key: _plexServerNameKey,
      value: connection.serverName ?? 'Plex Media Server',
    ),
    _storage.write(
      key: _plexMachineIdentifierKey,
      value: connection.machineIdentifier ?? '',
    ),
    _storage.write(
      key: _plexServerVersionKey,
      value: connection.serverVersion ?? 'unknown',
    ),
  ]);

  static String _friendlyError(Object error) => switch (error) {
    PlexException(:final message) => message,
    _ => 'TetoTV could not open that Plex server.',
  };
}
