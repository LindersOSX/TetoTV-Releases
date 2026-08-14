import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';

bool releaseAdvertisesDualAudio(ReleaseCandidate release) {
  final normalized = release.releaseName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return RegExp(r'\b(?:dual|multi) audio\b').hasMatch(normalized);
}

/// Whether a torrent can satisfy the requested playback style.
///
/// Dual/multi-audio releases are valid for both preferences. Older source
/// adapters expose them as `isDubbed`, so treating that flag as "dub only"
/// incorrectly hid perfectly usable Japanese tracks from sub viewers.
bool releaseSupportsAudioPreference(
  ReleaseCandidate release,
  PlaybackAudioPreference preference,
) => switch (preference) {
  PlaybackAudioPreference.dub =>
    release.isDubbed || releaseAdvertisesDualAudio(release),
  PlaybackAudioPreference.sub =>
    !release.isDubbed || releaseAdvertisesDualAudio(release),
};

/// Lower values are preferred. This is used when optional filters must be
/// relaxed after no matching cached release is available.
int releaseAudioPreferenceRank(
  ReleaseCandidate release,
  PlaybackAudioPreference preference,
) {
  if (!releaseSupportsAudioPreference(release, preference)) return 2;
  if (preference == PlaybackAudioPreference.sub && release.isDubbed) {
    // Prefer a known original-audio release, then a dual-audio release.
    return 1;
  }
  return 0;
}

bool subtitlesEnabledForAudioPreference(
  ReleaseCandidate release,
  PlaybackAudioPreference preference,
) => preference.subtitlesPreferred || !release.isDubbed;
