// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

typedef WebProxyTargetValidator = Future<void> Function(Uri uri);
typedef WebProxyHopFetcher =
    Future<WebProxyUpstreamResponse> Function(WebProxyUpstreamRequest request);

class WebPlaybackProxyLimits {
  const WebPlaybackProxyLimits({
    this.maximumConcurrentRequests = 6,
    this.maximumSessionRequests = 4,
    this.maximumTotalSessionRequests = 4096,
    this.maximumManifestBytes = 256 * 1024,
    this.maximumSubtitleBytes = 256 * 1024,
    this.maximumKeyBytes = 1024 * 1024,
    this.maximumSegmentBytes = 256 * 1024 * 1024,
    this.maximumProgressiveBytes = 32 * 1024 * 1024 * 1024,
    this.maximumManifestReferences = 512,
    this.maximumNestedManifests = 24,
    this.maximumManifestDepth = 4,
    this.maximumRedirects = 4,
    this.preparationTimeout = const Duration(seconds: 20),
    this.sessionIdleTimeout = const Duration(minutes: 10),
    this.sessionMaximumAge = const Duration(hours: 6),
    this.upstreamConnectTimeout = const Duration(seconds: 8),
    this.upstreamHeaderTimeout = const Duration(seconds: 12),
    this.upstreamIdleTimeout = const Duration(seconds: 20),
  });

  final int maximumConcurrentRequests;
  final int maximumSessionRequests;
  final int maximumTotalSessionRequests;
  final int maximumManifestBytes;
  final int maximumSubtitleBytes;
  final int maximumKeyBytes;
  final int maximumSegmentBytes;
  final int maximumProgressiveBytes;
  final int maximumManifestReferences;
  final int maximumNestedManifests;
  final int maximumManifestDepth;
  final int maximumRedirects;
  final Duration preparationTimeout;
  final Duration sessionIdleTimeout;
  final Duration sessionMaximumAge;
  final Duration upstreamConnectTimeout;
  final Duration upstreamHeaderTimeout;
  final Duration upstreamIdleTimeout;
}

class WebProxyUpstreamRequest {
  const WebProxyUpstreamRequest({
    required this.uri,
    required this.method,
    required this.headers,
    this.range,
    this.ifRange,
  });

  final Uri uri;
  final String method;
  final Map<String, String> headers;
  final String? range;
  final String? ifRange;
}

class WebProxyUpstreamResponse {
  WebProxyUpstreamResponse({
    required this.statusCode,
    required this.uri,
    required this.requestHeaders,
    required this.headers,
    required this.body,
    FutureOr<void> Function()? onClose,
  }) : _onClose = onClose;

  final int statusCode;
  final Uri uri;
  final Map<String, String> requestHeaders;
  final Map<String, List<String>> headers;
  final Stream<List<int>> body;
  final FutureOr<void> Function()? _onClose;
  bool _closed = false;

  String? header(String name) => headers[name.toLowerCase()]?.firstOrNull;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _onClose?.call();
  }
}

/// Fetches one upstream response with validation before every hop. Redirects
/// are deliberately handled here instead of by HttpClient so private targets
/// and cross-origin credential forwarding cannot bypass policy.
class PinnedPublicWebProxyUpstream {
  PinnedPublicWebProxyUpstream({
    this.limits = const WebPlaybackProxyLimits(),
    PublicHostLookup? lookup,
    WebProxyTargetValidator? targetValidator,
    WebProxyHopFetcher? hopFetcher,
  }) : _lookup = lookup,
       _targetValidator = targetValidator,
       _hopFetcher = hopFetcher;

  final WebPlaybackProxyLimits limits;
  final PublicHostLookup? _lookup;
  final WebProxyTargetValidator? _targetValidator;
  final WebProxyHopFetcher? _hopFetcher;

  Future<void> validateTarget(Uri uri) async {
    if (safePublicHttpsUri(uri.toString()) == null) {
      throw const FormatException('Only public HTTPS resources are allowed.');
    }
    if (_targetValidator case final validator?) {
      await validator(uri);
      return;
    }
    await validatePublicNetworkTarget(uri, lookup: _lookup);
  }

