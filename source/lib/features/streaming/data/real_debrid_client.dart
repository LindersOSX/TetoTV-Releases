import 'package:anime_tv/features/streaming/data/real_debrid_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:dio/dio.dart';

/// Describes whether retrying a different release can recover a failed
/// Real-Debrid request.
enum RealDebridFailureKind {
  /// The selected file or torrent cannot be handled, but another release may
  /// still work.
  releaseUnavailable,

  /// The access token is missing, invalid, or lacks permission.
  authorization,

  /// The account is locked, inactive, out of traffic, or otherwise unable to
  /// perform downloads until the user fixes the account.
  account,

  /// Real-Debrid asked the client to slow down.
  rateLimited,

  /// A temporary provider or network-side failure.
  transient,

  /// The API did not provide enough information to classify the failure.
  unknown,
}

class RealDebridException implements DebridProviderFailure {
  const RealDebridException(
    this.message, {
    this.code,
    this.kind = RealDebridFailureKind.unknown,
  });

  final String message;
  final int? code;
  final RealDebridFailureKind kind;

  /// Authentication and account failures apply to every release. Candidate
  /// failover must stop and let the user repair their Real-Debrid connection.
  bool get isTerminalAccountFailure =>
      kind == RealDebridFailureKind.authorization ||
      kind == RealDebridFailureKind.account;

  bool get isCandidateSpecific =>
      kind == RealDebridFailureKind.releaseUnavailable;

  /// Whether selecting a different torrent/file is a meaningful recovery.
  /// Refused requests count against Real-Debrid limits, so transient, rate,
  /// account, authorization, and unknown failures must not fan out.
  bool get canTryAnotherRelease => isCandidateSpecific;

  @override
  DebridFailureCategory get failureCategory => switch (kind) {
    RealDebridFailureKind.releaseUnavailable =>
      DebridFailureCategory.releaseUnavailable,
    RealDebridFailureKind.authorization => DebridFailureCategory.authorization,
    RealDebridFailureKind.account => DebridFailureCategory.account,
    RealDebridFailureKind.rateLimited => DebridFailureCategory.rateLimited,
    RealDebridFailureKind.transient ||
    RealDebridFailureKind.unknown => DebridFailureCategory.serviceUnavailable,
  };

  factory RealDebridException.fromApi({required int? code, int? httpStatus}) {
    if (code != null) {
      if (_authorizationErrorCodes.contains(code)) {
        return RealDebridException(
          'Your Real-Debrid connection has expired or is not authorized. '
          'Reconnect it in Accounts.',
          code: code,
          kind: RealDebridFailureKind.authorization,
        );
      }
      if (_accountErrorCodes.contains(code)) {
        return RealDebridException(
          'Your Real-Debrid account cannot start downloads right now. '
          'Check the account status and Premium traffic, then try again.',
          code: code,
          kind: RealDebridFailureKind.account,
        );
      }
      if (_releaseErrorCodes.contains(code)) {
        return RealDebridException(
          _releaseFailureMessage(code),
          code: code,
          kind: RealDebridFailureKind.releaseUnavailable,
        );
      }
      if (_rateLimitErrorCodes.contains(code)) {
        return RealDebridException(
          'Real-Debrid is receiving too many requests. Wait a moment and try '
          'again.',
          code: code,
          kind: RealDebridFailureKind.rateLimited,
        );
      }
      if (_transientErrorCodes.contains(code)) {
        return RealDebridException(
          'Real-Debrid is temporarily unable to process this release. Try '
          'again shortly.',
          code: code,
          kind: RealDebridFailureKind.transient,
        );
      }
    }
    if (httpStatus == 401 || httpStatus == 403) {
      return RealDebridException(
        'Your Real-Debrid connection has expired or is not authorized. '
        'Reconnect it in Accounts.',
        code: code ?? httpStatus,
        kind: RealDebridFailureKind.authorization,
      );
    }
    if (httpStatus == 429) {
      return RealDebridException(
        'Real-Debrid is receiving too many requests. Wait a moment and try '
        'again.',
        code: code ?? httpStatus,
        kind: RealDebridFailureKind.rateLimited,
      );
    }
    if (httpStatus != null && httpStatus >= 500) {
      return RealDebridException(
        'Real-Debrid is temporarily unavailable. Try again shortly.',
        code: code ?? httpStatus,
        kind: RealDebridFailureKind.transient,
      );
    }
    return RealDebridException(
      'Real-Debrid could not process this request.',
      code: code ?? httpStatus,
    );
  }

