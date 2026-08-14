import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const initialSetupCompletedStorageKey = 'initial_setup_completed_v1';

final setupProgressProvider =
    StateNotifierProvider<SetupProgressController, SetupProgressState>((ref) {
      return SetupProgressController(ref.watch(secureStorageProvider));
    });

class SetupProgressState {
  const SetupProgressState({this.loaded = false, this.completed = false});

  final bool loaded;
  final bool completed;
}

class SetupProgressController extends StateNotifier<SetupProgressState> {
  SetupProgressController(this._storage) : super(const SetupProgressState());

  final FlutterSecureStorage _storage;

  Future<void> load() async {
    if (state.loaded) return;
    try {
      final values = await _storage.readAll();
      final value = values[initialSetupCompletedStorageKey];
      // The setup flag was introduced after TetoTV already had users. Any
      // existing encrypted preference/account means this is an upgrade, not a
      // fresh install, so do not interrupt that user with onboarding.
      final existingInstallation = values.keys.any(
        (key) => key != initialSetupCompletedStorageKey,
      );
      final completed = value == 'true' || existingInstallation;
      if (completed && value != 'true') {
        await _storage.write(
          key: initialSetupCompletedStorageKey,
          value: 'true',
        );
      }
      if (!mounted) return;
      state = SetupProgressState(loaded: true, completed: completed);
    } catch (_) {
      if (mounted) state = const SetupProgressState(loaded: true);
    }
  }

  Future<void> complete() async {
    try {
      await _storage.write(key: initialSetupCompletedStorageKey, value: 'true');
    } finally {
      if (mounted) {
        state = const SetupProgressState(loaded: true, completed: true);
      }
    }
  }
}
