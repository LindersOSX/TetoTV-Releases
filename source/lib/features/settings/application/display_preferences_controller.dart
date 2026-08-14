import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const titleLanguagePreferenceStorageKey = 'title_language_preference';

final titleLanguagePreferenceProvider =
    StateNotifierProvider<
      TitleLanguagePreferenceController,
      TitleLanguagePreference
    >((ref) {
      final controller = TitleLanguagePreferenceController(
        ref.watch(secureStorageProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class TitleLanguagePreferenceController
    extends StateNotifier<TitleLanguagePreference> {
  TitleLanguagePreferenceController(this._storage)
    : super(TitleLanguagePreference.english);

  final FlutterSecureStorage _storage;

  Future<void> load() async {
    try {
      final saved = await _storage.read(key: titleLanguagePreferenceStorageKey);
      if (saved == TitleLanguagePreference.romaji.storageValue) {
        state = TitleLanguagePreference.romaji;
      }
    } catch (_) {
      // The visual preference is non-critical; English remains the default.
    }
  }

  Future<void> setPreference(TitleLanguagePreference preference) async {
    state = preference;
    try {
      await _storage.write(
        key: titleLanguagePreferenceStorageKey,
        value: preference.storageValue,
      );
    } catch (_) {
      // Keep the in-memory selection even if platform storage is unavailable.
    }
  }

  Future<void> toggle() => setPreference(
    state == TitleLanguagePreference.english
        ? TitleLanguagePreference.romaji
        : TitleLanguagePreference.english,
  );
}
