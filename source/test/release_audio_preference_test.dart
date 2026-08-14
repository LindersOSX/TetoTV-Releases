import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/release_audio_preference.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dual-audio labels satisfy dub when an adapter omits isDubbed', () {
    const release = ReleaseCandidate(
      infoHash: '0123456789012345678901234567890123456789',
      magnetUri: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
      releaseName: '[Third Party] Example S01E01 Dual Audio 1080p',
      seeders: 10,
      sourceId: 'third-party',
    );

    expect(release.isDubbed, isFalse);
    expect(releaseAdvertisesDualAudio(release), isTrue);
    expect(
      releaseSupportsAudioPreference(release, PlaybackAudioPreference.dub),
      isTrue,
    );
    expect(releaseAudioPreferenceRank(release, PlaybackAudioPreference.dub), 0);
  });

  test('single-audio sub releases still do not satisfy dub', () {
    const release = ReleaseCandidate(
      infoHash: 'abcdef0123456789abcdef0123456789abcdef01',
      magnetUri: 'magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01',
      releaseName: '[Sub Group] Example S01E01 1080p',
      seeders: 10,
      sourceId: 'sub-source',
    );

    expect(
      releaseSupportsAudioPreference(release, PlaybackAudioPreference.dub),
      isFalse,
    );
    expect(releaseAudioPreferenceRank(release, PlaybackAudioPreference.dub), 2);
  });
}
