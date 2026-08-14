import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/player/application/filler_episode_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fillerUnavailableNotifiedSeriesProvider = StateProvider<Set<int>>(
  (_) => const <int>{},
);

bool consumeFillerUnavailableNotice(
  StateController<Set<int>> controller,
  int anilistMediaId,
) {
  final notified = controller.state;
  if (notified.contains(anilistMediaId)) return false;
  controller.state = {...notified, anilistMediaId};
  return true;
}

void showFillerDataUnavailableNotice(
  BuildContext context, {
  required int episode,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(
        'Filler data is unavailable. Playing Episode $episode normally.',
      ),
    ),
  );
}

Future<void> showFillerSkipNotification(
  BuildContext context,
  FillerEpisodeNavigationDecision decision,
) async {
  if (!decision.skippedAny) return;
  final skipped = fillerEpisodeListLabel(decision.skippedEpisodes);
  final nextEpisode = decision.episode;
  final message = nextEpisode != null
      ? 'Skipped filler $skipped. Playing Episode $nextEpisode.'
      : '$skipped ${decision.skippedEpisodes.length == 1 ? 'is' : 'are'} marked as filler. There are no later non-filler episodes available.';
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Filler skipped'),
      content: Text(message),
      actions: [
        TvFocusable(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            color: dialogContext.appPalette.accent,
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}
