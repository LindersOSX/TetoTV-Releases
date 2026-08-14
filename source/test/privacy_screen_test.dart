import 'package:anime_tv/features/settings/presentation/privacy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy disclosure fits a phone and supports D-pad scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.textContaining('TetoTV privacy disclosure'), findsOneWidget);
    expect(find.textContaining('does not sell personal data'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'privacy.back');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
