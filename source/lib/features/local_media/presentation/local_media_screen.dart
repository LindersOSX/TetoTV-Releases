import 'dart:async';
import 'dart:typed_data';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/local_media/application/local_media_controller.dart';
import 'package:anime_tv/features/local_media/application/plex_controller.dart';
import 'package:anime_tv/features/local_media/data/jellyfin_client.dart';
import 'package:anime_tv/features/local_media/data/plex_client.dart';
import 'package:anime_tv/features/local_media/domain/jellyfin_models.dart';
import 'package:anime_tv/features/local_media/domain/plex_models.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/theme_studio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LocalMediaScreen extends ConsumerStatefulWidget {
  const LocalMediaScreen({super.key});

  @override
  ConsumerState<LocalMediaScreen> createState() => _LocalMediaScreenState();
}

class _LocalMediaScreenState extends ConsumerState<LocalMediaScreen> {
  final _addressController = TextEditingController(text: 'http://');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressFocus = FocusNode(debugLabel: 'Jellyfin server address');
  final _usernameFocus = FocusNode(debugLabel: 'Jellyfin username');
  final _passwordFocus = FocusNode(debugLabel: 'Jellyfin password');
  final _plexAddressController = TextEditingController(text: 'http://');
  final _plexTokenController = TextEditingController();
  final _plexAddressFocus = FocusNode(debugLabel: 'Plex server address');
  final _plexTokenFocus = FocusNode(debugLabel: 'Plex access token');
  bool _hydratedFields = false;
  bool _hydratedPlexFields = false;
  bool _openingPlayer = false;

  @override
  void dispose() {
    _addressController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _addressFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _plexAddressController.dispose();
    _plexTokenController.dispose();
    _plexAddressFocus.dispose();
    _plexTokenFocus.dispose();
    super.dispose();
  }

  void _hydrateFields(LocalMediaState state) {
    if (_hydratedFields || !state.loaded) return;
    _hydratedFields = true;
    final connection = state.connection;
    if (connection == null) return;
    _addressController.text = connection.baseUri.toString();
    _usernameController.text = connection.username;
  }

  void _hydratePlexFields(PlexState state) {
    if (_hydratedPlexFields || !state.loaded) return;
    _hydratedPlexFields = true;
    final connection = state.connection;
    if (connection != null) {
      _plexAddressController.text = connection.baseUri.toString();
    }
  }

  Future<void> _pickAndPlay() async {
    final controller = ref.read(localMediaControllerProvider.notifier);
    final document = await controller.pickLocalVideo();
    if (document != null && mounted) await _playDocument(document);
  }

  Future<void> _playDocument(LocalMediaDocument document) => _openPlayer(
    source: document.uri,
    title: document.name,
    releaseName: document.name,
    streamLabel: 'Local device media',
    headers: const {},
  );

  Future<void> _playJellyfin(JellyfinMediaItem item) async {
    final controller = ref.read(localMediaControllerProvider.notifier);
    await _openPlayer(
      source: controller.streamUri(item),
      title: item.displayTitle,
      releaseName: item.seriesName?.isNotEmpty == true
          ? '${item.seriesName} — ${item.displayTitle}'
          : item.displayTitle,
      streamLabel: 'Jellyfin • ${item.secondaryLabel}',
      headers: controller.playbackHeaders(),
      artworkUrl: controller.imageUri(item)?.toString(),
    );
  }

  Future<void> _playPlex(PlexMediaItem item) async {
    final controller = ref.read(plexControllerProvider.notifier);
    final source = controller.playbackUri(item);
    final series = item.grandparentTitle?.trim();
    await _openPlayer(
      source: source,
      title: item.displayTitle,
      releaseName: series?.isNotEmpty == true
          ? '$series — ${item.displayTitle}'
          : item.displayTitle,
      streamLabel: 'Plex • ${item.secondaryLabel}',
      headers: controller.playbackHeaders(),
    );
  }

