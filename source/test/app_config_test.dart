import 'package:anime_tv/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production brokers keep auth separate from source pairing', () {
    expect(AppConfig.authBrokerBaseUrl, 'https://tetotv-auth.onrender.com');
    expect(
      AppConfig.sourcePairingBrokerBaseUrl,
      'https://tetotv-updates-lindows.onrender.com',
    );
    expect(
      AppConfig.sourcePairingBrokerBaseUrl,
      isNot(AppConfig.authBrokerBaseUrl),
    );
  });
}
