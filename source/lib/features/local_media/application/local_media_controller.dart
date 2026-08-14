import 'dart:convert';
import 'dart:math';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:anime_tv/features/local_media/domain/jellyfin_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _jellyfinBaseUrlKey = 'local_media_jellyfin_base_url';
const _jellyfinServerNameKey = 'local_media_jellyfin_server_name';
const _jellyfinServerVersionKey = 'local_media_jellyfin_server_version';
const _jellyfinUserIdKey = 'local_media_jellyfin_user_id';
const _jellyfinUsernameKey = 'local_media_jellyfin_username';
const _jellyfinAccessTokenKey = 'local_media_jellyfin_access_token';
const _jellyfinDeviceIdKey = 'local_media_jellyfin_device_id';
const _recentLocalDocumentKey = 'local_media_recent_document';
const _localResumePrefix = 'local_media_resume_';

final jellyfinClientProvider = Provider<JellyfinClient>(
  (_) => JellyfinClient(),
);

final localMediaControllerProvider =
    StateNotifierProvider<LocalMediaController, LocalMediaState>((ref) {
      final controller = LocalMediaController(
        ref.watch(secureStorageProvider),
        ref.watch(jellyfinClientProvider),
        AndroidTvBridge.instance,
      );
      Future.microtask(controller.load);
      return controller;
    });

class JellyfinBreadcrumb {
  const JellyfinBreadcrumb({required this.id, required this.name});

  final String id;
  final String name;
}

class LocalMediaState {
  const LocalMediaState({
    this.loaded = false,
    this.busy = false,
    this.connection,
    this.items = const [],
    this.breadcrumbs = const [],
    this.totalCount = 0,
    this.nextStartIndex = 0,
    this.recentLocalDocument,
    this.message,
  });

  final bool loaded;
  final bool busy;
  final JellyfinConnection? connection;
  final List<JellyfinMediaItem> items;
  final List<JellyfinBreadcrumb> breadcrumbs;
  final int totalCount;
  final int nextStartIndex;
  final LocalMediaDocument? recentLocalDocument;
  final String? message;

  LocalMediaState copyWith({
    bool? loaded,
    bool? busy,
    Object? connection = _unset,
    List<JellyfinMediaItem>? items,
    List<JellyfinBreadcrumb>? breadcrumbs,
    int? totalCount,
    int? nextStartIndex,
    Object? recentLocalDocument = _unset,
    Object? message = _unset,
  }) => LocalMediaState(
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    connection: identical(connection, _unset)
        ? this.connection
        : connection as JellyfinConnection?,
    items: items ?? this.items,
    breadcrumbs: breadcrumbs ?? this.breadcrumbs,
    totalCount: totalCount ?? this.totalCount,
    nextStartIndex: nextStartIndex ?? this.nextStartIndex,
    recentLocalDocument: identical(recentLocalDocument, _unset)
        ? this.recentLocalDocument
        : recentLocalDocument as LocalMediaDocument?,
    message: identical(message, _unset) ? this.message : message as String?,
  );
}

const _unset = Object();

class LocalMediaController extends StateNotifier<LocalMediaState> {
  LocalMediaController(this._storage, this._client, this._bridge)
    : super(const LocalMediaState());

