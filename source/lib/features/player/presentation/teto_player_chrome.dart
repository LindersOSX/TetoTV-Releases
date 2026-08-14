import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double _playerControlMaxTextScale = 1.35;
const double _playerControlFocusGutter = 20;
const Color _defaultPlayerChromePanel = Color(0xD6080808);
const Color _defaultPlayerChromeShadow = Color(0xA8000000);
const Color _defaultPlayerControlSurface = Color(0x8F242429);
const Color _defaultPlayerSkipSurface = Color(0xB30B0B0D);
const Color _defaultPlayerSkipShadow = Color(0x77000000);

bool _usesDefaultPlayerPalette(AppThemePalette palette) =>
    palette == AppThemePalette.defaults;

Color _playerChromePanelColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? _defaultPlayerChromePanel
    : Color.lerp(
        palette.background,
        palette.surface,
        .62,
      )!.withValues(alpha: .84);

Color _playerChromeShadowColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? _defaultPlayerChromeShadow
    : Color.lerp(palette.background, Colors.black, .85)!.withValues(alpha: .66);

Color _playerControlSurfaceColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? _defaultPlayerControlSurface
    : palette.selectableSurface.withValues(alpha: .56);

Color _playerSkipSurfaceColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? _defaultPlayerSkipSurface
    : Color.lerp(
        palette.background,
        palette.surface,
        .55,
      )!.withValues(alpha: .70);

Color _playerSkipShadowColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? _defaultPlayerSkipShadow
    : _playerChromeShadowColor(palette).withValues(alpha: .47);

Color _playerPrimaryTextColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette) ? Colors.white : palette.primaryText;

Color _playerPrimaryControlTextColor(AppThemePalette palette) =>
    _usesDefaultPlayerPalette(palette)
    ? Colors.white
    : contrastForeground(palette.accent);

Color _playerProgressTrackColor(AppThemePalette palette) =>
    (_usesDefaultPlayerPalette(palette) ? Colors.white : palette.primaryText)
        .withValues(alpha: .24);

/// Visual language shared by every Flutter-backed playback engine.
///
/// Engine integration remains deliberately outside this widget. MPV and VLC
/// only provide their current state and callbacks, which prevents their
/// controls from drifting apart when the player UI changes.
class TetoPlayerChrome extends StatelessWidget {
  const TetoPlayerChrome({
    required this.engineKey,
    required this.title,
    required this.streamLabel,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playFocusNode,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onAudio,
    required this.onSubtitles,
    required this.onCaptionSize,
    required this.onPicture,
    required this.onFixVideo,
    this.onSources,
    required this.onOptions,
    required this.onDismiss,
    this.engineLabel,
    this.footerHint = 'D-pad controls  |  J/L seek  |  Menu/Y options',
    super.key,
  });

