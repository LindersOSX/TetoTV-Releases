import 'dart:async';
import 'dart:convert';

import 'package:anime_tv/core/diagnostics/diagnostics_exporter.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<_DiagnosticsViewData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_DiagnosticsViewData> _load() async {
    final values = await Future.wait([
      AndroidTvBridge.instance.getDeviceProfile(refresh: true),
      AndroidTvBridge.instance.getAppVersion(),
      TetoTvDatabase.instance.diagnosticsSnapshot(),
    ]);
    return _DiagnosticsViewData(
      profile: values[0] as TvDeviceProfile,
      version: values[1] as AppVersionInfo,
      database: values[2] as Map<String, Object?>,
    );
  }

  void _refresh() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.appPalette.background,
    body: SafeArea(
      minimum: context.responsiveScreenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DiagnosticsAction(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                autofocus: true,
                onPressed: context.pop,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Diagnostics',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              _DiagnosticsAction(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<_DiagnosticsViewData>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Diagnostics failed: ${snapshot.error}'),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: context.appPalette.accentBright,
                    ),
                  );
                }
                return _DiagnosticsBody(data: data);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _DiagnosticsBody extends StatelessWidget {
  const _DiagnosticsBody({required this.data});

  final _DiagnosticsViewData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final events = (data.database['diagnosticEvents'] as List? ?? const [])
        .whereType<Map>()
        .take(12)
        .toList(growable: false);
    final hardwareCodecs =
        data.profile.codecs
            .where((codec) => codec.hardware)
            .map((codec) => codec.mime)
            .toSet()
            .toList()
          ..sort();
    return ListView(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DiagnosticCard(
              title: 'APP',
              value: 'TetoTV ${data.version.name}',
              detail: 'Build ${data.version.code}',
              icon: Icons.tv_rounded,
            ),
            _DiagnosticCard(
              title: 'DEVICE',
              value: '${data.profile.manufacturer} ${data.profile.model}',
              detail:
                  'Android ${data.profile.sdk} • ${data.profile.abis.join(', ')}',
              icon: Icons.devices_rounded,
            ),
            _DiagnosticCard(
              title: 'DISPLAY',
              value: data.profile.hasHdr ? 'HDR available' : 'SDR display',
              detail: '${data.profile.displayModes.length} display mode(s)',
              icon: Icons.monitor_rounded,
            ),
            _DiagnosticCard(
              title: 'VIDEO DECODERS',
              value: '${hardwareCodecs.length} hardware format(s)',
              detail: hardwareCodecs.isEmpty
                  ? 'No hardware decoders reported'
                  : hardwareCodecs.join(', '),
              icon: Icons.video_settings_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RECENT REDACTED EVENTS',
                style: TextStyle(
                  color: palette.accentBright,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                Text(
                  'No recent playback or provider failures.',
                  style: TextStyle(color: palette.mutedText),
                )
              else
                for (final event in events) ...[
                  Text(
                    '${event['category'] ?? 'event'} • ${event['created_at'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event['message'] ?? ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.mutedText, fontSize: 10),
                  ),
                  const Divider(height: 14),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            _DiagnosticsAction(
              label: 'Device calibration',
              icon: Icons.tune_rounded,
              onPressed: () => context.push('/settings/device-setup'),
            ),
            _DiagnosticsAction(
              label: 'Copy summary',
              icon: Icons.copy_rounded,
              onPressed: () async {
                final summary = const JsonEncoder.withIndent('  ').convert({
                  'app': data.version.name,
                  'build': data.version.code,
                  'device': data.profile.toJson(),
                  'diagnostics': data.database,
                });
                await Clipboard.setData(ClipboardData(text: summary));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Redacted diagnostics copied.')),
                );
              },
            ),
            _DiagnosticsAction(
              label: 'Export report',
              icon: Icons.file_download_outlined,
              primary: true,
              onPressed: () async {
                final file = await const DiagnosticsExporter().export();
                await Clipboard.setData(ClipboardData(text: file.path));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved report: ${file.path}')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 285,
    height: 112,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: context.appPalette.primaryText.withValues(alpha: .07),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appPalette.accentBright),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DiagnosticsAction extends StatelessWidget {
  const _DiagnosticsAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = primary
        ? contrastForeground(palette.accent)
        : palette.primaryText;
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 41,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: primary ? palette.accent : palette.selectableSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.primaryText.withValues(alpha: .1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsViewData {
  const _DiagnosticsViewData({
    required this.profile,
    required this.version,
    required this.database,
  });

  final TvDeviceProfile profile;
  final AppVersionInfo version;
  final Map<String, Object?> database;
}