  final FlutterSecureStorage _storage;
  final JellyfinClient _client;
  final AndroidTvBridge _bridge;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final values = await Future.wait([
        _storage.read(key: _jellyfinBaseUrlKey),
        _storage.read(key: _jellyfinServerNameKey),
        _storage.read(key: _jellyfinServerVersionKey),
        _storage.read(key: _jellyfinUserIdKey),
        _storage.read(key: _jellyfinUsernameKey),
        _storage.read(key: _jellyfinAccessTokenKey),
        _storage.read(key: _jellyfinDeviceIdKey),
        _storage.read(key: _recentLocalDocumentKey),
      ]);
      if (generation != _generation) return;
      final baseUri = normalizeJellyfinServerUri(values[0] ?? '');
      final connection =
          baseUri == null ||
              values[3]?.isNotEmpty != true ||
              values[4]?.isNotEmpty != true ||
              values[5]?.isNotEmpty != true ||
              values[6]?.isNotEmpty != true
          ? null
          : JellyfinConnection(
              baseUri: baseUri,
              serverName: values[1]?.trim().isNotEmpty == true
                  ? values[1]!.trim()
                  : 'Jellyfin',
              serverVersion: values[2]?.trim().isNotEmpty == true
                  ? values[2]!.trim()
                  : 'unknown',
              userId: values[3]!,
              username: values[4]!,
              accessToken: values[5]!,
              deviceId: values[6]!,
            );
      state = state.copyWith(
        loaded: true,
        connection: connection,
        recentLocalDocument: _decodeDocument(values[7]),
        message: null,
      );
      if (connection != null) await refresh();
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(
        loaded: true,
        message: 'Saved local-media settings could not be loaded.',
      );
    }
  }

  Future<LocalMediaDocument?> pickLocalVideo() async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, message: null);
    try {
      final document = await _bridge.pickLocalVideo();
      if (document == null) return null;
      if (document.persistedReadPermission) {
        await _storage.write(
          key: _recentLocalDocumentKey,
          value: jsonEncode({
            'uri': document.uri.toString(),
            'name': document.name,
            'mimeType': document.mimeType,
            'size': document.size,
            'persistedReadPermission': true,
          }),
        );
      } else {
        await _storage.delete(key: _recentLocalDocumentKey);
      }
      state = state.copyWith(recentLocalDocument: document);
      if (!document.persistedReadPermission) {
        state = state.copyWith(
          message: 'This file provider grants access only until TetoTV closes.',
        );
      }
      return document;
    } catch (error) {
      state = state.copyWith(message: _friendlyError(error));
      return null;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> connect({
    required String address,
    required String username,
    required String password,
  }) async {
    if (state.busy) return;
    final baseUri = normalizeJellyfinServerUri(address);
    if (baseUri == null) {
      state = state.copyWith(
        message:
            'Use an HTTPS Jellyfin address, or an HTTP address on your private network.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(busy: true, message: 'Connecting to Jellyfin…');
    try {
      final deviceId = await _deviceId();
      final connection = await _client.authenticate(
        baseUri: baseUri,
        username: username,
        password: password,
        deviceId: deviceId,
      );
      if (generation != _generation) return;
      await _persistConnection(connection);
      state = state.copyWith(
        busy: false,
        connection: connection,
        items: const [],
        breadcrumbs: const [],
        totalCount: 0,
        nextStartIndex: 0,
        message: 'Connected to ${connection.serverName}.',
      );
      await refresh();
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(message: _friendlyError(error));
    } finally {
      if (generation == _generation) state = state.copyWith(busy: false);
    }
  }

  Future<void> disconnect() async {
    ++_generation;
    final connection = state.connection;
    if (connection != null) {
      try {
        await _client.logout(connection);
      } catch (_) {
        // Local unlink must remain available while the server is offline.
      }
    }
    await Future.wait([
      for (final key in const [
        _jellyfinBaseUrlKey,
        _jellyfinServerNameKey,
        _jellyfinServerVersionKey,
        _jellyfinUserIdKey,
        _jellyfinUsernameKey,
        _jellyfinAccessTokenKey,
      ])
        _storage.delete(key: key),
    ]);
    state = state.copyWith(
      busy: false,
      connection: null,
      items: const [],
      breadcrumbs: const [],
      totalCount: 0,
      nextStartIndex: 0,
      message: 'Jellyfin disconnected.',
    );
  }

  Future<void> refresh() => _loadItems(
    parentId: state.breadcrumbs.isEmpty ? null : state.breadcrumbs.last.id,
    breadcrumbs: state.breadcrumbs,
  );

  Future<void> loadMore() {
    if (state.nextStartIndex >= state.totalCount) return Future.value();
    return _loadItems(
      parentId: state.breadcrumbs.isEmpty ? null : state.breadcrumbs.last.id,
      breadcrumbs: state.breadcrumbs,
      append: true,
    );
  }

  Future<void> openFolder(JellyfinMediaItem item) {
    if (!item.isFolder) return Future.value();
    return _loadItems(
      parentId: item.id,
      breadcrumbs: [
        ...state.breadcrumbs,
        JellyfinBreadcrumb(id: item.id, name: item.name),
      ],
    );
  }

  Future<void> goUp() {
    if (state.breadcrumbs.isEmpty) return Future.value();
    final breadcrumbs = state.breadcrumbs.sublist(
      0,
      state.breadcrumbs.length - 1,
    );
    return _loadItems(
      parentId: breadcrumbs.isEmpty ? null : breadcrumbs.last.id,
      breadcrumbs: breadcrumbs,
    );
  }

  Uri streamUri(JellyfinMediaItem item) {
    final connection = state.connection;
    if (connection == null) {
      throw const JellyfinException('Connect Jellyfin before playing media.');
    }
    return _client.streamUri(connection, item);
  }

  Uri? imageUri(JellyfinMediaItem item) {
    final connection = state.connection;
    return connection == null ? null : _client.imageUri(connection, item);
  }

  Map<String, String> playbackHeaders() {
    final connection = state.connection;
    return connection == null ? const {} : _client.playbackHeaders(connection);
  }

  Future<Duration> resumePosition(Uri uri) async {
    final value = await _storage.read(key: _resumeKey(uri));
    return Duration(
      milliseconds: (int.tryParse(value ?? '') ?? 0).clamp(0, 1 << 53),
    );
  }

  Future<void> saveResumePosition(Uri uri, Duration position) async {
    if (position < const Duration(seconds: 5)) return;
    await _storage.write(
      key: _resumeKey(uri),
      value: position.inMilliseconds.toString(),
    );
  }

  Future<void> clearResumePosition(Uri uri) =>
      _storage.delete(key: _resumeKey(uri));

  String checkpointId(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  Future<void> _loadItems({
    required String? parentId,
    required List<JellyfinBreadcrumb> breadcrumbs,
    bool append = false,
  }) async {
    final connection = state.connection;
    if (connection == null || state.busy) return;
    final generation = ++_generation;
    state = state.copyWith(busy: true, message: 'Loading Jellyfin library…');
    try {
      final page = await _client.items(
        connection,
        parentId: parentId,
        startIndex: append ? state.nextStartIndex : 0,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        items: append
            ? List.unmodifiable([...state.items, ...page.items])
            : page.items,
        breadcrumbs: List.unmodifiable(breadcrumbs),
        totalCount: page.totalCount,
        nextStartIndex: page.nextStartIndex,
        message: page.items.isEmpty ? 'This Jellyfin folder is empty.' : null,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(message: _friendlyError(error));
    } finally {
      if (generation == _generation) state = state.copyWith(busy: false);
    }
  }

  Future<String> _deviceId() async {
    final saved = await _storage.read(key: _jellyfinDeviceIdKey);
    if (saved?.isNotEmpty == true) return saved!;
    final random = Random.secure();
    final value = List<int>.generate(
      24,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _jellyfinDeviceIdKey, value: value);
    return value;
  }

  Future<void> _persistConnection(JellyfinConnection connection) async {
    await Future.wait([
      _storage.write(
        key: _jellyfinBaseUrlKey,
        value: connection.baseUri.toString(),
      ),
      _storage.write(key: _jellyfinServerNameKey, value: connection.serverName),
      _storage.write(
        key: _jellyfinServerVersionKey,
        value: connection.serverVersion,
      ),
      _storage.write(key: _jellyfinUserIdKey, value: connection.userId),
      _storage.write(key: _jellyfinUsernameKey, value: connection.username),
      _storage.write(
        key: _jellyfinAccessTokenKey,
        value: connection.accessToken,
      ),
      _storage.write(key: _jellyfinDeviceIdKey, value: connection.deviceId),
    ]);
  }

  static LocalMediaDocument? _decodeDocument(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final document = LocalMediaDocument.fromMap(
        decoded.cast<Object?, Object?>(),
      );
      return document.persistedReadPermission ? document : null;
    } catch (_) {
      return null;
    }
  }

  static String _resumeKey(Uri uri) =>
      '$_localResumePrefix${sha256.convert(utf8.encode(uri.toString()))}';

  static String _friendlyError(Object error) => switch (error) {
    JellyfinException(:final message) => message,
    _ => 'Local media could not be opened on this device.',
  };
}
