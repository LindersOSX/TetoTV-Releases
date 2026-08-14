import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

const _maxPlexResponseBytes = 4 * 1024 * 1024;
const _maxPlexImageBytes = 8 * 1024 * 1024;
const _maxPageSize = 100;
const _maxCount = 1 << 31;

Uri? normalizePlexServerUri(String input) {
  final raw = input.trim();
  if (raw.isEmpty || _hasUnsafeUriText(raw)) return null;
  final withScheme = raw.contains('://') ? raw : 'http://$raw';
  try {
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null ||
        !const {'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.port <= 0 ||
        parsed.port > 65535 ||
        parsed.pathSegments.any((part) => part == '.' || part == '..')) {
      return null;
    }
    if (parsed.scheme.toLowerCase() == 'http' &&
        !isPrivatePlexHost(parsed.host)) {
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
  } on FormatException {
    return null;
  }
}

bool isPrivatePlexHost(String input) {
  final host = input.trim().toLowerCase();
  if (host == 'localhost') return true;
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  final bytes = address.rawAddress;
  if (address.isMulticast || bytes.every((byte) => byte == 0)) return false;
  if (address.isLoopback || address.isLinkLocal) return true;
  if (bytes.length == 4) return _isPrivateIpv4(bytes);
  if (_isIpv4MappedIpv6(bytes)) {
    return _isPrivateIpv4(bytes.sublist(12));
  }
  return bytes.length == 16 &&
      ((bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80));
}

bool _isPrivateIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];
  return first == 10 ||
      first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

bool _isIpv4MappedIpv6(List<int> bytes) =>
    bytes.length == 16 &&
    bytes.take(10).every((byte) => byte == 0) &&
    bytes[10] == 0xff &&
    bytes[11] == 0xff;

