import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/marketplace/data/addon_store.dart';
import 'package:anime_tv/features/marketplace/data/marketplace_client.dart';
import 'package:anime_tv/features/marketplace/data/seanime_javascript_provider.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final addonStoreProvider = Provider<AddonStore>(
  (ref) => AddonStore(ref.watch(tetoTvDatabaseProvider)),
);

final marketplaceClientProvider = Provider<MarketplaceClient>(
  (ref) => MarketplaceClient(ref.watch(addonStoreProvider)),
);

class MarketplaceState {
  const MarketplaceState({
    this.repositories = const [],
    this.catalog = const [],
    this.installed = const [],
    this.repositoryErrors = const {},
    this.providerHealth = const {},
    this.providerMessages = const {},
    this.loading = true,
    this.busyAddonId,
  });

  final List<AddonRepository> repositories;
  final List<MarketplaceAddon> catalog;
  final List<InstalledStreamingAddon> installed;
  final Map<String, String> repositoryErrors;
  final Map<String, ProviderHealth> providerHealth;
  final Map<String, String> providerMessages;
  final bool loading;
  final String? busyAddonId;

  MarketplaceState copyWith({
    List<AddonRepository>? repositories,
    List<MarketplaceAddon>? catalog,
    List<InstalledStreamingAddon>? installed,
    Map<String, String>? repositoryErrors,
    Map<String, ProviderHealth>? providerHealth,
    Map<String, String>? providerMessages,
    bool? loading,
    String? busyAddonId,
    bool clearBusyAddon = false,
  }) => MarketplaceState(
    repositories: repositories ?? this.repositories,
    catalog: catalog ?? this.catalog,
    installed: installed ?? this.installed,
    repositoryErrors: repositoryErrors ?? this.repositoryErrors,
    providerHealth: providerHealth ?? this.providerHealth,
    providerMessages: providerMessages ?? this.providerMessages,
    loading: loading ?? this.loading,
    busyAddonId: clearBusyAddon ? null : busyAddonId ?? this.busyAddonId,
  );

  InstalledStreamingAddon? installedById(String id) {
    for (final addon in installed) {
      if (addon.manifest.id == id) return addon;
    }
    return null;
  }

  bool updateAvailable(MarketplaceAddon addon) {
    final current = installedById(addon.id);
    return current != null &&
        addonProvenanceMatches(current, addon) &&
        _installedAddonNeedsRefresh(current, addon);
  }
}

