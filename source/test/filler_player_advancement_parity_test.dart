import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in const {
    'MPV': 'lib/features/player/presentation/tv_player_screen.dart',
    'VLC': 'lib/features/player/presentation/vlc_tv_player_screen.dart',
    'Media3':
        'lib/features/player/presentation/native_media3_player_screen.dart',
  }.entries) {
    test('${entry.key} next episode uses the shared fail-open filler flow', () {
      final source = File(entry.value).readAsStringSync();
      final start = source.indexOf('Future<void> _playNextEpisode() async');
      expect(start, greaterThanOrEqualTo(0));
      final tail = source.substring(start);
      final end = tail.indexOf('\n  Future<void> ', 40);
      final method = end < 0 ? tail : tail.substring(0, end);

      expect(
        method,
        contains('final catalog = ref.read(catalogClientProvider)'),
      );
      expect(
        method,
        contains(
          'final fillerRepository = ref.read(fillerEpisodeRepositoryProvider)',
        ),
      );
      expect(method, contains('final skipFillerEpisodes ='));
      expect(method, contains('final details = await catalog.details('));
      expect(method, contains('if (!mounted) return;'));
      expect(method, contains('episodeNavigationCeiling('));
      expect(method, contains('resolveFillerEpisodeNavigation('));
      expect(method, contains('repository: fillerRepository'));
      expect(method, contains('skipEnabled: skipFillerEpisodes'));
      expect(method, contains('showFillerSkipNotification(context, decision)'));
      expect(method, contains('decision.episode == null'));

      final firstRefRead = method.indexOf('ref.read(');
      final entryMountedGuard = method.indexOf('if (!mounted');
      final repositoryCapture = method.indexOf(
        'final fillerRepository = ref.read(fillerEpisodeRepositoryProvider)',
      );
      final firstAwait = method.indexOf('await catalog.details(');
      final mountedGuard = method.indexOf('if (!mounted) return;', firstAwait);
      final fillerLookup = method.indexOf('resolveFillerEpisodeNavigation(');
      expect(entryMountedGuard, greaterThanOrEqualTo(0));
      expect(entryMountedGuard, lessThan(firstRefRead));
      expect(repositoryCapture, lessThan(firstAwait));
      expect(mountedGuard, greaterThan(firstAwait));
      expect(mountedGuard, lessThan(fillerLookup));
    });
  }
}