class PlexClient {
  PlexClient([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 10),
              followRedirects: false,
              maxRedirects: 0,
              responseType: ResponseType.stream,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  Future<PlexServerIdentity> serverIdentity(PlexConnection connection) async {
    final baseUri = _validateConnection(connection);
    final response = await _requestXml(
      baseUri,
      headers: _xmlHeaders(connection),
    );
    final container = _mediaContainer(response.document);
    return PlexServerIdentity(
      name:
          _boundedAttribute(container, 'friendlyName', 1, 200) ??
          'Plex Media Server',
      machineIdentifier:
          _boundedAttribute(container, 'machineIdentifier', 1, 200) ?? '',
      version: _boundedAttribute(container, 'version', 1, 100) ?? 'unknown',
    );
  }

  Future<List<PlexLibrary>> libraries(PlexConnection connection) async {
    final baseUri = _validateConnection(connection);
    final response = await _requestXml(
      _endpoint(baseUri, '/library/sections'),
      headers: _xmlHeaders(connection),
    );
    final container = _mediaContainer(response.document);
    final result = <PlexLibrary>[];
    for (final element in _directElements(container, const {'Directory'})) {
      final key = _boundedAttribute(element, 'key', 1, 40);
      final title = _boundedAttribute(element, 'title', 1, 500);
      final type = plexMediaTypeFromName(_attribute(element, 'type'));
      if (key == null ||
          title == null ||
          !RegExp(r'^\d+$').hasMatch(key) ||
          (type != PlexMediaType.movie && type != PlexMediaType.show)) {
        continue;
      }
      result.add(
        PlexLibrary(
          key: key,
          title: title,
          type: type,
          uuid: _boundedAttribute(element, 'uuid', 1, 200),
          thumb: _safeResponseKey(
            _attribute(element, 'thumb'),
            connection.accessToken,
          ),
          art: _safeResponseKey(
            _attribute(element, 'art'),
            connection.accessToken,
          ),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<PlexPage<PlexMediaItem>> libraryItems(
    PlexConnection connection,
    PlexLibrary library, {
    int start = 0,
    int size = _maxPageSize,
  }) async {
    final baseUri = _validateConnection(connection);
    if (!RegExp(r'^\d{1,40}$').hasMatch(library.key)) {
      throw const PlexException('That Plex library key is invalid.');
    }
    final offset = _safeOffset(start);
    final limit = _safePageSize(size);
    final response = await _requestXml(
      _endpoint(baseUri, '/library/sections/${library.key}/all'),
      headers: _pageHeaders(connection, offset: offset, size: limit),
    );
    return _parseMediaPage(
      response.document,
      connection: connection,
      requestedOffset: offset,
      responseHeaders: response.headers,
    );
  }

  Future<PlexPage<PlexMediaItem>> children(
    PlexConnection connection,
    PlexMediaItem item, {
    int start = 0,
    int size = _maxPageSize,
  }) async {
    _validateConnection(connection);
    if (!item.isFolder) {
      throw const PlexException('Choose a Plex show or season to browse.');
    }
    final offset = _safeOffset(start);
    final limit = _safePageSize(size);
    final uri = _resolveResponseKey(connection, item.key, appendChildren: true);
    final response = await _requestXml(
      uri,
      headers: _pageHeaders(connection, offset: offset, size: limit),
    );
    return _parseMediaPage(
      response.document,
      connection: connection,
      requestedOffset: offset,
      responseHeaders: response.headers,
    );
  }

  Uri playbackUri(
    PlexConnection connection,
    PlexMediaItem item, {
    PlexMediaPart? part,
  }) {
    _validateConnection(connection);
    final selectedPart = part ?? item.preferredPart;
    if (selectedPart == null || selectedPart.key.isEmpty) {
      throw const PlexException('Plex did not provide a playable media part.');
    }
    return _resolveResponseKey(connection, selectedPart.key);
  }

  Uri? imageUri(
    PlexConnection connection,
    PlexMediaItem item, {
    bool background = false,
  }) {
    _validateConnection(connection);
    final key = background
        ? item.art ?? item.grandparentThumb ?? item.parentThumb ?? item.thumb
        : item.thumb ?? item.parentThumb ?? item.grandparentThumb ?? item.art;
    return key == null ? null : _resolveResponseKey(connection, key);
  }

  Uri? libraryImageUri(
    PlexConnection connection,
    PlexLibrary library, {
    bool background = false,
  }) {
    _validateConnection(connection);
    final key = background ? library.art ?? library.thumb : library.thumb;
    return key == null ? null : _resolveResponseKey(connection, key);
  }

  Map<String, String> authenticatedHeaders(PlexConnection connection) {
    _validateConnection(connection);
    return Map.unmodifiable(_authenticatedHeaders(connection));
  }

  /// Loads an authenticated thumbnail without allowing an HTTP redirect to
  /// carry the non-standard X-Plex-Token header to another origin.
  Future<Uint8List> imageBytes(PlexConnection connection, Uri uri) async {
    final baseUri = _validateConnection(connection);
    if (!_sameOrigin(baseUri, uri) ||
        !_isUnderBasePath(baseUri.path, uri.path)) {
      throw const PlexException('Plex returned an external image resource.');
    }
    try {
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: Options(
          method: 'GET',
          headers: _authenticatedHeaders(connection),
          followRedirects: false,
          maxRedirects: 0,
          responseType: ResponseType.stream,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        _closeResponseBody(response.data);
        throw const PlexException('Plex redirected an image request.');
      }
      if (status != 200) {
        _closeResponseBody(response.data);
        throw const PlexException('Plex image could not be loaded.');
      }
      final declared = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declared != null && declared > _maxPlexImageBytes) {
        _closeResponseBody(response.data);
        throw const PlexException('Plex returned an oversized image.');
      }
      final body = response.data;
      if (body == null) {
        throw const PlexException('Plex returned an empty image.');
      }
      final bytes = BytesBuilder(copy: false);
      try {
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > _maxPlexImageBytes) {
            throw const PlexException('Plex returned an oversized image.');
          }
          bytes.add(chunk);
        }
      } finally {
        _closeResponseBody(body);
      }
      final result = bytes.takeBytes();
      if (result.isEmpty) {
        throw const PlexException('Plex returned an empty image.');
      }
      return result;
    } on PlexException {
      rethrow;
    } on DioException {
      throw const PlexException('Plex image could not be loaded.');
    }
  }

  Future<_PlexXmlResponse> _requestXml(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: Options(
          method: 'GET',
          headers: headers,
          followRedirects: false,
          maxRedirects: 0,
          responseType: ResponseType.stream,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        _closeResponseBody(response.data);
        throw const PlexException('Plex rejected the saved access token.');
      }
      if (status >= 300 && status < 400) {
        _closeResponseBody(response.data);
        throw const PlexException(
          'Plex redirected the request. Enter the server’s final address.',
        );
      }
      if (status != 200) {
        _closeResponseBody(response.data);
        throw PlexException('Plex returned HTTP $status.');
      }
      final contentLength = response.headers.value(Headers.contentLengthHeader);
      if ((int.tryParse(contentLength ?? '') ?? 0) > _maxPlexResponseBytes) {
        _closeResponseBody(response.data);
        throw const PlexException('Plex returned too much data.');
      }
      final body = response.data;
      if (body == null) {
        throw const PlexException('Plex returned an empty response.');
      }
      final bytes = BytesBuilder(copy: false);
      try {
        await for (final chunk in body.stream) {
          if (bytes.length + chunk.length > _maxPlexResponseBytes) {
            throw const PlexException('Plex returned too much data.');
          }
          bytes.add(chunk);
        }
      } finally {
        _closeResponseBody(body);
      }
      final text = utf8.decode(bytes.takeBytes());
      if (text.trim().isEmpty) {
        throw const PlexException('Plex returned an empty response.');
      }
      final upper = text.toUpperCase();
      if (upper.contains('<!DOCTYPE') || upper.contains('<!ENTITY')) {
        throw const PlexException('Plex returned unsupported XML.');
      }
      try {
        return _PlexXmlResponse(
          document: XmlDocument.parse(text),
          headers: response.headers,
        );
      } on Object {
        throw const PlexException('Plex returned invalid XML.');
      }
    } on PlexException {
      rethrow;
    } on DioException catch (error) {
      final responseBody = error.response?.data;
      if (responseBody is ResponseBody) _closeResponseBody(responseBody);
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const PlexException('Plex rejected the saved access token.');
      }
      throw const PlexException('TetoTV could not reach that Plex server.');
    } on FormatException {
      throw const PlexException('Plex returned invalid XML.');
    }
  }

