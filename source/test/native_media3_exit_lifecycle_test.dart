import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'confirmed Media3 Exit is single-shot and releases before returning',
    () {
      final playerSource = _read(
        'android/app/src/main/kotlin/dev/animetv/anime_tv/player/'
        'Media3PlayerActivity.kt',
      );

      final exitConfirmation = _slice(
        playerSource,
        'private fun showExitConfirmation()',
        'private fun requestTransportFocus()',
      );
      _expectInOrder(exitConfirmation, const [
        '.setPositiveButton("Exit video")',
        'persistCheckpoint()',
        'finishWithResult(STATUS_STOPPED)',
      ]);

      final finish = _slice(
        playerSource,
        'private fun finishWithResult(status: String)',
        'private fun memoryClassMb()',
      );
      _expectInOrder(finish, const [
        'if (resultSent) return',
        'resultSent = true',
        'releasePlaybackResources()',
        'result.putExtra(RESULT_STATUS, deliveredStatus)',
        'setResult(RESULT_OK, result)',
        'finish()',
      ]);

      // A normal Exit must retain the exact terminal status. Only an engine or
      // direct-source handoff may become release_failed when teardown is
      // partial, because each can immediately launch a replacement decoder.
      _expectInOrder(finish, const [
        'val switchingEngine =',
        'status == STATUS_USE_MPV',
        'status == STATUS_USE_VLC',
        'status == STATUS_NEXT_STREAM',
      ]);
      expect(finish, contains('else {\n            status\n        }'));
      expect(playerSource, contains('const val STATUS_STOPPED = "stopped"'));
    },
  );
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _slice(String source, String startToken, String endToken) {
  final start = source.indexOf(startToken);
  final end = source.indexOf(endToken, start + startToken.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startToken');
  expect(
    end,
    greaterThan(start),
    reason: 'Missing $endToken after $startToken',
  );
  return source.substring(start, end);
}

void _expectInOrder(String source, List<String> tokens) {
  var previous = -1;
  for (final token in tokens) {
    final index = source.indexOf(token, previous + 1);
    expect(
      index,
      greaterThan(previous),
      reason: 'Missing/out of order: $token',
    );
    previous = index;
  }
}