  final String engineKey;
  final String title;
  final String streamLabel;
  final String? engineLabel;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final FocusNode playFocusNode;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onCaptionSize;
  final VoidCallback onPicture;
  final VoidCallback onFixVideo;
  final VoidCallback? onSources;
  final VoidCallback onOptions;
  final VoidCallback onDismiss;
  final String footerHint;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final palette = context.appPalette;
    final compact = media.size.width < 720 || media.size.height < 480;
    final horizontalInset = compact ? 12.0 : 28.0;
    final bottomInset = compact ? 10.0 : 24.0;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          horizontalInset,
          0,
          horizontalInset,
          bottomInset,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: DecoratedBox(
            key: ValueKey('$engineKey-bottom-player-chrome'),
            decoration: BoxDecoration(
              color: _playerChromePanelColor(palette),
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
              border: Border.all(
                color: palette.accent.withValues(alpha: .78),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: _playerChromeShadowColor(palette),
                  blurRadius: 26,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 18,
                compact ? 10 : 14,
                compact ? 12 : 18,
                compact ? 9 : 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (compact
                                      ? Theme.of(context).textTheme.titleMedium
                                      : Theme.of(
                                          context,
                                        ).textTheme.headlineSmall)
                                  ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!compact && engineLabel != null) ...[
                        _PlayerBadge(text: engineLabel!),
                        const SizedBox(width: 8),
                      ],
                      _PlayerBadge(text: streamLabel),
                    ],
                  ),
                  SizedBox(height: compact ? 7 : 10),
                  SingleChildScrollView(
                    key: ValueKey('$engineKey-player-controls-scroll'),
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    // TvFocusable paints a scaled focus ring and glow outside
                    // the pill's layout bounds. Keep an equal reserve at both
                    // scroll limits so MPV and VLC never paint their first or
                    // last focused control beyond the HUD card.
                    padding: const EdgeInsets.symmetric(
                      horizontal: _playerControlFocusGutter,
                    ),
                    child: Row(
                      children: [
                        TetoPlayerControl(
                          icon: Icons.replay_rounded,
                          label: 'Back ${seekBackSeconds}s',
                          iconOnly: true,
                          revealScrollStart: true,
                          onPressed: onRewind,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          focusNode: playFocusNode,
                          primary: true,
                          icon: isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: isPlaying ? 'Pause' : 'Play',
                          iconOnly: true,
                          onPressed: onPlayPause,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.forward_rounded,
                          label: 'Forward ${seekForwardSeconds}s',
                          iconOnly: true,
                          onPressed: onForward,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 18),
                        TetoPlayerControl(
                          icon: Icons.audiotrack_rounded,
                          label: 'Audio',
                          onPressed: onAudio,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.closed_caption_rounded,
                          label: 'CC',
                          onPressed: onSubtitles,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.text_fields_rounded,
                          label: 'Size',
                          onPressed: onCaptionSize,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.aspect_ratio_rounded,
                          label: 'Picture',
                          onPressed: onPicture,
                          onDismiss: onDismiss,
                        ),
                        const SizedBox(width: 8),
                        TetoPlayerControl(
                          icon: Icons.smart_display_outlined,
                          label: 'Player',
                          onPressed: onFixVideo,
                          onDismiss: onDismiss,
                        ),
                        if (onSources != null) ...[
                          const SizedBox(width: 8),
                          TetoPlayerControl(
                            icon: Icons.video_library_rounded,
                            label: 'Sources',
                            onPressed: onSources!,
                            onDismiss: onDismiss,
                          ),
                        ],
                        const SizedBox(width: 18),
                        TetoPlayerControl(
                          icon: Icons.tune_rounded,
                          label: 'Options',
                          revealScrollEnd: true,
                          onPressed: onOptions,
                          onDismiss: onDismiss,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 15 : 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      key: ValueKey('$engineKey-player-progress-bar'),
                      value: progress,
                      minHeight: compact ? 3 : 4,
                      color: palette.accentBright,
                      backgroundColor: _playerProgressTrackColor(palette),
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 9),
                  Row(
                    children: [
                      Text(
                        '${formatPlayerChromeDuration(position)}  /  '
                        '${formatPlayerChromeDuration(duration)}',
                        style: TextStyle(
                          color: _playerPrimaryTextColor(palette),
                          fontSize: compact ? 11 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!compact) ...[
                        const Spacer(),
                        Flexible(
                          child: Text(
                            footerHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
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

class TetoSkipSegmentOverlay extends StatelessWidget {
  const TetoSkipSegmentOverlay({
    required this.label,
    required this.onPressed,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return TvFocusable(
      key: const ValueKey('player-skip-segment-overlay'),
      focusNode: focusNode,
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: _playerSkipSurfaceColor(palette),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: palette.accentBright.withValues(alpha: .82),
          ),
          boxShadow: [
            BoxShadow(color: _playerSkipShadowColor(palette), blurRadius: 16),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.skip_next_rounded,
              color: palette.accentBright,
              size: 21,
            ),
            const SizedBox(width: 8),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: _playerControlMaxTextScale,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _playerPrimaryTextColor(palette),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TetoPlayerControl extends StatelessWidget {
  const TetoPlayerControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.primary = false,
    this.iconOnly = false,
    this.revealScrollStart = false,
    this.revealScrollEnd = false,
    this.onDismiss,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool primary;
  final bool iconOnly;
  final bool revealScrollStart;
  final bool revealScrollEnd;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = primary
        ? _playerPrimaryControlTextColor(palette)
        : _playerPrimaryTextColor(palette);
    final control = TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      onFocusChanged: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (revealScrollStart) {
            final position = Scrollable.maybeOf(context)?.position;
            if (position != null) {
              position.animateTo(
                position.minScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
              );
              return;
            }
          }
          if (revealScrollEnd) {
            final position = Scrollable.maybeOf(context)?.position;
            if (position != null) {
              position.animateTo(
                position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
              );
              return;
            }
          }
          Scrollable.ensureVisible(
            context,
            alignment: 1,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
        });
      },
      onKeyEvent: onDismiss == null
          ? null
          : (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                onDismiss!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: ValueKey('player-control-$label'),
        width: iconOnly ? 40 : null,
        height: 40,
        padding: iconOnly
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: primary ? palette.accent : _playerControlSurfaceColor(palette),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: iconOnly
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            if (!iconOnly) ...[
              const SizedBox(width: 6),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: _playerControlMaxTextScale,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!iconOnly) return control;
    return Semantics(label: label, button: true, child: control);
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: .35)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.accentBright,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

String formatPlayerChromeDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