  PlexPage<PlexMediaItem> _parseMediaPage(
    XmlDocument document, {
    required PlexConnection connection,
    required int requestedOffset,
    required Headers responseHeaders,
  }) {
    final container = _mediaContainer(document);
    final items = <PlexMediaItem>[];
    final rawElements = _directElements(container, const {
      'Directory',
      'Video',
      'Metadata',
    }).toList(growable: false);
    for (final element in rawElements) {
      final item = _parseMediaItem(element, connection);
      if (item != null) items.add(item);
    }
    final responseOffset =
        _nonNegativeAttribute(container, 'offset') ??
        _nonNegativeHeader(responseHeaders, 'X-Plex-Container-Start');
    final offset = responseOffset ?? requestedOffset;
    final nextOffset = (offset + rawElements.length).clamp(0, _maxCount);
    final minimumTotal = nextOffset;
    final reportedTotal =
        _nonNegativeAttribute(container, 'totalSize') ??
        _nonNegativeHeader(responseHeaders, 'X-Plex-Container-Total-Size') ??
        _nonNegativeAttribute(container, 'size') ??
        minimumTotal;
    final total = reportedTotal.clamp(minimumTotal, _maxCount);
    return PlexPage<PlexMediaItem>(
      items: List.unmodifiable(items),
      totalCount: total,
      offset: offset,
      nextOffset: nextOffset,
    );
  }

