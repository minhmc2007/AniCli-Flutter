# 🌸 Ani-Cli Flutter

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white)
![License](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)

[![Build Application](https://github.com/minhmc2007/AniCli-Flutter/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/minhmc2007/AniCli-Flutter/actions/workflows/main.yml)

> **The Cozy Anime Client.**
> A beautiful, animated Flutter port of the [ani-cli](https://github.com/pystardust/ani-cli) shell script.

**Ani-Cli Flutter** combines the powerful scraping logic of the terminal-based `ani-cli` with a high-end, glassmorphic user interface. Designed with a "Cozy" aesthetic (Cream & Peach palette), it provides a seamless and ad-free anime watching experience on Desktop and Mobile.

---

## ✨ Features

*   **🎨 Cozy UI**: A relaxing, pastel-themed interface with live moving gradients and milky glassmorphism.
*   **🚀 High Performance**: Built with Flutter for native performance on Linux, Windows, macOS, and iOS.
*   **🎞️ Dual Player Support**:
    *   **Built-in MPV**: Ready to use out of the box.
    *   **System MPV**: Connects to your local MPV installation for maximum hardware acceleration and custom configuration.
*   **❤️ Favorites**: Save your favorite shows for quick access.
*   **clock History**: Automatically tracks watched episodes and saves your progress locally.
*   **🔍 Powerful Search**: Scrapes `AllAnime` API for a vast library of Sub and Dub anime.
*   **✨ Animations**: Smooth Hero transitions, staggered list animations, and hover effects using `flutter_animate`.

---

## 🛠️ Prerequisites

**Note on Video Players:**
This app comes with a **Built-in MPV** player, so you can run it immediately without external dependencies.

**However, the developer strongly recommends using System MPV.**
Switching to the System MPV (via settings) provides the best experience, including better hardware acceleration, higher format compatibility, and lower resource usage.

If you wish to use the System Player, please install `mpv`:

### Linux (Arch/Manjaro)
```bash
sudo pacman -S mpv
```

### macOS (Homebrew)
```bash
brew install mpv
```

### Windows
1.  Download **MPV** from [sourceforge.net](https://sourceforge.net/projects/mpv-player-windows/files/).
2.  Extract it.
3.  **Important:** Add the folder containing `mpv.exe` to your System **PATH** environment variable.

---

## ⚙️ Installation & Running

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/ani-cli-flutter.git
cd ani-cli-flutter
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run the App
**Linux:**
```bash
flutter run -d linux
```

**Windows:**
```bash
flutter run -d windows
```

**macOS:**
```bash
flutter run -d macos
```

---

## 📦 Building for Release

### Windows (EXE)
```powershell
flutter build windows --release
```
The output file will be in `build\windows\x64\runner\Release\`.

### macOS (DMG/App)
```bash
flutter build macos --release
```

### Linux (Debian/RPM/Tarball)
```bash
flutter build linux --release
```
The binary will be located in `build/linux/x64/release/bundle/`.

---

## 🏗️ Architecture

This project follows a clean separation of concerns:

*   **`lib/api/ani_core.dart`**: The "Brain". Contains the port of the Bash script logic. Handles GraphQL queries, decryption of source links, and managing player processes.
*   **`lib/user_provider.dart`**: State Management. Uses `Provider` and `SharedPreferences` to handle History, Favorites, and Player settings persistence.
*   **`lib/main.dart`**: The UI. Contains the `LiveGradientBackground`, `GlassDock`, and all visual views.

---

## 🎨 Color Palette

The app uses a custom "Cozy" palette designed to be easy on the eyes:

*   **Cream**: `#FEEAC9` (Main Background)
*   **Peach**: `#FFCDC9` (Gradient Accent)
*   **Soft Pink**: `#FDACAC` (Borders)
*   **Coral**: `#FD7979` (Primary / Hero)
*   **Chocolate**: `#4A2B2B` (Text)

---

## 📜 License

This project is licensed under the **GPLv3 License**, effectively inheriting the license from the original `ani-cli` project.

---

## 🙏 Credits

*   Based on the [ani-cli](https://github.com/pystardust/ani-cli) project by pystardust.
*   Specific logic adapted from the [minhmc2007/ani-cli](https://github.com/minhmc2007/ani-cli) fork.
*   Built with [Flutter](https://flutter.dev).