  Future<WebProxyUpstreamResponse> fetch(
    Uri initialUri, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? range,
    String? ifRange,
  }) async {
    if (method != 'GET' && method != 'HEAD') {
      throw const FormatException('The proxy supports only GET and HEAD.');
    }
    var target = initialUri;
    var sanitized = sanitizeAddonHeaders(headers);
    for (var redirect = 0; redirect <= limits.maximumRedirects; redirect++) {
      await validateTarget(target);
      final response = await (_hopFetcher ?? _fetchPinnedHop)(
        WebProxyUpstreamRequest(
          uri: target,
          method: method,
          headers: sanitized,
          range: range,
          ifRange: ifRange,
        ),
      );
      if (response.uri != target) {
        await response.close();
        throw const FormatException(
          'A single upstream hop returned an unexpected target.',
        );
      }
      if (!_isRedirect(response.statusCode)) return response;
      final location = response.header(HttpHeaders.locationHeader);
      await response.close();
      if (location == null || redirect == limits.maximumRedirects) {
        throw const FormatException(
          'The upstream resource exceeded the redirect limit.',
        );
      }
      final redirected = target.resolve(location);
      if (safePublicHttpsUri(redirected.toString()) == null) {
        throw const FormatException(
          'The upstream resource redirected outside public HTTPS.',
        );
      }
      if (!_sameOrigin(target, redirected)) {
        sanitized = sanitizeAddonHeaders(sanitized, stripCredentials: true);
      }
      target = redirected;
    }
    throw const FormatException('The upstream resource could not be opened.');
  }

  Future<WebProxyUpstreamResponse> _fetchPinnedHop(
    WebProxyUpstreamRequest request,
  ) async {
    final client = createPinnedPublicHttpsClient(lookup: _lookup)
      ..connectionTimeout = limits.upstreamConnectTimeout
      ..idleTimeout = limits.upstreamIdleTimeout;
    try {
      final outgoing = request.method == 'HEAD'
          ? await client
                .headUrl(request.uri)
                .timeout(limits.upstreamHeaderTimeout)
          : await client
                .getUrl(request.uri)
                .timeout(limits.upstreamHeaderTimeout);
      outgoing.followRedirects = false;
      outgoing.headers.set(HttpHeaders.acceptHeader, '*/*');
      for (final entry in request.headers.entries) {
        outgoing.headers.set(entry.key, entry.value);
      }
      if (request.range != null) {
        outgoing.headers.set(HttpHeaders.rangeHeader, request.range!);
      }
      if (request.ifRange != null) {
        outgoing.headers.set(HttpHeaders.ifRangeHeader, request.ifRange!);
      }
      final incoming = await outgoing.close().timeout(
        limits.upstreamHeaderTimeout,
      );
      final responseHeaders = <String, List<String>>{};
      incoming.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
      });
      return WebProxyUpstreamResponse(
        statusCode: incoming.statusCode,
        uri: request.uri,
        requestHeaders: Map.unmodifiable(request.headers),
        headers: Map.unmodifiable(responseHeaders),
        body: incoming.timeout(limits.upstreamIdleTimeout),
        onClose: () => client.close(force: true),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

class WebPlaybackSession implements PlaybackResourceLease {
  WebPlaybackSession._({
    required this._proxy,
    required this.id,
    required this.playbackUri,
    required this.contentType,
    this.subtitleUri,
    this.subtitleContentType,
    this.subtitleRejected = false,
  });

  final WebPlaybackProxy _proxy;
  final String id;
  final Uri playbackUri;
  final Uri? subtitleUri;
  final String contentType;
  final String? subtitleContentType;
  final bool subtitleRejected;
  bool _released = false;

  @override
  Future<void> close() async {
    if (_released) return;
    _released = true;
    await _proxy.releaseSession(id);
  }
}

class WebPlaybackProxy {
  WebPlaybackProxy({
    this.limits = const WebPlaybackProxyLimits(),
    PinnedPublicWebProxyUpstream? upstream,
    Random? secureRandom,
    DateTime Function()? clock,
  }) : upstream = upstream ?? PinnedPublicWebProxyUpstream(limits: limits),
       _random = secureRandom ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  static final instance = WebPlaybackProxy();

  final WebPlaybackProxyLimits limits;
  final PinnedPublicWebProxyUpstream upstream;
  final Random _random;
  final DateTime Function() _clock;
  final Map<String, _ProxySessionState> _sessions = {};
  HttpServer? _server;
  Future<void>? _starting;
  StreamSubscription<HttpRequest>? _serverSubscription;
  Timer? _cleanupTimer;
  int _activeRequests = 0;

  int get activeSessionCount => _sessions.length;

  Future<void> start() async {
    if (_server != null) return;
    final starting = _starting;
    if (starting != null) return starting;
    final completer = Completer<void>();
    _starting = completer.future;
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      _server = server;
      _serverSubscription = server.listen(_handleRequest);
      _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _removeExpiredSessions();
      });
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  Future<WebPlaybackSession> prepare({
    required Uri uri,
    Map<String, String> headers = const {},
    Uri? subtitleUri,
  }) async {
    await start();
    _removeExpiredSessions();
    final sessionId = _opaqueToken();
    final state = _ProxySessionState(
      id: sessionId,
      createdAt: _clock(),
      lastAccessedAt: _clock(),
    );
    final preparation = _PreparationBudget(
      clock: _clock,
      deadline: _clock().add(limits.preparationTimeout),
    );
    try {
      final sanitized = sanitizeAddonHeaders(headers);
      final root = await preparation.wait(_fetchProbe(uri, sanitized));
      preparation.check();
      final kind = _classifyRoot(root);
      late final _ProxyResource playback;
      switch (kind) {
        case _RootResourceKind.hls:
          final budget = _ManifestBudget(limits);
          playback = await _prepareHlsManifest(
            state,
            root,
            budget: budget,
            preparation: preparation,
            depth: 0,
          );
        case _RootResourceKind.progressive:
          playback = _registerUpstreamResource(
            state,
            uri: root.uri,
            headers: root.requestHeaders,
            contentType: root.contentType,
            maximumBytes: limits.maximumProgressiveBytes,
          );
      }

      _ProxyResource? subtitle;
      var subtitleRejected = false;
      if (subtitleUri != null) {
        try {
          subtitle = await _prepareSubtitle(
            state,
            subtitleUri,
            streamUri: root.uri,
            streamHeaders: root.requestHeaders,
            preparation: preparation,
          );
        } catch (_) {
          subtitle = null;
          subtitleRejected = true;
        }
      }
      state.playbackToken = playback.token;
      state.subtitleToken = subtitle?.token;
      state.contentType = playback.contentType;
      state.subtitleContentType = subtitle?.contentType;
      state.subtitleRejected = subtitleRejected;
      preparation.check();
      _sessions[sessionId] = state;
      return _leaseFor(state);
    } catch (_) {
      preparation.cancel();
      state.close();
      rethrow;
    }
  }

  WebPlaybackSession? retainSessionForUri(Uri uri) {
    _removeExpiredSessions();
    if (!isOwnedPlaybackProxyUri(uri)) return null;
    final route = _ownedRoute(uri)!;
    final session = _sessions[route.$1]!;
    session.retainCount++;
    session.lastAccessedAt = _clock();
    return _leaseFor(session);
  }

  Future<void> releaseSession(String id) async {
    final session = _sessions[id];
    if (session == null || session.closed) return;
    session.retainCount--;
    if (session.retainCount <= 0 && session.activeRequests == 0) {
      _sessions.remove(id);
      session.close();
    }
  }

  Future<void> releaseSessionForUri(Uri uri) async {
    if (!isOwnedPlaybackProxyUri(uri)) return;
    final id = _sessionIdFromOwnedUri(uri);
    if (id != null) await releaseSession(id);
  }

  Future<void> closeSessionForUri(Uri uri) => releaseSessionForUri(uri);

  bool isOwnedPlaybackProxyUri(Uri uri) {
    _removeExpiredSessions();
    final server = _server;
    if (server == null ||
        uri.scheme != 'http' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.port != server.port) {
      return false;
    }
    final route = _ownedRoute(uri);
    if (route == null) return false;
    final session = _sessions[route.$1];
    return session != null &&
        !session.closed &&
        session.retainCount > 0 &&
        session.resources.containsKey(route.$2);
  }

  bool owns(Uri uri) => isOwnedPlaybackProxyUri(uri);

  Future<void> close() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  WebPlaybackSession _leaseFor(_ProxySessionState state) {
    final playbackToken = state.playbackToken;
    if (playbackToken == null) {
      throw StateError('The proxy session is not ready.');
    }
    final subtitleToken = state.subtitleToken;
    return WebPlaybackSession._(
      proxy: this,
      id: state.id,
      playbackUri: _resourceUri(state.id, playbackToken),
      subtitleUri: subtitleToken == null
          ? null
          : _resourceUri(state.id, subtitleToken),
      contentType: state.contentType,
      subtitleContentType: state.subtitleContentType,
      subtitleRejected: state.subtitleRejected,
    );
  }

  Future<_LoadedBytes> _fetchProbe(Uri uri, Map<String, String> headers) async {
    final response = await upstream.fetch(
      uri,
      headers: headers,
      range: 'bytes=0-${limits.maximumManifestBytes}',
    );
    try {
      _requireSuccess(response.statusCode);
      return await _readLoadedBytes(
        response,
        limits.maximumManifestBytes,
        allowTruncation: true,
      );
    } finally {
      await response.close();
    }
  }

  _RootResourceKind _classifyRoot(_LoadedBytes loaded) {
    final mime = _mimeType(loaded.contentType);
    final sample = loaded.text.trimLeft();
    final path = loaded.uri.path.toLowerCase();
    if (mime == 'application/dash+xml' ||
        sample.toLowerCase().contains('<mpd') ||
        path.endsWith('.mpd')) {
      throw const FormatException(
        'DASH playback is disabled because its dynamic URL templates cannot be safely rewritten.',
      );
    }
    if (const {
          'application/vnd.apple.mpegurl',
          'application/x-mpegurl',
        }.contains(mime) ||
        sample.startsWith('#EXTM3U') ||
        path.endsWith('.m3u8')) {
      if (loaded.truncated || !sample.startsWith('#EXTM3U')) {
        throw const FormatException(
          'The HLS manifest is incomplete or exceeds the safety limit.',
        );
      }
      return _RootResourceKind.hls;
    }
    if (mime == 'text/html' ||
        sample.toLowerCase().startsWith('<!doctype html')) {
      throw const FormatException(
        'The provider returned a web page instead of media.',
      );
    }
    if (mime.startsWith('video/') ||
        mime == 'application/octet-stream' ||
        const ['.mp4', '.mkv', '.webm', '.m4v', '.ts'].any(path.endsWith)) {
      return _RootResourceKind.progressive;
    }
    throw FormatException(
      'The provider returned an unsupported media response ($mime).',
    );
  }

  Future<_ProxyResource> _prepareHlsManifest(
    _ProxySessionState state,
    _LoadedBytes manifest, {
    required _ManifestBudget budget,
    required _PreparationBudget preparation,
    required int depth,
  }) async {
    preparation.check();
    if (depth > limits.maximumManifestDepth) {
      throw const FormatException('The HLS nesting limit was exceeded.');
    }
    budget.addManifest(manifest.uri);
    final token = _opaqueToken();
    if (!state.activeManifestUris.add(manifest.uri)) {
      throw const FormatException('Recursive HLS manifests are not allowed.');
    }
    try {
      final lines = const LineSplitter().convert(manifest.text);
      if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
        throw const FormatException('The provider returned invalid HLS.');
      }
      final trimmed = lines.map((line) => line.trim()).toList(growable: false);
      final isMediaPlaylist = trimmed.any(
        (line) =>
            line.startsWith('#EXTINF:') ||
            line.startsWith('#EXT-X-TARGETDURATION:') ||
            line.startsWith('#EXT-X-MEDIA-SEQUENCE:'),
      );
      if (isMediaPlaylist && !trimmed.contains('#EXT-X-ENDLIST')) {
        throw const FormatException(
          'Live or mutable HLS playlists are not allowed.',
        );
      }
      if (trimmed.any(
        (line) =>
            line.startsWith('#EXT-X-DEFINE') ||
            line.startsWith('#EXT-X-PART') ||
            line.startsWith('#EXT-X-PRELOAD-HINT') ||
            line.startsWith('#EXT-X-SERVER-CONTROL') ||
            line.startsWith('#EXT-X-SKIP'),
      )) {
        throw const FormatException(
          'Dynamic or variable HLS constructs are not allowed.',
        );
      }

      final rewritten = <String>[];
      var nextLineIsManifest = false;
      var mediaReferences = 0;
      for (final original in lines) {
        preparation.check();
        final line = original.trim();
        if (line.isEmpty) {
          rewritten.add(original);
          continue;
        }
        if (line.startsWith('#')) {
          final colon = line.indexOf(':');
          final tag = (colon < 0 ? line : line.substring(0, colon))
              .toUpperCase();
          if (tag == '#EXT-X-STREAM-INF') {
            nextLineIsManifest = true;
            rewritten.add(original);
            continue;
          }
          if (!line.toUpperCase().contains('URI=')) {
            rewritten.add(original);
            continue;
          }
          final allowedUriTags = const {
            '#EXT-X-I-FRAME-STREAM-INF',
            '#EXT-X-MEDIA',
            '#EXT-X-RENDITION-REPORT',
            '#EXT-X-KEY',
            '#EXT-X-SESSION-KEY',
            '#EXT-X-MAP',
          };
          if (!allowedUriTags.contains(tag)) {
            throw const FormatException(
              'The HLS manifest contains an unsupported URI construct.',
            );
          }
          final uriMatch = RegExp(
            r'URI=("[^"]*"|[^,]*)',
            caseSensitive: false,
          ).firstMatch(original);
          if (uriMatch == null) {
            throw const FormatException('The HLS URI attribute is malformed.');
          }
          final quoted = uriMatch.group(1)!;
          final rawReference = quoted.startsWith('"')
              ? quoted.substring(1, quoted.length - 1)
              : quoted;
          final nestedManifest = const {
            '#EXT-X-I-FRAME-STREAM-INF',
            '#EXT-X-MEDIA',
            '#EXT-X-RENDITION-REPORT',
          }.contains(tag);
          final local = await _registerHlsReference(
            state,
            manifest,
            rawReference,
            budget: budget,
            preparation: preparation,
            depth: depth,
            nestedManifest: nestedManifest,
            keyResource: tag == '#EXT-X-KEY' || tag == '#EXT-X-SESSION-KEY',
          );
          rewritten.add(
            original.replaceRange(uriMatch.start, uriMatch.end, 'URI="$local"'),
          );
          mediaReferences++;
          continue;
        }

        final local = await _registerHlsReference(
          state,
          manifest,
          line,
          budget: budget,
          preparation: preparation,
          depth: depth,
          nestedManifest: nextLineIsManifest,
          keyResource: false,
        );
        rewritten.add(local.toString());
        mediaReferences++;
        nextLineIsManifest = false;
      }
      if (nextLineIsManifest || mediaReferences == 0) {
        throw const FormatException(
          'The HLS manifest has no complete media references.',
        );
      }
      final bytes = utf8.encode(rewritten.join('\n'));
      if (bytes.length > limits.maximumManifestBytes) {
        throw const FormatException(
          'The rewritten HLS manifest exceeds the safety limit.',
        );
      }
      final resource = _ProxyResource.cached(
        token: token,
        bytes: bytes,
        contentType: 'application/vnd.apple.mpegurl',
      );
      preparation.check();
      state.resources[token] = resource;
      return resource;
    } finally {
      state.activeManifestUris.remove(manifest.uri);
    }
  }

  Future<Uri> _registerHlsReference(
    _ProxySessionState state,
    _LoadedBytes parent,
    String rawReference, {
    required _ManifestBudget budget,
    required _PreparationBudget preparation,
    required int depth,
    required bool nestedManifest,
    required bool keyResource,
  }) async {
    preparation.check();
    budget.addReference();
    final target = _resolvePublicHttps(parent.uri, rawReference);
    await preparation.wait(upstream.validateTarget(target));
    final crossOrigin = !_sameOrigin(parent.uri, target);
    final scopedHeaders = crossOrigin
        ? sanitizeAddonHeaders(parent.requestHeaders, stripCredentials: true)
        : parent.requestHeaders;
    if (nestedManifest || target.path.toLowerCase().endsWith('.m3u8')) {
      final nestedResponse = await preparation.wait(
        upstream.fetch(target, headers: scopedHeaders),
      );
      try {
        _requireSuccess(nestedResponse.statusCode);
        final nested = await preparation.wait(
          _readLoadedBytes(
            nestedResponse,
            limits.maximumManifestBytes,
            allowTruncation: false,
          ),
        );
        preparation.check();
        if (!nested.text.trimLeft().startsWith('#EXTM3U')) {
          throw const FormatException(
            'A nested HLS reference did not return HLS.',
          );
        }
        final resource = await preparation.wait(
          _prepareHlsManifest(
            state,
            nested,
            budget: budget,
            preparation: preparation,
            depth: depth + 1,
          ),
        );
        return _resourceUri(state.id, resource.token);
      } finally {
        await nestedResponse.close();
      }
    }
    preparation.check();
    final resource = _registerUpstreamResource(
      state,
      uri: target,
      headers: scopedHeaders,
      contentType: keyResource ? 'application/octet-stream' : '',
      maximumBytes: keyResource
          ? limits.maximumKeyBytes
          : limits.maximumSegmentBytes,
    );
    return _resourceUri(state.id, resource.token);
  }

  Future<_ProxyResource> _prepareSubtitle(
    _ProxySessionState state,
    Uri subtitleUri, {
    required Uri streamUri,
    required Map<String, String> streamHeaders,
    required _PreparationBudget preparation,
  }) async {
    preparation.check();
    final target = _resolvePublicHttps(streamUri, subtitleUri.toString());
    final headers = _sameOrigin(streamUri, target)
        ? streamHeaders
        : sanitizeAddonHeaders(streamHeaders, stripCredentials: true);
    final response = await preparation.wait(
      upstream.fetch(target, headers: headers),
    );
    try {
      _requireSuccess(response.statusCode);
      final loaded = await preparation.wait(
        _readLoadedBytes(
          response,
          limits.maximumSubtitleBytes,
          allowTruncation: false,
        ),
      );
      preparation.check();
      if (!_isSupportedSubtitle(loaded)) {
        throw const FormatException('The external subtitle is not supported.');
      }
      final resource = _ProxyResource.cached(
        token: _opaqueToken(),
        bytes: loaded.bytes,
        contentType: _subtitleContentType(loaded),
      );
      preparation.check();
      state.resources[resource.token] = resource;
      return resource;
    } finally {
      await response.close();
    }
  }

  _ProxyResource _registerUpstreamResource(
    _ProxySessionState state, {
    required Uri uri,
    required Map<String, String> headers,
    required String contentType,
    required int maximumBytes,
  }) {
    final key =
        '${uri.toString()}\u0000$maximumBytes\u0000${_headerFingerprint(headers)}';
    final existingToken = state.upstreamResourceTokens[key];
    if (existingToken != null) return state.resources[existingToken]!;
    final resource = _ProxyResource.upstream(
      token: _opaqueToken(),
      uri: uri,
      headers: Map.unmodifiable(sanitizeAddonHeaders(headers)),
      contentType: contentType,
      maximumBytes: maximumBytes,
    );
    state.resources[resource.token] = resource;
    state.upstreamResourceTokens[key] = resource.token;
    return resource;
  }

  Future<_LoadedBytes> _readLoadedBytes(
    WebProxyUpstreamResponse response,
    int maximumBytes, {
    required bool allowTruncation,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var truncated = false;
    await for (final chunk in response.body.timeout(
      limits.upstreamIdleTimeout,
    )) {
      final remaining = maximumBytes - bytes.length;
      if (remaining <= 0) {
        truncated = true;
        break;
      }
      if (chunk.length > remaining) {
        bytes.add(chunk.take(remaining).toList(growable: false));
        truncated = true;
        break;
      }
      bytes.add(chunk);
    }
    final declaredTotal = _declaredTotalLength(response);
    if (declaredTotal != null && declaredTotal > bytes.length) {
      truncated = true;
    }
    if (truncated && !allowTruncation) {
      throw const FormatException(
        'The upstream response exceeds the safety limit.',
      );
    }
    return _LoadedBytes(
      uri: response.uri,
      requestHeaders: response.requestHeaders,
      contentType: response.header(HttpHeaders.contentTypeHeader) ?? '',
      bytes: bytes.takeBytes(),
      truncated: truncated,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.connectionInfo?.remoteAddress.isLoopback != true) {
      await _sendError(request.response, HttpStatus.forbidden);
      return;
    }
    final match = _ownedRoute(request.uri);
    if (match == null) {
      await _sendError(request.response, HttpStatus.notFound);
      return;
    }
    final session = _sessions[match.$1];
    final resource = session?.resources[match.$2];
    if (session == null ||
        resource == null ||
        session.closed ||
        session.retainCount <= 0) {
      await _sendError(request.response, HttpStatus.notFound);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendError(request.response, HttpStatus.methodNotAllowed);
      return;
    }
    if (_activeRequests >= limits.maximumConcurrentRequests ||
        session.activeRequests >= limits.maximumSessionRequests ||
        session.totalRequests >= limits.maximumTotalSessionRequests) {
      await _sendError(request.response, HttpStatus.serviceUnavailable);
      return;
    }
    _activeRequests++;
    session.activeRequests++;
    session.totalRequests++;
    session.lastAccessedAt = _clock();
    try {
      if (resource.cachedBytes != null) {
        await _serveCached(request, resource);
      } else {
        await _serveUpstream(request, session, resource);
      }
    } on FormatException {
      await _sendFailure(request.response);
    } catch (_) {
      await _sendFailure(request.response);
    } finally {
      _activeRequests--;
      session.activeRequests--;
      session.lastAccessedAt = _clock();
      if (session.retainCount <= 0 && session.activeRequests == 0) {
        _sessions.remove(session.id);
        session.close();
      }
    }
  }

  Future<void> _serveCached(
    HttpRequest request,
    _ProxyResource resource,
  ) async {
    final bytes = resource.cachedBytes!;
    final range = _parseByteRange(
      request.headers.value(HttpHeaders.rangeHeader),
      bytes.length,
    );
    final start = range?.$1 ?? 0;
    final end = range?.$2 ?? bytes.length - 1;
    final selected = bytes.sublist(start, end + 1);
    request.response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      resource.contentType,
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.contentLength = selected.length;
    if (range != null) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      );
    }
    if (request.method == 'GET') request.response.add(selected);
    await request.response.close();
  }

  Future<void> _serveUpstream(
    HttpRequest request,
    _ProxySessionState session,
    _ProxyResource resource,
  ) async {
    final range = _sanitizeRange(
      request.headers.value(HttpHeaders.rangeHeader),
    );
    final ifRange = range == null
        ? null
        : _sanitizeIfRange(request.headers.value(HttpHeaders.ifRangeHeader));
    final upstreamResponse = await upstream.fetch(
      resource.upstreamUri!,
      method: request.method,
      headers: resource.headers,
      range: range,
      ifRange: ifRange,
    );
    session.activeUpstreams.add(upstreamResponse);
    try {
      _requireSuccess(upstreamResponse.statusCode);
      final declaredTotal = _declaredTotalLength(upstreamResponse);
      if (declaredTotal != null && declaredTotal > resource.maximumBytes) {
        throw const FormatException(
          'The upstream response exceeds the per-request safety limit.',
        );
      }
      request.response.statusCode = upstreamResponse.statusCode;
      _copySafeResponseHeaders(upstreamResponse, request.response);
      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }
      var written = 0;
      await for (final chunk in upstreamResponse.body.timeout(
        limits.upstreamIdleTimeout,
      )) {
        written += chunk.length;
        if (written > resource.maximumBytes) {
          throw const FormatException(
            'The upstream response exceeded the streaming safety limit.',
          );
        }
        request.response.add(chunk);
      }
      await request.response.close();
    } finally {
      session.activeUpstreams.remove(upstreamResponse);
      await upstreamResponse.close();
    }
  }

  void _copySafeResponseHeaders(
    WebProxyUpstreamResponse upstreamResponse,
    HttpResponse response,
  ) {
    const allowed = {
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.lastModifiedHeader,
      HttpHeaders.etagHeader,
    };
    for (final name in allowed) {
      final value = upstreamResponse.header(name);
      if (value != null && !value.contains(RegExp(r'[\r\n]'))) {
        response.headers.set(name, value);
      }
    }
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  Future<void> _sendError(HttpResponse response, int status) async {
    response.statusCode = status;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = 0;
    await response.close();
  }

  Future<void> _sendFailure(HttpResponse response) async {
    try {
      response.statusCode = HttpStatus.badGateway;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = 0;
    } catch (_) {
      // Headers may already be committed by a bounded streaming response.
    }
    try {
      await response.close();
    } catch (_) {
      // The client may already have disconnected after a truncated response.
    }
  }

  Uri _resourceUri(String sessionId, String token) {
    final server = _server;
    if (server == null) throw StateError('The playback proxy is not running.');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['tetotv-web', 'v1', sessionId, token],
    );
  }

  (String, String)? _ownedRoute(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'tetotv-web' ||
        segments[1] != 'v1' ||
        !_isOpaqueToken(segments[2]) ||
        !_isOpaqueToken(segments[3]) ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    return (segments[2], segments[3]);
  }

  String? _sessionIdFromOwnedUri(Uri uri) {
    final server = _server;
    if (server == null ||
        uri.scheme != 'http' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.port != server.port) {
      return null;
    }
    return _ownedRoute(uri)?.$1;
  }

  String _opaqueToken() {
    final bytes = Uint8List(24);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = _random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _removeExpiredSessions() {
    final now = _clock();
    final expired = _sessions.values
        .where(
          (session) =>
              session.activeRequests == 0 &&
              (now.difference(session.createdAt) > limits.sessionMaximumAge ||
                  (session.retainCount <= 0 &&
                      now.difference(session.lastAccessedAt) >
                          limits.sessionIdleTimeout)),
        )
        .map((session) => session.id)
        .toList(growable: false);
    for (final id in expired) {
      _sessions.remove(id)?.close();
    }
  }
}