final marketplaceControllerProvider =
    StateNotifierProvider<MarketplaceController, MarketplaceState>((ref) {
      final controller = MarketplaceController(
        ref.watch(addonStoreProvider),
        ref.watch(marketplaceClientProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class MarketplaceController extends StateNotifier<MarketplaceState> {
  MarketplaceController(
    this._store,
    this._client, {
    Future<void> Function(Uri uri)? targetValidator,
  }) : _targetValidator = targetValidator ?? validatePublicNetworkTarget,
       super(const MarketplaceState());

  final AddonStore _store;
  final MarketplaceClient _client;
  final Future<void> Function(Uri uri) _targetValidator;

  Future<void> load() async {
    try {
      final repositories = await _store.repositories();
      final installed = await _store.installedAddons();
      final health = await _store.providerHealth();
      state = state.copyWith(
        repositories: repositories,
        installed: installed,
        providerHealth: health,
        loading: true,
      );
      await refresh(refreshNetwork: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        repositoryErrors: {'local': _message(error)},
      );
    }
  }

  Future<void> refresh({bool refreshNetwork = true}) async {
    state = state.copyWith(loading: true);
    final enabled = state.repositories.where((item) => item.enabled).toList();
    final results = await Future.wait(
      enabled.map((repository) async {
        try {
          final addons = await _client.catalog(
            repository,
            refresh: refreshNetwork,
          );
          return (
            repository: repository,
            addons: addons,
            error: null as String?,
          );
        } catch (error) {
          return (
            repository: repository,
            addons: const <MarketplaceAddon>[],
            error: _message(error),
          );
        }
      }),
    );
    final combined = <String, MarketplaceAddon>{};
    final errors = <String, String>{};
    for (final result in results) {
      if (result.error != null) errors[result.repository.url] = result.error!;
      for (final addon in result.addons) {
        combined.putIfAbsent(addon.id, () => addon);
      }
    }
    var catalog = combined.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final installedIds = state.installed
        .map((addon) => addon.manifest.id)
        .toSet();
    if (installedIds.isNotEmpty) {
      catalog = await Future.wait(
        catalog.map((addon) async {
          if (!installedIds.contains(addon.id)) return addon;
          try {
            return await _client.manifest(addon);
          } catch (_) {
            return addon;
          }
        }),
      );
    }

    // Catalog refresh is read-only for installed executable add-ons. Replacing
    // third-party code always remains an explicit Install/Update action so a
    // compromised repository cannot silently change an enabled provider.
    state = state.copyWith(
      catalog: catalog,
      repositoryErrors: errors,
      loading: false,
    );
  }

  Future<String?> addRepository(
    String rawUrl, {
    bool refreshAfterAdd = true,
  }) async {
    final uri = safePublicHttpsUri(rawUrl);
    if (uri == null) return 'Enter a public HTTPS repository URL.';
    final normalized = uri.toString();
    if (state.repositories.any((item) => item.url == normalized)) {
      return 'That repository is already added.';
    }
    if (state.repositories.length >= 32) {
      return 'Remove a repository before adding another (maximum 32).';
    }
    try {
      await _targetValidator(uri);
    } catch (_) {
      return 'The repository must resolve to a public HTTPS address.';
    }
    final repository = AddonRepository(
      url: normalized,
      updatedAt: DateTime.now(),
    );
    await _store.saveRepository(repository);
    state = state.copyWith(repositories: [...state.repositories, repository]);
    if (refreshAfterAdd) await refresh();
    return null;
  }

  Future<void> setRepositoryEnabled(
    AddonRepository repository,
    bool enabled,
  ) async {
    final next = repository.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    await _store.saveRepository(next);
    state = state.copyWith(
      repositories: [
        for (final item in state.repositories)
          if (item.url == repository.url) next else item,
      ],
    );
    await refresh(refreshNetwork: false);
  }

  Future<void> removeRepository(AddonRepository repository) async {
    await _store.removeRepository(repository.url);
    state = state.copyWith(
      repositories: state.repositories
          .where((item) => item.url != repository.url)
          .toList(),
    );
    await refresh(refreshNetwork: false);
  }

  Future<void> install(MarketplaceAddon addon) async {
    if (!addon.isCompatible) {
      throw const FormatException('This provider runtime is not supported.');
    }
    final previous = state.installedById(addon.id);
    if (previous != null && !addonProvenanceMatches(previous, addon)) {
      throw const FormatException(
        'Another repository already owns this provider ID. Uninstall it '
        'before installing code from a different repository.',
      );
    }
    state = state.copyWith(busyAddonId: addon.id);
    try {
      final downloaded = await _client.downloadAddon(addon);
      if (previous != null &&
          !addonProvenanceMatches(previous, downloaded.manifest)) {
        throw const FormatException(
          'Another repository already owns this provider ID. Uninstall it '
          'before installing code from a different repository.',
        );
      }
      final installed = InstalledStreamingAddon(
        manifest: downloaded.manifest,
        payload: downloaded.payload,
        enabled: previous?.enabled ?? true,
        installedAt: previous?.installedAt ?? downloaded.installedAt,
        updatedAt: DateTime.now(),
      );
      await _store.install(installed);
      state = state.copyWith(
        installed: [
          ...state.installed.where((item) => item.manifest.id != addon.id),
          installed,
        ]..sort((a, b) => a.manifest.name.compareTo(b.manifest.name)),
        clearBusyAddon: true,
      );
    } catch (_) {
      state = state.copyWith(clearBusyAddon: true);
      rethrow;
    }
  }

  Future<void> setAddonEnabled(String id, bool enabled) async {
    await _store.setEnabled(id, enabled);
    if (enabled) await _store.clearProviderHealth(id);
    state = state.copyWith(
      installed: [
        for (final item in state.installed)
          if (item.manifest.id == id) item.copyWith(enabled: enabled) else item,
      ],
      providerHealth: enabled
          ? ({...state.providerHealth}..remove(id))
          : state.providerHealth,
    );
  }

  Future<void> testAddon(InstalledStreamingAddon addon) async {
    final id = addon.manifest.id;
    state = state.copyWith(
      busyAddonId: id,
      providerMessages: {...state.providerMessages, id: 'Testing provider…'},
    );
    try {
      final streams = await SeanimeJavascriptProvider(addon).streams(
        const EpisodeReference(
          anilistMediaId: 5114,
          malMediaId: 5114,
          title: 'Fullmetal Alchemist Brotherhood',
          alternativeTitles: ['Hagane no Renkinjutsushi Fullmetal Alchemist'],
          episode: 1,
        ),
      );
      if (streams.isEmpty) {
        throw StateError('Provider returned no playable test streams.');
      }
      await _store.recordProviderSuccess(id);
      state = state.copyWith(
        providerHealth: await _store.providerHealth(),
        providerMessages: {
          ...state.providerMessages,
          id: 'Healthy • ${streams.length} test stream(s) found',
        },
        clearBusyAddon: true,
      );
    } catch (error) {
      if (isSeanimeProviderNoMatch(error)) {
        state = state.copyWith(
          providerMessages: {
            ...state.providerMessages,
            id: 'Runtime ready - the test title is not available here',
          },
          clearBusyAddon: true,
        );
        return;
      }
      final health = await _store.recordProviderFailure(id, error);
      state = state.copyWith(
        providerHealth: {...state.providerHealth, id: health},
        providerMessages: {
          ...state.providerMessages,
          id: 'Test failed: ${_message(error)}',
        },
        clearBusyAddon: true,
      );
    }
  }

  Future<void> resetAddonHealth(String id) async {
    await _store.clearProviderHealth(id);
    final messages = {...state.providerMessages}..remove(id);
    final health = {...state.providerHealth}..remove(id);
    state = state.copyWith(providerHealth: health, providerMessages: messages);
  }

  Future<void> uninstall(String id) async {
    await _store.uninstall(id);
    await _store.clearProviderHealth(id);
    state = state.copyWith(
      installed: state.installed
          .where((item) => item.manifest.id != id)
          .toList(),
    );
  }
}

/// An add-on ID alone is not a trusted update identity. A second repository
/// may legitimately or maliciously reuse it, so executable replacement is
/// allowed only from the repository the user originally installed.
bool addonProvenanceMatches(
  InstalledStreamingAddon installed,
  MarketplaceAddon candidate,
) =>
    installed.manifest.id == candidate.id &&
    installed.manifest.repositoryUrl == candidate.repositoryUrl;

bool _installedAddonNeedsRefresh(
  InstalledStreamingAddon installed,
  MarketplaceAddon available,
) {
  final unresolvedConfig = RegExp(
    r'\{\{[A-Za-z0-9._-]+\}\}',
  ).hasMatch(installed.payload);
  final versionChanged =
      available.version != null &&
      (installed.manifest.version == null ||
          _compareVersions(available.version!, installed.manifest.version!) >
              0);
  final defaultsChanged = !_sameStringMap(
    installed.manifest.userConfigDefaults,
    available.userConfigDefaults,
  );
  return unresolvedConfig || versionChanged || defaultsChanged;
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int _compareVersions(String left, String right) {
  List<int> numbers(String value) => RegExp(r'\d+')
      .allMatches(value)
      .take(4)
      .map((match) => int.tryParse(match.group(0)!) ?? 0)
      .toList();
  final a = numbers(left);
  final b = numbers(right);
  for (var index = 0; index < 4; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

String _message(Object error) {
  final text = error.toString().replaceFirst(
    RegExp(r'^[A-Za-z]+Exception:\s*'),
    '',
  );
  return text.length > 180 ? '${text.substring(0, 180)}…' : text;
}
