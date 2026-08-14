import 'dart:async';

import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class CatalogGrid extends StatefulWidget {
  const CatalogGrid({
    required this.items,
    required this.titlePreference,
    this.autofocus = true,
    this.firstFocusNode,
    this.onNavigateUpFromFirstRow,
    this.onLongPress,
    super.key,
  });

  final List<AnimeSummary> items;
  final TitleLanguagePreference titlePreference;
  final bool autofocus;
  final FocusNode? firstFocusNode;
  final VoidCallback? onNavigateUpFromFirstRow;
  final ValueChanged<AnimeSummary>? onLongPress;

  @override
  State<CatalogGrid> createState() => _CatalogGridState();
}

class _CatalogGridState extends State<CatalogGrid> {
  static const _maximumCardWidth = 150.0;
  static const _crossAxisSpacing = 10.0;
  static const _mainAxisSpacing = 14.0;
  static const _gridPadding = EdgeInsets.fromLTRB(4, 8, 4, 28);

  final List<FocusNode> _focusNodes = [];
  final ScrollController _scrollController = ScrollController();
  int? _pendingFocusIndex;
  int _focusRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ensureFocusNodes();
  }

  @override
  void didUpdateWidget(CatalogGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureFocusNodes();
  }

  void _ensureFocusNodes() {
    while (_focusNodes.length < widget.items.length) {
      _focusNodes.add(
        FocusNode(debugLabel: 'catalog.result.${_focusNodes.length}'),
      );
    }
  }

  FocusNode _focusNodeAt(int index) {
    if (index == 0 && widget.firstFocusNode != null) {
      return widget.firstFocusNode!;
    }
    return _focusNodes[index];
  }

  KeyEventResult _handleCardKey({
    required int index,
    required int crossAxisCount,
    required double cardMainAxisExtent,
    required KeyEvent event,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final originIndex = _pendingFocusIndex ?? index;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final right = key == LogicalKeyboardKey.arrowRight;
      final visualDelta = Directionality.of(context) == TextDirection.rtl
          ? (right ? -1 : 1)
          : (right ? 1 : -1);
      final column = originIndex % crossAxisCount;
      final targetColumn = column + visualDelta;
      final targetIndex = originIndex + visualDelta;
      if (targetColumn >= 0 &&
          targetColumn < crossAxisCount &&
          targetIndex >= 0 &&
          targetIndex < widget.items.length) {
        _focusAndReveal(
          targetIndex,
          towardEnd: visualDelta > 0,
          crossAxisCount: crossAxisCount,
          cardMainAxisExtent: cardMainAxisExtent,
        );
      }
      // A horizontal edge is still handled. Letting the global geometric
      // policy search beyond the row can move focus into the header (or out
      // of a lazily built grid), which makes the selected-card ring vanish.
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (originIndex < crossAxisCount) {
        final navigateUp = widget.onNavigateUpFromFirstRow;
        if (navigateUp == null) return KeyEventResult.ignored;
        // Cancel any lazy reveal that is still completing before handing focus
        // to the header. Otherwise its post-frame callback can steal focus
        // back into the grid after a rapid series of Up presses.
        _focusRequestGeneration++;
        _pendingFocusIndex = null;
        navigateUp();
      } else {
        _focusAndReveal(
          originIndex - crossAxisCount,
          towardEnd: false,
          crossAxisCount: crossAxisCount,
          cardMainAxisExtent: cardMainAxisExtent,
        );
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final targetIndex = originIndex + crossAxisCount;
      if (targetIndex < widget.items.length) {
        _focusAndReveal(
          targetIndex,
          towardEnd: true,
          crossAxisCount: crossAxisCount,
          cardMainAxisExtent: cardMainAxisExtent,
        );
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _focusAndReveal(
    int index, {
    required bool towardEnd,
    required int crossAxisCount,
    required double cardMainAxisExtent,
  }) {
    final generation = ++_focusRequestGeneration;
    final node = _focusNodeAt(index);
    _pendingFocusIndex = index;
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _focusRequestGeneration) return;
        _focusAndReveal(
          index,
          towardEnd: towardEnd,
          crossAxisCount: crossAxisCount,
          cardMainAxisExtent: cardMainAxisExtent,
        );
      });
      return;
    }

    final position = _scrollController.position;
    final row = index ~/ crossAxisCount;
    final rowTop =
        _gridPadding.top + row * (cardMainAxisExtent + _mainAxisSpacing);
    final rowBottom = rowTop + cardMainAxisExtent;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    final attached = node.context != null && node.parent != null;
    if (attached) {
      _pendingFocusIndex = null;
      node.requestFocus();
      var attachedOffset = viewportTop;
      if (rowTop < viewportTop + 6) {
        attachedOffset = rowTop - 6;
      } else if (rowBottom > viewportBottom - 6) {
        attachedOffset = rowBottom - position.viewportDimension + 6;
      }
      attachedOffset = attachedOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - attachedOffset).abs() >= 1) {
        unawaited(
          position.animateTo(
            attachedOffset,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    var requestedOffset = viewportTop;
    if (rowTop < viewportTop + 6) {
      requestedOffset = rowTop - 6;
    } else if (rowBottom > viewportBottom - 6) {
      requestedOffset = rowBottom - position.viewportDimension + 6;
    } else if (node.context == null) {
      // The row lies on a cache boundary but is not attached yet. Nudge it to
      // the directional viewport edge so GridView builds it before focus.
      requestedOffset = towardEnd
          ? rowBottom - position.viewportDimension + 6
          : rowTop - 6;
    }
    final offset = requestedOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final reveal = (position.pixels - offset).abs() < 1
        ? Future<void>.value()
        : position.animateTo(
            offset,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
          );
    unawaited(
      reveal.whenComplete(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _focusRequestGeneration) return;
          _pendingFocusIndex = null;
          node.requestFocus();
        });
      }),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = (constraints.maxWidth - _gridPadding.horizontal)
            .clamp(0.0, double.infinity);
        // Keep keyboard row math byte-for-byte equivalent to Flutter's
        // SliverGridDelegateWithMaxCrossAxisExtent.getLayout formula. Adding
        // spacing to the numerator changes columns too early at boundary
        // widths (for example, 151..160 px would be treated as two columns
        // here while the sliver still lays out one), so Down/Up would target
        // a card in a different visual row.
        final calculatedCrossAxisCount =
            (gridWidth / (_maximumCardWidth + _crossAxisSpacing)).ceil();
        final crossAxisCount = calculatedCrossAxisCount < 1
            ? 1
            : calculatedCrossAxisCount;
        final cardCrossAxisExtent =
            (gridWidth - _crossAxisSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final cardMainAxisExtent = cardCrossAxisExtent / .57;
        return GridView.builder(
          controller: _scrollController,
          padding: _gridPadding,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _maximumCardWidth,
            childAspectRatio: .57,
            crossAxisSpacing: _crossAxisSpacing,
            mainAxisSpacing: _mainAxisSpacing,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final anime = widget.items[index];
            return TvFocusable(
              focusNode: _focusNodeAt(index),
              autofocus: widget.autofocus && index == 0,
              onKeyEvent: (_, event) => _handleCardKey(
                index: index,
                crossAxisCount: crossAxisCount,
                cardMainAxisExtent: cardMainAxisExtent,
                event: event,
              ),
              onPressed: () => context.push('/anime/${anime.id}'),
              onLongPress: widget.onLongPress == null
                  ? null
                  : () => widget.onLongPress!(anime),
              focusScale: 1.035,
              borderRadius: BorderRadius.circular(7),
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetworkArtwork(
                              url: anime.coverImageUrl,
                              cacheWidth: 260,
                            ),
                            if (animeAiringStatusLabel(anime.status) != null)
                              Positioned(
                                left: 5,
                                top: 5,
                                child: PosterAiringStatusBadge(
                                  status: anime.status,
                                ),
                              ),
                            Positioned(
                              left: 5,
                              right: 5,
                              bottom: 5,
                              child: PosterMetadataOverlay(
                                score: anime.score,
                                releaseYear: anime.seasonYear,
                                durationMinutes: anime.durationMinutes,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      // TvFocusable paints a 3 px focus ring plus an inner
                      // keyline over the card. Keep title glyphs clear of it
                      // on every edge instead of letting the red ring cover
                      // the first letter or second-line descenders.
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        anime.displayTitle(widget.titlePreference),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.appPalette.primaryText,
                          fontSize: 11,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