  PlexMediaItem? _parseMediaItem(
    XmlElement element,
    PlexConnection connection,
  ) {
    final type = plexMediaTypeFromName(_attribute(element, 'type'));
    if (type == PlexMediaType.unknown) return null;
    final key = _safeResponseKey(
      _attribute(element, 'key'),
      connection.accessToken,
    );
    final title = _boundedAttribute(element, 'title', 1, 500);
    final ratingKey =
        _boundedAttribute(element, 'ratingKey', 1, 200) ??
        _ratingKeyFromPath(key);
    if (key == null || title == null || ratingKey == null) return null;

    final parts = <PlexMediaPart>[];
    for (final media in _directElements(element, const {'Media'})) {
      final mediaContainer = _boundedAttribute(media, 'container', 1, 80);
      for (final part in _directElements(media, const {'Part'})) {
        final partKey = _safeResponseKey(
          _attribute(part, 'key'),
          connection.accessToken,
        );
        if (partKey == null) continue;
        parts.add(
          PlexMediaPart(
            key: partKey,
            id: _boundedAttribute(part, 'id', 1, 200),
            container:
                _boundedAttribute(part, 'container', 1, 80) ?? mediaContainer,
            file: _boundedAttribute(part, 'file', 1, 2048),
            durationMilliseconds: _nonNegativeAttribute(part, 'duration'),
            sizeBytes: _nonNegativeAttribute(part, 'size'),
          ),
        );
      }
    }

    return PlexMediaItem(
      ratingKey: ratingKey,
      key: key,
      title: title,
      type: type,
      summary: _boundedAttribute(element, 'summary', 1, 8000),
      parentTitle: _boundedAttribute(element, 'parentTitle', 1, 500),
      grandparentTitle: _boundedAttribute(element, 'grandparentTitle', 1, 500),
      year: _nonNegativeAttribute(element, 'year'),
      index: _nonNegativeAttribute(element, 'index'),
      parentIndex: _nonNegativeAttribute(element, 'parentIndex'),
      durationMilliseconds: _nonNegativeAttribute(element, 'duration'),
      viewOffsetMilliseconds: _nonNegativeAttribute(element, 'viewOffset'),
      thumb: _safeResponseKey(
        _attribute(element, 'thumb'),
        connection.accessToken,
      ),
      art: _safeResponseKey(_attribute(element, 'art'), connection.accessToken),
      parentThumb: _safeResponseKey(
        _attribute(element, 'parentThumb'),
        connection.accessToken,
      ),
      grandparentThumb: _safeResponseKey(
        _attribute(element, 'grandparentThumb'),
        connection.accessToken,
      ),
      parts: List.unmodifiable(parts),
    );
  }

  Uri _validateConnection(PlexConnection connection) {
    final normalized = normalizePlexServerUri(connection.baseUri.toString());
    if (normalized == null || normalized != connection.baseUri) {
      throw const PlexException('The saved Plex server address is invalid.');
    }
    if (!_validHeaderValue(connection.accessToken, min: 8, max: 4096)) {
      throw const PlexException('The saved Plex access token is invalid.');
    }
    if (!_validHeaderValue(connection.clientIdentifier, min: 8, max: 200)) {
      throw const PlexException('The saved Plex client identifier is invalid.');
    }
    if (_containsSecret(normalized.toString(), connection.accessToken)) {
      throw const PlexException('The saved Plex server address is invalid.');
    }
    return normalized;
  }

  Map<String, String> _authenticatedHeaders(PlexConnection connection) => {
    'X-Plex-Product': 'TetoTV',
    'X-Plex-Version': '1.0.0',
    'X-Plex-Platform': 'Android',
    'X-Plex-Device': 'Android TV',
    'X-Plex-Client-Identifier': connection.clientIdentifier,
    'X-Plex-Token': connection.accessToken,
  };

  Map<String, String> _xmlHeaders(PlexConnection connection) => {
    ..._authenticatedHeaders(connection),
    'Accept': 'application/xml',
  };

  Map<String, String> _pageHeaders(
    PlexConnection connection, {
    required int offset,
    required int size,
  }) => {
    ..._xmlHeaders(connection),
    'X-Plex-Container-Start': '$offset',
    'X-Plex-Container-Size': '$size',
  };

