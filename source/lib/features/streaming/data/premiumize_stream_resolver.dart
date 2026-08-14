import 'package:anime_tv/features/streaming/data/premiumize_client.dart';
import 'package:anime_tv/features/streaming/data/premiumize_models.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

class PremiumizeStreamResolver implements StreamResolver {
  PremiumizeStreamResolver(
    this._client,
    this._releaseSource, {
    this.pollInterval = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 20),
  });

  final PremiumizeClient _client;
  final ReleaseSource _releaseSource;
  final Duration pollInterval;
  final Duration timeout;

  @override
  Stream<StreamResolution> resolve(EpisodeReference episode) async* {
    final releases = await _releaseSource.search(episode);
    if (releases.isEmpty) {
      throw StateError('No releases found for episode ${episode.episode}.');
    }
    final release = releases.first;
    if (!await _client.isCached(release.magnetUri)) {
      throw const DebridCacheMissException(
        DebridService.premiumize,
        detail:
            'This release is not cached on Premiumize. TetoTV did not create '
            'a cloud transfer.',
      );
    }
    final files = await _client.directDownload(release.magnetUri);
    final selected = selectPremiumizeEpisodeFile(
      files,
      episode.episode,
      preferredFileIndex: release.preferredFileIndex,
    );
    yield StreamReady(
      uri: selected.link,
      displayName: selected.name,
      debridService: DebridService.premiumize,
    );
  }
}

PremiumizeFile selectPremiumizeEpisodeFile(
  List<PremiumizeFile> files,
  int episode, {
  int? preferredFileIndex,
}) {
  final playable = files.where((file) => file.isPlayable).toList();
  if (playable.isEmpty) {
    throw StateError('The Premiumize transfer contains no supported videos.');
  }
  if (preferredFileIndex != null &&
      preferredFileIndex >= 0 &&
      preferredFileIndex < files.length &&
      files[preferredFileIndex].isPlayable) {
    return files[preferredFileIndex];
  }
  if (playable.length == 1) return playable.single;

  final padded = episode.toString().padLeft(2, '0');
  final patterns = [
    RegExp('(?:^|[^0-9])E$padded(?:[^0-9]|\$)', caseSensitive: false),
    RegExp('(?:^|[^0-9])EP?\\s*0*$episode(?:[^0-9]|\$)', caseSensitive: false),
    RegExp('(?:^|[^0-9])0*$episode(?:[^0-9]|\$)'),
  ];
  for (final pattern in patterns) {
    final matches = playable.where((file) => pattern.hasMatch(file.name));
    if (matches.isNotEmpty) {
      return matches.reduce((a, b) => a.size >= b.size ? a : b);
    }
  }
  return playable.reduce((a, b) => a.size >= b.size ? a : b);
}