  @override
  String toString() => message;
}

// Real-Debrid REST API error codes. Keep the raw API message out of the UI:
// values such as `infringing_file` are implementation details and make it
// sound as if the whole episode is unavailable when only one release failed.
const _authorizationErrorCodes = {8, 9, 10, 11, 12, 13};
const _accountErrorCodes = {14, 15, 20, 21, 22, 23, 36};
const _releaseErrorCodes = {7, 16, 24, 28, 29, 30, 35};
const _rateLimitErrorCodes = {5, 34};
const _transientErrorCodes = {6, 17, 18, 19, 25, 37};

String _releaseFailureMessage(int code) => switch (code) {
  29 => 'This release is too large for Real-Debrid. Choose another release.',
  30 => 'This release contains an invalid torrent. Choose another release.',
  35 =>
    'Real-Debrid cannot provide this release. TetoTV can try a different '
        'release.',
  _ =>
    'This release is unavailable through Real-Debrid. Choose another release.',
};

class RealDebridClient {
  RealDebridClient({required String token, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.real-debrid.com/rest/1.0',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
              maxRedirects: 0,
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            ),
          );

  final Dio _dio;

  Future<RealDebridAccount> account() async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.get('/user'),
    );
    return RealDebridAccount.fromJson(response.data!);
  }

  Future<String> addMagnet(String magnetUri) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.post(
        '/torrents/addMagnet',
        data: {'magnet': magnetUri},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    return response.data!['id'] as String;
  }

  Future<RealDebridTorrentInfo> torrentInfo(String id) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.get('/torrents/info/$id'),
    );
    return RealDebridTorrentInfo.fromJson(response.data!);
  }

  Future<void> selectFiles(String id, Iterable<int> fileIds) async {
    final selected = fileIds.join(',');
    if (selected.isEmpty) {
      throw const RealDebridException('No playable torrent files were found.');
    }
    await _request<void>(
      () => _dio.post(
        '/torrents/selectFiles/$id',
        data: {'files': selected},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (status) =>
              status != null && (status == 202 || status < 400),
        ),
      ),
    );
  }

  Future<void> deleteTorrent(String id) async {
    await _request<void>(
      () => _dio.delete(
        '/torrents/delete/$id',
        options: Options(
          validateStatus: (status) =>
              status != null && (status == 204 || status == 404),
        ),
      ),
    );
  }

  Future<RealDebridUnrestrictedLink> unrestrict(String link) async {
    final response = await _request<Map<String, dynamic>>(
      () => _dio.post(
        '/unrestrict/link',
        data: {'link': link},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
    );
    return RealDebridUnrestrictedLink.fromJson(response.data!);
  }

  Future<Response<T>> _request<T>(
    Future<Response<T>> Function() operation,
  ) async {
    try {
      return await operation();
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        throw RealDebridException.fromApi(
          code: switch (data['error_code']) {
            final int value => value,
            final num value => value.toInt(),
            final String value => int.tryParse(value),
            _ => null,
          },
          httpStatus: error.response?.statusCode,
        );
      }
      final status = error.response?.statusCode;
      if (status != null) {
        throw RealDebridException.fromApi(httpStatus: status, code: null);
      }
      throw RealDebridException(
        error.message ?? 'Could not reach Real-Debrid.',
        code: error.response?.statusCode,
      );
    }
  }
}
