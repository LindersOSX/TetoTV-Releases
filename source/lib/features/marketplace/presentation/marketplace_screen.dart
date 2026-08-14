import 'dart:async';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceFocusTarget {
  const _MarketplaceFocusTarget(this.node, this.rect);

  final FocusNode node;
  final Rect rect;
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final FocusNode _backFocus = FocusNode(debugLabel: 'Marketplace: Settings');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'Marketplace: Refresh');
  final FocusNode _phoneFocus = FocusNode(
    debugLabel: 'Marketplace: Add sources with phone',
  );
  final FocusNode _addManifestFocus = FocusNode(
    debugLabel: 'Marketplace: Add Torrent source manifest',
  );
  final FocusNode _addRepositoryFocus = FocusNode(
    debugLabel: 'Marketplace: Add Marketplace repository',
  );
  final Map<String, FocusNode> _dynamicFocusNodes = {};

  FocusNode _dynamicFocus(String key, String debugLabel) => _dynamicFocusNodes
      .putIfAbsent(key, () => FocusNode(debugLabel: debugLabel));

  @override
  void dispose() {
    _backFocus.dispose();
    _refreshFocus.dispose();
    _phoneFocus.dispose();
    _addManifestFocus.dispose();
    _addRepositoryFocus.dispose();
    for (final node in _dynamicFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  _MarketplaceFocusTarget? _focusTarget(FocusNode node) {
    if (!node.canRequestFocus) return null;
    final focusContext = node.context;
    if (focusContext == null || !focusContext.mounted) return null;
    try {
      final renderObject = focusContext.findRenderObject();
      if (renderObject == null || !renderObject.attached) return null;
      final rect = node.rect;
      return rect.isFinite ? _MarketplaceFocusTarget(node, rect) : null;
    } catch (_) {
      // A lazy sliver can detach between the context, render-object, and rect
      // checks. Treat transient geometry as unavailable; the next D-pad event
      // rebuilds the graph after layout instead of crashing the application.
      return null;
    }
  }

  List<List<_MarketplaceFocusTarget>> _groupByVisualRow(
    Iterable<FocusNode> candidates,
  ) {
    final nodes = candidates.map(_focusTarget).nonNulls.toList()
      ..sort((a, b) {
        final vertical = a.rect.center.dy.compareTo(b.rect.center.dy);
        return vertical != 0
            ? vertical
            : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    final rows = <List<_MarketplaceFocusTarget>>[];
    for (final node in nodes) {
      if (rows.isEmpty ||
          (rows.last.first.rect.center.dy - node.rect.center.dy).abs() > 12) {
        rows.add(<_MarketplaceFocusTarget>[node]);
      } else {
        rows.last.add(node);
      }
    }
    for (final row in rows) {
      row.sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    }
    return rows;
  }

  List<List<_MarketplaceFocusTarget>> _navigationRows() {
    final marketplace = ref.read(marketplaceControllerProvider);
    final torrentSources = ref.read(userTorrentSourcesControllerProvider);
    final rows = <List<_MarketplaceFocusTarget>>[];

    final header = [
      _backFocus,
      _refreshFocus,
    ].map(_focusTarget).nonNulls.toList();
    if (header.isNotEmpty) rows.add(header);
    rows.addAll(
      _groupByVisualRow([_phoneFocus, _addManifestFocus, _addRepositoryFocus]),
    );

    for (final url in torrentSources.manifestUrls) {
      final row = [
        _dynamicFocus(
          'torrent:$url:remove',
          'Marketplace torrent source Remove',
        ),
      ].map(_focusTarget).nonNulls.toList();
      if (row.isNotEmpty) rows.add(row);
    }
    for (final repository in marketplace.repositories) {
      final row = [
        _dynamicFocus(
          'repository:${repository.url}:toggle',
          'Marketplace repository Enabled',
        ),
        _dynamicFocus(
          'repository:${repository.url}:remove',
          'Marketplace repository Remove',
        ),
      ].map(_focusTarget).nonNulls.toList();
      if (row.isNotEmpty) rows.add(row);
    }

    rows.addAll(
      _groupByVisualRow(
        marketplace.installed.expand((addon) {
          final id = addon.manifest.id;
          return [
            _dynamicFocus(
              'installed:$id:test',
              'Marketplace installed addon Test',
            ),
            _dynamicFocus(
              'installed:$id:toggle',
              'Marketplace installed addon Toggle',
            ),
            _dynamicFocus(
              'installed:$id:reset',
              'Marketplace installed addon Reset',
            ),
            _dynamicFocus(
              'installed:$id:uninstall',
              'Marketplace installed addon Uninstall',
            ),
          ];
        }),
      ),
    );
    rows.addAll(
      _groupByVisualRow(
        marketplace.catalog.map(
          (addon) => _dynamicFocus(
            'catalog:${addon.id}:action',
            'Marketplace catalog addon action',
          ),
        ),
      ),
    );
    return rows;
  }

  KeyEventResult _handleNavigationKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final horizontal =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final vertical =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (!horizontal && !vertical) return KeyEventResult.ignored;

    final current = FocusManager.instance.primaryFocus;
    if (current == null) return KeyEventResult.ignored;
    final repositoryTarget = _focusTarget(_addRepositoryFocus);
    final manifestTarget = _focusTarget(_addManifestFocus);
    if (key == LogicalKeyboardKey.arrowUp &&
        current == _addRepositoryFocus &&
        repositoryTarget != null &&
        manifestTarget != null &&
        repositoryTarget.rect.center.dy - manifestTarget.rect.center.dy > 12) {
      _focusAndReveal(_addManifestFocus, key);
      return KeyEventResult.handled;
    }
    final rows = _navigationRows();
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final columnIndex = row.indexWhere((target) => target.node == current);
      if (columnIndex < 0) continue;

      if (horizontal) {
        final nextColumn = key == LogicalKeyboardKey.arrowLeft
            ? columnIndex - 1
            : columnIndex + 1;
        if (nextColumn < 0 || nextColumn >= row.length) {
          return KeyEventResult.handled;
        }
        _focusAndReveal(row[nextColumn].node, key);
        return KeyEventResult.handled;
      }

      final nextRowIndex = key == LogicalKeyboardKey.arrowUp
          ? rowIndex - 1
          : rowIndex + 1;
      // Let Flutter's traversal policy scroll a lazy sliver when its next
      // semantic row has not been built yet. The following D-pad event will
      // see that mounted row and resume this explicit graph.
      if (nextRowIndex < 0 || nextRowIndex >= rows.length) {
        return KeyEventResult.ignored;
      }
      final currentX = row[columnIndex].rect.center.dx;
      final nextRow = rows[nextRowIndex];
      // Moving down from a one-action semantic row (for example a Torrent
      // source Remove control) enters the next row at its primary action.
      // Otherwise, keep the closest visual column for natural reverse/grid
      // travel.
      final target = key == LogicalKeyboardKey.arrowDown && row.length == 1
          ? nextRow.first
          : nextRow.reduce(
              (best, candidate) =>
                  (candidate.rect.center.dx - currentX).abs() <
                      (best.rect.center.dx - currentX).abs()
                  ? candidate
                  : best,
            );
      _focusAndReveal(target.node, key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusAndReveal(FocusNode target, LogicalKeyboardKey direction) {
    target.requestFocus();
    final targetContext = target.context;
    if (targetContext == null) return;
    final towardEnd =
        direction == LogicalKeyboardKey.arrowDown ||
        direction == LogicalKeyboardKey.arrowRight;
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        alignment: towardEnd ? 1 : 0,
        alignmentPolicy: towardEnd
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketplaceControllerProvider);
    final controller = ref.read(marketplaceControllerProvider.notifier);
    final torrentSources = ref.watch(userTorrentSourcesControllerProvider);
    final torrentSourceController = ref.read(
      userTorrentSourcesControllerProvider.notifier,
    );
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleNavigationKey,
      child: Scaffold(
        backgroundColor: context.appPalette == AppThemePalette.defaults
            ? Colors.black
            : context.appPalette.background,
        body: SafeArea(
          minimum: context.responsiveScreenPadding,
          child: Column(
            children: [
              Row(
                children: [
                  _MarketplaceButton(
                    icon: Icons.arrow_back_rounded,
                    label: context.isCompactWidth ? null : 'Settings',
                    autofocus: true,
                    focusNode: _backFocus,
                    onPressed: context.pop,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sources',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        if (!context.isCompactWidth)
                          Text(
                            'Add Marketplace repositories and Torrent source manifests you trust.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  _MarketplaceButton(
                    icon: Icons.refresh_rounded,
                    label: context.isCompactWidth ? null : 'Refresh',
                    focusNode: _refreshFocus,
                    onPressed: state.loading
                        ? null
                        : () => controller.refresh(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: state.loading && state.repositories.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(
                          color: context.appPalette.accentBright,
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          _section(
                            context,
                            icon: Icons.hub_rounded,
                            title: 'Sources',
                            subtitle:
                                'Enter URLs manually or use one QR code to add both source types from your phone.',
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _MarketplaceButton(
                                    icon: Icons.phone_android_rounded,
                                    label: 'Add sources with phone',
                                    focusNode: _phoneFocus,
                                    onPressed: () =>
                                        showSourcePairingDialog(context),
                                  ),
                                  _MarketplaceButton(
                                    icon: Icons.add_link_rounded,
                                    label: 'Add Torrent source manifest',
                                    focusNode: _addManifestFocus,
                                    onPressed: () => _addTorrentSource(
                                      context,
                                      torrentSourceController,
                                    ),
                                  ),
                                  _MarketplaceButton(
                                    icon: Icons.playlist_add_rounded,
                                    label: 'Add Marketplace repository',
                                    focusNode: _addRepositoryFocus,
                                    onPressed: () =>
                                        _addRepository(context, controller),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _section(
                            context,
                            icon: Icons.cloud_download_outlined,
                            title: 'Torrent source manifests',
                            subtitle:
                                'Optional Stremio-compatible manifests you add yourself. TetoTV does not include or recommend a torrent catalog.',
                          ),
                          if (torrentSources.manifestUrls.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'No torrent sources added. Debrid searches stay unavailable until you explicitly add one.',
                                  style: TextStyle(
                                    color: context.appPalette.mutedText,
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: torrentSources.manifestUrls.length,
                              itemBuilder: (context, index) {
                                final url = torrentSources.manifestUrls[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _TorrentSourceTile(
                                    url: url,
                                    removeFocusNode: _dynamicFocus(
                                      'torrent:$url:remove',
                                      'Marketplace torrent source Remove',
                                    ),
                                    onRemove: () =>
                                        torrentSourceController.remove(url),
                                  ),
                                );
                              },
                            ),
                          _section(
                            context,
                            icon: Icons.hub_outlined,
                            title: 'Marketplace repositories',
                            subtitle:
                                'Catalogs are cached locally. Disabling one keeps installed addons.',
                          ),
                          SliverList.builder(
                            itemCount: state.repositories.length,
                            itemBuilder: (context, index) {
                              final repository = state.repositories[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _RepositoryTile(
                                  repository: repository,
                                  error: state.repositoryErrors[repository.url],
                                  toggleFocusNode: _dynamicFocus(
                                    'repository:${repository.url}:toggle',
                                    'Marketplace repository Enabled',
                                  ),
                                  removeFocusNode: _dynamicFocus(
                                    'repository:${repository.url}:remove',
                                    'Marketplace repository Remove',
                                  ),
                                  onToggle: () =>
                                      controller.setRepositoryEnabled(
                                        repository,
                                        !repository.enabled,
                                      ),
                                  onRemove: () => _confirmRepositoryRemoval(
                                    context,
                                    repository,
                                    controller,
                                  ),
                                ),
                              );
                            },
                          ),
                          if (state.installed.isNotEmpty) ...[
                            _section(
                              context,
                              icon: Icons.extension_rounded,
                              title: 'Installed providers',
                              subtitle:
                                  'Enabled providers participate in Web Stream searches.',
                            ),
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 540,
                                    mainAxisExtent: 260,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final addon = state.installed[index];
                                return _InstalledAddonCard(
                                  addon: addon,
                                  health:
                                      state.providerHealth[addon.manifest.id],
                                  message:
                                      state.providerMessages[addon.manifest.id],
                                  busy: state.busyAddonId == addon.manifest.id,
                                  testFocusNode: _dynamicFocus(
                                    'installed:${addon.manifest.id}:test',
                                    'Marketplace installed addon Test',
                                  ),
                                  toggleFocusNode: _dynamicFocus(
                                    'installed:${addon.manifest.id}:toggle',
                                    'Marketplace installed addon Toggle',
                                  ),
                                  resetFocusNode: _dynamicFocus(
                                    'installed:${addon.manifest.id}:reset',
                                    'Marketplace installed addon Reset',
                                  ),
                                  uninstallFocusNode: _dynamicFocus(
                                    'installed:${addon.manifest.id}:uninstall',
                                    'Marketplace installed addon Uninstall',
                                  ),
                                  onToggle: () => controller.setAddonEnabled(
                                    addon.manifest.id,
                                    !addon.enabled,
                                  ),
                                  onUninstall: () => _confirmUninstall(
                                    context,
                                    addon,
                                    controller,
                                  ),
                                  onTest: () => controller.testAddon(addon),
                                  onReset: () => controller.resetAddonHealth(
                                    addon.manifest.id,
                                  ),
                                );
                              }, childCount: state.installed.length),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 28),
                            ),
                          ],
                          _section(
                            context,
                            icon: Icons.storefront_outlined,
                            title: 'Available web providers',
                            subtitle:
                                '${state.catalog.where((item) => item.isCompatible).length} compatible JavaScript and TypeScript providers. '
                                'TypeScript is compiled once during installation.',
                          ),
                          if (state.catalog.isEmpty)
                            SliverToBoxAdapter(
                              child: _EmptyCatalog(
                                errors: state.repositoryErrors,
                              ),
                            )
                          else
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 540,
                                    mainAxisExtent: 250,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final addon = state.catalog[index];
                                final installed = state.installedById(addon.id);
                                final busy = state.busyAddonId == addon.id;
                                return _CatalogAddonCard(
                                  addon: addon,
                                  installed: installed,
                                  updateAvailable: state.updateAvailable(addon),
                                  busy: busy,
                                  actionFocusNode: _dynamicFocus(
                                    'catalog:${addon.id}:action',
                                    'Marketplace catalog addon action',
                                  ),
                                  onInstall: addon.isCompatible && !busy
                                      ? () => _confirmInstall(
                                          context,
                                          addon,
                                          controller,
                                        )
                                      : null,
                                );
                              }, childCount: state.catalog.length),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 28)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

SliverToBoxAdapter _section(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) => SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appPalette.accentBright),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  ),
);

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({
    required this.repository,
    required this.error,
    required this.toggleFocusNode,
    required this.removeFocusNode,
    required this.onToggle,
    required this.onRemove,
  });

  final AddonRepository repository;
  final String? error;
  final FocusNode toggleFocusNode;
  final FocusNode removeFocusNode;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(
            repository.enabled ? Icons.link_rounded : Icons.link_off_rounded,
            color: repository.enabled
                ? context.appPalette.secondaryAccent
                : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User repository',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  repository.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Text(
                    error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF929B),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          _MarketplaceButton(
            icon: repository.enabled
                ? Icons.toggle_on_rounded
                : Icons.toggle_off_rounded,
            label: context.isCompactWidth
                ? null
                : repository.enabled
                ? 'Enabled'
                : 'Disabled',
            focusNode: toggleFocusNode,
            onPressed: onToggle,
          ),
          const SizedBox(width: 8),
          _MarketplaceButton(
            icon: Icons.delete_outline_rounded,
            label: context.isCompactWidth ? null : 'Remove',
            focusNode: removeFocusNode,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _TorrentSourceTile extends StatelessWidget {
  const _TorrentSourceTile({
    required this.url,
    required this.removeFocusNode,
    required this.onRemove,
  });

  final String url;
  final FocusNode removeFocusNode;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.cloud_done_outlined,
          color: context.appPalette.secondaryAccent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User torrent source',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _MarketplaceButton(
          icon: Icons.delete_outline_rounded,
          label: context.isCompactWidth ? null : 'Remove',
          focusNode: removeFocusNode,
          onPressed: onRemove,
        ),
      ],
    ),
  );
}

class _InstalledAddonCard extends StatelessWidget {
  const _InstalledAddonCard({
    required this.addon,
    required this.health,
    required this.message,
    required this.busy,
    required this.testFocusNode,
    required this.toggleFocusNode,
    required this.resetFocusNode,
    required this.uninstallFocusNode,
    required this.onToggle,
    required this.onUninstall,
    required this.onTest,
    required this.onReset,
  });

  final InstalledStreamingAddon addon;
  final ProviderHealth? health;
  final String? message;
  final bool busy;
  final FocusNode testFocusNode;
  final FocusNode toggleFocusNode;
  final FocusNode resetFocusNode;
  final FocusNode uninstallFocusNode;
  final VoidCallback onToggle;
  final VoidCallback onUninstall;
  final VoidCallback onTest;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => _AddonShell(
    addon: addon.manifest,
    badge: !addon.enabled
        ? 'DISABLED'
        : health?.isQuarantined == true
        ? 'PAUSED AFTER FAILURES'
        : health?.lastSuccessAt != null
        ? 'HEALTHY'
        : 'NOT TESTED',
    footer: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message != null || health?.lastError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              message ??
                  '${health!.consecutiveFailures} failure(s): ${health!.lastError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.appPalette.mutedText,
                fontSize: 11,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MarketplaceButton(
              icon: busy
                  ? Icons.hourglass_top_rounded
                  : Icons.health_and_safety,
              label: busy ? 'Testing…' : 'Test',
              focusNode: testFocusNode,
              onPressed: busy || !addon.enabled ? null : onTest,
            ),
            _MarketplaceButton(
              icon: addon.enabled
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              label: addon.enabled ? 'Disable' : 'Enable',
              focusNode: toggleFocusNode,
              onPressed: onToggle,
            ),
            if (health != null)
              _MarketplaceButton(
                icon: Icons.restart_alt_rounded,
                label: 'Reset',
                focusNode: resetFocusNode,
                onPressed: onReset,
              ),
            _MarketplaceButton(
              icon: Icons.delete_outline_rounded,
              label: 'Uninstall',
              focusNode: uninstallFocusNode,
              onPressed: onUninstall,
            ),
          ],
        ),
      ],
    ),
  );
}

class _CatalogAddonCard extends StatelessWidget {
  const _CatalogAddonCard({
    required this.addon,
    required this.installed,
    required this.updateAvailable,
    required this.busy,
    required this.actionFocusNode,
    required this.onInstall,
  });

  final MarketplaceAddon addon;
  final InstalledStreamingAddon? installed;
  final bool updateAvailable;
  final bool busy;
  final FocusNode actionFocusNode;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final unsupported = !addon.isCompatible;
    return _AddonShell(
      addon: addon,
      badge: unsupported
          ? '${addon.language.toUpperCase()} / UNSUPPORTED'
          : installed == null
          ? addon.isTypescript
                ? 'TYPESCRIPT'
                : 'AVAILABLE'
          : updateAvailable
          ? 'UPDATE AVAILABLE'
          : 'INSTALLED',
      footer: _MarketplaceButton(
        icon: busy
            ? Icons.hourglass_top_rounded
            : updateAvailable
            ? Icons.system_update_alt_rounded
            : installed == null
            ? Icons.download_rounded
            : Icons.check_rounded,
        label: busy
            ? 'Installing…'
            : updateAvailable
            ? 'Update'
            : installed == null
            ? unsupported
                  ? 'Incompatible runtime'
                  : 'Install'
            : 'Installed',
        focusNode: actionFocusNode,
        onPressed: installed != null && !updateAvailable ? null : onInstall,
      ),
    );
  }
}