enum _RootResourceKind { progressive, hls }

class _LoadedBytes {
  const _LoadedBytes({
    required this.uri,
    required this.requestHeaders,
    required this.contentType,
    required this.bytes,
    required this.truncated,
  });

  final Uri uri;
  final Map<String, String> requestHeaders;
  final String contentType;
  final List<int> bytes;
  final bool truncated;

  String get text => utf8.decode(bytes, allowMalformed: true);
}

class _ProxyResource {
  const _ProxyResource._({
    required this.token,
    required this.contentType,
    required this.maximumBytes,
    this.cachedBytes,
    this.upstreamUri,
    this.headers = const {},
  });

  factory _ProxyResource.cached({
    required String token,
    required List<int> bytes,
    required String contentType,
  }) => _ProxyResource._(
    token: token,
    cachedBytes: List.unmodifiable(bytes),
    contentType: contentType,
    maximumBytes: bytes.length,
  );

  factory _ProxyResource.upstream({
    required String token,
    required Uri uri,
    required Map<String, String> headers,
    required String contentType,
    required int maximumBytes,
  }) => _ProxyResource._(
    token: token,
    upstreamUri: uri,
    headers: headers,
    contentType: contentType,
    maximumBytes: maximumBytes,
  );

  final String token;
  final Uri? upstreamUri;
  final Map<String, String> headers;
  final List<int>? cachedBytes;
  final String contentType;
  final int maximumBytes;
}

