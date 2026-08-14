import 'dart:async';
import 'package:anime_tv/app/app.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/diagnostics/anonymous_crash_reporter.dart';
import 'package:anime_tv/core/legal/bundled_licenses.dart';
import 'package:anime_tv/core/performance/performance_monitor.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledThirdPartyLicenses();
  FlutterError.onError = (details) {
    // Full framework exceptions can contain signed media URLs supplied by a
    // decoder or network stack. Keep rich console output for development, but
    // rely on the redacted on-device diagnostics store in release builds.
    if (kDebugMode) FlutterError.presentError(details);
    unawaited(
      TetoTvDatabase.instance.recordDiagnosticEvent(
        category: 'flutter',
        message: details.exceptionAsString(),
        details: details.stack?.toString(),
      ),
    );
    unawaited(
      recordAnonymousCrash(
        kind: 'flutter',
        error: details.exception,
        stack: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      TetoTvDatabase.instance.recordDiagnosticEvent(
        category: 'platform',
        message: error,
        details: stack.toString(),
      ),
    );
    unawaited(
      recordAnonymousCrash(kind: 'platform', error: error, stack: stack),
    );
    return true;
  };
  MediaKit.ensureInitialized();
  PerformanceMonitor.instance.start();
  final isTelevision = await AndroidTvBridge.instance.isTelevision().timeout(
    const Duration(seconds: 2),
    onTimeout: () => false,
  );
  runApp(
    ProviderScope(
      observers: [AnonymousHandledErrorObserver()],
      overrides: [isTelevisionProvider.overrideWithValue(isTelevision)],
      child: const TetoTvApp(),
    ),
  );
}
