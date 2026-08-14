import 'package:anime_tv/core/legal/bundled_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registers native and bundled JavaScript notices', () async {
    registerBundledThirdPartyLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final byPackage = <String, String>{};
    for (final entry in entries) {
      final text = entry.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      for (final package in entry.packages) {
        byPackage[package] = text;
      }
    }

    expect(
      byPackage['Android JS Runtimes bridge 0.3.6'],
      contains('Copyright (c) 2020 fast-development'),
    );
    expect(
      byPackage['QuickJS 2026-06-04'],
      contains('Copyright (c) 2017-2021 Fabrice Bellard'),
    );
    final javascriptNotices =
        byPackage['Bundled add-on JavaScript runtime packages'];
    expect(javascriptNotices, contains('Package: linkedom 0.18.12'));
    expect(javascriptNotices, contains('Package: sucrase 3.35.0'));
    expect(javascriptNotices, contains('Package: boolbase 1.0.0'));
    expect(byPackage['Noto Sans Regular'], contains('SIL OPEN FONT LICENSE'));
    expect(
      byPackage['Noto Sans Regular'],
      contains('Copyright 2018 The Noto Project Authors'),
    );
  });
}
