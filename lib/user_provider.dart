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
  // Normal Data
  List<AnimeModel> _normalFavorites = [];
  List<HistoryItem> _normalHistory = [];

  // Incognito/NSFW Data
  List<AnimeModel> _nsfwFavorites = [];
  List<HistoryItem> _nsfwHistory = [];

  bool _isNSFW = false;

  // Dynamic getters based on current mode
  List<AnimeModel> get favorites => List.unmodifiable(_isNSFW ? _nsfwFavorites : _normalFavorites);
  List<HistoryItem> get history => List.unmodifiable(_isNSFW ? _nsfwHistory : _normalHistory);
  bool get isNSFW => _isNSFW;

  UserProvider() {
    _loadData();
  }

  // ── Mode Switching ──────────────────────────────────────────────────────────

  void setMode(bool isNsfw) {
    if (_isNSFW != isNsfw) {
      _isNSFW = isNsfw;
      notifyListeners();
    }
  }

  // ── Favorites ───────────────────────────────────────────────────────────────

  bool isFavorite(String id) {
    final list = _isNSFW ? _nsfwFavorites : _normalFavorites;
    return list.any((e) => e.id == id);
  }

  Future<void> toggleFavorite(AnimeModel anime) async {
    final list = _isNSFW ? _nsfwFavorites : _normalFavorites;
    final isFav = list.any((e) => e.id == anime.id);
    if (isFav) {
      list.removeWhere((e) => e.id == anime.id);
    } else {
      list.add(anime);
    }
    notifyListeners();
    await _saveFavorites();
  }

  // ── History ─────────────────────────────────────────────────────────────────

  Future<void> addToHistory(AnimeModel anime, String episode) async {
    final list = _isNSFW ? _nsfwHistory : _normalHistory;
    list.removeWhere((e) => e.anime.id == anime.id);
    list.insert(
      0,
      HistoryItem(anime: anime, episode: episode, timestamp: DateTime.now()),
    );
    if (list.length > 50) list.removeLast();
    notifyListeners();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    if (_isNSFW) {
      _nsfwHistory.clear();
    } else {
      _normalHistory.clear();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_isNSFW ? 'nsfw_history' : 'history');
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Check saved mode on startup
    _isNSFW = prefs.getString('anime_source') == 'hentaivietsub';

    // Load Normal Data
    final favString = prefs.getString('favorites');
    if (favString != null) {
      _normalFavorites = (jsonDecode(favString) as List).map((e) => AnimeModel.fromJson(e)).toList();
    }
    final histString = prefs.getString('history');
    if (histString != null) {
      _normalHistory = (jsonDecode(histString) as List).map((e) => HistoryItem.fromJson(e)).toList();
    }

    // Load NSFW Data
    final nsfwFavString = prefs.getString('nsfw_favorites');
    if (nsfwFavString != null) {
      _nsfwFavorites = (jsonDecode(nsfwFavString) as List).map((e) => AnimeModel.fromJson(e)).toList();
    }
    final nsfwHistString = prefs.getString('nsfw_history');
    if (nsfwHistString != null) {
      _nsfwHistory = (jsonDecode(nsfwHistString) as List).map((e) => HistoryItem.fromJson(e)).toList();
    }

    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _isNSFW ? 'nsfw_favorites' : 'favorites';
    final list = _isNSFW ? _nsfwFavorites : _normalFavorites;
    await prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _isNSFW ? 'nsfw_history' : 'history';
    final list = _isNSFW ? _nsfwHistory : _normalHistory;
    await prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}