class _ProxySessionState {
  _ProxySessionState({
    required this.id,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  final String id;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  final Map<String, _ProxyResource> resources = {};
  final Map<String, String> upstreamResourceTokens = {};
  final Set<Uri> activeManifestUris = {};
  final Set<WebProxyUpstreamResponse> activeUpstreams = {};
  int activeRequests = 0;
  int totalRequests = 0;
  int retainCount = 1;
  String? playbackToken;
  String? subtitleToken;
  String contentType = 'application/octet-stream';
  String? subtitleContentType;
  bool subtitleRejected = false;
  bool closed = false;

  void close() {
    closed = true;
    for (final response in activeUpstreams) {
      unawaited(response.close());
    }
    activeUpstreams.clear();
    resources.clear();
    upstreamResourceTokens.clear();
    activeManifestUris.clear();
  }
}

class _ManifestBudget {
  _ManifestBudget(this.limits);

  final WebPlaybackProxyLimits limits;
  final Set<Uri> manifests = {};
  int references = 0;

  void addManifest(Uri uri) {
    if (manifests.add(uri) &&
        manifests.length > limits.maximumNestedManifests) {
      throw const FormatException('The HLS manifest count is too large.');
    }
  }

  void addReference() {
    references++;
    if (references > limits.maximumManifestReferences) {
      throw const FormatException('The HLS reference count is too large.');
    }
  }
}

/// One wall-clock budget shared by every validation, request, body read, and
/// recursive manifest step performed while a session is being prepared.
///
/// Future.timeout cannot cancel an arbitrary future. The guarded continuation
/// therefore closes any response that arrives after cancellation and every
/// caller checks this token immediately before mutating the candidate session.
class _PreparationBudget {
  _PreparationBudget({required this.clock, required this.deadline});

  final DateTime Function() clock;
  final DateTime deadline;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void check() {
    if (_cancelled || !clock().isBefore(deadline)) {
      _cancelled = true;
      throw const FormatException('Web playback preparation timed out.');
    }
  }

  Future<T> wait<T>(Future<T> operation) async {
    check();
    final remaining = deadline.difference(clock());
    final guarded = operation.then((value) {
      if (_cancelled && value is WebProxyUpstreamResponse) {
        unawaited(value.close());
      }
      return value;
    });
    try {
      final value = await guarded.timeout(remaining);
      check();
      return value;
    } on TimeoutException {
      _cancelled = true;
      throw const FormatException('Web playback preparation timed out.');
    }
  }
}

Uri _resolvePublicHttps(Uri base, String rawReference) {
  final value = rawReference.trim();
  if (value.isEmpty ||
      value.length > 2048 ||
      value.contains(RegExp(r'[\x00-\x1F]')) ||
      value.contains(r'{$')) {
    throw const FormatException('The manifest contains an unsafe URI.');
  }
  final resolved = base.resolve(value);
  final safe = safePublicHttpsUri(resolved.toString());
  if (safe == null) {
    throw const FormatException(
      'Manifest resources must use public HTTPS addresses.',
    );
  }
  return safe;
}

String _mimeType(String value) => value.toLowerCase().split(';').first.trim();

bool _sameOrigin(Uri left, Uri right) =>
    left.scheme == right.scheme &&
    left.host.toLowerCase() == right.host.toLowerCase() &&
    left.port == right.port;

bool _isRedirect(int status) => const {
  HttpStatus.movedPermanently,
  HttpStatus.found,
  HttpStatus.seeOther,
  HttpStatus.temporaryRedirect,
  HttpStatus.permanentRedirect,
}.contains(status);

void _requireSuccess(int status) {
  if (status < 200 || status >= 300) {
    throw FormatException('The upstream resource returned HTTP $status.');
  }
}

int? _declaredTotalLength(WebProxyUpstreamResponse response) {
  final contentRange = response.header(HttpHeaders.contentRangeHeader);
  final total = contentRange == null
      ? null
      : RegExp(r'/([0-9]+)$').firstMatch(contentRange)?.group(1);
  return int.tryParse(
    total ?? response.header(HttpHeaders.contentLengthHeader) ?? '',
  );
}

String? _sanitizeRange(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.length > 80 ||
      !RegExp(r'^bytes=(?:[0-9]+-[0-9]*|-[0-9]+)$').hasMatch(trimmed)) {
    throw const FormatException('Only one bounded byte range is supported.');
  }
  return trimmed;
}

String? _sanitizeIfRange(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 256 ||
      trimmed.contains(RegExp(r'[\r\n\x00]'))) {
    throw const FormatException('The If-Range validator is invalid.');
  }
  return trimmed;
}

