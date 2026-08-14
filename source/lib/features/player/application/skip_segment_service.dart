import 'dart:math' as math;

import 'package:dio/dio.dart';

enum SkipSegmentKind { opening, ending, recap }

enum SkipSegmentSource { embeddedChapter, aniSkip }

class SkipSegment {
  const SkipSegment({
    required this.start,
    required this.end,
    required this.kind,
    required this.source,
  });

  final Duration start;
  final Duration end;
  final SkipSegmentKind kind;
  final SkipSegmentSource source;

  Duration get duration => end - start;

  String get actionLabel => switch (kind) {
    SkipSegmentKind.opening => 'Skip intro',
    SkipSegmentKind.ending => 'Skip outro',
    SkipSegmentKind.recap => 'Skip recap',
  };

  bool contains(Duration position) => position >= start && position < end;
}

class MediaChapter {
  const MediaChapter({required this.title, required this.start});

  final String title;
  final Duration start;
}

class AniSkipClient {
  AniSkipClient({Dio? dio, this.retryDelay = const Duration(milliseconds: 600)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;
  final Duration retryDelay;

  Future<List<SkipSegment>> segments({
    required int malMediaId,
    required int episode,
    required Duration episodeDuration,
  }) async {
    if (malMediaId <= 0 || episode <= 0 || episodeDuration.inSeconds <= 0) {
      return const [];
    }
    final episodeLength = episodeDuration.inMilliseconds / 1000;
    final uri = Uri.parse(
      'https://api.aniskip.com/v2/skip-times/$malMediaId/$episode?'
      'types%5B%5D=op&types%5B%5D=ed&types%5B%5D=mixed-op&'
      'types%5B%5D=mixed-ed&types%5B%5D=recap&'
      'episodeLength=$episodeLength',
    );
    Response<Map<String, dynamic>>? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = await _dio.getUri<Map<String, dynamic>>(uri);
        break;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final retryable =
            status == 429 ||
            (status != null && status >= 500) ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.unknown;
        if (!retryable || attempt == 1) rethrow;
        await Future<void>.delayed(retryDelay);
      }
    }
    if (response == null) return const [];
    final body = response.data;
    if (body == null || body['found'] != true || body['results'] is! List) {
      return const [];
    }
    final actualSeconds = episodeDuration.inMilliseconds / 1000;
    // Container runtimes can include/exclude credits or round broadcast
    // durations. AniSkip markers are still valid when that small difference is
    // present, so use a conservative five-percent window with a 45s floor.
    final durationTolerance = math.max(45.0, actualSeconds * .05);
    final candidates = <({SkipSegment segment, double durationDelta})>[];
    for (final item in body['results'] as List) {
      if (item is! Map) continue;
      final interval = item['interval'];
      final start = interval is Map ? interval['startTime'] : null;
      final end = interval is Map ? interval['endTime'] : null;
      final referenceLength = item['episodeLength'];
      if (start is! num || end is! num) continue;
      final durationDelta = referenceLength is num
          ? (referenceLength.toDouble() - actualSeconds).abs()
          : 0.0;
      if (durationDelta > durationTolerance) continue;
      final startSeconds = start.toDouble().clamp(0, actualSeconds);
      final endSeconds = end.toDouble().clamp(0, actualSeconds);
      if (endSeconds - startSeconds < 8 || endSeconds - startSeconds > 240) {
        continue;
      }
      final kind = _aniSkipKind(item['skipType']?.toString());
      if (kind == null) continue;
      candidates.add((
        segment: SkipSegment(
          start: Duration(milliseconds: (startSeconds * 1000).round()),
          end: Duration(milliseconds: (endSeconds * 1000).round()),
          kind: kind,
          source: SkipSegmentSource.aniSkip,
        ),
        durationDelta: durationDelta,
      ));
    }
    candidates.sort((a, b) => a.durationDelta.compareTo(b.durationDelta));
    final selected = <SkipSegment>[];
    for (final candidate in candidates) {
      final duplicate = selected.any(
        (existing) =>
            existing.kind == candidate.segment.kind &&
            _overlapRatio(existing, candidate.segment) >= .65,
      );
      if (!duplicate) selected.add(candidate.segment);
    }
    selected.sort((a, b) => a.start.compareTo(b.start));
    return selected;
  }
}

List<SkipSegment> skipSegmentsFromChapters(
  List<MediaChapter> chapters,
  Duration mediaDuration,
) {
  if (chapters.isEmpty || mediaDuration <= Duration.zero) return const [];
  final ordered = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
  final result = <SkipSegment>[];
  for (var index = 0; index < ordered.length; index++) {
    final chapter = ordered[index];
    final kind = _chapterKind(chapter.title);
    if (kind == null) continue;
    final end = index + 1 < ordered.length
        ? ordered[index + 1].start
        : mediaDuration;
    final segment = SkipSegment(
      start: chapter.start,
      end: end > mediaDuration ? mediaDuration : end,
      kind: kind,
      source: SkipSegmentSource.embeddedChapter,
    );
    if (segment.duration >= const Duration(seconds: 8) &&
        segment.duration <= const Duration(minutes: 4)) {
      result.add(segment);
    }
  }
  return result;
}

List<SkipSegment> mergeSkipSegments(
  List<SkipSegment> embedded,
  List<SkipSegment> external,
) {
  final result = [...embedded];
  for (final candidate in external) {
    if (result.any(
      (existing) =>
          existing.kind == candidate.kind &&
          _overlapRatio(existing, candidate) >= .5,
    )) {
      continue;
    }
    result.add(candidate);
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

SkipSegmentKind? _aniSkipKind(String? value) => switch (value) {
  'op' || 'mixed-op' => SkipSegmentKind.opening,
  'ed' || 'mixed-ed' => SkipSegmentKind.ending,
  'recap' => SkipSegmentKind.recap,
  _ => null,
};

SkipSegmentKind? _chapterKind(String title) {
  final normalized = title
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-.]+'), ' ')
      .trim();
  if (RegExp(
    r'(^|\b)(opening|op|intro)(?:\s*\d+)?(\b|$)',
  ).hasMatch(normalized)) {
    return SkipSegmentKind.opening;
  }
  if (RegExp(
    r'(^|\b)(ending|ed|outro|credits)(?:\s*\d+)?(\b|$)',
  ).hasMatch(normalized)) {
    return SkipSegmentKind.ending;
  }
  if (RegExp(r'(^|\b)(recap|previously)(\b|$)').hasMatch(normalized)) {
    return SkipSegmentKind.recap;
  }
  return null;
}

double _overlapRatio(SkipSegment left, SkipSegment right) {
  final start = math.max(left.start.inMilliseconds, right.start.inMilliseconds);
  final end = math.min(left.end.inMilliseconds, right.end.inMilliseconds);
  if (end <= start) return 0;
  final shorter = math.min(
    left.duration.inMilliseconds,
    right.duration.inMilliseconds,
  );
  return shorter <= 0 ? 0 : (end - start) / shorter;
}
