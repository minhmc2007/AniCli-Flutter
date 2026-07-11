# AniCli Flutter — AGENTS.md

## Quick start

```bash
flutter pub get
flutter run                          # runs on default device
flutter run -d windows               # target a specific platform
```

## Commands

| What | Command |
|------|---------|
| Analyze | `flutter analyze` |
| Test | `flutter test` |
| Test with coverage | `flutter test --coverage` |
| Lint | `dart analyze lib/` |
| Build Windows | `flutter build windows --release` |
| Build Linux | `flutter build linux --release` |
| Build APK | `flutter build apk --release` |
| Build iOS (unsigned) | `flutter build ios --release --no-codesign` |
| API sanity check | `python test_api.py` |

CI runs `unittest.yml` (flutter test + build check), `main.yml` (full build), and `api_sanity_check.yml` (daily + on push).

**Note:** `test/` directory is empty — `flutter test` passes with zero tests. The only real API verification is the Python script `test_api.py` at root.

## Architecture

Single-package Flutter app (`name: animeclient`), no monorepo tooling. SDK `>=3.2.0 <4.0.0`.

### Key files

| File | Purpose |
|------|---------|
| `lib/main.dart` (~3000+ lines) | Monolithic — app shell, navigation, onboarding, all UI components (browse, reader, detail views, settings, players) |
| `lib/api/manga.dart` | Manga cores: MangaDex, ZetTruyen, WeebCentral, TruyenQQ + EnMangaCore/ViMangaCore aggregators |
| `lib/api/anime.dart` | Anime cores: AniCore (AllAnime), ViAnimeCore (OPhim), HentaiVietsubCore + ProviderCoordinator (new provider stack) |
| `lib/api/providers/` | Provider-based anime sources: Senshi, Anipub, Anineko, AllAnime, Animepahe — registered in `ProviderRegistry` |
| `lib/user_provider.dart` | History, favorites, backup/restore (SharedPreferences-backed) |
| `lib/i18n.dart` + `lib/i18n/` | Manual i18n (no Flutter intl), EN + VI string maps |

### State management

`provider` package — `MultiProvider` wraps `UserProvider`, `SettingsProvider`, `SourceProvider`, `MangaSourceProvider`, `ProgressProvider`. All extend `ChangeNotifier`.

### Video playback

`media_kit` + `media_kit_video` (MPV-based). `media_kit_libs_video` bundles MPV binaries.

## Important quirks

- **Version** is defined as `kAppVersion` in `lib/main.dart:33`, **not** in `pubspec.yaml`.
- **No generated code** — no build_runner, freezed, json_serializable. JSON models are handwritten factories.
- **All UI in one file** — `lib/main.dart` contains the entire widget tree. No widget decomposition into separate files.
- **Thumbnail CDN fallback** — `CozyHeroImage` tries alternate CDN hosts (`ophim.live` ↔ `phimimg.com`) on load failure.
- **Performance tiers** (auto/bestLooking/balanced/bestPerformance) gate animations and blur effects throughout the UI.
- **Updater** fetches releases from GitHub API, downloads platform-appropriate asset (APK/setup.exe/AppImage/ipa).

## External repos (not part of Flutter build)

| Directory | Language | Purpose |
|-----------|----------|---------|
| `curd/` | Go | Reference anime scraper (unrelated) |
| `Sudachi/` | Bash | Vietnamese movie player (has own `AGENTS.md`) |
| `manga-tui/` | Rust | Reference manga TUI (unrelated) |

These are standalone repos with their own `.git/` directories, excluded via `.gitignore`. Do not modify them.

## UI conventions

- **Pastel theme**: cream/peach/coral color palette (`kColorCream`, `kColorPeach`, `kColorCoral`)
- **Glassmorphism**: `LiquidGlassContainer` widget with blur + backdrop filter
- **Live gradient**: `LiveGradientBackground` animates a `LinearGradient` — pauses on scroll
- **Animation tiers**: `Widget.adapt(tier)` and `Widget.simpleDrop(tier)` control fade/slide/scale per `PerformanceTier`
- **Hero transitions**: `CozyHeroImage` wraps `Hero` + `CachedNetworkImage` with CDN fallback
- **Locale**: `BuildContext.tr(key)` extension reads from manual string maps in `lib/i18n/`
