// ═══════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════

class SelectionOption {
  final String key;
  final String label;
  final String title;
  final String? thumbnail;
  final Map<String, dynamic>? extraData;

  SelectionOption({
    required this.key,
    required this.label,
    required this.title,
    this.thumbnail,
    this.extraData,
  });
}

class PlaybackConfig {
  final String subOrDub;
  final String subStyle;

  PlaybackConfig({
    this.subOrDub = 'sub',
    this.subStyle = 'ask',
  });

  PlaybackConfig copyWith({String? subOrDub, String? subStyle}) =>
      PlaybackConfig(
        subOrDub: subOrDub ?? this.subOrDub,
        subStyle: subStyle ?? this.subStyle,
      );
}

class StreamPlaybackHint {
  final String? referrer;
  final String? subtitle;
  final Map<String, String>? extraHeaders;

  StreamPlaybackHint({this.referrer, this.subtitle, this.extraHeaders});

  Map<String, String> get allHeaders {
    final headers = <String, String>{};
    if (referrer != null && referrer!.isNotEmpty) {
      headers['Referer'] = referrer!;
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders!);
    }
    return headers;
  }
}

class ProviderMeta {
  final String name;
  final List<String> aliases;
  final String referrer;
  final bool defaultDisabled;
  final String? disableReason;
  final String? optOutToken;

  const ProviderMeta({
    required this.name,
    this.aliases = const [],
    this.referrer = '',
    this.defaultDisabled = false,
    this.disableReason,
    this.optOutToken,
  });
}

// ═══════════════════════════════════════════════════════════════
// PROVIDER INTERFACE
// ═══════════════════════════════════════════════════════════════

bool isHttpOk(int statusCode) => statusCode >= 200 && statusCode < 300;

abstract class AnimeProvider {
  String get name;

  Future<List<SelectionOption>> searchAnime(String query, String mode);

  Future<List<SelectionOption>> getTrending(String mode) async {
    try {
      return await searchAnime('', mode);
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> episodesList(String showId, String mode);

  Future<List<String>> getEpisodeUrl(
    PlaybackConfig config,
    String id,
    int epNo,
  );

  Future<List<String>> getEpisodeUrlForMode(
    PlaybackConfig config,
    String id,
    int epNo,
    String mode,
  ) {
    return getEpisodeUrl(config.copyWith(subOrDub: mode), id, epNo);
  }

  Future<Map<String, StreamPlaybackHint>> getEpisodeUrlForModeWithHints(
    PlaybackConfig config,
    String id,
    int epNo,
    String mode,
  ) async {
    final urls = await getEpisodeUrlForMode(config, id, epNo, mode);
    final hints = <String, StreamPlaybackHint>{};
    for (final url in urls) {
      hints[url] = StreamPlaybackHint();
    }
    return hints;
  }

  Future<String?> resolveProviderId(String providerId, String query) async =>
      null;

  String get providerId;
}

// ═══════════════════════════════════════════════════════════════
// REGISTRY
// ═══════════════════════════════════════════════════════════════

class ProviderRegistry {
  final _providers = <String, AnimeProvider>{};
  final _aliases = <String, String>{};

  void register(AnimeProvider provider) {
    final id = provider.providerId.toLowerCase().trim();
    _providers[id] = provider;
    _aliases[provider.name.toLowerCase().trim()] = id;
    _aliases[provider.name.toLowerCase().trim().replaceAll(RegExp(r'[\s\-_]'), '')] = id;
  }

  AnimeProvider provider(String id) {
    final lookup = id.toLowerCase().trim();
    final resolved = _providers[lookup] ?? _providers[_aliases[lookup]];
    if (resolved == null) throw Exception('Unknown provider: "$id"');
    return resolved;
  }

  AnimeProvider? tryProvider(String id) {
    final lookup = id.toLowerCase().trim();
    return _providers[lookup] ?? _providers[_aliases[lookup]];
  }

  List<String> get registeredNames => _providers.keys.toList()..sort();

  List<String> get defaultStack => defaultProviderStack
      .where((name) => _providers.containsKey(name))
      .toList();
}

// ═══════════════════════════════════════════════════════════════
// LANGUAGE HELPERS
// ═══════════════════════════════════════════════════════════════

String normalizeTranslationType(String type) {
  final t = type.toLowerCase().trim();
  return t == 'dub' ? 'dub' : 'sub';
}

String alternateTranslationType(String type) {
  return type == 'dub' ? 'sub' : 'dub';
}

// ═══════════════════════════════════════════════════════════════
// QUALIFIED ID HELPERS
// ═══════════════════════════════════════════════════════════════

String qualifyProviderId(String providerName, String rawId) {
  if (rawId.contains('::')) return rawId;
  return '$providerName::$rawId';
}

(String providerName, String rawId)? parseQualifiedId(String qid) {
  final idx = qid.indexOf('::');
  if (idx < 0) return null;
  return (qid.substring(0, idx), qid.substring(idx + 2));
}

(String providerName, String rawId) parseQualifiedIdUnsafe(String qid) {
  final result = parseQualifiedId(qid);
  if (result == null) throw Exception('Invalid qualified ID: "$qid"');
  return result;
}

String makeQualifiedId(Map<String, dynamic>? extraData, String key, String defaultProvider) {
  if (key.contains('::')) return key;
  final pd = extraData?['provider'] as String?;
  return '${pd ?? defaultProvider}::$key';
}

// ═══════════════════════════════════════════════════════════════
// DEFAULT PROVIDER STACK
// ═══════════════════════════════════════════════════════════════

const List<String> defaultProviderStack = [
  'allanime',
  'senshi',
  'anipub',
  'anineko',
  'animepahe',
];

// ───────────────────────────────────────────────────────────────
// RESULT MERGING HELPERS
// ───────────────────────────────────────────────────────────────

int extractEpisodeCount(String label) {
  final patterns = [
    RegExp(r'(\d+)\s*eps?', caseSensitive: false),
    RegExp(r'Sub:\s*(\d+)', caseSensitive: false),
    RegExp(r'(\d+)\s*s/', caseSensitive: false),
    RegExp(r'(\d+)\s*episodes?', caseSensitive: false),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(label);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
  }
  return 0;
}

String normalizeTitle(String title) {
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<SelectionOption> mergeResults(List<SelectionOption> results) {
  if (results.isEmpty) return results;
  final grouped = <String, List<SelectionOption>>{};
  for (final opt in results) {
    final key = normalizeTitle(opt.title);
    grouped.putIfAbsent(key, () => []).add(opt);
  }
  return grouped.values.map((group) {
    if (group.length == 1) return group.first;
    group.sort((a, b) => extractEpisodeCount(b.label).compareTo(extractEpisodeCount(a.label)));
    final best = group.first;
    final bestProviderParts = best.key.split('::');
    final bestProvider = best.extraData?['provider'] as String? ??
        (bestProviderParts.length > 1 ? bestProviderParts.first : null);
    final mergedFrom = group.map((o) {
      final p = o.extraData?['provider'] as String?;
      if (p != null) return p;
      final parts = o.key.split('::');
      return parts.length > 1 ? parts.first : null;
    }).where((p) => p != null).toList();
    final mergedExtra = <String, dynamic>{
      ...?best.extraData,
      'merged_from': mergedFrom,
    };
    if (bestProvider != null) mergedExtra['provider'] = bestProvider;
    return SelectionOption(
      key: best.key,
      label: best.label,
      title: best.title,
      thumbnail: best.thumbnail,
      extraData: mergedExtra,
    );
  }).toList();
}
