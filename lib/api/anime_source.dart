import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anime source: EN (AllAnime) or VI (PhimAPI Vietsub)
enum AnimeSource {
  en,
  vi,
}

extension AnimeSourceX on AnimeSource {
  String get label => this == AnimeSource.en ? 'English' : 'Tiếng Việt';
  String get description =>
      this == AnimeSource.en ? 'AllAnime · Sub' : 'PhimAPI · Vietsub';
}

class SourceProvider extends ChangeNotifier {
  static const _key = 'anime_source';
  AnimeSource _source = AnimeSource.en;

  AnimeSource get source => _source;
  bool get isVi => _source == AnimeSource.vi;

  SourceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == 'vi') {
      _source = AnimeSource.vi;
    } else {
      _source = AnimeSource.en;
    }
    notifyListeners();
  }

  Future<void> setSource(AnimeSource s) async {
    _source = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.name);
    notifyListeners();
  }
}
