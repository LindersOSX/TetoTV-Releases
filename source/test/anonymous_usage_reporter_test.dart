import 'package:anime_tv/core/telemetry/anonymous_usage_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUsageClient implements AnonymousUsageClient {
  int creates = 0;
  int closes = 0;
  final states = <AnonymousUsageState>[];

  @override
  Future<AnonymousUsageSession> createSession() async {
    creates += 1;
    return const AnonymousUsageSession(
      token: 'abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOP',
      heartbeatInterval: Duration(seconds: 45),
    );
  }

  @override
  Future<void> heartbeat(String token, AnonymousUsageState state) async {
    states.add(state);
  }

  @override
  Future<void> closeSession(String token) async {
    closes += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports only active/streaming state and honors opt out', (
    tester,
  ) async {
    final client = _FakeUsageClient();
    final reporter = AnonymousUsageReporter(client);

    reporter.setEnabled(true);
    await tester.pump();
    expect(client.creates, 1);
    expect(client.states, [AnonymousUsageState.active]);

    reporter.setStreaming(true);
    await tester.pump();
    expect(client.states.last, AnonymousUsageState.streaming);

    reporter.setEnabled(false);
    await tester.pump();
    expect(client.closes, 1);

    reporter.dispose();
  });

  testWidgets('does not create a session while disabled', (tester) async {
    final client = _FakeUsageClient();
    final reporter = AnonymousUsageReporter(client);

    reporter.setStreaming(true);
    await tester.pump();
    expect(client.creates, 0);

    reporter.dispose();
  });
}
