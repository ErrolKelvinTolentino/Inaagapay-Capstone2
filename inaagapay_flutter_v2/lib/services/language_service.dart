import 'package:flutter/material.dart';

import 'auth_storage.dart';

enum AppLanguage { english, filipino }

class LanguageService {
  static final ValueNotifier<AppLanguage> selectedLanguage =
      ValueNotifier<AppLanguage>(AppLanguage.english);

  /// Reads the language chosen on this phone. Called once, before the first
  /// screen is drawn.
  ///
  /// The choice used to live only in memory, so every launch started in
  /// English again: a mother who picked Filipino found the whole app back in
  /// English the next morning, and had to know to go to Settings to undo it.
  static Future<void> restore() async {
    try {
      final saved = await AuthStorage.getLanguage();
      selectedLanguage.value = saved == AppLanguage.filipino.name
          ? AppLanguage.filipino
          : AppLanguage.english;
    } catch (e) {
      debugPrint('Could not read the saved language: $e');
    }
  }

  /// Switches the app's language and remembers it on this phone.
  static Future<void> setLanguage(AppLanguage language) async {
    selectedLanguage.value = language;
    try {
      await AuthStorage.saveLanguage(language.name);
    } catch (e) {
      debugPrint('Could not save the language: $e');
    }
  }

  static bool get isFilipino => selectedLanguage.value == AppLanguage.filipino;

  static String displayName(AppLanguage language) {
    return language == AppLanguage.filipino ? 'Filipino' : 'English';
  }

  static String translate(String english, String filipino) {
    return isFilipino ? filipino : english;
  }
}

extension LocalizedString on String {
  String t(String filipino) => LanguageService.isFilipino ? filipino : this;
}
