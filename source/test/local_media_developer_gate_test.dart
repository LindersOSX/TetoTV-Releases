import 'package:anime_tv/app/router.dart';
import 'package:anime_tv/features/settings/presentation/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('direct Local Media route redirects outside Developer Mode', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => appRouter.go('/'));

    appRouter.go('/settings/local-media');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(
      appRouter.routeInformationProvider.value.uri.path,
      '/settings/accounts',
    );
    expect(tester.takeException(), isNull);
  });
}