(int, int)? _parseByteRange(String? value, int length) {
  final range = _sanitizeRange(value);
  if (range == null || length == 0) return null;
  final spec = range.substring(6);
  final pieces = spec.split('-');
  int start;
  int end;
  if (pieces[0].isEmpty) {
    final suffix = int.parse(pieces[1]);
    if (suffix <= 0) throw const FormatException('Invalid byte range.');
    start = max(0, length - suffix);
    end = length - 1;
  } else {
    start = int.parse(pieces[0]);
    end = pieces[1].isEmpty ? length - 1 : int.parse(pieces[1]);
  }
  if (start < 0 || start >= length || end < start) {
    throw const FormatException('The byte range is outside the resource.');
  }
  return (start, min(end, length - 1));
}

bool _isSupportedSubtitle(_LoadedBytes loaded) {
  final mime = _mimeType(loaded.contentType);
  final text = loaded.text.trimLeft();
  if (text.isEmpty ||
      mime == 'text/html' ||
      text.toLowerCase().startsWith('<!doctype html')) {
    return false;
  }
  final signature =
      text.startsWith('WEBVTT') ||
      text.contains('-->') ||
      text.startsWith('[Script Info]') ||
      RegExp(r'<(?:\w+:)?tt(?:\s|>)', caseSensitive: false).hasMatch(text);
  return signature &&
      const {
        'text/vtt',
        'text/plain',
        'application/x-subrip',
        'application/srt',
        'text/x-ssa',
        'text/x-ass',
        'application/ttml+xml',
        'application/xml',
        'text/xml',
        'application/octet-stream',
      }.contains(mime);
}

String _subtitleContentType(_LoadedBytes loaded) {
  final text = loaded.text.trimLeft();
  if (text.startsWith('WEBVTT')) return 'text/vtt';
  if (text.startsWith('[Script Info]')) return 'text/x-ssa';
  if (RegExp(r'<(?:\w+:)?tt(?:\s|>)', caseSensitive: false).hasMatch(text)) {
    return 'application/ttml+xml';
  }
  if (text.contains('-->')) return 'application/x-subrip';
  throw const FormatException('The external subtitle is not supported.');
}

String _headerFingerprint(Map<String, String> headers) {
  final entries = headers.entries.toList()
    ..sort(
      (left, right) =>
          left.key.toLowerCase().compareTo(right.key.toLowerCase()),
    );
  return entries
      .map((entry) => '${entry.key.toLowerCase()}=${entry.value}')
      .join('&');
}

bool _isOpaqueToken(String value) =>
    value.length == 32 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
