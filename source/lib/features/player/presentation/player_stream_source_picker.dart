import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/player/presentation/player_presentation_palette.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter/material.dart';

/// Converts a marketplace result into the same player-safe model used by the
/// resolver screen. No credentials or provider implementation details cross
/// this boundary; only the bounded URL, headers and optional subtitle survive.
PlaybackStreamOption playbackOptionForWebStream(WebStreamResult result) {
  final release = ReleaseCandidate(
    infoHash:
        'web:${result.providerId}:'
        '${result.uri.toString().hashCode.toUnsigned(32).toRadixString(16)}',
    magnetUri: '',
    releaseName: '${result.providerName} / ${result.title}',
    seeders: 0,
    sourceId: 'web:${result.providerId}',
    quality: result.quality,
    provider: result.providerName,
    isDubbed: result.isDubbed,
    hasSubtitles: result.subtitleUri != null,
  );
  return PlaybackStreamOption(
    stream: StreamReady(
      uri: result.uri,
      displayName: release.releaseName,
      headers: result.headers,
      externalSubtitle: result.subtitleUri,
      providerId: result.providerId,
      providerName: '${result.providerName} web stream',
    ),
    release: release,
  );
}

/// Stable within a playback session without embedding a provider's signed URL
/// or query parameters in widget diagnostics.
String playbackStreamOptionKey(PlaybackStreamOption option) =>
    '${option.stream.providerId ?? option.release.sourceId}:'
    '${option.stream.uri.toString().hashCode.toUnsigned(32).toRadixString(16)}';

bool hasUntriedDirectWebStream({
  required StreamReady current,
  required Iterable<PlaybackStreamOption> options,
  Set<String> failedUris = const {},
}) =>
    current.isWebStream &&
    options.any(
      (option) =>
          option.stream.isWebStream &&
          option.stream.uri != current.uri &&
          !failedUris.contains(option.stream.uri.toString()),
    );

int playbackStreamQualityRank(PlaybackStreamOption option) {
  final value = '${option.release.quality ?? ''} ${option.release.releaseName}'
      .toLowerCase();
  if (value.contains('4320') || value.contains('8k')) return 7;
  if (value.contains('2160') || value.contains('4k') || value.contains('uhd')) {
    return 6;
  }
  if (value.contains('1440') || value.contains('2k')) return 5;
  if (value.contains('1080') || value.contains('full hd')) return 4;
  if (value.contains('720') || RegExp(r'\bhd\b').hasMatch(value)) return 3;
  if (value.contains('576')) return 2;
  if (value.contains('480') || value.contains('360')) return 1;
  return 0;
}

int comparePlaybackStreamOptions(
  PlaybackStreamOption left,
  PlaybackStreamOption right,
) {
  final quality = playbackStreamQualityRank(
    right,
  ).compareTo(playbackStreamQualityRank(left));
  if (quality != 0) return quality;
  final leftProvider =
      left.stream.providerName ??
      left.release.provider ??
      left.release.sourceId;
  final rightProvider =
      right.stream.providerName ??
      right.release.provider ??
      right.release.sourceId;
  final provider = leftProvider.compareTo(rightProvider);
  return provider != 0
      ? provider
      : left.release.releaseName.compareTo(right.release.releaseName);
}

/// Merges late provider results without allowing the same URI to grow the
/// picker indefinitely. Existing options win so a preflighted redirect and its
/// sanitized headers are not replaced by the raw provider result.
List<PlaybackStreamOption> mergePlaybackStreamOptions(
  Iterable<PlaybackStreamOption> existing,
  Iterable<PlaybackStreamOption> discovered,
) {
  final unique = <String, PlaybackStreamOption>{};
  for (final option in [...existing, ...discovered]) {
    unique.putIfAbsent(option.stream.uri.toString(), () => option);
  }
  return unique.values.toList(growable: false)
    ..sort(comparePlaybackStreamOptions);
}

/// Replaces the provider's preflight URL with its validated destination.
/// Keeping both the raw URL and its redirect target would let recovery loop
/// through the same failed target instead of advancing to another provider.
List<PlaybackStreamOption> replaceValidatedPlaybackStreamOption({
  required Iterable<PlaybackStreamOption> options,
  required Uri requestedUri,
  required PlaybackStreamOption validated,
}) => mergePlaybackStreamOptions(
  [validated],
  options.where(
    (option) =>
        option.stream.uri != requestedUri &&
        option.stream.uri != validated.stream.uri,
  ),
);

bool validatedRedirectWasAlreadyAttempted({
  required Uri requestedUri,
  required Uri validatedUri,
  required Set<String> attemptedUris,
}) =>
    requestedUri != validatedUri &&
    attemptedUris.contains(validatedUri.toString());

List<PlaybackStreamOption> playbackStreamOptionsForHandoff({
  required StreamReady currentStream,
  required ReleaseCandidate currentRelease,
  required Iterable<PlaybackStreamOption> existing,
}) => mergePlaybackStreamOptions([
  PlaybackStreamOption(stream: currentStream, release: currentRelease),
  ...existing,
], const []);

String playbackStreamOptionLabel(PlaybackStreamOption option) {
  final quality = option.release.quality?.trim();
  final provider =
      option.stream.providerName ??
      option.release.provider ??
      option.release.sourceId;
  return [
    if (quality != null && quality.isNotEmpty) quality,
    provider,
  ].join(' | ');
}

typedef PlayerSourceDiscovery =
    Stream<WebStreamSearchProgress> Function({bool refresh});

