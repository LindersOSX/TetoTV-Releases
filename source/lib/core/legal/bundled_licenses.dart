import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds notices for code that is compiled into TetoTV assets or an Android
/// AAR, and therefore is not discovered by Flutter's generated Dart-package
/// license registry.
void registerBundledThirdPartyLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  final assets = bundle ?? rootBundle;

  LicenseRegistry.addLicense(() async* {
    for (final notice in _bundledNotices) {
      final text = await assets.loadString(notice.asset);
      yield LicenseEntryWithLineBreaks(notice.packages, text);
    }
  });
}

const _bundledNotices = <_BundledNotice>[
  _BundledNotice([
    'Android JS Runtimes bridge 0.3.6',
  ], 'assets/addon_runtime/ANDROID_JS_RUNTIMES_LICENSE.txt'),
  _BundledNotice([
    'QuickJS 2026-06-04',
  ], 'assets/addon_runtime/QUICKJS_LICENSE.txt'),
  _BundledNotice([
    'Bundled add-on JavaScript runtime packages',
  ], 'assets/addon_runtime/JS_RUNTIME_NOTICES.txt'),
  _BundledNotice([
    'Discord Social SDK bundled components 1.10.18369',
  ], 'third_party/discord_social_sdk/License-Notices.txt'),
  _BundledNotice(['Noto Sans Regular'], 'assets/fonts/OFL.txt'),
];

class _BundledNotice {
  const _BundledNotice(this.packages, this.asset);

  final List<String> packages;
  final String asset;
}
