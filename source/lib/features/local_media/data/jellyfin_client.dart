import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anime_tv/features/local_media/domain/jellyfin_models.dart';
import 'package:dio/dio.dart';

const _maxJellyfinResponseBytes = 4 * 1024 * 1024;

Uri? normalizeJellyfinServerUri(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final withScheme = raw.contains('://') ? raw : 'http://$raw';
  final parsed = Uri.tryParse(withScheme);
  if (parsed == null ||
      !const {'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.hasQuery ||
      parsed.hasFragment ||
      parsed.port <= 0 ||
      parsed.port > 65535) {
    return null;
  }
  if (parsed.scheme.toLowerCase() == 'http' &&
      !isPrivateJellyfinHost(parsed.host)) {
    return null;
  }
  final path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
  return parsed.replace(
    scheme: parsed.scheme.toLowerCase(),
    host: parsed.host.toLowerCase(),
    path: path,
    query: null,
    fragment: null,
  );
}

bool isPrivateJellyfinHost(String input) {
  final host = input.trim().toLowerCase();
  if (host == 'localhost') return true;
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  final bytes = address.rawAddress;
  if (address.isMulticast || bytes.every((byte) => byte == 0)) return false;
  if (address.isLoopback || address.isLinkLocal) {
    return true;
  }
  if (bytes.length == 4) {
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
  return bytes.isNotEmpty &&
      ((bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80));
}

class JellyfinClient {
  JellyfinClient([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 10),
              followRedirects: false,
              maxRedirects: 0,
              responseType: ResponseType.json,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<JellyfinServerInfo> publicInfo(Uri baseUri) async {
    final response = await _request(
      baseUri.resolve('${_basePath(baseUri)}/System/Info/Public'),
    );
    final data = _map(response);
    return JellyfinServerInfo(
      name: _bounded(data['ServerName'], 1, 200) ?? 'Jellyfin',
      version: _bounded(data['Version'], 1, 80) ?? 'unknown',
      id: _bounded(data['Id'], 1, 160) ?? '',
    );
  }

  Future<JellyfinConnection> authenticate({
    required Uri baseUri,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || cleanUsername.length > 200) {
      throw const JellyfinException('Enter a valid Jellyfin username.');
    }
    final server = await publicInfo(baseUri);
    final response = await _request(
      baseUri.resolve('${_basePath(baseUri)}/Users/AuthenticateByName'),
      method: 'POST',
      data: {'Username': cleanUsername, 'Pw': password},
      headers: {'Authorization': _authorization(deviceId: deviceId)},
    );
    final data = _map(response);
    final token = _bounded(data['AccessToken'], 16, 4096);
    final user = _map(data['User']);
    final userId = _bounded(user['Id'], 8, 160);
    final returnedUsername = _bounded(user['Name'], 1, 200) ?? cleanUsername;
    if (token == null || userId == null) {
      throw const JellyfinException(
        'Jellyfin did not return a usable account session.',
      );
    }
    return JellyfinConnection(
      baseUri: baseUri,
      serverName: server.name,
      serverVersion: server.version,
      userId: userId,
      username: returnedUsername,
      accessToken: token,
      deviceId: deviceId,
    );
  }

  Future<JellyfinLibraryPage> items(
    JellyfinConnection connection, {
    String? parentId,
    int startIndex = 0,
  }) async {
    final response = await _request(
      connection.baseUri.resolve('${_basePath(connection.baseUri)}/Items'),
      queryParameters: {
        'userId': connection.userId,
        if (parentId?.isNotEmpty == true) 'parentId': parentId,
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'includeItemTypes':
            'CollectionFolder,Folder,Series,Season,BoxSet,Movie,Episode,Video',
        'fields': 'Overview,MediaSources,PrimaryImageAspectRatio',
        'enableImages': true,
        'enableTotalRecordCount': true,
        'startIndex': startIndex.clamp(0, 1 << 31),
        'limit': 100,
      },
      headers: _sessionHeaders(connection),
    );
    final data = _map(response);
    final rawItems = data['Items'] is List ? data['Items'] as List : const [];
    final parsed = <JellyfinMediaItem>[];
    for (final value in rawItems.whereType<Map>()) {
      final item = value.cast<Object?, Object?>();
      final id = _bounded(item['Id'], 8, 160);
      final name = _bounded(item['Name'], 1, 500);
      final type = _bounded(item['Type'], 1, 80);
      if (id == null || name == null || type == null) continue;
      final imageTags = _map(item['ImageTags']);
      final mediaSources = item['MediaSources'] is List
          ? item['MediaSources'] as List
          : const [];
      final sourceMaps = mediaSources.whereType<Map>();
      final firstSource = sourceMaps.isEmpty ? null : sourceMaps.first;
      parsed.add(
        JellyfinMediaItem(
          id: id,
          name: name,
          type: type,
          seriesName: _bounded(item['SeriesName'], 1, 500),
          seasonNumber: _integer(item['ParentIndexNumber']),
          episodeNumber: _integer(item['IndexNumber']),
          runTimeTicks: _integer(item['RunTimeTicks']),
          primaryImageTag: _bounded(imageTags['Primary'], 1, 300),
          mediaSourceId: firstSource == null
              ? null
              : _bounded(firstSource['Id'], 1, 300),
          container: firstSource == null
              ? _bounded(item['Container'], 1, 80)
              : _bounded(firstSource['Container'], 1, 80),
          overview: _bounded(item['Overview'], 1, 4000),
        ),
      );
    }
    final minimumTotal = startIndex.clamp(0, 1 << 31) + parsed.length;
    final reportedTotal = _integer(data['TotalRecordCount']) ?? minimumTotal;
    return JellyfinLibraryPage(
      items: List.unmodifiable(parsed),
      // A stale or malformed total must not hide items already returned by
      // the server, and an absurd value must not leak into the UI.
      totalCount: reportedTotal.clamp(minimumTotal, 1 << 31),
      // Advance by the raw server page, not just the valid parsed rows. A
      // malformed item must not make the next request repeat the same record.
      nextStartIndex: startIndex.clamp(0, 1 << 31) + rawItems.length,
    );
  }

  Uri streamUri(JellyfinConnection connection, JellyfinMediaItem item) {
    final path = '${_basePath(connection.baseUri)}/Videos/${item.id}/stream';
    return connection.baseUri
        .resolve(path)
        .replace(
          queryParameters: {
            'static': 'true',
            'deviceId': connection.deviceId,
            if (item.mediaSourceId?.isNotEmpty == true)
              'mediaSourceId': item.mediaSourceId!,
            if (item.container?.isNotEmpty == true)
              'container': item.container!,
          },
        );
  }

  Uri? imageUri(JellyfinConnection connection, JellyfinMediaItem item) {
    if (item.primaryImageTag == null) return null;
    final path =
        '${_basePath(connection.baseUri)}/Items/${item.id}/Images/Primary';
    return connection.baseUri
        .resolve(path)
        .replace(
          queryParameters: {
            'maxWidth': '480',
            'quality': '85',
            'tag': item.primaryImageTag!,
          },
        );
  }

  Map<String, String> playbackHeaders(JellyfinConnection connection) =>
      _sessionHeaders(connection);

  Future<void> logout(JellyfinConnection connection) async {
    await _request(
      connection.baseUri.resolve(
        '${_basePath(connection.baseUri)}/Sessions/Logout',
      ),
      method: 'POST',
      headers: _sessionHeaders(connection),
      expectedStatuses: const {200, 204},
    );
  }

  Future<Object?> _request(
    Uri uri, {
    String method = 'GET',
    Object? data,
    Map<String, Object?>? queryParameters,
    Map<String, String>? headers,
    Set<int> expectedStatuses = const {200},
  }) async {
    try {
      final requestUri = queryParameters == null
          ? uri
          : uri.replace(
              queryParameters: {
                for (final entry in queryParameters.entries)
                  if (entry.value != null) entry.key: entry.value.toString(),
              },
            );
      final response = await _dio.requestUri<ResponseBody>(
        requestUri,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          followRedirects: false,
          maxRedirects: 0,
          responseType: ResponseType.stream,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        _closeResponseBody(response.data);
        throw const JellyfinException(
          'Jellyfin rejected the username, password, or saved session.',
        );
      }
      if (status >= 300 && status < 400) {
        _closeResponseBody(response.data);
        throw const JellyfinException(
          'Jellyfin redirected the request. Enter the server’s final address.',
        );
      }
      if (!expectedStatuses.contains(status)) {
        _closeResponseBody(response.data);
        throw JellyfinException('Jellyfin returned HTTP $status.');
      }
      if (status == 204) {
        _closeResponseBody(response.data);
        return null;
      }
      final contentLength = response.headers.value(Headers.contentLengthHeader);
      if ((int.tryParse(contentLength ?? '') ?? 0) >
          _maxJellyfinResponseBytes) {
        _closeResponseBody(response.data);
        throw const JellyfinException('Jellyfin returned too much data.');
      }
      final body = response.data;
      if (body == null) {
        throw const JellyfinException('Jellyfin returned an empty response.');
      }
      final bytes = BytesBuilder(copy: false);
      try {
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > _maxJellyfinResponseBytes) {
            throw const JellyfinException('Jellyfin returned too much data.');
          }
          bytes.add(chunk);
        }
      } finally {
        _closeResponseBody(body);
      }
      try {
        return jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException {
        throw const JellyfinException('Jellyfin returned invalid data.');
      }
    } on JellyfinException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const JellyfinException(
          'Jellyfin rejected the username, password, or saved session.',
        );
      }
      throw const JellyfinException(
        'TetoTV could not reach that Jellyfin server.',
      );
    }
  }

  Map<String, String> _sessionHeaders(JellyfinConnection connection) => {
    'Authorization': _authorization(
      deviceId: connection.deviceId,
      token: connection.accessToken,
    ),
  };

  String _authorization({required String deviceId, String? token}) {
    String quote(String value) => value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(RegExp(r'[\r\n]'), '');
    return [
      'MediaBrowser Client="TetoTV"',
      'Device="Android TV"',
      'DeviceId="${quote(deviceId)}"',
      'Version="1.0.0"',
      if (token != null) 'Token="${quote(token)}"',
    ].join(', ');
  }

  static String _basePath(Uri baseUri) =>
      baseUri.path.replaceFirst(RegExp(r'/+$'), '');

  static Map<Object?, Object?> _map(Object? value) => value is Map
      ? value.cast<Object?, Object?>()
      : const <Object?, Object?>{};

  static String? _bounded(Object? value, int min, int max) {
    final text = value is String ? value.trim() : '';
    return text.length >= min && text.length <= max ? text : null;
  }

  static int? _integer(Object? value) => switch (value) {
    num number => number.toInt(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
}

// Dio exposes streaming response bodies publicly but keeps their close hook
// internal. Rejected and size-limited responses must release the socket now.
// ignore: invalid_use_of_internal_member
void _closeResponseBody(ResponseBody? body) => body?.close();