  Uri _resolveResponseKey(
    PlexConnection connection,
    String rawKey, {
    bool appendChildren = false,
  }) {
    final baseUri = _validateConnection(connection);
    final key = _safeResponseKey(rawKey, connection.accessToken);
    if (key == null || _hasUnsafeUriText(key)) {
      throw const PlexException('Plex returned an invalid resource key.');
    }
    final parsed = Uri.tryParse(key);
    if (parsed == null ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasFragment ||
        parsed.pathSegments.any((part) => part == '.' || part == '..')) {
      throw const PlexException('Plex returned an invalid resource key.');
    }

    late String path;
    if (parsed.hasScheme || parsed.hasAuthority) {
      if (!_sameOrigin(baseUri, parsed) ||
          !_isUnderBasePath(baseUri.path, parsed.path)) {
        throw const PlexException('Plex returned an external resource key.');
      }
      path = parsed.path;
    } else {
      final rawPath = parsed.path.startsWith('/')
          ? parsed.path
          : '/${parsed.path}';
      final basePath = _basePath(baseUri);
      path = _isUnderBasePath(basePath, rawPath)
          ? rawPath
          : '$basePath$rawPath';
    }
    path = path.replaceFirst(RegExp(r'/+$'), '');
    if (appendChildren && !path.endsWith('/children')) {
      path = '$path/children';
    }
    if (path.isEmpty || !_isUnderBasePath(baseUri.path, path)) {
      throw const PlexException('Plex returned an invalid resource key.');
    }

    final cleanQuery = <String>[];
    for (final entry in parsed.queryParametersAll.entries) {
      if (entry.key.toLowerCase() == 'x-plex-token') continue;
      for (final value in entry.value) {
        if (_containsSecret(value, connection.accessToken)) continue;
        cleanQuery.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    final result = baseUri.replace(
      path: path,
      query: cleanQuery.isEmpty ? null : cleanQuery.join('&'),
      fragment: null,
    );
    if (_containsSecret(result.toString(), connection.accessToken)) {
      throw const PlexException('Plex returned an invalid resource key.');
    }
    return result;
  }
}

Uri _endpoint(Uri baseUri, String suffix) => baseUri.replace(
  path: '${_basePath(baseUri)}${suffix.startsWith('/') ? suffix : '/$suffix'}',
  query: null,
  fragment: null,
);

String _basePath(Uri baseUri) => baseUri.path.replaceFirst(RegExp(r'/+$'), '');

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
    first.host.toLowerCase() == second.host.toLowerCase() &&
    first.port == second.port;

bool _isUnderBasePath(String basePath, String path) {
  final base = basePath.replaceFirst(RegExp(r'/+$'), '');
  return base.isEmpty || path == base || path.startsWith('$base/');
}

bool _validHeaderValue(String value, {required int min, required int max}) =>
    value.length >= min &&
    value.length <= max &&
    value.trim() == value &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

bool _hasUnsafeUriText(String value) {
  try {
    final decoded = Uri.decodeComponent(value);
    return decoded.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(decoded) ||
        RegExp(r'/(?:\.{1,2})(?:/|$)').hasMatch(decoded);
  } on FormatException {
    return true;
  }
}

String? _safeResponseKey(String? value, String accessToken) {
  final key = value?.trim();
  if (key == null ||
      key.isEmpty ||
      key.length > 2048 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(key) ||
      _containsSecret(key, accessToken)) {
    return null;
  }
  return key;
}

bool _containsSecret(String value, String secret) {
  if (secret.isEmpty || value.contains(secret)) return secret.isNotEmpty;
  try {
    return Uri.decodeComponent(value).contains(secret);
  } on FormatException {
    return false;
  }
}

int _safeOffset(int value) => value.clamp(0, _maxCount);

int _safePageSize(int value) => value.clamp(1, _maxPageSize);

XmlElement _mediaContainer(XmlDocument document) {
  final roots = document.childElements.toList(growable: false);
  if (roots.length != 1 || roots.single.name.local != 'MediaContainer') {
    throw const PlexException('Plex returned an unexpected XML response.');
  }
  return roots.single;
}

Iterable<XmlElement> _directElements(XmlElement parent, Set<String> names) =>
    parent.childElements.where((child) => names.contains(child.name.local));

String? _attribute(XmlElement element, String name) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == name) return attribute.value;
  }
  return null;
}

String? _boundedAttribute(XmlElement element, String name, int min, int max) {
  final value = _attribute(element, name)?.trim();
  return value != null && value.length >= min && value.length <= max
      ? value
      : null;
}

int? _nonNegativeAttribute(XmlElement element, String name) {
  final parsed = int.tryParse(_attribute(element, name)?.trim() ?? '');
  return parsed == null || parsed < 0 ? null : parsed.clamp(0, _maxCount);
}

int? _nonNegativeHeader(Headers headers, String name) {
  final parsed = int.tryParse(headers.value(name)?.trim() ?? '');
  return parsed == null || parsed < 0 ? null : parsed.clamp(0, _maxCount);
}

String? _ratingKeyFromPath(String? key) {
  if (key == null) return null;
  final match = RegExp(r'/library/metadata/([^/?]+)').firstMatch(key);
  final value = match?.group(1);
  return value == null || value.isEmpty || value.length > 200 ? null : value;
}

// Dio exposes streaming response bodies publicly but keeps their close hook
// internal. Rejected and size-limited responses must release the socket now.
// ignore: invalid_use_of_internal_member
void _closeResponseBody(ResponseBody? body) => body?.close();

class _PlexXmlResponse {
  const _PlexXmlResponse({required this.document, required this.headers});

  final XmlDocument document;
  final Headers headers;
}