  Future<void> _openPlayer({
    required Uri source,
    required String title,
    required String releaseName,
    required String streamLabel,
    required Map<String, String> headers,
    String? artworkUrl,
  }) async {
    if (_openingPlayer) return;
    setState(() => _openingPlayer = true);
    final controller = ref.read(localMediaControllerProvider.notifier);
    final appearance = ref.read(settingsPreferencesProvider);
    try {
      final resume = await controller.resumePosition(source);
      final result = await AndroidTvBridge.instance.startNativePlayer(
        source: source,
        title: title,
        checkpointKey: 'local:${controller.checkpointId(source)}',
        releaseName: releaseName,
        streamLabel: streamLabel,
        resumePosition: resume,
        resumeUpdatedAt: resume > Duration.zero ? DateTime.now() : null,
        startFromBeginning: false,
        audioLanguage: appearance.preferredAudio.audioLanguage,
        subtitlesEnabled: appearance.preferredAudio.subtitlesPreferred,
        subtitleSize: appearance.captionTextSize,
        subtitleTextColor: appearance.captionTextColor,
        subtitleBackgroundColor: appearance.captionBackgroundColor,
        seekBackSeconds: appearance.seekBackSeconds,
        seekForwardSeconds: appearance.seekForwardSeconds,
        autoSkipIntros: appearance.autoSkipIntros,
        autoSkipOutros: appearance.autoSkipOutros,
        artworkUrl: artworkUrl,
        headers: headers,
        trustedLocalSource: true,
        theme: ref
            .read(themeStudioControllerProvider)
            .palette
            .nativePlayerThemePayload,
      );
      if (result.completed) {
        await controller.clearResumePosition(source);
      } else {
        await controller.saveResumePosition(source, result.position);
      }
      if (!mounted) return;
      if (result.failed) {
        _showMessage(result.error ?? 'This video could not be played.');
      } else if (const {'use_mpv', 'use_vlc'}.contains(result.status)) {
        _showMessage(
          'Local, Jellyfin, and Plex media currently use the native Media3 player.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _openingPlayer = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localMediaControllerProvider);
    final plexState = ref.watch(plexControllerProvider);
    _hydrateFields(state);
    _hydratePlexFields(plexState);
    ref.listen(localMediaControllerProvider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showMessage(next.message!);
        });
      }
    });
    ref.listen(plexControllerProvider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showMessage(next.message!);
        });
      }
    });
    return Scaffold(
      backgroundColor: context.appPalette == AppThemePalette.defaults
          ? Colors.black
          : context.appPalette.background,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ActionButton(
                  label: 'Back',
                  icon: Icons.arrow_back_rounded,
                  autofocus: true,
                  onPressed: context.pop,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Local media, Jellyfin & Plex',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (state.busy || plexState.busy || _openingPlayer)
                  SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: context.appPalette.accentBright,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _SectionCard(
                    title: 'USB OR INTERNAL STORAGE',
                    subtitle:
                        'Choose a video with Android’s secure file picker. TetoTV keeps read access only to the file you select.',
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ActionButton(
                          label: 'Choose video',
                          icon: Icons.video_file_rounded,
                          onPressed: state.busy ? null : _pickAndPlay,
                        ),
                        if (state.recentLocalDocument case final recent?)
                          _ActionButton(
                            label: 'Play ${recent.name}',
                            icon: Icons.replay_rounded,
                            onPressed: _openingPlayer
                                ? null
                                : () => _playDocument(recent),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'JELLYFIN SERVER',
                    subtitle: state.connection == null
                        ? 'Connect to a Jellyfin server on your home network or an HTTPS server. Your password is used once and is never saved. HTTPS is recommended.'
                        : '${state.connection!.serverName} • ${state.connection!.username} • Jellyfin ${state.connection!.serverVersion}',
                    child: state.connection == null
                        ? _buildConnectionForm(state)
                        : _buildLibrary(state),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'PLEX MEDIA SERVER',
                    subtitle: plexState.connection == null
                        ? 'Connect with a Plex server address and X-Plex-Token. The token is stored in Android secure storage and is never placed in a media or artwork URL.'
                        : '${plexState.connection!.serverName ?? 'Plex Media Server'} • Plex ${plexState.connection!.serverVersion ?? 'unknown'}',
                    child: plexState.connection == null
                        ? _buildPlexConnectionForm(plexState)
                        : _buildPlexLibrary(plexState),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionForm(LocalMediaState state) => Column(
    children: [
      TvTextInput(
        controller: _addressController,
        focusNode: _addressFocus,
        labelText: 'Server address',
        hintText: '192.168.1.20:8096 or https://jellyfin.example.com',
        keyboardTitle: 'Jellyfin server address',
      ),
      const SizedBox(height: 12),
      TvTextInput(
        controller: _usernameController,
        focusNode: _usernameFocus,
        labelText: 'Username',
        keyboardTitle: 'Jellyfin username',
      ),
      const SizedBox(height: 12),
      TvTextInput(
        controller: _passwordController,
        focusNode: _passwordFocus,
        labelText: 'Password',
        keyboardTitle: 'Jellyfin password',
        obscureText: true,
        onSubmitted: (_) => _connectJellyfin(),
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: _ActionButton(
          label: 'Connect Jellyfin',
          icon: Icons.lan_rounded,
          onPressed: state.busy ? null : _connectJellyfin,
        ),
      ),
    ],
  );

  Future<void> _connectJellyfin() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final address = normalizeJellyfinServerUri(_addressController.text);
    if (address?.scheme == 'http') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use an unencrypted local connection?'),
          content: const Text(
            'HTTP is limited to a numeric private-network address, but your '
            'Jellyfin password and video traffic are not encrypted. Use HTTPS '
            'when your server supports it.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Connect on private network'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    await ref
        .read(localMediaControllerProvider.notifier)
        .connect(
          address: _addressController.text,
          username: _usernameController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;
    _passwordController.clear();
  }

  Widget _buildLibrary(LocalMediaState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (state.breadcrumbs.isNotEmpty)
            _ActionButton(
              label: 'Up',
              icon: Icons.arrow_upward_rounded,
              onPressed: state.busy
                  ? null
                  : ref.read(localMediaControllerProvider.notifier).goUp,
            ),
          _ActionButton(
            label: 'Refresh',
            icon: Icons.refresh_rounded,
            onPressed: state.busy
                ? null
                : ref.read(localMediaControllerProvider.notifier).refresh,
          ),
          _ActionButton(
            label: 'Disconnect',
            icon: Icons.link_off_rounded,
            onPressed: state.busy
                ? null
                : ref.read(localMediaControllerProvider.notifier).disconnect,
          ),
        ],
      ),
      if (state.breadcrumbs.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          state.breadcrumbs.map((crumb) => crumb.name).join('  /  '),
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      const SizedBox(height: 14),
      if (state.items.isNotEmpty)
        SizedBox(
          height: (state.items.length * 92.0).clamp(92.0, 520.0),
          child: ListView.separated(
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final item = state.items[index];
              return _MediaRow(
                item: item,
                imageUri: ref
                    .read(localMediaControllerProvider.notifier)
                    .imageUri(item),
                imageHeaders: ref
                    .read(localMediaControllerProvider.notifier)
                    .playbackHeaders(),
                onPressed: state.busy || _openingPlayer
                    ? null
                    : item.isFolder
                    ? () => ref
                          .read(localMediaControllerProvider.notifier)
                          .openFolder(item)
                    : () => _playJellyfin(item),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: 10),
          ),
        ),
      if (state.nextStartIndex < state.totalCount)
        _ActionButton(
          label: 'Load more (${state.items.length} of ${state.totalCount})',
          icon: Icons.expand_more_rounded,
          onPressed: state.busy
              ? null
              : ref.read(localMediaControllerProvider.notifier).loadMore,
        ),
    ],
  );

  Widget _buildPlexConnectionForm(PlexState state) => Column(
    children: [
      TvTextInput(
        controller: _plexAddressController,
        focusNode: _plexAddressFocus,
        labelText: 'Server address',
        hintText: '192.168.1.20:32400 or https://plex.example.com',
        keyboardTitle: 'Plex server address',
      ),
      const SizedBox(height: 12),
      TvTextInput(
        controller: _plexTokenController,
        focusNode: _plexTokenFocus,
        labelText: 'X-Plex-Token',
        keyboardTitle: 'Plex access token',
        obscureText: true,
        onSubmitted: (_) => _connectPlex(),
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: _ActionButton(
          label: 'Connect Plex',
          icon: Icons.connected_tv_rounded,
          onPressed: state.busy ? null : _connectPlex,
        ),
      ),
    ],
  );

  Future<void> _connectPlex() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final address = normalizePlexServerUri(_plexAddressController.text);
    if (address?.scheme == 'http') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Use an unencrypted local connection?'),
          content: const Text(
            'HTTP is limited to a numeric private-network address, but your '
            'Plex access token and video traffic are not encrypted. Use HTTPS '
            'when your server supports it.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Connect on private network'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    await ref
        .read(plexControllerProvider.notifier)
        .connect(
          address: _plexAddressController.text,
          token: _plexTokenController.text,
        );
    if (mounted) _plexTokenController.clear();
  }

  Widget _buildPlexLibrary(PlexState state) {
    final controller = ref.read(plexControllerProvider.notifier);
    final browsingItems = state.locations.isNotEmpty;
    final rowCount = browsingItems
        ? state.items.length
        : state.libraries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (browsingItems)
              _ActionButton(
                label: 'Up',
                icon: Icons.arrow_upward_rounded,
                onPressed: state.busy ? null : controller.goUp,
              ),
            _ActionButton(
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              onPressed: state.busy ? null : controller.refresh,
            ),
            _ActionButton(
              label: 'Disconnect',
              icon: Icons.link_off_rounded,
              onPressed: state.busy ? null : controller.disconnect,
            ),
          ],
        ),
        if (browsingItems) ...[
          const SizedBox(height: 14),
          Text(
            state.locations.map((location) => location.label).join('  /  '),
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (rowCount > 0) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: (rowCount * 92.0).clamp(92.0, 520.0),
            child: ListView.separated(
              key: const ValueKey('plex-library-list'),
              itemCount: rowCount,
              itemBuilder: (context, index) {
                if (!browsingItems) {
                  final library = state.libraries[index];
                  return _PlexBrowseRow(
                    key: ValueKey('plex-library-${library.key}'),
                    title: library.title,
                    subtitle: library.isMovieLibrary ? 'Movies' : 'TV shows',
                    isFolder: true,
                    imageUri: controller.libraryImageUri(library),
                    imageLoader: controller.imageBytes,
                    onPressed: state.busy
                        ? null
                        : () => controller.openLibrary(library),
                  );
                }
                final item = state.items[index];
                return _PlexBrowseRow(
                  key: ValueKey('plex-item-${item.ratingKey}'),
                  title: item.displayTitle,
                  subtitle: item.secondaryLabel,
                  isFolder: item.isFolder,
                  imageUri: controller.imageUri(item),
                  imageLoader: controller.imageBytes,
                  onPressed: state.busy || _openingPlayer
                      ? null
                      : item.isFolder
                      ? () => controller.openFolder(item)
                      : item.isPlayable
                      ? () => _playPlex(item)
                      : null,
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 10),
            ),
          ),
        ],
        if (browsingItems && state.nextOffset < state.totalCount) ...[
          const SizedBox(height: 12),
          _ActionButton(
            label: 'Load more (${state.items.length} of ${state.totalCount})',
            icon: Icons.expand_more_rounded,
            onPressed: state.busy ? null : controller.loadMore,
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appPalette.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: context.appPalette.accent.withValues(alpha: .26),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.appPalette.accentBright,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.item,
    required this.imageUri,
    required this.imageHeaders,
    required this.onPressed,
  });

  final JellyfinMediaItem item;
  final Uri? imageUri;
  final Map<String, String> imageHeaders;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .55 : 1,
    child: TvFocusable(
      onPressed: onPressed ?? () {},
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appPalette.selectableSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 64,
                height: 64,
                child: imageUri == null
                    ? ColoredBox(
                        color: context.appPalette.surfaceRaised,
                        child: Icon(Icons.movie_rounded),
                      )
                    : Image.network(
                        imageUri.toString(),
                        headers: imageHeaders,
                        cacheWidth: 128,
                        cacheHeight: 128,
                        filterQuality: FilterQuality.low,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: context.appPalette.surfaceRaised,
                          child: Icon(Icons.movie_rounded),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.secondaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(
              item.isFolder
                  ? Icons.chevron_right_rounded
                  : Icons.play_arrow_rounded,
              color: context.appPalette.accentBright,
              size: 30,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlexBrowseRow extends StatelessWidget {
  const _PlexBrowseRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isFolder,
    required this.imageUri,
    required this.imageLoader,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool isFolder;
  final Uri? imageUri;
  final Future<Uint8List> Function(Uri uri) imageLoader;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .55 : 1,
    child: TvFocusable(
      onPressed: onPressed ?? () {},
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.appPalette.selectableSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _PlexArtwork(uri: imageUri, loader: imageLoader),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(
              isFolder ? Icons.chevron_right_rounded : Icons.play_arrow_rounded,
              color: context.appPalette.accentBright,
              size: 30,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlexArtwork extends StatefulWidget {
  const _PlexArtwork({required this.uri, required this.loader});

  final Uri? uri;
  final Future<Uint8List> Function(Uri uri) loader;

  @override
  State<_PlexArtwork> createState() => _PlexArtworkState();
}

class _PlexArtworkState extends State<_PlexArtwork> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PlexArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _load();
  }

  void _load() {
    final uri = widget.uri;
    _bytes = uri == null ? null : widget.loader(uri);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const _MediaArtworkPlaceholder();
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null || value.isEmpty) {
          return const _MediaArtworkPlaceholder();
        }
        return Image.memory(
          value,
          cacheWidth: 128,
          cacheHeight: 128,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const _MediaArtworkPlaceholder(),
        );
      },
    );
  }
}

class _MediaArtworkPlaceholder extends StatelessWidget {
  const _MediaArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.appPalette.surfaceRaised,
    child: const Icon(Icons.movie_rounded),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .5 : 1,
    child: TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed ?? () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.appPalette.selectableSurface,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