Future<PlaybackStreamOption?> showPlayerStreamSourcePicker({
  required BuildContext context,
  required List<PlaybackStreamOption> initialOptions,
  required Uri selectedUri,
  required void Function(List<PlaybackStreamOption>) onOptionsChanged,
  PlayerSourceDiscovery? discover,
}) {
  final palette = context.appPalette;
  return showDialog<PlaybackStreamOption>(
    context: context,
    barrierColor: palette.usesDefaultPlayerPalette
        ? const Color(0x99000000)
        : palette.background.withValues(alpha: .60),
    builder: (_) => PlayerStreamSourcePicker(
      initialOptions: initialOptions,
      selectedUri: selectedUri,
      onOptionsChanged: onOptionsChanged,
      discover: discover,
    ),
  );
}

class PlayerStreamSourcePicker extends StatefulWidget {
  const PlayerStreamSourcePicker({
    required this.initialOptions,
    required this.selectedUri,
    required this.onOptionsChanged,
    this.discover,
    super.key,
  });

  final List<PlaybackStreamOption> initialOptions;
  final Uri selectedUri;
  final void Function(List<PlaybackStreamOption>) onOptionsChanged;
  final PlayerSourceDiscovery? discover;

  @override
  State<PlayerStreamSourcePicker> createState() =>
      _PlayerStreamSourcePickerState();
}

class _PlayerStreamSourcePickerState extends State<PlayerStreamSourcePicker> {
  late List<PlaybackStreamOption> _options;
  StreamSubscription<WebStreamSearchProgress>? _subscription;
  bool _searching = false;
  int _completed = 0;
  int _total = 0;
  int _failureCount = 0;

  @override
  void initState() {
    super.initState();
    _options = mergePlaybackStreamOptions(widget.initialOptions, const []);
    if (widget.discover != null) unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _refresh({bool force = false}) async {
    final discover = widget.discover;
    if (discover == null || _searching) return;
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _searching = true;
      _completed = 0;
      _total = 0;
      _failureCount = 0;
    });
    final done = Completer<void>();
    _subscription = discover(refresh: force).listen(
      (progress) {
        if (!mounted) return;
        final discovered = progress.aggregation.streams.map(
          playbackOptionForWebStream,
        );
        final merged = mergePlaybackStreamOptions(_options, discovered);
        setState(() {
          _options = merged;
          _completed = progress.completedProviders;
          _total = progress.totalProviders;
          _failureCount = progress.aggregation.failures.length;
          _searching = !progress.isComplete;
        });
        widget.onOptionsChanged(List.unmodifiable(merged));
      },
      onError: (_) {
        if (mounted) setState(() => _searching = false);
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final selectedKey = widget.selectedUri.toString();
    final hasSelected = _options.any(
      (option) => option.stream.uri.toString() == selectedKey,
    );
    final status = widget.discover == null
        ? 'Web discovery is disabled'
        : _searching
        ? _total > 0
              ? 'Searching providers: $_completed/$_total'
              : 'Finding providers...'
        : '${_options.length} source${_options.length == 1 ? '' : 's'}'
              '${_failureCount > 0 ? ' | $_failureCount unavailable' : ''}';
    return Dialog(
      key: const ValueKey('player-source-picker'),
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 330),
          child: DecoratedBox(
            key: const ValueKey('player-source-picker-panel'),
            decoration: BoxDecoration(
              color: palette.playerSurface(
                defaultColor: const Color(0xF5080808),
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: .75)),
              boxShadow: [
                BoxShadow(
                  color: palette.usesDefaultPlayerPalette
                      ? const Color(0x99000000)
                      : palette.background.withValues(alpha: .60),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.video_library_rounded,
                        color: palette.accentBright,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sources and quality',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              status,
                              key: const ValueKey('player-source-status'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.mutedText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_searching)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (widget.discover != null)
                        TvFocusable(
                          key: const ValueKey('player-source-refresh'),
                          focusScale: 1.03,
                          borderRadius: BorderRadius.circular(9),
                          onPressed: () => unawaited(_refresh(force: true)),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Refresh',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: _options.isEmpty
                        ? const Center(child: Text('No playable sources yet'))
                        : ListView.custom(
                            scrollDirection: Axis.horizontal,
                            childrenDelegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final option = _options[index];
                                final uriKey = option.stream.uri.toString();
                                final optionKey = playbackStreamOptionKey(
                                  option,
                                );
                                final selected = uriKey == selectedKey;
                                return Padding(
                                  key: ValueKey(
                                    'player-source-option-$optionKey',
                                  ),
                                  padding: const EdgeInsets.only(right: 9),
                                  child: TvFocusable(
                                    autofocus:
                                        selected ||
                                        (!hasSelected && index == 0),
                                    focusScale: 1.02,
                                    borderRadius: BorderRadius.circular(9),
                                    onPressed: () =>
                                        Navigator.of(context).pop(option),
                                    child: Container(
                                      width: 230,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? palette.accent.withValues(
                                                alpha: .3,
                                              )
                                            : palette.playerSelectableSurface(
                                                defaultColor: const Color(
                                                  0xFF171717,
                                                ),
                                              ),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected
                                                ? Icons.check_circle_rounded
                                                : Icons
                                                      .play_circle_outline_rounded,
                                            size: 19,
                                            color: selected
                                                ? palette.accentBright
                                                : palette.mutedText,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  playbackStreamOptionLabel(
                                                    option,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                Text(
                                                  option.release.releaseName,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.mutedText,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _options.length,
                              findChildIndexCallback: (key) {
                                for (
                                  var index = 0;
                                  index < _options.length;
                                  index++
                                ) {
                                  final optionKey = playbackStreamOptionKey(
                                    _options[index],
                                  );
                                  if (key ==
                                      ValueKey(
                                        'player-source-option-$optionKey',
                                      )) {
                                    return index;
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
