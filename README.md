
<p align="center">
  <img src="banner.png" alt="Ani-Cli Flutter Banner">
</p>

# 🌸 Ani-Cli Flutter

![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)

> **The Cozy Anime & Manga Client.**
> A beautiful, animated Flutter port of the [ani-cli](https://github.com/pystardust/ani-cli) shell script with multi-source support for English and Vietnamese content.

---

## ✨ Features

*   **🎨 Cozy UI**: A relaxing, pastel-themed interface with live moving gradients and milky glassmorphism.
*   **📖 Multi-Source Manga**: Aggregators for EN (MangaDex + WeebCentral) and VN (ZetTruyen + TruyenQQ), plus individual source selection.
*   **🎞️ Multi-Source Anime**: English (Multi-Provider via AllAnime/Senshi/Anipub/etc.) and Vietnamese (PhimAPI) backends.
*   **🔍 Smart Deduplication**: Aggregators merge results from multiple sources by normalized title, preferring the more reliable source.
*   **🔄 Manga Reader**: Dedicated reader with per-source referer headers, image caching, download support.
*   **✨ Animations**: Smooth Hero transitions and hover effects using `flutter_animate`.
*   **🌐 Cross-Platform**: Windows, Linux, macOS, Android, iOS.

---

## 🛠️ Installation

```bash
# Clone
git clone https://github.com/minhmc2007/AniCli-Flutter
cd AniCli-Flutter

# Install Dependencies
flutter pub get

# Run
flutter run
```

---

## 🏗️ Architecture

*   **`lib/main.dart`**: App shell, navigation, OOBE onboarding, settings, and all UI components (cards, reader, detail views).
*   **`lib/api/manga.dart`**: All manga cores — `MangaCore` (MangaDex), `ZetTruyenCore`, `WeebCentralCore`, `TruyenQQCore`, plus `EnMangaCore` and `ViMangaCore` aggregators.
*   **`lib/api/anime.dart`**: Anime source definitions and core coordination.
*   **`lib/api/providers/`**: Provider-based anime sources (AllAnime, Senshi, Anipub, AniNeko, AnimePahe).
*   **`lib/user_provider.dart`**: State management for history and favorites.

---

## 🙏 Credits

This project builds upon the work of many open-source projects and providers:

*   **Original Logic**: [ani-cli](https://github.com/pystardust/ani-cli) by pystardust.
*   **Manga Implementation**: [manga-tui](https://github.com/josueBarretogit/manga-tui) by josueBarretogit.
*   **Anime Implementation**: [curd](https://github.com/Wraient/curd) by Wraient.
*   **Anime Scrapers**: [Sudachi](https://github.com/KabosuNeko/Sudachi) / PhimAPI.
*   **Manga Sources**: [MangaDex](https://mangadex.org), [ZetTruyen](https://www.zettruyen.ink), [WeebCentral](https://weebcentral.com), [TruyenQQ](https://truyenqq.com.vn).
*   **NSFW/AO Content**: [HentaiVietsub](https://hentaivietsub.com).
*   **UI/Framework**: [Flutter](https://flutter.dev).

---

## 📜 License

This project is licensed under the **GPLv3 License**, inheriting the license from the original `ani-cli` project. If you fork this project, you **must** keep the source code open under the same license.
