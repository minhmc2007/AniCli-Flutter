import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:animeclient/api/manga.dart' show AnimeModel;

class HistoryItem {
  final AnimeModel anime;
  final String episode;
  final DateTime timestamp;

  HistoryItem({
    required this.anime,
    required this.episode,
    required this.timestamp,
  });

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

  /// Returns a clean display string for the episode.
  /// Handles the "id|num [lang]" format used by MangaDex/AllManga chapters.
  String get displayEpisode {
    if (episode.contains('|')) return episode.split('|')[1];
    return episode;
  }
}

class UserProvider extends ChangeNotifier {
  List<AnimeModel> _favorites = [];
  List<HistoryItem> _history = [];

  List<AnimeModel> get favorites => List.unmodifiable(_favorites);
  List<HistoryItem> get history => List.unmodifiable(_history);

  UserProvider() {
    _loadData();
  }

  // ── Favorites ───────────────────────────────────────────────────────────────

  bool isFavorite(String id) => _favorites.any((e) => e.id == id);

  Future<void> toggleFavorite(AnimeModel anime) async {
    final isFav = isFavorite(anime.id);
    if (isFav) {
      _favorites.removeWhere((e) => e.id == anime.id);
    } else {
      _favorites.add(anime);
    }
    notifyListeners();
    await _saveFavorites();
  }

  // ── History ─────────────────────────────────────────────────────────────────

  Future<void> addToHistory(AnimeModel anime, String episode) async {
    _history.removeWhere((e) => e.anime.id == anime.id);
    _history.insert(
      0,
      HistoryItem(anime: anime, episode: episode, timestamp: DateTime.now()),
    );
    if (_history.length > 50) _history.removeLast();
    notifyListeners();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('history');
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final favString = prefs.getString('favorites');
    if (favString != null) {
      final List decoded = jsonDecode(favString);
      _favorites = decoded.map((e) => AnimeModel.fromJson(e)).toList();
    }

    final histString = prefs.getString('history');
    if (histString != null) {
      final List decoded = jsonDecode(histString);
      _history = decoded.map((e) => HistoryItem.fromJson(e)).toList();
    }

    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'favorites',
      jsonEncode(_favorites.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'history',
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }
}
