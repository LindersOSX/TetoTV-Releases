import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/core/widgets/copyable_qr_interaction.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/discord/application/discord_account_link_resolver.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:anime_tv/features/settings/application/all_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/premiumize_settings_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/settings/presentation/theme_studio_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _SettingsArea { customize, streaming, tracking, system }

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  _SettingsArea _activeArea = _SettingsArea.customize;
  final _torBoxTokenController = TextEditingController();
  final _allDebridTokenController = TextEditingController();
  final _premiumizeTokenController = TextEditingController();
  final _backFocus = FocusNode(debugLabel: 'accounts.back');
  final _titleLanguageFocus = FocusNode(debugLabel: 'accounts.title-language');
  final _debridProviderFocus = FocusNode(
    debugLabel: 'accounts.debrid.provider',
  );
  final _trackingProviderFocus = FocusNode(
    debugLabel: 'accounts.tracking.provider',
  );
  final _trackingThresholdFocus = FocusNode(
    debugLabel: 'accounts.tracking.update-threshold',
  );
  final _debridStreamsFocus = FocusNode(
    debugLabel: 'accounts.streaming.debrid',
  );
  final _webStreamsFocus = FocusNode(debugLabel: 'accounts.streaming.web');
  final _marketplaceFocus = FocusNode(
    debugLabel: 'accounts.streaming.marketplace',
  );
  final _localMediaFocus = FocusNode(
    debugLabel: 'accounts.streaming.local-media',
  );
  final _customizationFocus = FocusNode(
    debugLabel: 'accounts.customization.first',
  );
  final _setupFocus = FocusNode(debugLabel: 'accounts.system.setup');
  final _calibrationFocus = FocusNode(
    debugLabel: 'accounts.system.calibration',
  );
  final _diagnosticsFocus = FocusNode(
    debugLabel: 'accounts.system.diagnostics',
  );
  final _debridConnectFocus = FocusNode(debugLabel: 'accounts.debrid.connect');
  final _tokenFocus = FocusNode(debugLabel: 'accounts.debrid.token');
  final _tokenSaveFocus = FocusNode(debugLabel: 'accounts.debrid.save');
  final _torBoxActionFocus = FocusNode(debugLabel: 'accounts.torbox.action');
  final _torBoxTokenFocus = FocusNode(debugLabel: 'accounts.torbox.token');
  final _torBoxSaveFocus = FocusNode(debugLabel: 'accounts.torbox.save');
  final _allDebridActionFocus = FocusNode(
    debugLabel: 'accounts.alldebrid.action',
  );
  final _allDebridTokenFocus = FocusNode(
    debugLabel: 'accounts.alldebrid.token',
  );
  final _allDebridSaveFocus = FocusNode(debugLabel: 'accounts.alldebrid.save');
  final _premiumizeActionFocus = FocusNode(
    debugLabel: 'accounts.premiumize.action',
  );
  final _premiumizeTokenFocus = FocusNode(
    debugLabel: 'accounts.premiumize.token',
  );
  final _premiumizeSaveFocus = FocusNode(
    debugLabel: 'accounts.premiumize.save',
  );
  final _anilistFocus = FocusNode(debugLabel: 'accounts.anilist');
  final _malFocus = FocusNode(debugLabel: 'accounts.myanimelist');
  final _anilistTokenFocus = FocusNode(debugLabel: 'accounts.anilist.token');
  final _anilistSaveFocus = FocusNode(debugLabel: 'accounts.anilist.save');
  final _malTokenFocus = FocusNode(debugLabel: 'accounts.myanimelist.token');
  final _malSaveFocus = FocusNode(debugLabel: 'accounts.myanimelist.save');
  final _automaticUpdatesFocus = FocusNode(
    debugLabel: 'accounts.updates.automatic',
  );
  final _checkUpdatesFocus = FocusNode(debugLabel: 'accounts.updates.check');
  final _updateChannelFocus = FocusNode(debugLabel: 'accounts.updates.channel');
  final _releaseHistoryFocus = FocusNode(
    debugLabel: 'accounts.updates.release-history',
  );
  final _discordFocus = FocusNode(debugLabel: 'accounts.system.discord');
  final _discordQrFocus = FocusNode(debugLabel: 'accounts.system.discord-qr');
  final _discordPresenceFocus = FocusNode(
    debugLabel: 'accounts.system.discord-presence',
  );
  final _discordDisconnectFocus = FocusNode(
    debugLabel: 'accounts.system.discord-unlink',
  );
  final _donateFocus = FocusNode(debugLabel: 'accounts.system.donate');
  final _donationQrFocus = FocusNode(debugLabel: 'accounts.system.donation-qr');
  final _clearCacheFocus = FocusNode(debugLabel: 'accounts.system.clear-cache');
  final _resetAppFocus = FocusNode(debugLabel: 'accounts.system.reset-app');
  final _privacyFocus = FocusNode(debugLabel: 'accounts.system.privacy');
  final _legalFocus = FocusNode(debugLabel: 'accounts.system.legal');
  final _areaFocusNodes = {
    for (final area in _SettingsArea.values)
      area: FocusNode(debugLabel: 'accounts.area.${area.name}'),
  };
  final _shelfFocusNodes = {
    for (final shelf in HomeShelf.values)
      shelf: FocusNode(debugLabel: 'accounts.shelf.${shelf.name}'),
  };
  int _systemActivationCount = 0;

  @override
  void dispose() {
    _torBoxTokenController.dispose();
    _allDebridTokenController.dispose();
    _premiumizeTokenController.dispose();
    _backFocus.dispose();
    _titleLanguageFocus.dispose();
    _debridProviderFocus.dispose();
    _trackingProviderFocus.dispose();
    _trackingThresholdFocus.dispose();
    _debridStreamsFocus.dispose();
    _webStreamsFocus.dispose();
    _marketplaceFocus.dispose();
    _localMediaFocus.dispose();
    _customizationFocus.dispose();
    _setupFocus.dispose();
    _calibrationFocus.dispose();
    _diagnosticsFocus.dispose();
    _debridConnectFocus.dispose();
    _tokenFocus.dispose();
    _tokenSaveFocus.dispose();
    _torBoxActionFocus.dispose();
    _torBoxTokenFocus.dispose();
    _torBoxSaveFocus.dispose();
    _allDebridActionFocus.dispose();
    _allDebridTokenFocus.dispose();
    _allDebridSaveFocus.dispose();
    _premiumizeActionFocus.dispose();
    _premiumizeTokenFocus.dispose();
    _premiumizeSaveFocus.dispose();
    _anilistFocus.dispose();
    _malFocus.dispose();
    _anilistTokenFocus.dispose();
    _anilistSaveFocus.dispose();
    _malTokenFocus.dispose();
    _malSaveFocus.dispose();
    _automaticUpdatesFocus.dispose();
    _checkUpdatesFocus.dispose();
    _updateChannelFocus.dispose();
    _releaseHistoryFocus.dispose();
    _discordFocus.dispose();
    _discordQrFocus.dispose();
    _discordPresenceFocus.dispose();
    _discordDisconnectFocus.dispose();
    _donateFocus.dispose();
    _donationQrFocus.dispose();
    _clearCacheFocus.dispose();
    _resetAppFocus.dispose();
    _privacyFocus.dispose();
    _legalFocus.dispose();
    for (final node in _areaFocusNodes.values) {
      node.dispose();
    }
    for (final node in _shelfFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final current = FocusManager.instance.primaryFocus;
    final key = event.logicalKey;
    final preferences = ref.read(settingsPreferencesProvider);
    final selectedDebridAction = switch (preferences.debridProvider) {
      DebridService.realDebrid => _debridConnectFocus,
      DebridService.torBox => _torBoxActionFocus,
      DebridService.allDebrid => _allDebridActionFocus,
      DebridService.premiumize => _premiumizeActionFocus,
    };
    final selectedDebridToken = switch (preferences.debridProvider) {
      DebridService.realDebrid => _tokenFocus,
      DebridService.torBox => _torBoxTokenFocus,
      DebridService.allDebrid => _allDebridTokenFocus,
      DebridService.premiumize => _premiumizeTokenFocus,
    };
    final selectedDebridLast = switch (preferences.debridProvider) {
      DebridService.realDebrid => _tokenSaveFocus,
      DebridService.torBox => _torBoxSaveFocus,
      DebridService.allDebrid => _allDebridSaveFocus,
      DebridService.premiumize => _premiumizeSaveFocus,
    };
    final selectedTrackingAction =
        preferences.trackingProvider == TrackingProvider.anilist
        ? _anilistFocus
        : _malFocus;
    FocusNode? target;
    final shelfNodes = [
      for (final shelf in ref.read(homeShelfOrderProvider))
        _shelfFocusNodes[shelf]!,
    ];
    final shelfIndex = current == null ? -1 : shelfNodes.indexOf(current);
    final areaNodes = [
      for (final area in _SettingsArea.values) _areaFocusNodes[area]!,
    ];
    final areaIndex = current == null ? -1 : areaNodes.indexOf(current);

    if (areaIndex >= 0) {
      if (key == LogicalKeyboardKey.arrowLeft && areaIndex > 0) {
        target = areaNodes[areaIndex - 1];
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          areaIndex < areaNodes.length - 1) {
        target = areaNodes[areaIndex + 1];
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _titleLanguageFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = switch (_activeArea) {
          _SettingsArea.customize => shelfNodes.first,
          _SettingsArea.streaming => _debridProviderFocus,
          _SettingsArea.tracking => _trackingProviderFocus,
          _SettingsArea.system => _setupFocus,
        };
      }
    } else if (shelfIndex >= 0) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = shelfIndex > 0
            ? shelfNodes[shelfIndex - 1]
            : _areaFocusNodes[_SettingsArea.customize];
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = shelfIndex < shelfNodes.length - 1
            ? shelfNodes[shelfIndex + 1]
            : _customizationFocus;
      }
    }

    if (areaIndex >= 0 || shelfIndex >= 0) {
      // Settings-area and Home-shelf navigation were handled above.
    } else if (current == _backFocus) {
      if (key == LogicalKeyboardKey.arrowRight) {
        target = _titleLanguageFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _areaFocusNodes[_activeArea];
      }
    } else if (current == _titleLanguageFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _areaFocusNodes[_activeArea];
      }
    } else if (current == _debridProviderFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.streaming];
      }
      if (key == LogicalKeyboardKey.arrowDown) target = selectedDebridAction;
    } else if (current == selectedDebridAction) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _debridProviderFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = selectedDebridToken.context == null
            ? _debridStreamsFocus
            : selectedDebridToken;
      }
    } else if (current == selectedDebridToken) {
      if (key == LogicalKeyboardKey.arrowRight) target = selectedDebridLast;
      if (key == LogicalKeyboardKey.arrowUp) target = selectedDebridAction;
    } else if (current == selectedDebridLast) {
      if (key == LogicalKeyboardKey.arrowLeft) target = selectedDebridToken;
      if (key == LogicalKeyboardKey.arrowUp) target = selectedDebridAction;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _debridStreamsFocus;
      }
    } else if (current == _debridStreamsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = selectedDebridLast.context == null
            ? selectedDebridAction
            : selectedDebridLast;
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _webStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _marketplaceFocus;
    } else if (current == _webStreamsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = selectedDebridLast.context == null
            ? selectedDebridAction
            : selectedDebridLast;
      }
      if (key == LogicalKeyboardKey.arrowLeft) target = _debridStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _marketplaceFocus;
    } else if (current == _marketplaceFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _debridStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown &&
          ref.read(appUpdateControllerProvider).developerMode) {
        target = _localMediaFocus;
      }
    } else if (current == _localMediaFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _marketplaceFocus;
      // Streaming is the end of this tab. Keep focus here instead of pointing
      // at a control which is not mounted while this tab is active.
      if (key == LogicalKeyboardKey.arrowDown) target = _localMediaFocus;
    } else if (current == _trackingProviderFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.tracking];
      }
      if (key == LogicalKeyboardKey.arrowDown) target = selectedTrackingAction;
    } else if (current == _anilistFocus) {
      if (key == LogicalKeyboardKey.arrowDown &&
          _anilistTokenFocus.context != null) {
        target = _anilistTokenFocus;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        target = _trackingThresholdFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _trackingProviderFocus;
    } else if (current == _malFocus) {
      if (key == LogicalKeyboardKey.arrowDown &&
          _malTokenFocus.context != null) {
        target = _malTokenFocus;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        target = _trackingThresholdFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _trackingProviderFocus;
    } else if (current == _anilistTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _anilistSaveFocus;
    } else if (current == _anilistSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _anilistTokenFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _trackingThresholdFocus;
      }
    } else if (current == _malTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _malFocus;
      if (key == LogicalKeyboardKey.arrowLeft &&
          _anilistSaveFocus.context != null) {
        target = _anilistSaveFocus;
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _malSaveFocus;
    } else if (current == _malSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _malFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _malTokenFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _trackingThresholdFocus;
      }
    } else if (current == _trackingThresholdFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        final selectedSave =
            preferences.trackingProvider == TrackingProvider.anilist
            ? _anilistSaveFocus
            : _malSaveFocus;
        target = selectedSave.context == null
            ? selectedTrackingAction
            : selectedSave;
      }
    } else if (current == _setupFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _calibrationFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _automaticUpdatesFocus;
      }
    } else if (current == _calibrationFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowLeft) target = _setupFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _diagnosticsFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _automaticUpdatesFocus;
      }
    } else if (current == _diagnosticsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowLeft) target = _calibrationFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _automaticUpdatesFocus;
      }
    } else if (current == _automaticUpdatesFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _setupFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _checkUpdatesFocus;
    } else if (current == _checkUpdatesFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _setupFocus;
      if (key == LogicalKeyboardKey.arrowLeft) {
        target = _automaticUpdatesFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = ref.read(appUpdateControllerProvider).developerMode
            ? _updateChannelFocus
            : _discordPresenceFocus;
      }
    } else if (current == _updateChannelFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _checkUpdatesFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _releaseHistoryFocus;
    } else if (current == _releaseHistoryFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _updateChannelFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _discordPresenceFocus;
    } else if (current == _discordPresenceFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = ref.read(appUpdateControllerProvider).developerMode
            ? _releaseHistoryFocus
            : _checkUpdatesFocus;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          _discordDisconnectFocus.context != null) {
        target = _discordDisconnectFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) target = _discordQrFocus;
    } else if (current == _discordDisconnectFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _discordPresenceFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _checkUpdatesFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _discordQrFocus;
    } else if (current == _discordQrFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _discordDisconnectFocus.context != null
            ? _discordDisconnectFocus
            : _discordPresenceFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) target = _discordFocus;
    } else if (current == _discordFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _discordQrFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _donationQrFocus;
    } else if (current == _donationQrFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _discordFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _donateFocus;
    } else if (current == _donateFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _donationQrFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _clearCacheFocus;
    } else if (current == _clearCacheFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _donateFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _resetAppFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _privacyFocus;
    } else if (current == _resetAppFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _donateFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _clearCacheFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _privacyFocus;
    } else if (current == _privacyFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _clearCacheFocus;
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        target = _legalFocus;
      }
    } else if (current == _legalFocus) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp) {
        target = _privacyFocus;
      }
    }

    if (target == null || target.context == null) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    // Settings intentionally uses a screen-local focus graph for a few
    // cross-column transitions, so reveal that explicit target exactly once.
    // Normal app-wide D-pad traversal is revealed by Flutter's policy.
    final alignmentPolicy =
        key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target?.context;
      if (mounted && targetContext != null && targetContext.mounted) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          alignmentPolicy: alignmentPolicy,
        );
      }
    });
    return KeyEventResult.handled;
  }

  Future<void> _selectSettingsArea(_SettingsArea area) async {
    setState(() => _activeArea = area);
    final updateState = ref.read(appUpdateControllerProvider);
    if (updateState.developerMode) return;
    if (area != _SettingsArea.system) {
      _systemActivationCount = 0;
      return;
    }
    _systemActivationCount += 1;
    if (_systemActivationCount < 10) return;
    _systemActivationCount = 0;
    await ref.read(appUpdateControllerProvider.notifier).enableDeveloperMode();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Developer mode enabled. You can now choose Public or Beta updates.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final debrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final allDebrid = ref.watch(allDebridSettingsControllerProvider);
    final premiumize = ref.watch(premiumizeSettingsControllerProvider);
    final tracking = ref.watch(trackingAccountsControllerProvider);
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final homeShelves = ref.watch(homeShelfPreferencesProvider);
    final homeShelfOrder = ref.watch(homeShelfOrderProvider);
    final appUpdate = ref.watch(appUpdateControllerProvider);
    final discordPresence = ref.watch(discordPresenceControllerProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    final isTelevision = ref.watch(isTelevisionProvider);
    return Scaffold(
      backgroundColor: _settingsPageBackground(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: context.responsiveScreenPadding.copyWith(top: 0, bottom: 0),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handleKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final showSecurityLabel = constraints.maxWidth >= 1180;
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _TvIconButton(
                              autofocus: true,
                              focusNode: _backFocus,
                              icon: Icons.arrow_back_rounded,
                              onPressed: context.pop,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Settings',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: context.appPalette.secondaryAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _TitleLanguageToggle(
                          focusNode: _titleLanguageFocus,
                          preference: titlePreference,
                          onPressed: () => ref
                              .read(titleLanguagePreferenceProvider.notifier)
                              .toggle(),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      _TvIconButton(
                        autofocus: true,
                        focusNode: _backFocus,
                        icon: Icons.arrow_back_rounded,
                        onPressed: context.pop,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          'Settings',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _TitleLanguageToggle(
                        focusNode: _titleLanguageFocus,
                        preference: titlePreference,
                        onPressed: () {
                          ref
                              .read(titleLanguagePreferenceProvider.notifier)
                              .toggle();
                        },
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: 'Secrets stay encrypted on this device',
                        child: Icon(
                          Icons.lock_rounded,
                          size: 18,
                          color: context.appPalette.secondaryAccent,
                        ),
                      ),
                      if (showSecurityLabel) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Secrets stay encrypted on this device',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _SettingsAreaTabs(
                selected: _activeArea,
                focusNodes: _areaFocusNodes,
                onSelected: _selectSettingsArea,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
                  ),
                  children: [
                    if (_activeArea == _SettingsArea.customize) ...[
                      const _SectionHeader(
                        icon: Icons.tune_rounded,
                        title: 'APPEARANCE & NAVIGATION',
                        subtitle:
                            'Personalize layout, Home content, controls, captions, and sounds.',
                      ),
                      const SizedBox(height: 8),
                      _HomeShelfOrganizer(
                        order: homeShelfOrder,
                        enabled: homeShelves,
                        focusNodes: _shelfFocusNodes,
                        onToggle: (shelf) => ref
                            .read(homeShelfPreferencesProvider.notifier)
                            .toggle(shelf),
                        onMove: (shelf, offset) => ref
                            .read(homeShelfOrderProvider.notifier)
                            .move(shelf, offset),
                      ),
                      const SizedBox(height: 10),
                      _CustomizationPanel(
                        preferences: preferences,
                        controller: ref.read(
                          settingsPreferencesProvider.notifier,
                        ),
                        firstFocusNode: _customizationFocus,
                        onOpenThemeStudio: () =>
                            context.push(ThemeStudioScreen.routePath),
                        onReset: () async {
                          final controller = ref.read(
                            settingsPreferencesProvider.notifier,
                          );
                          await controller.resetCustomization();
                          await controller.resetAppearance();
                          await ref
                              .read(homeShelfPreferencesProvider.notifier)
                              .reset();
                          await ref
                              .read(homeShelfOrderProvider.notifier)
                              .reset();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.streaming) ...[
                      const _SectionHeader(
                        icon: Icons.cloud_done_rounded,
                        title: 'DEBRID STREAMING',
                        subtitle:
                            'Choose the provider used to resolve streams.',
                      ),
                      const SizedBox(height: 8),
                      _SettingsSelection<DebridService>(
                        focusNode: _debridProviderFocus,
                        label: 'Debrid provider',
                        value: preferences.debridProvider,
                        options: [
                          for (final service in DebridService.values)
                            _SettingsOption(
                              value: service,
                              label: service.displayName,
                              detail:
                                  switch (service) {
                                    DebridService.realDebrid =>
                                      debrid.hasSavedToken,
                                    DebridService.torBox =>
                                      torBox.hasSavedToken,
                                    DebridService.allDebrid =>
                                      allDebrid.hasSavedToken,
                                    DebridService.premiumize =>
                                      premiumize.hasSavedToken,
                                  }
                                  ? 'Connected'
                                  : 'Not connected',
                            ),
                        ],
                        onSelected: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setDebridProvider,
                      ),
                      const SizedBox(height: 8),
                      switch (preferences.debridProvider) {
                        DebridService.realDebrid => _RealDebridPanel(
                          state: debrid,
                          onDisconnect: () => ref
                              .read(
                                realDebridSettingsControllerProvider.notifier,
                              )
                              .disconnect(),
                          onDeviceConnect: () =>
                              context.push('/pair/realdebrid'),
                          connectFocusNode: _debridConnectFocus,
                        ),
                        DebridService.torBox => _TorBoxPanel(
                          state: torBox,
                          tokenController: _torBoxTokenController,
                          onSave: () async {
                            final saved = await ref
                                .read(torBoxSettingsControllerProvider.notifier)
                                .saveAndValidate(_torBoxTokenController.text);
                            if (saved) _torBoxTokenController.clear();
                          },
                          onDisconnect: () => ref
                              .read(torBoxSettingsControllerProvider.notifier)
                              .disconnect(),
                          onDeviceConnect: () async {
                            await context.push('/pair/torbox');
                            await ref
                                .read(torBoxSettingsControllerProvider.notifier)
                                .load();
                          },
                          actionFocusNode: _torBoxActionFocus,
                          tokenFocusNode: _torBoxTokenFocus,
                          saveFocusNode: _torBoxSaveFocus,
                        ),
                        DebridService.allDebrid => _ApiKeyDebridPanel(
                          title: 'AllDebrid',
                          icon: Icons.cloud_sync_rounded,
                          gradient: [
                            context.appPalette.accent,
                            context.appPalette.secondaryAccent,
                          ],
                          connected: allDebrid.account != null,
                          hasSavedToken: allDebrid.hasSavedToken,
                          connectedLabel: 'PREMIUM',
                          description: allDebrid.account == null
                              ? 'Authorize with AllDebrid PIN, or enter a personal API key.'
                              : 'Connected as ${allDebrid.account!.username}. '
                                    'Torrent files resolve through AllDebrid only.',
                          errorMessage: allDebrid.errorMessage,
                          isLoading: allDebrid.isLoading,
                          tokenController: _allDebridTokenController,
                          tokenTitle: 'AllDebrid API key',
                          keyboardTitle: 'Enter AllDebrid API key',
                          connectLabel: 'Connect by PIN',
                          connectIcon: Icons.qr_code_rounded,
                          onSave: () async {
                            final saved = await ref
                                .read(
                                  allDebridSettingsControllerProvider.notifier,
                                )
                                .saveAndValidate(
                                  _allDebridTokenController.text,
                                );
                            if (saved) _allDebridTokenController.clear();
                          },
                          onDisconnect: () => ref
                              .read(
                                allDebridSettingsControllerProvider.notifier,
                              )
                              .disconnect(),
                          onConnect: () async {
                            await context.push('/pair/alldebrid');
                            await ref
                                .read(
                                  allDebridSettingsControllerProvider.notifier,
                                )
                                .load();
                          },
                          actionFocusNode: _allDebridActionFocus,
                          tokenFocusNode: _allDebridTokenFocus,
                          saveFocusNode: _allDebridSaveFocus,
                        ),
                        DebridService.premiumize => _ApiKeyDebridPanel(
                          title: 'Premiumize',
                          icon: Icons.cloud_queue_rounded,
                          gradient: [
                            context.appPalette.secondaryAccent,
                            context.appPalette.accentBright,
                          ],
                          connected: premiumize.account != null,
                          hasSavedToken: premiumize.hasSavedToken,
                          connectedLabel: 'PREMIUM',
                          description: premiumize.account == null
                              ? 'Enter the API key from your Premiumize account page.'
                              : 'Connected as customer '
                                    '${premiumize.account!.customerId}. '
                                    'Torrent files resolve through Premiumize only.',
                          errorMessage: premiumize.errorMessage,
                          isLoading: premiumize.isLoading,
                          tokenController: _premiumizeTokenController,
                          tokenTitle: 'Premiumize API key',
                          keyboardTitle: 'Enter Premiumize API key',
                          connectLabel: 'Connection help',
                          connectIcon: Icons.key_rounded,
                          onSave: () async {
                            final saved = await ref
                                .read(
                                  premiumizeSettingsControllerProvider.notifier,
                                )
                                .saveAndValidate(
                                  _premiumizeTokenController.text,
                                );
                            if (saved) _premiumizeTokenController.clear();
                          },
                          onDisconnect: () => ref
                              .read(
                                premiumizeSettingsControllerProvider.notifier,
                              )
                              .disconnect(),
                          onConnect: () async {
                            await context.push('/pair/premiumize');
                            await ref
                                .read(
                                  premiumizeSettingsControllerProvider.notifier,
                                )
                                .load();
                          },
                          actionFocusNode: _premiumizeActionFocus,
                          tokenFocusNode: _premiumizeTokenFocus,
                          saveFocusNode: _premiumizeSaveFocus,
                        ),
                      },
                      const SizedBox(height: 14),
                      const _SectionHeader(
                        icon: Icons.stream_rounded,
                        title: 'SOURCES',
                        subtitle:
                            'Choose which source types are searched for each episode.',
                      ),
                      const SizedBox(height: 8),
                      _StreamingSourcesPanel(
                        preferences: preferences,
                        debridFocusNode: _debridStreamsFocus,
                        webFocusNode: _webStreamsFocus,
                        marketplaceFocusNode: _marketplaceFocus,
                        onDebridChanged: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setDebridStreamsEnabled,
                        onWebChanged: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setWebStreamsEnabled,
                        onMarketplace: () =>
                            context.push('/settings/marketplace'),
                      ),
                      if (appUpdate.developerMode) ...[
                        const SizedBox(height: 8),
                        _Panel(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Local media, Jellyfin & Plex',
                                      style: TextStyle(
                                        color: context.appPalette.primaryText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Play from USB/internal storage, Jellyfin, or Plex.',
                                      style: TextStyle(
                                        color: context.appPalette.mutedText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _TvTextButton(
                                label: 'Open media',
                                icon: Icons.video_library_rounded,
                                focusNode: _localMediaFocus,
                                onPressed: () =>
                                    context.push('/settings/local-media'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const _DebridOnlyPanel(),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.tracking) ...[
                      const _SectionHeader(
                        icon: Icons.sync_alt_rounded,
                        title: 'ANIME TRACKING',
                        subtitle: 'Configure one list service at a time.',
                      ),
                      const SizedBox(height: 8),
                      _SettingsSelection<TrackingProvider>(
                        focusNode: _trackingProviderFocus,
                        label: 'Anime-list provider',
                        value: preferences.trackingProvider,
                        options: [
                          for (final provider in TrackingProvider.values)
                            _SettingsOption(
                              value: provider,
                              label: provider.displayName,
                              detail: tracking.isConnected(provider)
                                  ? 'Connected as ${tracking.usernames[provider]}'
                                  : 'Not connected',
                            ),
                        ],
                        onSelected: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setTrackingProvider,
                      ),
                      const SizedBox(height: 8),
                      _TrackingPanel(
                        provider: preferences.trackingProvider,
                        color:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? context.appPalette.accentBright
                            : const Color(0xFFB41F3D),
                        description:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? 'Seasonal discovery, lists, and automatic episode progress.'
                            : 'Sync watch progress and MAL statuses automatically.',
                        username:
                            tracking.usernames[preferences.trackingProvider],
                        error: tracking.errors[preferences.trackingProvider],
                        isLoading: tracking.isLoading,
                        onConnect: () async {
                          await context.push(
                            preferences.trackingProvider ==
                                    TrackingProvider.anilist
                                ? '/pair/anilist'
                                : '/pair/myanimelist',
                          );
                          await ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .load();
                        },
                        onDisconnect: () => ref
                            .read(trackingAccountsControllerProvider.notifier)
                            .disconnect(preferences.trackingProvider),
                        onSaveToken: (token) => ref
                            .read(trackingAccountsControllerProvider.notifier)
                            .save(preferences.trackingProvider, token),
                        focusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistFocus
                            : _malFocus,
                        tokenFocusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistTokenFocus
                            : _malTokenFocus,
                        saveFocusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistSaveFocus
                            : _malSaveFocus,
                      ),
                      const SizedBox(height: 8),
                      _SettingsSelection<TrackerUpdateThreshold>(
                        focusNode: _trackingThresholdFocus,
                        label: 'When to update episode progress',
                        value: preferences.trackerUpdateThreshold,
                        options: [
                          for (final threshold in TrackerUpdateThreshold.values)
                            _SettingsOption(
                              value: threshold,
                              label: threshold.displayName,
                              detail: threshold.description,
                            ),
                        ],
                        onSelected: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setTrackerUpdateThreshold,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Trackers store whole completed episodes, so the '
                        'selected percentage marks the current episode watched.',
                        style: TextStyle(
                          color: context.appPalette.mutedText,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.system) ...[
                      const _SectionHeader(
                        icon: Icons.memory_rounded,
                        title: 'SYSTEM & SUPPORT',
                        subtitle:
                            'Setup, device compatibility, diagnostics, and app updates.',
                      ),
                      const SizedBox(height: 8),
                      _Panel(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final actions = [
                              _TvTextButton(
                                label: 'Run setup again',
                                icon: Icons.auto_awesome_rounded,
                                focusNode: _setupFocus,
                                onPressed: () => context.push('/setup'),
                              ),
                              _TvTextButton(
                                label: 'Device calibration',
                                icon: Icons.tune_rounded,
                                focusNode: _calibrationFocus,
                                onPressed: () =>
                                    context.push('/settings/device-setup'),
                              ),
                              _TvTextButton(
                                label: 'Diagnostics',
                                icon: Icons.monitor_heart_rounded,
                                focusNode: _diagnosticsFocus,
                                onPressed: () =>
                                    context.push('/settings/diagnostics'),
                              ),
                            ];
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: actions,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.system_update_alt_rounded,
                        title: 'APP UPDATES',
                        subtitle:
                            'Stable public releases download directly to this device.',
                      ),
                      const SizedBox(height: 8),
                      _AppUpdatePanel(
                        state: appUpdate,
                        automaticFocusNode: _automaticUpdatesFocus,
                        checkFocusNode: _checkUpdatesFocus,
                        onToggleAutomatic: () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .setAutomaticUpdates(!appUpdate.automaticUpdates),
                        onCheckOrInstall: () {
                          final controller = ref.read(
                            appUpdateControllerProvider.notifier,
                          );
                          if (appUpdate.downloadedPath != null) {
                            controller.installDownloadedUpdate();
                          } else {
                            controller.checkForUpdates(launchInstaller: true);
                          }
                        },
                      ),
                      if (appUpdate.developerMode) ...[
                        const SizedBox(height: 8),
                        _DeveloperUpdatePanel(
                          state: appUpdate,
                          channelFocusNode: _updateChannelFocus,
                          releaseHistoryFocusNode: _releaseHistoryFocus,
                          onChannelSelected: ref
                              .read(appUpdateControllerProvider.notifier)
                              .setUpdateChannel,
                          onRefreshHistory: ref
                              .read(appUpdateControllerProvider.notifier)
                              .refreshReleaseHistory,
                          onReleaseSelected: ref
                              .read(appUpdateControllerProvider.notifier)
                              .installReleaseFromHistory,
                        ),
                      ],
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.sports_esports_rounded,
                        title: 'DISCORD RICH PRESENCE',
                        subtitle:
                            'Control the optional Discord activity shown while you watch.',
                      ),
                      const SizedBox(height: 8),
                      _DiscordPresencePanel(
                        state: discordPresence,
                        primaryFocusNode: _discordPresenceFocus,
                        unlinkFocusNode: _discordDisconnectFocus,
                        onLink: () async {
                          final resolver = ref.read(
                            discordAccountLinkResolverProvider,
                          );
                          final controller = ref.read(
                            discordPresenceControllerProvider.notifier,
                          );
                          final flow = await resolver.resolve(
                            startupTelevision: isTelevision,
                          );
                          if (!context.mounted) return;
                          if (flow == DiscordAccountLinkFlow.deviceQr) {
                            await context.push('/pair/discord');
                          } else {
                            await controller.linkAccount();
                          }
                        },
                        onToggle: () => ref
                            .read(discordPresenceControllerProvider.notifier)
                            .setEnabled(!discordPresence.enabled),
                        onRetry: () => ref
                            .read(discordPresenceControllerProvider.notifier)
                            .retry(),
                        onUnlink: () => ref
                            .read(discordPresenceControllerProvider.notifier)
                            .unlinkAccount(),
                      ),
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.forum_rounded,
                        title: 'COMMUNITY',
                        subtitle:
                            'Join the TetoTV Discord for announcements, support, and feature requests.',
                      ),
                      const SizedBox(height: 8),
                      _DiscordCommunityPanel(
                        qrFocusNode: _discordQrFocus,
                        focusNode: _discordFocus,
                      ),
                      const SizedBox(height: 8),
                      _DonationPanel(
                        qrFocusNode: _donationQrFocus,
                        focusNode: _donateFocus,
                      ),
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.storage_rounded,
                        title: 'STORAGE & RESET',
                        subtitle:
                            'Remove temporary files or return TetoTV to first-time setup.',
                      ),
                      const SizedBox(height: 8),
                      _StorageResetPanel(
                        clearCacheFocusNode: _clearCacheFocus,
                        resetAppFocusNode: _resetAppFocus,
                      ),
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.info_rounded,
                        title: 'ABOUT & LEGAL',
                        subtitle:
                            'Privacy, attribution, and open-source notices.',
                      ),
                      const SizedBox(height: 8),
                      _LegalNoticesPanel(
                        privacyFocusNode: _privacyFocus,
                        licenseFocusNode: _legalFocus,
                      ),
                    ],
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

class _SettingsAreaTabs extends StatelessWidget {
  const _SettingsAreaTabs({
    required this.selected,
    required this.focusNodes,
    required this.onSelected,
  });

  final _SettingsArea selected;
  final Map<_SettingsArea, FocusNode> focusNodes;
  final ValueChanged<_SettingsArea> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget tab(_SettingsArea area, {required bool compact}) {
      final active = area == selected;
      final (icon, label) = switch (area) {
        _SettingsArea.customize => (Icons.tune_rounded, 'Customize'),
        _SettingsArea.streaming => (Icons.live_tv_rounded, 'Streaming'),
        _SettingsArea.tracking => (Icons.sync_rounded, 'Tracking'),
        _SettingsArea.system => (Icons.settings_rounded, 'System'),
      };
      return TvFocusable(
        focusNode: focusNodes[area],
        onPressed: () => onSelected(area),
        focusScale: 1.02,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 16,
            vertical: compact ? 5 : 0,
          ),
          decoration: BoxDecoration(
            color: active
                ? context.appPalette.accent
                : context.appPalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? context.appPalette.accentBright
                  : _settingsBorderColor(context, .08),
            ),
          ),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: active
                          ? _settingsAccentForeground(context)
                          : context.appPalette.primaryText,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: active
                              ? _settingsAccentForeground(context)
                              : context.appPalette.primaryText,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 19,
                      color: active
                          ? _settingsAccentForeground(context)
                          : context.appPalette.primaryText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? _settingsAccentForeground(context)
                            : context.appPalette.primaryText,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        if (compact) {
          return SizedBox(
            height: 58,
            child: Row(
              children: [
                for (final area in _SettingsArea.values) ...[
                  if (area != _SettingsArea.values.first)
                    const SizedBox(width: 5),
                  Expanded(child: tab(area, compact: true)),
                ],
              ],
            ),
          );
        }
        return SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            itemCount: _SettingsArea.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) =>
                tab(_SettingsArea.values[index], compact: false),
          ),
        );
      },
    );
  }
}

class _SettingsOption<T> {
  const _SettingsOption({
    required this.value,
    required this.label,
    required this.detail,
  });

  final T value;
  final String label;
  final String detail;
}

class _SettingsSelection<T> extends StatelessWidget {
  const _SettingsSelection({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.focusNode,
  });

  final String label;
  final T value;
  final List<_SettingsOption<T>> options;
  final ValueChanged<T> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere((option) => option.value == value);
    return TvFocusable(
      focusNode: focusNode,
      onPressed: () async {
        final result = await showDialog<T>(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: context.appPalette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.appPalette.accent.withValues(alpha: .7),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .78,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final option = options[index];
                          return TvFocusable(
                            autofocus: option.value == value,
                            onPressed: () =>
                                Navigator.of(context).pop(option.value),
                            borderRadius: BorderRadius.circular(9),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: option.value == value
                                    ? context.appPalette.accent.withValues(
                                        alpha: .28,
                                      )
                                    : context.appPalette.surfaceRaised,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.value == value
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: option.value == value
                                        ? context.appPalette.accentBright
                                        : context.appPalette.mutedText,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option.label,
                                          style: TextStyle(
                                            color: _settingsPrimaryText(
                                              context,
                                            ),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          option.detail,
                                          style: TextStyle(
                                            color: context.appPalette.mutedText,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (result != null) onSelected(result);
      },
      borderRadius: BorderRadius.circular(10),
      focusScale: 1.01,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.appPalette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _settingsBorderColor(context, .1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final value = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected.label,
                  style: TextStyle(
                    color: _settingsPrimaryText(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  selected.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appPalette.mutedText,
                    fontSize: 10,
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 560) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: context.appPalette.mutedText,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        value,
                      ],
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    color: context.appPalette.accentBright,
                  ),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.appPalette.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(child: value),
                const SizedBox(width: 12),
                Icon(
                  Icons.expand_more_rounded,
                  color: context.appPalette.accentBright,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CustomizationPanel extends StatelessWidget {
  const _CustomizationPanel({
    required this.preferences,
    required this.controller,
    required this.firstFocusNode,
    required this.onOpenThemeStudio,
    required this.onReset,
  });

  final SettingsPreferences preferences;
  final SettingsPreferencesController controller;
  final FocusNode firstFocusNode;
  final VoidCallback onOpenThemeStudio;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    Widget toggle({
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
      FocusNode? focusNode,
    }) => _PreferenceChip(
      label: '$label ${value ? 'ON' : 'OFF'}',
      selected: value,
      focusNode: focusNode,
      onPressed: () => onChanged(!value),
    );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MiniSectionLabel('DISPLAY'),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: 'Open Theme Studio',
              icon: Icons.palette_rounded,
              focusNode: firstFocusNode,
              onPressed: onOpenThemeStudio,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsSelection<InterfaceMode>(
            label: 'Screen layout',
            value: preferences.interfaceMode,
            options: [
              for (final mode in InterfaceMode.values)
                _SettingsOption(
                  value: mode,
                  label: mode.displayName,
                  detail: mode.description,
                ),
            ],
            onSelected: controller.setInterfaceMode,
          ),
          _PreferenceRow(
            label: 'Interface scale',
            children: [
              for (final option in const [
                (.8, '80%'),
                (.9, '90%'),
                (1.0, '100%'),
                (1.1, '110%'),
                (1.2, '120%'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.interfaceScale == option.$1,
                  onPressed: () => controller.setInterfaceScale(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Content density',
            children: [
              for (final density in ContentDensity.values)
                _PreferenceChip(
                  label: density.displayName,
                  selected: preferences.contentDensity == density,
                  onPressed: () => controller.setContentDensity(density),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Thumbnail size',
            children: [
              for (final option in const [
                (.85, 'Small'),
                (1.0, 'Medium'),
                (1.15, 'Large'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.thumbnailScale == option.$1,
                  onPressed: () => controller.setThumbnailScale(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Layout style',
            children: [
              for (final layout in HomeLayout.values)
                _PreferenceChip(
                  label: layout.displayName,
                  selected: preferences.homeLayout == layout,
                  onPressed: () => controller.setHomeLayout(layout),
                ),
            ],
          ),
          const _PreferenceDivider(),
          const _MiniSectionLabel('HOME & NAVIGATION'),
          const SizedBox(height: 6),
          _SettingsSelection<LandingPage>(
            label: 'Default landing page',
            value: preferences.defaultLandingPage,
            options: [
              for (final page in LandingPage.values.where(
                (page) => switch (page) {
                  LandingPage.home => true,
                  LandingPage.search => preferences.showSearch,
                  LandingPage.myList => preferences.showMyList,
                  LandingPage.discover => preferences.showDiscover,
                  LandingPage.calendar => preferences.showCalendar,
                },
              ))
                _SettingsOption(
                  value: page,
                  label: page.displayName,
                  detail: page.route,
                ),
            ],
            onSelected: controller.setDefaultLandingPage,
          ),
          _PreferenceRow(
            label: 'Home content',
            children: [
              toggle(
                label: 'Featured',
                value: preferences.showHero,
                onChanged: controller.setShowHero,
              ),
              toggle(
                label: 'Poster badges',
                value: preferences.showPosterMetadata,
                onChanged: controller.setShowPosterMetadata,
              ),
              toggle(
                label: 'Card details',
                value: preferences.showCardSubtitles,
                onChanged: controller.setShowCardSubtitles,
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Visible shortcuts',
            children: [
              toggle(
                label: 'Search',
                value: preferences.showSearch,
                onChanged: controller.setShowSearch,
              ),
              toggle(
                label: 'My List',
                value: preferences.showMyList,
                onChanged: controller.setShowMyList,
              ),
              toggle(
                label: 'Discover',
                value: preferences.showDiscover,
                onChanged: controller.setShowDiscover,
              ),
              toggle(
                label: 'Calendar',
                value: preferences.showCalendar,
                onChanged: controller.setShowCalendar,
              ),
            ],
          ),
          const _PreferenceDivider(),
          const _MiniSectionLabel('INPUT & FEEDBACK'),
          _PreferenceRow(
            label: 'On-screen keyboard',
            children: [
              _PreferenceChip(
                label: 'Built-in',
                selected: preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(true),
              ),
              _PreferenceChip(
                label: 'Device keyboard',
                selected: !preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(false),
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Interface sounds',
            children: [
              toggle(
                label: 'Navigation',
                value: preferences.navigationSounds,
                onChanged: controller.setNavigationSounds,
              ),
              toggle(
                label: 'Click',
                value: preferences.clickSounds,
                onChanged: controller.setClickSounds,
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Community activity',
            children: [
              toggle(
                label: 'Anonymous live count',
                value: preferences.anonymousUsageCountEnabled,
                onChanged: controller.setAnonymousUsageCountEnabled,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Shares only whether this app session is active or playing. '
              'TetoTV never sends the show, episode, account, device ID, '
              'stream provider, or URL.',
              style: TextStyle(
                color: context.appPalette.mutedText,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
          _PreferenceRow(
            label: 'Privacy diagnostics',
            children: [
              toggle(
                label: 'Anonymous error reports',
                value: preferences.anonymousCrashReportingEnabled,
                onChanged: controller.setAnonymousCrashReportingEnabled,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Off by default. Sends only the app/build, error type and time, '
              'Android version, CPU architecture, device class, and a '
              'redacted technical trace. No show, episode, '
              'account, device ID, source, or URL is sent.',
              style: TextStyle(
                color: context.appPalette.mutedText,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
          const _PreferenceDivider(),
          const _MiniSectionLabel('CLOSED CAPTIONS'),
          _PreferenceRow(
            label: 'Text color',
            children: [
              for (final option in const [
                (0xFFFFFFFF, 'White'),
                (0xFFFFFF66, 'Yellow'),
                (0xFF66E7FF, 'Cyan'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.captionTextColor == option.$1,
                  swatch: Color(option.$1),
                  onPressed: () => controller.setCaptionTextColor(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Background',
            children: [
              for (final option in const [
                (0x00000000, 'Off'),
                (0x99000000, 'Dark'),
                (0xDD000000, 'Strong'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.captionBackgroundColor == option.$1,
                  swatch: Color(option.$1),
                  onPressed: () =>
                      controller.setCaptionBackgroundColor(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Text size',
            children: [
              for (final size in const [28.0, 34.0, 42.0, 50.0])
                _PreferenceChip(
                  label: '${size.round()}',
                  selected: preferences.captionTextSize == size,
                  onPressed: () => controller.setCaptionTextSize(size),
                ),
            ],
          ),
          const _PreferenceDivider(),
          const _MiniSectionLabel('PLAYER CONTROLS'),
          _SettingsSelection<PreferredPlayer>(
            label: 'Preferred player',
            value: preferences.preferredPlayer,
            options: [
              for (final player in PreferredPlayer.values)
                _SettingsOption(
                  value: player,
                  label: player.displayName,
                  detail: player.description,
                ),
            ],
            onSelected: controller.setPreferredPlayer,
          ),
          const SizedBox(height: 8),
          _SettingsSelection<PlaybackAudioPreference>(
            label: 'Preferred audio',
            value: preferences.preferredAudio,
            options: [
              for (final preference in PlaybackAudioPreference.values)
                _SettingsOption(
                  value: preference,
                  label: preference.displayName,
                  detail: preference.description,
                ),
            ],
            onSelected: controller.setPreferredAudio,
          ),
          const SizedBox(height: 8),
          _PreferenceRow(
            label: 'Rewind',
            children: [
              for (final seconds in const [5, 10, 15, 30, 60])
                _PreferenceChip(
                  label: '${seconds}s',
                  selected: preferences.seekBackSeconds == seconds,
                  onPressed: () => controller.setSeekBackSeconds(seconds),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Fast-forward',
            children: [
              for (final seconds in const [5, 10, 15, 30, 60])
                _PreferenceChip(
                  label: '${seconds}s',
                  selected: preferences.seekForwardSeconds == seconds,
                  onPressed: () => controller.setSeekForwardSeconds(seconds),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Automatic skipping',
            children: [
              toggle(
                label: 'Intros',
                value: preferences.autoSkipIntros,
                onChanged: controller.setAutoSkipIntros,
              ),
              toggle(
                label: 'Outros',
                value: preferences.autoSkipOutros,
                onChanged: controller.setAutoSkipOutros,
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Episode information',
            children: [
              toggle(
                label: 'Show filler episode labels',
                value: preferences.showFillerIndicators,
                onChanged: controller.setShowFillerIndicators,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: 'Reset appearance & navigation',
              icon: Icons.restart_alt_rounded,
              onPressed: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSectionLabel extends StatelessWidget {
  const _MiniSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.appPalette.accentBright,
      fontSize: 9,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.1,
    ),
  );
}

class _PreferenceDivider extends StatelessWidget {
  const _PreferenceDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(color: _settingsBorderColor(context, .07), height: 1),
  );
}

class _StreamingSourcesPanel extends StatelessWidget {
  const _StreamingSourcesPanel({
    required this.preferences,
    required this.debridFocusNode,
    required this.webFocusNode,
    required this.marketplaceFocusNode,
    required this.onDebridChanged,
    required this.onWebChanged,
    required this.onMarketplace,
  });

  final SettingsPreferences preferences;
  final FocusNode debridFocusNode;
  final FocusNode webFocusNode;
  final FocusNode marketplaceFocusNode;
  final ValueChanged<bool> onDebridChanged;
  final ValueChanged<bool> onWebChanged;
  final VoidCallback onMarketplace;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _settingsBorderColor(context, .07)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sources = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreferenceChip(
                label:
                    'DEBRID ${preferences.debridStreamsEnabled ? 'ON' : 'OFF'}',
                selected: preferences.debridStreamsEnabled,
                focusNode: debridFocusNode,
                onPressed: () =>
                    onDebridChanged(!preferences.debridStreamsEnabled),
              ),
              _PreferenceChip(
                label: 'WEB ${preferences.webStreamsEnabled ? 'ON' : 'OFF'}',
                selected: preferences.webStreamsEnabled,
                focusNode: webFocusNode,
                onPressed: () => onWebChanged(!preferences.webStreamsEnabled),
              ),
            ],
          );
          final marketplace = _TvTextButton(
            label: 'Manage sources',
            icon: Icons.hub_rounded,
            focusNode: marketplaceFocusNode,
            onPressed: onMarketplace,
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [sources, const SizedBox(height: 10), marketplace],
            );
          }
          return Row(
            children: [
              Expanded(child: sources),
              marketplace,
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final options = Wrap(spacing: 7, runSpacing: 7, children: children);
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.appPalette.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                options,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 180,
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.appPalette.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(child: options),
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.swatch,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected
              ? context.appPalette.accent
              : context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? context.appPalette.accentBright
                : _settingsBorderColor(context, .1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatch case final color?) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: _settingsBorderColor(context, .54)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? _settingsAccentForeground(context)
                    : _settingsPrimaryText(context),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeveloperUpdatePanel extends StatelessWidget {
  const _DeveloperUpdatePanel({
    required this.state,
    required this.channelFocusNode,
    required this.releaseHistoryFocusNode,
    required this.onChannelSelected,
    required this.onRefreshHistory,
    required this.onReleaseSelected,
  });

  final AppUpdateState state;
  final FocusNode channelFocusNode;
  final FocusNode releaseHistoryFocusNode;
  final ValueChanged<AppUpdateChannel> onChannelSelected;
  final VoidCallback onRefreshHistory;
  final ValueChanged<AppReleaseInfo> onReleaseSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeAppVersion(state.currentVersion);
    final versionParts = normalized.split('+');
    final versionName = versionParts.first;
    final buildNumber = versionParts.length > 1
        ? versionParts.sublist(1).join('+')
        : 'Not reported';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.developer_mode_rounded,
                color: context.appPalette.accentBright,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer mode',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Preview builds may be less stable than public releases.',
                      style: TextStyle(
                        color: context.appPalette.mutedText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const _StatusPill(connected: true, label: 'ENABLED'),
            ],
          ),
          const SizedBox(height: 10),
          _SettingsSelection<AppUpdateChannel>(
            label: 'Update channel',
            value: state.updateChannel,
            focusNode: channelFocusNode,
            options: [
              for (final channel in AppUpdateChannel.values)
                _SettingsOption(
                  value: channel,
                  label: channel.displayName,
                  detail: channel.description,
                ),
            ],
            onSelected: onChannelSelected,
          ),
          const SizedBox(height: 10),
          Divider(color: _settingsBorderColor(context, .08), height: 1),
          const SizedBox(height: 10),
          if (state.releaseHistory.isNotEmpty)
            _SettingsSelection<AppReleaseInfo>(
              label: 'Choose a release to install',
              value: state.releaseHistory.first,
              focusNode: releaseHistoryFocusNode,
              options: [
                for (final release in state.releaseHistory)
                  _SettingsOption(
                    value: release,
                    label: state.updateChannel.versionLabel(release.version),
                    detail:
                        normalizeAppVersion(
                              state.currentVersion,
                            ).split('+').first ==
                            release.version
                        ? 'Currently installed'
                        : compareAppVersions(
                                release.version,
                                state.currentVersion,
                              ) <
                              0
                        ? 'Previous release • compatibility checked before install'
                        : 'Newer release • compatibility checked before install',
                  ),
              ],
              onSelected: onReleaseSelected,
            )
          else
            _TvTextButton(
              key: const ValueKey('release-history-refresh'),
              label: state.releaseHistoryLoading
                  ? 'Loading releases…'
                  : 'Load release history',
              icon: Icons.history_rounded,
              focusNode: releaseHistoryFocusNode,
              onPressed: state.isBusy || state.releaseHistoryLoading
                  ? null
                  : onRefreshHistory,
            ),
          const SizedBox(height: 7),
          Text(
            'Previous versions are available only when their signed APK is '
            'package-compatible with this installation. Android will reject '
            'a lower build code, wrong signer, unsupported ABI, or newer SDK requirement.',
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Text(
                'Installed version: $versionName',
                style: TextStyle(
                  color: context.appPalette.primaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Build: $buildNumber',
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 11,
                ),
              ),
              if (state.latestVersion case final latest?)
                Text(
                  'Latest ${state.updateChannel.displayName}: '
                  '${state.updateChannel.versionLabel(latest)}',
                  style: TextStyle(
                    color: context.appPalette.mutedText,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppUpdatePanel extends StatelessWidget {
  const _AppUpdatePanel({
    required this.state,
    required this.automaticFocusNode,
    required this.checkFocusNode,
    required this.onToggleAutomatic,
    required this.onCheckOrInstall,
  });

  final AppUpdateState state;
  final FocusNode automaticFocusNode;
  final FocusNode checkFocusNode;
  final VoidCallback onToggleAutomatic;
  final VoidCallback onCheckOrInstall;

  @override
  Widget build(BuildContext context) {
    final latest = state.latestVersion;
    final status =
        state.message ??
        'Current ${state.currentVersion}'
            '${latest == null ? '' : ' • Latest $latest'}';
    final checkLabel = switch (state.phase) {
      AppUpdatePhase.checking => 'Checking…',
      AppUpdatePhase.downloading =>
        'Downloading ${(state.progress * 100).round()}%',
      AppUpdatePhase.installing => 'Opening installer…',
      AppUpdatePhase.ready => 'Install update',
      _ => 'Check for updates',
    };
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.appPalette.accent.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  color: context.appPalette.accentBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'TetoTV ${state.currentVersion}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        _StatusPill(
                          connected: true,
                          label: 'SECURE UPDATES READY',
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Signed releases download securely from the official '
                      'TetoTV repository.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: state.phase == AppUpdatePhase.error
                  ? const Color(0xFFFF929B)
                  : context.appPalette.mutedText,
              fontSize: 10,
            ),
          ),
          if (state.release?.notes.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _settingsPageBackground(context).withValues(alpha: .35),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _settingsBorderColor(context, .07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHAT’S NEW',
                    style: TextStyle(
                      color: context.appPalette.accentBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.release!.notes.trim(),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            key: const ValueKey('app-update-actions'),
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _TvTextButton(
                  label: state.automaticUpdates
                      ? 'Automatic: ON'
                      : 'Automatic: OFF',
                  icon: state.automaticUpdates
                      ? Icons.autorenew_rounded
                      : Icons.update_disabled_rounded,
                  onPressed: state.isBusy ? null : onToggleAutomatic,
                  focusNode: automaticFocusNode,
                ),
                _TvTextButton(
                  label: checkLabel,
                  icon: state.downloadedPath == null
                      ? Icons.refresh_rounded
                      : Icons.install_mobile_rounded,
                  onPressed: state.isBusy ? null : onCheckOrInstall,
                  focusNode: checkFocusNode,
                ),
              ],
            ),
          ),
          if (state.phase == AppUpdatePhase.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              color: context.appPalette.accentBright,
              backgroundColor: const Color(0xFF2A2A2A),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeShelfOrganizer extends StatelessWidget {
  const _HomeShelfOrganizer({
    required this.order,
    required this.enabled,
    required this.focusNodes,
    required this.onToggle,
    required this.onMove,
  });

  final List<HomeShelf> order;
  final Set<HomeShelf> enabled;
  final Map<HomeShelf, FocusNode> focusNodes;
  final ValueChanged<HomeShelf> onToggle;
  final void Function(HomeShelf shelf, int offset) onMove;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MiniSectionLabel('HOME SHELVES'),
          const SizedBox(height: 3),
          Text(
            'Choose what appears on Home and move favorites toward the top.',
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < order.length; index++) ...[
            _HomeShelfRow(
              index: index,
              total: order.length,
              shelf: order[index],
              enabled: enabled.contains(order[index]),
              focusNode: focusNodes[order[index]]!,
              onToggle: () => onToggle(order[index]),
              onMoveUp: () => onMove(order[index], -1),
              onMoveDown: () => onMove(order[index], 1),
            ),
            if (index != order.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _HomeShelfRow extends StatelessWidget {
  const _HomeShelfRow({
    required this.index,
    required this.total,
    required this.shelf,
    required this.enabled,
    required this.focusNode,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final int total;
  final HomeShelf shelf;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appPalette.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TvFocusable(
            focusNode: focusNode,
            onPressed: onToggle,
            focusScale: 1.01,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: enabled
                    ? context.appPalette.accent.withValues(alpha: .28)
                    : context.appPalette.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: enabled
                      ? context.appPalette.accentBright.withValues(alpha: .7)
                      : _settingsBorderColor(context, .08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    enabled
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 17,
                    color: enabled
                        ? _settingsPrimaryText(context)
                        : context.appPalette.mutedText,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      shelf.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? _settingsPrimaryText(context)
                            : context.appPalette.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    enabled ? 'SHOWN' : 'HIDDEN',
                    style: TextStyle(
                      color: enabled
                          ? context.appPalette.accentBright
                          : context.appPalette.mutedText,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        _ShelfOrderButton(
          icon: Icons.keyboard_arrow_up_rounded,
          label: 'Move ${shelf.displayName} up',
          onPressed: index == 0 ? null : onMoveUp,
        ),
        const SizedBox(width: 5),
        _ShelfOrderButton(
          icon: Icons.keyboard_arrow_down_rounded,
          label: 'Move ${shelf.displayName} down',
          onPressed: index == total - 1 ? null : onMoveDown,
        ),
      ],
    );
  }
}

class _ShelfOrderButton extends StatelessWidget {
  const _ShelfOrderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, color: _settingsBorderColor(context, .24), size: 19),
      );
    }
    return Semantics(
      label: label,
      button: true,
      child: TvFocusable(
        onPressed: onPressed!,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.appPalette.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 19),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.appPalette.accentBright),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _settingsPrimaryText(context),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
    if (MediaQuery.sizeOf(context).width < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 23),
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appPalette.mutedText,
                fontSize: 10,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        heading,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _LegalNoticesPanel extends StatelessWidget {
  const _LegalNoticesPanel({
    required this.privacyFocusNode,
    required this.licenseFocusNode,
  });

  final FocusNode privacyFocusNode;
  final FocusNode licenseFocusNode;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const notice =
              'TetoTV is an independent, unofficial client. It is not '
              'affiliated with or endorsed by AniList, MAL, debrid '
              'services, addon authors, or media rights holders. Users add '
              'and are responsible for their own services and repositories.';
          const attribution = '重音テト © 線 / 小山乃舞世 / TWINDRILL';
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice,
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 7),
              Text(
                attribution,
                style: TextStyle(
                  color: _settingsPrimaryText(context),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Development disclosure: TetoTV includes code created and '
                'reviewed with AI-assisted development tools. Releases are '
                'tested and maintained by the project owner.',
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _TvTextButton(
                label: 'Privacy & data',
                icon: Icons.privacy_tip_rounded,
                focusNode: privacyFocusNode,
                onPressed: () => context.push('/settings/privacy'),
              ),
              _TvTextButton(
                label: 'Third-party notices',
                icon: Icons.description_rounded,
                focusNode: licenseFocusNode,
                onPressed: () => context.push('/settings/notices'),
              ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 18),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _DiscordCommunityPanel extends StatelessWidget {
  const _DiscordCommunityPanel({
    required this.qrFocusNode,
    required this.focusNode,
  });

  static const inviteUrl = 'https://discord.gg/juC6k7d4WY';
  final FocusNode qrFocusNode;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final qr = CopyableQrInteraction(
      data: inviteUrl,
      semanticsLabel: 'QR code for the TetoTV Discord invite',
      confirmationMessage: 'Discord invite copied.',
      focusNode: qrFocusNode,
      child: Container(
        width: 132,
        height: 132,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: inviteUrl,
          version: QrVersions.auto,
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Join the TetoTV Discord',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 5),
        Text(
          'Scan the code with your phone, or select the invite below to copy it.',
          style: TextStyle(color: context.appPalette.mutedText, fontSize: 11),
        ),
        const SizedBox(height: 10),
        TvFocusable(
          focusNode: focusNode,
          borderRadius: BorderRadius.circular(10),
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: inviteUrl));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Discord invite copied.')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            color: context.appPalette.selectableSurface,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: context.appPalette.accentBright,
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    inviteUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                qr,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: copy),
              ],
            );
          }
          return Row(
            children: [
              qr,
              const SizedBox(width: 18),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _DiscordPresencePanel extends StatelessWidget {
  const _DiscordPresencePanel({
    required this.state,
    required this.primaryFocusNode,
    required this.unlinkFocusNode,
    required this.onLink,
    required this.onToggle,
    required this.onRetry,
    required this.onUnlink,
  });

  final DiscordPresenceState state;
  final FocusNode primaryFocusNode;
  final FocusNode unlinkFocusNode;
  final VoidCallback onLink;
  final VoidCallback onToggle;
  final VoidCallback onRetry;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final statusLabel = !state.loaded
        ? 'CHECKING'
        : !state.available
        ? 'UNAVAILABLE'
        : !state.linked
        ? 'NOT LINKED'
        : state.connected
        ? 'CONNECTED'
        : state.enabled
        ? state.connectionStatus.toUpperCase()
        : 'DISABLED';
    final primaryLabel = !state.loaded
        ? 'Checking Discord'
        : !state.available
        ? 'Unavailable on this device'
        : !state.linked
        ? 'Connect Discord'
        : state.enabled && !state.connected
        ? 'Retry connection'
        : state.enabled
        ? 'Disable Rich Presence'
        : 'Enable Rich Presence';
    final primaryIcon = !state.linked
        ? Icons.login_rounded
        : state.enabled && state.connected
        ? Icons.visibility_off_rounded
        : Icons.sensors_rounded;
    final VoidCallback? primaryAction = state.busy || !state.available
        ? null
        : !state.linked
        ? onLink
        : state.enabled && !state.connected
        ? onRetry
        : onToggle;

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sports_esports_rounded,
              color: Color(0xFFB7BCFF),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Discord Rich Presence',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _StatusPill(connected: state.connected, label: statusLabel),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Optional. When enabled, Discord can show the anime title, episode, '
          'playing or paused state, and playback timer. TetoTV never asks for '
          'or stores your Discord password.',
          style: TextStyle(color: context.appPalette.mutedText, fontSize: 11),
        ),
        if (state.error case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(color: Color(0xFFFF929B), fontSize: 11),
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _TvTextButton(
          label: state.busy ? 'Please wait…' : primaryLabel,
          icon: primaryIcon,
          focusNode: primaryFocusNode,
          onPressed: primaryAction,
        ),
        if (state.linked)
          _TvTextButton(
            label: 'Unlink Discord',
            icon: Icons.link_off_rounded,
            focusNode: unlinkFocusNode,
            onPressed: state.busy ? null : onUnlink,
          ),
      ],
    );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          copy,
          const SizedBox(height: 12),
          Align(
            key: const ValueKey('discord-presence-actions'),
            alignment: Alignment.centerRight,
            child: actions,
          ),
        ],
      ),
    );
  }
}

class _DonationPanel extends StatelessWidget {
  const _DonationPanel({required this.qrFocusNode, required this.focusNode});

  static const donationUrl = 'https://ko-fi.com/lindowsosx';
  final FocusNode qrFocusNode;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final qr = CopyableQrInteraction(
      data: donationUrl,
      semanticsLabel: 'QR code for the TetoTV Ko-fi donation page',
      confirmationMessage: 'Ko-fi donation link copied.',
      focusNode: qrFocusNode,
      child: Container(
        width: 132,
        height: 132,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: donationUrl,
          version: QrVersions.auto,
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Support TetoTV', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(
          'Donations are optional. Scan with your phone to open the official '
          'TetoTV Ko-fi page, or select the link below to copy it.',
          style: TextStyle(color: context.appPalette.mutedText, fontSize: 11),
        ),
        const SizedBox(height: 10),
        TvFocusable(
          focusNode: focusNode,
          borderRadius: BorderRadius.circular(10),
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: donationUrl));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ko-fi donation link copied.')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            color: context.appPalette.selectableSurface,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.volunteer_activism_rounded,
                  size: 18,
                  color: context.appPalette.accentBright,
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    donationUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                qr,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: copy),
              ],
            );
          }
          return Row(
            children: [
              qr,
              const SizedBox(width: 18),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceAccountHeader extends StatelessWidget {
  const _ServiceAccountHeader({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.status,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final List<Color> gradient;
  final String title;
  final Widget status;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: context.appPalette.background, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  status,
                ],
              ),
              const SizedBox(height: 3),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            const SizedBox(width: 12),
            action,
          ],
        );
      },
    );
  }
}

class _RealDebridPanel extends StatelessWidget {
  const _RealDebridPanel({
    required this.state,
    required this.onDisconnect,
    required this.onDeviceConnect,
    required this.connectFocusNode,
  });

  final RealDebridSettingsState state;
  final VoidCallback onDisconnect;
  final VoidCallback onDeviceConnect;
  final FocusNode connectFocusNode;

  @override
  Widget build(BuildContext context) {
    final account = state.account;
    return _Panel(
      child: Column(
        children: [
          _ServiceAccountHeader(
            icon: Icons.cloud_download_rounded,
            gradient: [
              context.appPalette.accent,
              context.appPalette.secondaryAccent,
            ],
            title: 'Real-Debrid',
            status: _StatusPill(
              connected: account != null,
              label: account == null
                  ? state.hasSavedToken
                        ? 'RECONNECTING'
                        : 'NOT CONNECTED'
                  : account.isPremium
                  ? 'PREMIUM'
                  : account.type.toUpperCase(),
            ),
            description: account == null
                ? 'Authorize securely with Real-Debrid on your phone or computer.'
                : 'Connected as ${account.username}. Cached torrents will '
                      'resolve almost instantly.',
            action: account == null
                ? _TvTextButton(
                    label: 'Connect by QR',
                    icon: Icons.qr_code_rounded,
                    onPressed: onDeviceConnect,
                    focusNode: connectFocusNode,
                  )
                : _TvTextButton(
                    label: 'Disconnect',
                    icon: Icons.link_off_rounded,
                    onPressed: onDisconnect,
                    focusNode: connectFocusNode,
                  ),
          ),
          if (state.errorMessage case final error?) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFFF929B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TorBoxPanel extends StatelessWidget {
  const _TorBoxPanel({
    required this.state,
    required this.tokenController,
    required this.onSave,
    required this.onDisconnect,
    required this.onDeviceConnect,
    required this.actionFocusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
  });

  final TorBoxSettingsState state;
  final TextEditingController tokenController;
  final VoidCallback onSave;
  final VoidCallback onDisconnect;
  final VoidCallback onDeviceConnect;
  final FocusNode actionFocusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;

  @override
  Widget build(BuildContext context) {
    final account = state.account;
    return _Panel(
      child: Column(
        children: [
          _ServiceAccountHeader(
            icon: Icons.cloud_circle_rounded,
            gradient: [
              context.appPalette.accent,
              context.appPalette.accentBright,
            ],
            title: 'TorBox',
            status: _StatusPill(
              connected: account != null,
              label: account == null
                  ? state.hasSavedToken
                        ? 'RECONNECTING'
                        : 'NOT CONNECTED'
                  : account.planName.toUpperCase(),
            ),
            description: account == null
                ? 'Authorize with a QR code, or enter a TorBox API token below.'
                : 'Connected as ${account.email}. Torrent files are resolved '
                      'and streamed through TorBox only.',
            action: account == null
                ? _TvTextButton(
                    label: 'Connect by QR',
                    icon: Icons.qr_code_rounded,
                    onPressed: onDeviceConnect,
                    focusNode: actionFocusNode,
                  )
                : _TvTextButton(
                    label: 'Disconnect',
                    icon: Icons.link_off_rounded,
                    onPressed: onDisconnect,
                    focusNode: actionFocusNode,
                  ),
          ),
          if (state.errorMessage case final error?) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFFF929B)),
              ),
            ),
          ],
          if (account == null) ...[
            const SizedBox(height: 10),
            Divider(color: _settingsBorderColor(context, .08), height: 1),
            const SizedBox(height: 10),
            _ResponsiveTokenRow(
              title: 'TorBox API token',
              input: TvTextInput(
                focusNode: tokenFocusNode,
                controller: tokenController,
                labelText: 'Personal API token',
                hintText: 'Select to open the TV keyboard',
                keyboardTitle: 'Enter TorBox token',
                obscureText: true,
                onSubmitted: (_) => onSave(),
              ),
              action: _TvTextButton(
                label: state.isLoading ? 'Checking…' : 'Save & verify',
                icon: state.isLoading
                    ? Icons.sync_rounded
                    : Icons.verified_user_rounded,
                onPressed: state.isLoading ? null : onSave,
                focusNode: saveFocusNode,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApiKeyDebridPanel extends StatelessWidget {
  const _ApiKeyDebridPanel({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.connected,
    required this.hasSavedToken,
    required this.connectedLabel,
    required this.description,
    required this.isLoading,
    required this.tokenController,
    required this.tokenTitle,
    required this.keyboardTitle,
    required this.connectLabel,
    required this.connectIcon,
    required this.onSave,
    required this.onDisconnect,
    required this.onConnect,
    required this.actionFocusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
    this.errorMessage,
  });

  final String title;
  final IconData icon;
  final List<Color> gradient;
  final bool connected;
  final bool hasSavedToken;
  final String connectedLabel;
  final String description;
  final String? errorMessage;
  final bool isLoading;
  final TextEditingController tokenController;
  final String tokenTitle;
  final String keyboardTitle;
  final String connectLabel;
  final IconData connectIcon;
  final VoidCallback onSave;
  final VoidCallback onDisconnect;
  final VoidCallback onConnect;
  final FocusNode actionFocusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: [
        _ServiceAccountHeader(
          icon: icon,
          gradient: gradient,
          title: title,
          status: _StatusPill(
            connected: connected,
            label: connected
                ? connectedLabel
                : hasSavedToken
                ? 'RECONNECTING'
                : 'NOT CONNECTED',
          ),
          description: description,
          action: _TvTextButton(
            label: connected ? 'Disconnect' : connectLabel,
            icon: connected ? Icons.link_off_rounded : connectIcon,
            onPressed: connected ? onDisconnect : onConnect,
            focusNode: actionFocusNode,
          ),
        ),
        if (errorMessage case final error?) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              error,
              style: const TextStyle(color: Color(0xFFFF929B)),
            ),
          ),
        ],
        if (!connected) ...[
          const SizedBox(height: 10),
          Divider(color: _settingsBorderColor(context, .08), height: 1),
          const SizedBox(height: 10),
          _ResponsiveTokenRow(
            title: tokenTitle,
            input: TvTextInput(
              focusNode: tokenFocusNode,
              controller: tokenController,
              labelText: 'Personal API key',
              hintText: 'Select to open the TV keyboard',
              keyboardTitle: keyboardTitle,
              obscureText: true,
              onSubmitted: (_) => onSave(),
            ),
            action: _TvTextButton(
              label: isLoading ? 'Checking…' : 'Save & verify',
              icon: isLoading
                  ? Icons.sync_rounded
                  : Icons.verified_user_rounded,
              onPressed: isLoading ? null : onSave,
              focusNode: saveFocusNode,
            ),
          ),
        ],
      ],
    ),
  );
}

class _TrackingPanel extends StatefulWidget {
  const _TrackingPanel({
    required this.provider,
    required this.color,
    required this.description,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSaveToken,
    required this.focusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
    required this.isLoading,
    this.username,
    this.error,
  });

  final TrackingProvider provider;
  final Color color;
  final String description;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function(String) onSaveToken;
  final FocusNode focusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;
  final bool isLoading;
  final String? username;
  final String? error;

  @override
  State<_TrackingPanel> createState() => _TrackingPanelState();
}

class _TrackingPanelState extends State<_TrackingPanel> {
  final _tokenController = TextEditingController();
  String? _inputError;
  bool _saving = false;

  Future<void> _saveToken([String? submitted]) async {
    final token = (submitted ?? _tokenController.text).trim();
    if (token.isEmpty) {
      setState(() => _inputError = 'Enter a token before saving.');
      return;
    }
    setState(() {
      _inputError = null;
      _saving = true;
    });
    try {
      await widget.onSaveToken(token);
      if (mounted && widget.error == null) _tokenController.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.playlist_add_check_rounded,
                  color: widget.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.provider.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                connected: widget.username != null,
                label: widget.username != null ? 'CONNECTED' : 'NOT CONNECTED',
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            widget.username == null
                ? widget.description
                : 'Connected as ${widget.username}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: widget.username != null ? 'Disconnect' : 'Connect by QR',
              icon: widget.username == null
                  ? Icons.qr_code_rounded
                  : Icons.link_off_rounded,
              onPressed: widget.username == null
                  ? widget.onConnect
                  : widget.onDisconnect,
              focusNode: widget.focusNode,
            ),
          ),
          if (widget.username == null) ...[
            const SizedBox(height: 8),
            Divider(color: _settingsBorderColor(context, .08), height: 1),
            const SizedBox(height: 8),
            _ResponsiveTokenRow(
              title: 'Manual API token',
              input: TvTextInput(
                controller: _tokenController,
                focusNode: widget.tokenFocusNode,
                labelText: 'Personal Access Token',
                hintText: 'Select to open the TV keyboard',
                keyboardTitle: 'Enter ${widget.provider.displayName} token',
                obscureText: true,
                onSubmitted: _saveToken,
              ),
              action: _TvTextButton(
                label: _saving || widget.isLoading
                    ? 'Checking…'
                    : 'Save & verify',
                icon: Icons.verified_user_rounded,
                focusNode: widget.saveFocusNode,
                onPressed: _saving || widget.isLoading ? null : _saveToken,
              ),
            ),
            if (_inputError ?? widget.error case final message?) ...[
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(color: Color(0xFFFF8DA0))),
            ],
          ],
        ],
      ),
    );
  }
}

class _DebridOnlyPanel extends StatelessWidget {
  const _DebridOnlyPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.appPalette.accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.verified_user_rounded,
              color: context.appPalette.accentBright,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protected streaming paths',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  'Torrents are only played through the debrid service you '
                  'connect. '
                  'Installed web addons run without access to account tokens '
                  'or device files.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.lock_rounded, color: context.appPalette.accentBright),
        ],
      ),
    );
  }
}

class _ResponsiveTokenRow extends StatelessWidget {
  const _ResponsiveTokenRow({
    required this.title,
    required this.input,
    required this.action,
  });

  final String title;
  final Widget input;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldAndAction = constraints.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  input,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              )
            : Row(
                children: [
                  Expanded(child: input),
                  const SizedBox(width: 12),
                  action,
                ],
              );
        if (constraints.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              fieldAndAction,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 210,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(child: fieldAndAction),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _settingsBorderColor(context, .10)),
      ),
      child: child,
    );
  }
}

class _StorageResetPanel extends StatefulWidget {
  const _StorageResetPanel({
    required this.clearCacheFocusNode,
    required this.resetAppFocusNode,
  });

  final FocusNode clearCacheFocusNode;
  final FocusNode resetAppFocusNode;

  @override
  State<_StorageResetPanel> createState() => _StorageResetPanelState();
}

class _StorageResetPanelState extends State<_StorageResetPanel> {
  bool _clearingCache = false;
  bool _resetting = false;

  Future<void> _clearCache() async {
    if (_clearingCache || _resetting) return;
    setState(() => _clearingCache = true);
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      final bytes = await AndroidTvBridge.instance.clearAppCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bytes > 0
                ? 'Cleared ${_formatStorageBytes(bytes)} of temporary files.'
                : 'TetoTV cache is already clear.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'This device could not clear the TetoTV cache.',
          ),
        ),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This device does not support TetoTV cache cleanup.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_clearingCache || _resetting) return;
    final firstConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ResetWarningDialog(),
    );
    if (firstConfirmed != true || !mounted) return;
    final finalConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ResetFinalDialog(),
    );
    if (finalConfirmed != true || !mounted) return;
    setState(() => _resetting = true);
    try {
      await AndroidTvBridge.instance.resetApplicationData();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'This device could not reset TetoTV.'),
        ),
      );
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This device does not support resetting TetoTV.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final clear = _StorageAction(
            key: const ValueKey('storage-clear-cache'),
            focusNode: widget.clearCacheFocusNode,
            icon: Icons.cleaning_services_rounded,
            title: _clearingCache ? 'Clearing cache…' : 'Clear cache',
            detail:
                'Removes temporary images, playback cache, and downloaded update leftovers. Accounts, settings, history, and sources stay saved.',
            accent: context.appPalette.secondaryAccent,
            enabled: !_clearingCache && !_resetting,
            onPressed: _clearCache,
          );
          final reset = _StorageAction(
            key: const ValueKey('storage-reset-app'),
            focusNode: widget.resetAppFocusNode,
            icon: Icons.delete_forever_rounded,
            title: _resetting ? 'Resetting TetoTV…' : 'Reset TetoTV',
            detail:
                'Erases every account, preference, source, and watch-history item. The app closes and starts at first-time setup.',
            accent: context.appPalette.accentBright,
            enabled: !_clearingCache && !_resetting,
            onPressed: _confirmReset,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [clear, const SizedBox(height: 10), reset],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: clear),
              const SizedBox(width: 10),
              Expanded(child: reset),
            ],
          );
        },
      ),
    );
  }
}

class _StorageAction extends StatelessWidget {
  const _StorageAction({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String detail;
  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: enabled ? onPressed : () {},
      borderRadius: BorderRadius.circular(9),
      focusScale: 1.01,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appPalette.surfaceRaised,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: .45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: enabled ? accent : context.appPalette.mutedText,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? _settingsPrimaryText(context)
                          : context.appPalette.mutedText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: TextStyle(
                      color: context.appPalette.mutedText,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetWarningDialog extends StatelessWidget {
  const _ResetWarningDialog();

  @override
  Widget build(BuildContext context) => _ResetDialogFrame(
    key: const ValueKey('reset-warning-dialog'),
    icon: Icons.warning_amber_rounded,
    title: 'Reset all TetoTV data?',
    message:
        'This erases linked accounts, encrypted credentials, preferences, Marketplace sources, and local watch history. It cannot be undone.',
    actions: [
      _DialogAction(
        key: const ValueKey('reset-warning-cancel'),
        autofocus: true,
        label: 'Keep my data',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      _DialogAction(
        key: const ValueKey('reset-warning-continue'),
        label: 'Continue',
        icon: Icons.warning_rounded,
        dangerous: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

class _ResetFinalDialog extends StatelessWidget {
  const _ResetFinalDialog();

  @override
  Widget build(BuildContext context) => _ResetDialogFrame(
    key: const ValueKey('reset-final-dialog'),
    icon: Icons.delete_forever_rounded,
    title: 'Final confirmation',
    message:
        'TetoTV will close immediately. When you reopen it, first-time setup begins with no saved data.',
    actions: [
      _DialogAction(
        key: const ValueKey('reset-final-cancel'),
        autofocus: true,
        label: 'Cancel reset',
        icon: Icons.close_rounded,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      _DialogAction(
        key: const ValueKey('reset-final-confirm'),
        label: 'Erase everything',
        icon: Icons.delete_forever_rounded,
        dangerous: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}

class _ResetDialogFrame extends StatelessWidget {
  const _ResetDialogFrame({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      width: 620,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appPalette.accentBright, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.appPalette.accentBright, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(message, style: TextStyle(color: context.appPalette.mutedText)),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      if (index > 0) const SizedBox(height: 10),
                      actions[index],
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(child: actions[index]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.dangerous = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool dangerous;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dangerous
            ? context.appPalette.accent
            : context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    ),
  );
}

bool _usesDefaultSettingsPalette(BuildContext context) =>
    context.appPalette == AppThemePalette.defaults;

Color _settingsPageBackground(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? Colors.black
    : context.appPalette.background;

Color _settingsPrimaryText(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? Colors.white
    : context.appPalette.primaryText;

Color _settingsAccentForeground(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? Colors.white
    : contrastForeground(context.appPalette.accent);

Color _settingsTitleToggleSurface(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? const Color(0xFF171717)
    : context.appPalette.surfaceRaised;

Color _settingsDisabledActionSurface(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? const Color(0xFF3A2228)
    : context.appPalette.selectableSurface;

Color _settingsDisabledText(BuildContext context) =>
    _usesDefaultSettingsPalette(context)
    ? Colors.white54
    : context.appPalette.mutedText;

Color _settingsBorderColor(BuildContext context, double opacity) =>
    (_usesDefaultSettingsPalette(context)
            ? Colors.white
            : context.appPalette.primaryText)
        .withValues(alpha: opacity);

String _formatStorageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
  return '${(mib / 1024).toStringAsFixed(1)} GB';
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected, required this.label});

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? const Color(0xFF67D49B)
        : context.appPalette.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _TitleLanguageToggle extends StatelessWidget {
  const _TitleLanguageToggle({
    required this.focusNode,
    required this.preference,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final TitleLanguagePreference preference;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      focusScale: 1.02,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: _settingsTitleToggleSurface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _settingsBorderColor(context, .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate_rounded,
              size: 17,
              color: context.appPalette.accentBright,
            ),
            const SizedBox(width: 7),
            Text(
              'Titles: ${preference.displayName}',
              style: TextStyle(
                color: _settingsPrimaryText(context),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvIconButton extends StatelessWidget {
  const _TvIconButton({
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: context.appPalette.surface,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _TvTextButton extends StatelessWidget {
  const _TvTextButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.focusNode,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return TvFocusable(
      onPressed: onPressed ?? () {},
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: enabled
            ? context.appPalette.accent
            : _settingsDisabledActionSurface(context),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: enabled
                  ? _settingsAccentForeground(context)
                  : _settingsDisabledText(context),
              size: 19,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: enabled
                      ? _settingsAccentForeground(context)
                      : _settingsDisabledText(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
