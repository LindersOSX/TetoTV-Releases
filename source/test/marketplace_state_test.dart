import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MarketplaceAddon manifest({
    String? version,
    Map<String, String> defaults = const {},
  }) => MarketplaceAddon(
    id: 'provider.test',
    name: 'Test provider',
    description: 'Fixture',
    author: 'TetoTV tests',
    manifestUri: Uri.parse('https://example.com/manifest.json'),
    repositoryUrl: 'https://example.com/marketplace.json',
    language: 'typescript',
    type: 'onlinestream-provider',
    locale: 'en',
    version: version,
    userConfigDefaults: defaults,
  );

  InstalledStreamingAddon installed({
    required MarketplaceAddon addon,
    String payload = 'export default class Provider {}',
  }) => InstalledStreamingAddon(
    manifest: addon,
    payload: payload,
    enabled: true,
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('marks newer provider code for an explicit update', () {
    final current = installed(addon: manifest(version: '1.0.0'));
    final state = MarketplaceState(installed: [current]);

    expect(state.updateAvailable(manifest(version: '1.1.0')), isTrue);
    expect(state.installed.single.payload, current.payload);
  });

  test('marks unresolved legacy configuration for explicit repair', () {
    final current = installed(
      addon: manifest(version: '1.0.0'),
      payload: 'const baseUrl = "{{api}}";',
    );
    final state = MarketplaceState(installed: [current]);

    expect(
      state.updateAvailable(
        manifest(version: '1.0.0', defaults: const {'api': 'https://api.test'}),
      ),
      isTrue,
    );
  });

  test('marks changed safe defaults for explicit update', () {
    final current = installed(
      addon: manifest(
        version: '1.0.0',
        defaults: const {'api': 'https://old.example'},
      ),
    );
    final state = MarketplaceState(installed: [current]);

    expect(
      state.updateAvailable(
        manifest(
          version: '1.0.0',
          defaults: const {'api': 'https://new.example'},
        ),
      ),
      isTrue,
    );
  });

  test('never treats a different repository as an installed addon update', () {
    final current = installed(addon: manifest(version: '1.0.0'));
    final spoofed = MarketplaceAddon(
      id: current.manifest.id,
      name: 'Spoofed provider',
      description: 'Fixture',
      author: 'Unknown',
      manifestUri: Uri.parse('https://untrusted.example/manifest.json'),
      repositoryUrl: 'https://untrusted.example/marketplace.json',
      language: 'javascript',
      type: 'onlinestream-provider',
      locale: 'en',
      version: '99.0.0',
    );
    final state = MarketplaceState(installed: [current]);

    expect(addonProvenanceMatches(current, spoofed), isFalse);
    expect(state.updateAvailable(spoofed), isFalse);
  });

  test('rejects a non-public repository before persisting it', () async {
    final store = AddonStore(TetoTvDatabase.instance);
    final controller = MarketplaceController(
      store,
      MarketplaceClient(store),
      targetValidator: (_) async =>
          throw const FormatException('private target'),
    );

    final error = await controller.addRepository(
      'https://private.example/marketplace.json',
    );

    expect(error, 'The repository must resolve to a public HTTPS address.');
    expect(controller.state.repositories, isEmpty);
  });

  test(
    'blocks a cross-repository ID collision before downloading code',
    () async {
      final store = AddonStore(TetoTvDatabase.instance);
      final current = installed(addon: manifest(version: '1.0.0'));
      final client = _DownloadMustNotRunClient(store);
      final controller = _SeededMarketplaceController(
        store,
        client,
        MarketplaceState(installed: [current], loading: false),
      );
      final spoofed = MarketplaceAddon(
        id: current.manifest.id,
        name: 'Spoofed provider',
        description: 'Fixture',
        author: 'Unknown',
        manifestUri: Uri.parse('https://untrusted.example/manifest.json'),
        repositoryUrl: 'https://untrusted.example/marketplace.json',
        language: 'javascript',
        type: 'onlinestream-provider',
        locale: 'en',
      );

      await expectLater(
        controller.install(spoofed),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('already owns this provider ID'),
          ),
        ),
      );
      expect(client.downloadAttempted, isFalse);
    },
  );
}

class _DownloadMustNotRunClient extends MarketplaceClient {
  _DownloadMustNotRunClient(super.store);

  bool downloadAttempted = false;

  @override
  Future<InstalledStreamingAddon> downloadAddon(
    MarketplaceAddon summary,
  ) async {
    downloadAttempted = true;
    throw StateError('Untrusted payload was downloaded.');
  }
}

class _SeededMarketplaceController extends MarketplaceController {
  _SeededMarketplaceController(
    super.store,
    super.client,
    MarketplaceState initial,
  ) {
    state = initial;
  }
}
