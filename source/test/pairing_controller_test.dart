import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes a secure broker origin', () {
    expect(
      normalizeAuthBrokerBaseUrl('  https://auth.example.com/  '),
      'https://auth.example.com',
    );
    expect(
      normalizeAuthBrokerBaseUrl('https://auth.example.com/tetotv/'),
      'https://auth.example.com/tetotv',
    );
  });

  test('rejects unsafe or ambiguous broker URLs', () {
    expect(normalizeAuthBrokerBaseUrl('http://auth.example.com'), isNull);
    expect(normalizeAuthBrokerBaseUrl('https://user@auth.example.com'), isNull);
    expect(normalizeAuthBrokerBaseUrl('https://auth.example.com/?x=1'), isNull);
    expect(normalizeAuthBrokerBaseUrl('not a URL'), isNull);
  });
}
