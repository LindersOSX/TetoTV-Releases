import 'dart:convert';
import 'dart:io';

class AddonRepository {
  const AddonRepository({
    required this.url,
    this.enabled = true,
    this.isDefault = false,
    required this.updatedAt,
  });

  final String url;
  final bool enabled;
  final bool isDefault;
  final DateTime updatedAt;

  AddonRepository copyWith({bool? enabled, DateTime? updatedAt}) =>
      AddonRepository(
        url: url,
        enabled: enabled ?? this.enabled,
        isDefault: isDefault,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class MarketplaceAddon {
  const MarketplaceAddon({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.manifestUri,
    required this.repositoryUrl,
    required this.language,
    required this.type,
    required this.locale,
    this.version,
    this.iconUri,
    this.payloadUri,
    this.inlinePayload,
    this.userConfigDefaults = const {},
  });

  final String id;
  final String name;
  final String description;
  final String author;
  final Uri manifestUri;
  final String repositoryUrl;
  final String language;
  final String type;
  final String locale;
  final String? version;
  final Uri? iconUri;
  final Uri? payloadUri;
  final String? inlinePayload;
  final Map<String, String> userConfigDefaults;

  bool get isOnlineStreamProvider => type == 'onlinestream-provider';
  bool get isJavascript => language.toLowerCase() == 'javascript';
  bool get isTypescript => language.toLowerCase() == 'typescript';
  bool get isCompatible =>
      isOnlineStreamProvider && (isJavascript || isTypescript);

  MarketplaceAddon mergeManifest(MarketplaceAddon manifest) => MarketplaceAddon(
    id: id,
    name: manifest.name,
    description: manifest.description,
    author: manifest.author,
    manifestUri: manifestUri,
    repositoryUrl: repositoryUrl,
    language: manifest.language,
    type: manifest.type,
    locale: manifest.locale,
    version: manifest.version,
    iconUri: manifest.iconUri ?? iconUri,
    payloadUri: manifest.payloadUri,
    inlinePayload: manifest.inlinePayload,
    userConfigDefaults: manifest.userConfigDefaults,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'author': author,
    'manifestURI': manifestUri.toString(),
    'repositoryURL': repositoryUrl,
    'language': language,
    'type': type,
    'lang': locale,
    'version': version,
    'icon': iconUri?.toString(),
    'payloadURI': payloadUri?.toString(),
    if (userConfigDefaults.isNotEmpty)
      'userConfig': {
        'fields': [
          for (final entry in userConfigDefaults.entries)
            {'name': entry.key, 'default': entry.value},
        ],
      },
  };

  static MarketplaceAddon? tryParse(
    Object? value, {
    required String repositoryUrl,
  }) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry('$key', value));
    final id = _clean(json['id'], 80);
    final name = _clean(json['name'], 120);
    final manifest = safePublicHttpsUri(json['manifestURI']);
    if (id == null ||
        name == null ||
        manifest == null ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      return null;
    }
    return MarketplaceAddon(
      id: id,
      name: name,
      description: _clean(json['description'], 600) ?? '',
      author: _clean(json['author'], 120) ?? 'Unknown',
      manifestUri: manifest,
      repositoryUrl: repositoryUrl,
      language: (_clean(json['language'], 24) ?? '').toLowerCase(),
      type: (_clean(json['type'], 48) ?? '').toLowerCase(),
      locale: (_clean(json['lang'], 12) ?? 'unknown').toLowerCase(),
      version: _clean(json['version'], 32),
      iconUri: safePublicHttpsUri(json['icon']),
      payloadUri: safePublicHttpsUri(json['payloadURI']),
      inlinePayload: _cleanPayload(json['payload']),
      userConfigDefaults: _userConfigDefaults(json['userConfig']),
    );
  }
}

Map<String, String> _userConfigDefaults(Object? value) {
  if (value is! Map || value['fields'] is! List) return const {};
  final result = <String, String>{};
  for (final raw in (value['fields'] as List).take(32)) {
    if (raw is! Map) continue;
    final name = _clean(raw['name'], 80);
    final defaultValue = _clean(raw['default'], 2048);
    if (name != null &&
        defaultValue != null &&
        RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      result[name] = defaultValue;
    }
  }
  return Map.unmodifiable(result);
}