class _AddonShell extends StatelessWidget {
  const _AddonShell({
    required this.addon,
    required this.badge,
    required this.footer,
  });

  final MarketplaceAddon addon;
  final String badge;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AddonIcon(uri: addon.iconUri),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addon.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${addon.author} • ${addon.locale.toUpperCase()}'
                      '${addon.version == null ? '' : ' • v${addon.version}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      addon.manifestUri.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appPalette.mutedText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: context.appPalette.accent.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              addon.description.isEmpty
                  ? 'No description provided.'
                  : addon.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Align(alignment: Alignment.centerRight, child: footer),
        ],
      ),
    );
  }
}

class _AddonIcon extends StatelessWidget {
  const _AddonIcon({required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 50,
    height: 50,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.appPalette.accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        uri == null ? Icons.extension_rounded : Icons.language_rounded,
      ),
    ),
  );
}

class _MarketplaceButton extends StatelessWidget {
  const _MarketplaceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return ExcludeFocus(
      excluding: disabled,
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? .42 : 1,
          child: TvFocusable(
            autofocus: autofocus,
            focusNode: focusNode,
            onPressed: onPressed ?? () {},
            borderRadius: BorderRadius.circular(12),
            focusScale: 1.025,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              color: context.appPalette.selectableSurface,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  if (label != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      label!,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.errors});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Center(
      child: Text(
        errors.isEmpty
            ? 'No compatible providers were found.'
            : 'Repositories could not be loaded. Select Refresh to retry.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

Future<void> _addRepository(
  BuildContext context,
  MarketplaceController controller,
) async {
  final input = TextEditingController();
  try {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appPalette.surface,
        title: const Text('Add Marketplace repository'),
        content: SizedBox(
          width: 680,
          child: TvTextInput(
            controller: input,
            autofocus: true,
            labelText: 'HTTPS catalog URL',
            hintText: 'https://example.com/marketplace.json',
            keyboardTitle: 'Repository URL',
            onSubmitted: (_) => Navigator.pop(context, true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final error = await controller.addRepository(input.text.trim());
    if (error != null && context.mounted) _notice(context, error);
  } finally {
    input.dispose();
  }
}

Future<void> _addTorrentSource(
  BuildContext context,
  UserTorrentSourcesController controller,
) async {
  final input = TextEditingController();
  try {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appPalette.surface,
        title: const Text('Add torrent source'),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Only add a Torrent source manifest you trust and use it for content you are authorized to access.',
              ),
              const SizedBox(height: 14),
              TvTextInput(
                controller: input,
                autofocus: true,
                labelText: 'HTTPS manifest URL',
                hintText: 'https://example.com/addon/manifest.json',
                keyboardTitle: 'Torrent manifest URL',
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final error = await controller.add(input.text.trim());
    if (error != null && context.mounted) _notice(context, error);
  } finally {
    input.dispose();
  }
}

Future<void> _confirmInstall(
  BuildContext context,
  MarketplaceAddon addon,
  MarketplaceController controller,
) async {
  final accepted = await _confirm(
    context,
    title: 'Install ${addon.name}?',
    body:
        'This third-party provider may access public HTTPS websites. It cannot access TetoTV tokens, device files, or native Android APIs. Only install repositories you trust.',
    action: 'INSTALL',
  );
  if (!accepted) return;
  try {
    await controller.install(addon);
  } catch (error) {
    if (context.mounted) _notice(context, error.toString());
  }
}

Future<void> _confirmUninstall(
  BuildContext context,
  InstalledStreamingAddon addon,
  MarketplaceController controller,
) async {
  if (await _confirm(
    context,
    title: 'Uninstall ${addon.manifest.name}?',
    body:
        'Its web streams will no longer appear. Playback history and tracking are not changed.',
    action: 'UNINSTALL',
  )) {
    await controller.uninstall(addon.manifest.id);
  }
}

Future<void> _confirmRepositoryRemoval(
  BuildContext context,
  AddonRepository repository,
  MarketplaceController controller,
) async {
  if (await _confirm(
    context,
    title: 'Remove repository?',
    body:
        'Already installed providers remain installed. Add the repository URL again later if you want its catalog back.',
    action: 'REMOVE',
  )) {
    await controller.removeRepository(repository);
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) => showMarketplaceConfirmationDialog(
  context,
  title: title,
  body: body,
  action: action,
  autofocusAction: action == 'UNINSTALL',
);

/// Shows the Marketplace confirmation used for install and removal actions.
///
/// The uninstall action deliberately owns initial focus so a TV remote can
/// confirm it immediately. Left and right are handled explicitly because some
/// Android TV focus engines do not enter [AlertDialog.actions] until a second
/// directional key press.
Future<bool> showMarketplaceConfirmationDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool autofocusAction = false,
}) async {
  final cancelFocus = FocusNode(debugLabel: 'marketplace.confirm.cancel');
  final actionFocus = FocusNode(debugLabel: 'marketplace.confirm.action');
  try {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: dialogContext.appPalette.surface,
            title: Text(title),
            content: SizedBox(width: 620, child: Text(body)),
            actions: [
              Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    cancelFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    actionFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      focusNode: cancelFocus,
                      autofocus: !autofocusAction,
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('CANCEL'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      focusNode: actionFocus,
                      autofocus: autofocusAction,
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(action),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ) ??
        false;
  } finally {
    cancelFocus.dispose();
    actionFocus.dispose();
  }
}

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1119)),
  );
}
