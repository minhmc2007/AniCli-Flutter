import 'package:flutter/material.dart';
import 'i18n/en.dart';
import 'i18n/vi.dart';

enum AppLocale { en, vi }

Map<String, Map<AppLocale, String>> _buildStrings() {
  final keys = <String>{...enStrings.keys, ...viStrings.keys};
  final map = <String, Map<AppLocale, String>>{};
  for (final k in keys) {
    map[k] = {AppLocale.en: enStrings[k] ?? viStrings[k] ?? k, AppLocale.vi: viStrings[k] ?? enStrings[k] ?? k};
  }
  return map;
}

class Translations {
  static final Translations _instance = Translations._();
  Translations._();

  static AppLocale _locale = AppLocale.en;

  static Translations of(BuildContext context) {
    _locale = Localizations.localeOf(context).languageCode == 'vi' ? AppLocale.vi : AppLocale.en;
    return _instance;
  }

  static final Map<String, Map<AppLocale, String>> _strings = _buildStrings();

  String tr(String key, [List<String>? args]) {
    final map = _strings[key];
    if (map == null) return key;
    var s = map[_locale] ?? map[AppLocale.en] ?? key;
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        s = s.replaceAll('{$i}', args[i]);
      }
    }
    return s;
  }
}

extension TranslateX on BuildContext {
  String tr(String key, [List<String>? args]) => Translations.of(this).tr(key, args);
}