String? _cleanPayload(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  if (utf8.encode(value).length > 768 * 1024) return null;
  return value;
}

class InstalledStreamingAddon {
  const InstalledStreamingAddon({
    required this.manifest,
    required this.payload,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
  });

  final MarketplaceAddon manifest;
  final String payload;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;

  InstalledStreamingAddon copyWith({bool? enabled}) => InstalledStreamingAddon(
    manifest: manifest,
    payload: payload,
    enabled: enabled ?? this.enabled,
    installedAt: installedAt,
    updatedAt: updatedAt,
  );

  factory InstalledStreamingAddon.fromRow(Map<String, Object?> row) {
    final raw = jsonDecode(row['manifest_json']! as String);
    final manifest = MarketplaceAddon.tryParse(
      raw,
      repositoryUrl: row['repository_url']! as String,
    );
    if (manifest == null) throw const FormatException('Invalid addon manifest');
    return InstalledStreamingAddon(
      manifest: manifest,
      payload: row['payload']! as String,
      enabled: row['enabled'] == 1,
      installedAt: DateTime.fromMillisecondsSinceEpoch(
        row['installed_at']! as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }
}

class WebStreamResult {
  const WebStreamResult({
    required this.providerId,
    required this.providerName,
    required this.title,
    required this.uri,
    this.quality,
    this.headers = const {},
    this.subtitleUri,
    this.subtitleLanguage,
    this.isDubbed = false,
  });

  final String providerId;
  final String providerName;
  final String title;
  final Uri uri;
  final String? quality;
  final Map<String, String> headers;
  final Uri? subtitleUri;
  final String? subtitleLanguage;
  final bool isDubbed;
}

class WebProviderFailure {
  const WebProviderFailure({required this.providerName, required this.message});

  final String providerName;
  final String message;
}

class WebStreamAggregation {
  const WebStreamAggregation({
    this.streams = const [],
    this.failures = const [],
  });

  final List<WebStreamResult> streams;
  final List<WebProviderFailure> failures;
}

Uri? safePublicHttpsUri(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      host == 'localhost' ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      _literalAddressIsNonPublic(host)) {
    return null;
  }
  return uri;
}

typedef PublicHostLookup = Future<List<InternetAddress>> Function(String host);

Future<List<InternetAddress>> resolvePublicNetworkTarget(
  Uri uri, {
  PublicHostLookup? lookup,
}) async {
  if (safePublicHttpsUri(uri.toString()) == null) {
    throw const FormatException('Only public HTTPS resources are allowed.');
  }
  final addresses = await (lookup ?? InternetAddress.lookup)(
    uri.host,
  ).timeout(const Duration(seconds: 4));
  if (addresses.isEmpty || addresses.any(_isNonPublicAddress)) {
    throw const FormatException(
      'The resource host does not resolve to a public address.',
    );
  }
  return List<InternetAddress>.unmodifiable(addresses);
}

Future<void> validatePublicNetworkTarget(
  Uri uri, {
  PublicHostLookup? lookup,
}) async {
  await resolvePublicNetworkTarget(uri, lookup: lookup);
}

/// Creates an HTTPS client whose socket is connected to the exact public IP
/// address that was validated for the request. This closes the DNS-rebinding
/// gap between a preflight lookup and the operating system's later connect.
///
/// TLS still authenticates [Uri.host] (including SNI); certificates are never
/// accepted for the pinned IP address and no bad-certificate callback is used.
HttpClient createPinnedPublicHttpsClient({PublicHostLookup? lookup}) {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null || proxyPort != null) {
      throw const FormatException(
        'Network proxies are not permitted for addon resources.',
      );
    }
    final addresses = await resolvePublicNetworkTarget(uri, lookup: lookup);
    ConnectionTask<Socket>? activeTask;
    Socket? connectedSocket;
    var cancelled = false;
    final secureSocket = () async {
      Object? lastError;
      StackTrace? lastStack;
      for (final address in addresses) {
        if (cancelled) {
          throw const SocketException('Connection attempt was cancelled.');
        }
        try {
          activeTask = await Socket.startConnect(address, uri.port);
          final socket = await activeTask!.socket;
          connectedSocket = socket;
          if (cancelled) {
            socket.destroy();
            throw const SocketException('Connection attempt was cancelled.');
          }
          return await SecureSocket.secure(
            socket,
            host: uri.host,
            supportedProtocols: const ['http/1.1'],
          );
        } catch (error, stackTrace) {
          connectedSocket?.destroy();
          connectedSocket = null;
          if (cancelled) rethrow;
          lastError = error;
          lastStack = stackTrace;
        }
      }
      Error.throwWithStackTrace(
        lastError ?? const SocketException('No public address was available.'),
        lastStack ?? StackTrace.current,
      );
    }();
    return ConnectionTask.fromSocket<Socket>(secureSocket, () {
      cancelled = true;
      activeTask?.cancel();
      connectedSocket?.destroy();
    });
  };
  return client;
}

