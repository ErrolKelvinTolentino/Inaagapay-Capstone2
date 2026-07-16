import 'package:flutter/material.dart';

enum AppLanguage { english, filipino }

class LanguageService {
  static final ValueNotifier<AppLanguage> selectedLanguage =
      ValueNotifier<AppLanguage>(AppLanguage.english);

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
