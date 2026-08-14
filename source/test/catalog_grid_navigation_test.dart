import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/catalog_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = [
    for (var index = 0; index < 5; index++)
      AnimeSummary(
        id: index + 1,
        title: 'Boundary result ${index + 1}',
        description: '',
        episodes: 12,
        score: 8,
      ),
  ];

  for (final testCase in const [
    (width: 168.0, expectedIndex: 1, expectedColumns: 1),
    (width: 169.0, expectedIndex: 2, expectedColumns: 2),
  ]) {
    testWidgets('D-pad rows match the max-extent sliver at '
        '${testCase.width}px (${testCase.expectedColumns} columns)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: testCase.width,
                height: 700,
                child: CatalogGrid(
                  items: items,
                  titlePreference: TitleLanguagePreference.romaji,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'catalog.result.0',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'catalog.result.${testCase.expectedIndex}',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