bool _literalAddressIsNonPublic(String host) {
  final address = InternetAddress.tryParse(host);
  return address != null && _isNonPublicAddress(address);
}

bool _isNonPublicAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) return true;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    return _isNonPublicIpv4(bytes);
  }
  if (bytes.length != 16) return true;

  // IPv4-mapped IPv6 (::ffff:a.b.c.d) must be checked using the embedded
  // IPv4 address. Otherwise loopback/RFC1918 literals can bypass IPv4 guards.
  final isIpv4Mapped =
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (isIpv4Mapped) return _isNonPublicIpv4(bytes.sublist(12));

  final isUnspecified = bytes.every((byte) => byte == 0);
  final isLoopback =
      bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
  final isIpv4Compatible = bytes.take(12).every((byte) => byte == 0);
  final isUniqueLocal = (bytes[0] & 0xfe) == 0xfc; // fc00::/7
  final isLinkLocal =
      bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80; // fe80::/10
  final isSiteLocal =
      bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0xc0; // fec0::/10
  final isMulticast = bytes[0] == 0xff; // ff00::/8
  final isDocumentation =
      bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x0d &&
      bytes[3] == 0xb8; // 2001:db8::/32
  final isNat64WellKnown =
      bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes.sublist(4, 12).every((byte) => byte == 0);
  final nat64MapsNonPublic =
      isNat64WellKnown && _isNonPublicIpv4(bytes.sublist(12));
  final isNat64LocalUse =
      bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes[4] == 0x00 &&
      bytes[5] == 0x01; // 64:ff9b:1::/48 (RFC 8215 local-use translation)
  final is6to4 = bytes[0] == 0x20 && bytes[1] == 0x02;
  final sixToFourMapsNonPublic =
      is6to4 && _isNonPublicIpv4(bytes.sublist(2, 6));
  return isUnspecified ||
      isLoopback ||
      isIpv4Compatible ||
      isUniqueLocal ||
      isLinkLocal ||
      isSiteLocal ||
      isMulticast ||
      isDocumentation ||
      nat64MapsNonPublic ||
      isNat64LocalUse ||
      sixToFourMapsNonPublic;
}

bool _isNonPublicIpv4(List<int> bytes) {
  if (bytes.length != 4) return true;
  final first = bytes[0];
  final second = bytes[1];
  final third = bytes[2];
  return first == 0 || // current network / unspecified
      first == 10 || // RFC1918
      (first == 100 && second >= 64 && second <= 127) || // CGNAT
      first == 127 || // loopback
      (first == 169 && second == 254) || // link-local
      (first == 172 && second >= 16 && second <= 31) || // RFC1918
      (first == 192 && second == 0 && third == 0) || // IETF assignments
      (first == 192 && second == 0 && third == 2) || // documentation
      (first == 192 && second == 88 && third == 99) || // deprecated 6to4
      (first == 192 && second == 168) || // RFC1918
      (first == 198 && (second == 18 || second == 19)) || // benchmarking
      (first == 198 && second == 51 && third == 100) || // documentation
      (first == 203 && second == 0 && third == 113) || // documentation
      first >= 224; // multicast, reserved, limited broadcast
}

String? _clean(Object? value, int maximum) {
  if (value is! String) return null;
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length <= maximum ? cleaned : cleaned.substring(0, maximum);
}
