import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:anime_tv/core/layout/interface_scaling.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic layout follows device category', () {
    expect(
      useTelevisionCanvas(
        detectedTelevision: true,
        mode: InterfaceMode.automatic,
      ),
      isTrue,
    );
    expect(
      useTelevisionCanvas(
        detectedTelevision: false,
        mode: InterfaceMode.automatic,
      ),
      isFalse,
    );
  });

  test('phone mode bypasses the virtual TV canvas on the same APK', () {
    final tvScale = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: 1,
    );
    final phoneScale = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.phone,
      userScale: 1,
    );

    expect(tvScale, 2);
    expect(phoneScale, 1);
  });

  test('user interface scale changes TV geometry', () {
    final compact = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: .8,
    );
    final large = interfaceCanvasScale(
      logicalWidth: 1920,
      physicalWidth: 1920,
      detectedTelevision: true,
      mode: InterfaceMode.television,
      userScale: 1.2,
    );

    expect(compact, 1.6);
    expect(large, 2.4);
  });

  const devices = <String, Size>{
    'folded phone portrait': Size(412, 915),
    'folded phone landscape': Size(915, 412),
    'unfolded foldable portrait': Size(884, 1104),
    'unfolded foldable landscape': Size(1104, 884),
    'tablet landscape': Size(1280, 800),
  };
  const scales = <double>[.8, .9, 1.1, 1.2];

  for (final device in devices.entries) {
    for (final scale in scales) {
      testWidgets(
        '${device.key} fills viewport and hit-tests at scale $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = device.value;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);

          var taps = 0;
          Size? reportedSize;
          final contentKey = GlobalKey();
          final mediaQuery = MediaQueryData(
            size: device.value,
            devicePixelRatio: 1,
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 12),
          );

          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: mediaQuery,
                child: InterfaceScaleViewport(
                  mediaQuery: mediaQuery,
                  scale: scale,
                  child: Builder(
                    builder: (context) {
                      reportedSize = MediaQuery.sizeOf(context);
                      return GestureDetector(
                        key: contentKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps += 1,
                        child: const ColoredBox(color: Colors.red),
                      );
                    },
                  ),
                ),
              ),
            ),
          );

          expect(
            reportedSize,
            _closeToSize(device.value / scale),
            reason: 'responsive widgets must receive the virtual canvas size',
          );
          expect(
            tester.getTopLeft(find.byKey(contentKey)),
            _closeToOffset(Offset.zero),
          );
          expect(
            tester.getBottomRight(find.byKey(contentKey)),
            _closeToOffset(Offset(device.value.width, device.value.height)),
            reason: 'the scaled canvas must fill every viewport edge',
          );

          await tester.tapAt(
            Offset(device.value.width - 2, device.value.height - 2),
          );
          expect(
            taps,
            1,
            reason: 'edge hit testing must follow visual scaling',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('fold display features use scaled canvas coordinates', (
    tester,
  ) async {
    const viewport = Size(884, 1104);
    const scale = .8;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Rect? reportedFold;
    final mediaQuery = MediaQueryData(
      size: viewport,
      displayFeatures: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(439, 0, 6, 1104),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: mediaQuery,
          child: InterfaceScaleViewport(
            mediaQuery: mediaQuery,
            scale: scale,
            child: Builder(
              builder: (context) {
                reportedFold = MediaQuery.of(
                  context,
                ).displayFeatures.single.bounds;
                return const ColoredBox(color: Colors.black);
              },
            ),
          ),
        ),
      ),
    );

    expect(reportedFold, const Rect.fromLTWH(548.75, 0, 7.5, 1380));
    expect(tester.takeException(), isNull);
  });
}

Matcher _closeToSize(Size expected) => isA<Size>()
    .having((value) => value.width, 'width', closeTo(expected.width, .01))
    .having((value) => value.height, 'height', closeTo(expected.height, .01));

Matcher _closeToOffset(Offset expected) => isA<Offset>()
    .having((value) => value.dx, 'dx', closeTo(expected.dx, .01))
    .having((value) => value.dy, 'dy', closeTo(expected.dy, .01));
