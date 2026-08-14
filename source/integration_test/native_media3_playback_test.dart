import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native Media3 SurfaceView renders and completes',
    (tester) async {
      final result = await AndroidTvBridge.instance.startNativePlayer(
        source: Uri.parse('asset:///assets/videos/vlc_smoke.mp4'),
        title: 'TetoTV native playback smoke test',
        checkpointKey:
            'integration:media3:${DateTime.now().microsecondsSinceEpoch}',
        releaseName: 'vlc_smoke.mp4',
        streamLabel: 'Media3 smoke stream',
        resumePosition: Duration.zero,
        startFromBeginning: true,
      );

      expect(result.status, 'completed');
      expect(result.firstFrameRendered, isTrue);
      expect(result.duration, greaterThan(const Duration(seconds: 10)));
      expect(result.decoder, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native Media3 starts atomically from the supplied resume position',
    (tester) async {
      final stopwatch = Stopwatch()..start();
      final result = await AndroidTvBridge.instance.startNativePlayer(
        source: Uri.parse('asset:///assets/videos/vlc_smoke.mp4'),
        title: 'TetoTV native resume smoke test',
        checkpointKey:
            'integration:media3-resume:'
            '${DateTime.now().microsecondsSinceEpoch}',
        releaseName: 'vlc_smoke.mp4',
        streamLabel: 'Media3 smoke stream',
        resumePosition: const Duration(seconds: 8),
        startFromBeginning: false,
      );
      stopwatch.stop();

      expect(result.status, 'completed');
      expect(result.firstFrameRendered, isTrue);
      // The asset is 15 seconds long. A real 8-second resume should complete
      // much sooner than replaying it from zero, with headroom for an emulator.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 13)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native Media3 can create its HLS source factory',
    (tester) async {
      final result = await AndroidTvBridge.instance.startNativePlayer(
        // A closed local HTTPS port makes the stream fail immediately after
        // Media3 has selected and instantiated its optional HLS module. The
        // regression is Activity startup: a missing module crashes before a
        // normal playback error can be returned.
        source: Uri.parse('https://127.0.0.1:9/tetotv-hls-smoke.m3u8'),
        title: 'TetoTV native HLS module smoke test',
        checkpointKey:
            'integration:media3-hls:'
            '${DateTime.now().microsecondsSinceEpoch}',
        releaseName: 'tetotv-hls-smoke.m3u8',
        streamLabel: 'Media3 HLS module smoke stream',
        resumePosition: Duration.zero,
        startFromBeginning: true,
      );

      expect(result.status, 'error');
      expect(result.error, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
