import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a truly fresh install requires setup', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final controller = SetupProgressController(const FlutterSecureStorage());
    await controller.load();
    expect(controller.state.loaded, isTrue);
    expect(controller.state.completed, isFalse);
  });

  test('an upgrade with existing preferences skips forced setup', () async {
    FlutterSecureStorage.setMockInitialValues({
      'settings_selected_debrid_provider': 'real-debrid',
    });
    const storage = FlutterSecureStorage();
    final controller = SetupProgressController(storage);
    await controller.load();
    expect(controller.state.completed, isTrue);
    expect(await storage.read(key: initialSetupCompletedStorageKey), 'true');
  });

  test('skip or finish persists completion', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = SetupProgressController(storage);
    await controller.complete();
    expect(controller.state.completed, isTrue);

    final restored = SetupProgressController(storage);
    await restored.load();
    expect(restored.state.completed, isTrue);
  });
}
