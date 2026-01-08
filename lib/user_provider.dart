import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/ani_core.dart';

class HistoryItem {
  final AnimeModel anime;
  final String episode;
  final DateTime timestamp;

  HistoryItem({required this.anime, required this.episode, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'anime': anime.toJson(),
    'episode': episode,
    'timestamp': timestamp.toIso8601String(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      anime: AnimeModel.fromJson(json['anime']),
      episode: json['episode'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class UserProvider extends ChangeNotifier {
  List<AnimeModel> _favorites = [];
  List<HistoryItem> _history = [];

  List<AnimeModel> get favorites => _favorites;
  List<HistoryItem> get history => _history;

  UserProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Favs
    final favString = prefs.getString('favorites');
    if (favString != null) {
      final List decoded = jsonDecode(favString);
      _favorites = decoded.map((e) => AnimeModel.fromJson(e)).toList();
    }

    // Load History
    final histString = prefs.getString('history');
    if (histString != null) {
      final List decoded = jsonDecode(histString);
      _history = decoded.map((e) => HistoryItem.fromJson(e)).toList();
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(AnimeModel anime) async {
    final isFav = _favorites.any((e) => e.id == anime.id);
    if (isFav) {
      _favorites.removeWhere((e) => e.id == anime.id);
    } else {
      _favorites.add(anime);
    }
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    prefs.setString('favorites', jsonEncode(_favorites.map((e) => e.toJson()).toList()));
  }

  bool isFavorite(String id) {
    return _favorites.any((e) => e.id == id);
  }

  Future<void> addToHistory(AnimeModel anime, String episode) async {
    // Remove existing entry for this anime so we can move it to the top
    _history.removeWhere((e) => e.anime.id == anime.id);

    // Add to top
    _history.insert(0, HistoryItem(
      anime: anime,
      episode: episode,
      timestamp: DateTime.now()
    ));

    // Limit history to 50 items
    if (_history.length > 50) _history.removeLast();

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    prefs.setString('history', jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  // Clean history
  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('history');
  }
}
