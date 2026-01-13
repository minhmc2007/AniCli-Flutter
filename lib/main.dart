import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
// Ensure this points to your actual API file
import 'package:animeclient/api/ani_core.dart';
import 'package:animeclient/user_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// --- APP CONSTANTS ---
const String kAppVersion = "1.6.3";
const String kBuildNumber = "163";

// --- THEME COLORS ---
const kColorCream = Color(0xFFFEEAC9);
const kColorPeach = Color(0xFFFFCDC9);
const kColorSoftPink = Color(0xFFFDACAC);
const kColorCoral = Color(0xFFFD7979);
const kColorDarkText = Color(0xFF4A2B2B);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
      ],
      child: const AniCliApp(),
    ),
  );
}

// --- UPDATER SERVICE ---
class UpdaterService {
  static const String _releaseUrl =
  "https://api.github.com/repos/minhmc2007/AniCli-Flutter/releases/latest";

static String? _extractSemVer(String raw) {
  final RegExp regExp = RegExp(r'(\d+)\.(\d+)(\.(\d+))?');
  final match = regExp.firstMatch(raw);
  if (match != null) {
    String major = match.group(1) ?? "0";
    String minor = match.group(2) ?? "0";
    String patch = match.group(4) ?? "0";
    return "$major.$minor.$patch";
  }
  return null;
}

static bool _isNewer(String current, String remote) {
  try {
    List<int> cParts = current.split('.').map(int.parse).toList();
    List<int> rParts = remote.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      int c = (i < cParts.length) ? cParts[i] : 0;
      int r = (i < rParts.length) ? rParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
  } catch (e) {
    debugPrint("Version parsing error: $e");
  }
  return false;
}

static Future<void> checkAndUpdate(BuildContext context) async {
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Checking for updates...")));

    final response = await http.get(Uri.parse(_releaseUrl));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String remoteTag = data['tag_name'];
      String body = data['body'];
      List assets = data['assets'];

      String? cleanCurrent = _extractSemVer(kAppVersion);
      String? cleanRemote = _extractSemVer(remoteTag);

      if (cleanCurrent != null &&
        cleanRemote != null &&
        _isNewer(cleanCurrent, cleanRemote)) {
        if (context.mounted) {
          _showCozyUpdateDialog(context, remoteTag, body, assets);
        }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("You are up to date! ($kAppVersion)"),
              backgroundColor: Colors.green));
          }
        }
    } else {
      throw Exception("GitHub API returned ${response.statusCode}");
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Update check failed: $e"),
        backgroundColor: kColorCoral));
    }
  }
}

static void _showCozyUpdateDialog(
  BuildContext context, String version, String notes, List assets) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "Dismiss",
    barrierColor: Colors.black.withOpacity(0.6),
    pageBuilder: (ctx, anim1, anim2) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: kColorCream, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kColorCoral.withOpacity(0.1),
                        shape: BoxShape.circle),
                        child: const Icon(LucideIcons.sparkles,
                                          color: kColorCoral, size: 24),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("New Version Available",
                               style: GoogleFonts.inter(
                                 fontSize: 18,
                                 fontWeight: FontWeight.bold,
                                 color: kColorDarkText)),
                                 Text(version,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: kColorCoral,
                                        fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ).animate().slideY(begin: -0.2, end: 0, duration: 400.ms).fadeIn(),
                const SizedBox(height: 20),
                Divider(color: kColorPeach.withOpacity(0.5)),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: MarkdownBody(
                      data: notes,
                      styleSheet: MarkdownStyleSheet(
                        p: GoogleFonts.inter(color: kColorDarkText, fontSize: 14),
                        h1: GoogleFonts.inter(
                          color: kColorDarkText,
                          fontWeight: FontWeight.bold,
                          fontSize: 20),
                          h2: GoogleFonts.inter(
                            color: kColorDarkText,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                            h3: GoogleFonts.inter(
                              color: kColorDarkText,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                              listBullet: GoogleFonts.inter(color: kColorCoral),
                              strong: GoogleFonts.inter(
                                fontWeight: FontWeight.bold, color: kColorCoral),
                                code: GoogleFonts.jetBrainsMono(
                                  backgroundColor: kColorCream, color: kColorDarkText),
                      ),
                    ),
                  ),
                ).animate(delay: 200.ms).fadeIn().slideX(begin: 0.1, end: 0),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text("Later",
                                  style: GoogleFonts.inter(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kColorCoral,
                        foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                              elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _performUpdate(context, assets, version);
                      },
                      icon: const Icon(LucideIcons.downloadCloud, size: 18),
                      label: Text("Update Now",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim1, anim2, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim1.value),
        child: Opacity(
          opacity: anim1.value,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 400),
  );
  }

  static Future<void> _performUpdate(
    BuildContext context, List assets, String version) async {
      String? downloadUrl;
      String fileName = "";

      if (Platform.isAndroid) {
        final asset = assets.firstWhere(
          (a) => a['name'].toString().endsWith('.apk'),
          orElse: () => null);
        downloadUrl = asset?['browser_download_url'];
        fileName = "AniCli_$version.apk";
      } else if (Platform.isWindows) {
        final asset = assets.firstWhere(
          (a) =>
          a['name'].toString().endsWith('.zip') ||
          a['name'].toString().endsWith('.exe'),
          orElse: () => null);
        downloadUrl = asset?['browser_download_url'];
        fileName = "AniCli_$version.zip";
      } else if (Platform.isLinux) {
        final asset = assets.firstWhere(
          (a) =>
          a['name'].toString().endsWith('.tar.gz') ||
          a['name'].toString().endsWith('.AppImage'),
          orElse: () => null);
        downloadUrl = asset?['browser_download_url'];
        fileName = "AniCli_$version.tar.gz";
      } else {
        launchUrl(
          Uri.parse(
            "https://github.com/minhmc2007/AniCli-Flutter/releases/latest"),
            mode: LaunchMode.externalApplication);
        return;
      }

      if (downloadUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No compatible asset found.")));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Downloading $fileName..."),
        duration: const Duration(seconds: 2)));

      try {
        final dir = await getApplicationDocumentsDirectory();
        String savePath = "${dir.path}/$fileName";

        if (Platform.isAndroid) {
          final tempDir = await getExternalStorageDirectory();
          if (tempDir != null) savePath = "${tempDir.path}/$fileName";
        }

        final response = await http.get(Uri.parse(downloadUrl));
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Download complete! Launching..."),
            backgroundColor: Colors.green));
        }

        if (Platform.isAndroid) {
          await OpenFile.open(savePath);
        } else {
          if (Platform.isWindows || Platform.isLinux) {
            await launchUrl(Uri.directory(file.parent.path));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                Text("Update downloaded. Please extract/install manually."),
                duration: Duration(seconds: 5)));
            }
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Update error: $e")));
        }
      }
    }
}

// --- PROVIDERS ---

class ProgressProvider extends ChangeNotifier {
  Map<String, int> _progress = {};

  ProgressProvider() {
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString('watch_progress');
    if (stored != null) {
      _progress = Map<String, int>.from(jsonDecode(stored));
      notifyListeners();
    }
  }

  Future<void> saveProgress(String animeId, String epNum, int seconds) async {
    _progress["${animeId}_$epNum"] = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_progress', jsonEncode(_progress));
  }

  int getProgress(String animeId, String epNum) {
    return _progress["${animeId}_$epNum"] ?? 0;
  }
}

class SettingsProvider extends ChangeNotifier {
  bool _useInternalPlayer = false;
  bool get useInternalPlayer => _useInternalPlayer;
  void toggleInternalPlayer(bool value) {
    _useInternalPlayer = value;
    notifyListeners();
  }
}

class AniCliApp extends StatelessWidget {
  const AniCliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniCli Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: kColorCream,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(
          bodyColor: kColorDarkText,
          displayColor: kColorDarkText,
        ),
        useMaterial3: true,
        iconTheme: const IconThemeData(color: kColorDarkText),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: ZoomPageTransitionsBuilder(),
            TargetPlatform.linux: ZoomPageTransitionsBuilder(),
            TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          },
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// --- LIQUID GLASS WIDGET ---
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Border? border;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.4,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final rRadius = borderRadius ?? BorderRadius.circular(20);
    return ClipRRect(
      borderRadius: rRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: rRadius,
            border: border ??
            Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.6),
                Colors.white.withOpacity(0.1),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// --- COZY HERO IMAGE (With Shadow Support for Flight) ---
class CozyHeroImage extends StatelessWidget {
  final String heroTag;
  final String imageUrl;
  final double radius;
  final bool withShadow;
  final BoxFit boxFit;

  const CozyHeroImage({
    super.key,
    required this.heroTag,
    required this.imageUrl,
    this.radius = 20.0,
    this.withShadow = true,
    this.boxFit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: withShadow
            ? [
              BoxShadow(
                color: kColorCoral.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ]
            : [],
          ),
          // ClipRRect needs to be inside the Container decoration to match shape
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: boxFit, // Use the passed fit
              alignment: Alignment.center,
              placeholder: (context, url) => Container(color: kColorPeach),
              errorWidget: (context, url, error) => Container(color: kColorPeach),
            ),
          ),
        ),
      ),
    );
  }
}

// --- LIVE BACKGROUND ---
class LiveGradientBackground extends StatefulWidget {
  final Widget child;
  const LiveGradientBackground({super.key, required this.child});

  @override
  State<LiveGradientBackground> createState() => _LiveGradientBackgroundState();
}

class _LiveGradientBackgroundState extends State<LiveGradientBackground>
with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Alignment> _topAlignmentAnimation;
  late Animation<Alignment> _bottomAlignmentAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);

    _topAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
        weight: 1),
        TweenSequenceItem(
          tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
          weight: 1),
          TweenSequenceItem(
            tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
            weight: 1),
            TweenSequenceItem(
              tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
              weight: 1),
    ]).animate(_controller);

    _bottomAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft),
        weight: 1),
        TweenSequenceItem(
          tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft),
          weight: 1),
          TweenSequenceItem(
            tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight),
            weight: 1),
            TweenSequenceItem(
              tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight),
              weight: 1),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [kColorCream, kColorPeach],
              begin: _topAlignmentAnimation.value,
              end: _bottomAlignmentAnimation.value,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// --- MAIN SCREEN ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final GlobalKey<_BrowseViewState> _browseKey = GlobalKey();
  final GlobalKey<_HistoryViewState> _historyKey = GlobalKey();
  final GlobalKey<_FavoritesViewState> _favKey = GlobalKey();
  final GlobalKey<_SettingsViewState> _settingsKey = GlobalKey();

  void _openDetail(AnimeModel anime, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        AnimeDetailView(anime: anime, heroTag: heroTag),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget activePage;
    Key activeKey;

    switch (_selectedIndex) {
      case 0:
        activePage = BrowseView(key: _browseKey, onAnimeTap: _openDetail);
        activeKey = const ValueKey("BrowseTab");
        break;
      case 1:
        activePage = HistoryView(key: _historyKey, onAnimeTap: _openDetail);
        activeKey = const ValueKey("HistoryTab");
        break;
      case 2:
        activePage = FavoritesView(key: _favKey, onAnimeTap: _openDetail);
        activeKey = const ValueKey("FavTab");
        break;
      case 3:
      default:
        activePage = SettingsView(key: _settingsKey);
        activeKey = const ValueKey("SettingsTab");
        break;
    }

    return Scaffold(
      body: LiveGradientBackground(
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutQuart,
                switchOutCurve: Curves.easeInQuart,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0), end: Offset.zero)
                        .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(key: activeKey, child: activePage),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: GlassDock(
                  selectedIndex: _selectedIndex,
                  onItemSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- INTERNAL PLAYER SCREEN ---
class InternalPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String animeId;
  final String epNum;

  const InternalPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.animeId,
    required this.epNum,
  });

  @override
  State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}

class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late final Player player;
  late final VideoController controller;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  bool _showForward = false;
  bool _showRewind = false;

  @override
  void initState() {
    super.initState();

    player = Player(
      configuration: const PlayerConfiguration(
        vo: 'gpu',
      ),
    );

    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    player.open(Media(
      widget.streamUrl,
      httpHeaders: {'Referer': AniCore.referer},
    ));

    Future.delayed(const Duration(milliseconds: 500), _checkResume);

    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final pos = player.state.position.inSeconds;
      if (pos > 10) {
        context.read<ProgressProvider>().saveProgress(widget.animeId, widget.epNum, pos);
      }
    });

    player.play();
    player.setVolume(100);
    _startHideTimer();
  }

  Future<void> _checkResume() async {
    final savedSeconds = context.read<ProgressProvider>().getProgress(widget.animeId, widget.epNum);

    if (savedSeconds > 10) {
      player.pause();

      final shouldResume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: kColorCream,
          title: const Text("Resume Watching?", style: TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)),
          content: Text("You left off at ${_formatDuration(Duration(seconds: savedSeconds))}. Continue?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Start Over", style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Resume"),
            ),
          ],
        ),
      );

      if (shouldResume == true) {
        player.seek(Duration(seconds: savedSeconds));
      }
      player.play();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _handleDoubleTap(bool isForward) {
    final current = player.state.position;
    final newPos = isForward
    ? current + const Duration(seconds: 10)
    : current - const Duration(seconds: 10);
    player.seek(newPos);

    setState(() {
      if (isForward) _showForward = true;
      else _showRewind = true;
    });

      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() { _showForward = false; _showRewind = false; });
      });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    final pos = player.state.position.inSeconds;
    if (pos > 10) {
      context.read<ProgressProvider>().saveProgress(widget.animeId, widget.epNum, pos);
    }
    // FIX: Force stop audio immediately before disposal
    player.stop();
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(controller: controller, controls: NoVideoControls),

            // Gesture Layer
            Row(
              children: [
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: () => _handleDoubleTap(false),
                  child: Container(color: Colors.transparent),
                )),
                Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: () => _handleDoubleTap(true),
                  child: Container(color: Colors.transparent),
                )),
              ],
            ),

            // Feedback Animations
            if (_showRewind)
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 50), child: _buildFeedbackIcon(LucideIcons.rewind, "-10s"))),
              if (_showForward)
                Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 50), child: _buildFeedbackIcon(LucideIcons.fastForward, "+10s"))),

                // Custom Controls
                if (_showControls)
                  CustomMobileControls(
                    controller: controller,
                    title: widget.title,
                    onClose: () => Navigator.pop(context),
                    formatDuration: _formatDuration
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackIcon(IconData icon, String text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white.withOpacity(0.8), size: 40), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])
    .animate().scale(duration: 200.ms, curve: Curves.easeOutBack).fadeOut(delay: 300.ms, duration: 300.ms);
  }
}

class CustomMobileControls extends StatefulWidget {
  final VideoController controller;
  final String title;
  final VoidCallback onClose;
  final String Function(Duration) formatDuration;

  const CustomMobileControls({
    super.key,
    required this.controller,
    required this.title,
    required this.onClose,
    required this.formatDuration,
  });

  @override
  State<CustomMobileControls> createState() => _CustomMobileControlsState();
}

class _CustomMobileControlsState extends State<CustomMobileControls> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black54, Colors.transparent, Colors.black54],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Top Bar
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onClose),
                Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
          ),

          const Expanded(child: SizedBox()),

          // Bottom Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    // Current Time
                    StreamBuilder<Duration>(
                      stream: widget.controller.player.stream.position,
                      initialData: widget.controller.player.state.position,
                      builder: (context, snapshot) {
                        final pos = _isDragging ? Duration(seconds: _dragValue.toInt()) : (snapshot.data ?? Duration.zero);
                        return Text(widget.formatDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 12));
                      },
                    ),
                    const SizedBox(width: 10),
                    // Slider
                    Expanded(
                      child: StreamBuilder<Duration>(
                        stream: widget.controller.player.stream.position,
                        initialData: widget.controller.player.state.position,
                        builder: (context, posSnap) {
                          return StreamBuilder<Duration>(
                            stream: widget.controller.player.stream.duration,
                            initialData: widget.controller.player.state.duration,
                            builder: (context, durSnap) {
                              final duration = durSnap.data ?? Duration.zero;
                              final position = posSnap.data ?? Duration.zero;
                              final max = duration.inSeconds.toDouble();
                              final isValid = max > 0;
                              final val = _isDragging ? _dragValue : position.inSeconds.toDouble();

                              return SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                                  activeTrackColor: kColorCoral,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: kColorCoral,
                                  overlayColor: kColorCoral.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: isValid ? val.clamp(0.0, max) : 0.0,
                                  min: 0.0,
                                  max: isValid ? max : 1.0,
                                  onChanged: isValid ? (v) { setState(() { _isDragging = true; _dragValue = v; }); } : null,
                                  onChangeEnd: isValid ? (v) { widget.controller.player.seek(Duration(seconds: v.toInt())); setState(() { _isDragging = false; }); } : null,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Total Time
                    StreamBuilder<Duration>(
                      stream: widget.controller.player.stream.duration,
                      initialData: widget.controller.player.state.duration,
                      builder: (context, snapshot) => Text(widget.formatDuration(snapshot.data ?? Duration.zero), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
                // Play/Pause Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(icon: const Icon(Icons.replay_10, color: Colors.white, size: 32), onPressed: () => widget.controller.player.seek(widget.controller.player.state.position - const Duration(seconds: 10))),
                    StreamBuilder<bool>(
                      stream: widget.controller.player.stream.playing,
                      initialData: widget.controller.player.state.playing,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return CenterPlayButton(
                          isPlaying: isPlaying,
                          onPressed: () => isPlaying ? widget.controller.player.pause() : widget.controller.player.play(),
                        );
                      },
                    ),
                    IconButton(icon: const Icon(Icons.forward_10, color: Colors.white, size: 32), onPressed: () => widget.controller.player.seek(widget.controller.player.state.position + const Duration(seconds: 10))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FANCY PLAY BUTTON ---
class CenterPlayButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  const CenterPlayButton({super.key, required this.isPlaying, required this.onPressed});

  @override
  State<CenterPlayButton> createState() => _CenterPlayButtonState();
}

class _CenterPlayButtonState extends State<CenterPlayButton> with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _iconCtrl;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    if (widget.isPlaying) _iconCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant CenterPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _iconCtrl.forward();
      } else {
        _iconCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing Glow
            if (!widget.isPlaying)
              FadeTransition(
                opacity: TweenSequence([
                  TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.5), weight: 50),
                  TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.0), weight: 50),
                ]).animate(_pulseCtrl),
                child: ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.5).animate(_pulseCtrl),
                  child: Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kColorCoral.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
              // Button Body
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: kColorCoral,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kColorCoral.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Center(
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _iconCtrl,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- VIEWS ---

class BrowseView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  const BrowseView({super.key, required this.onAnimeTap});
  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView>
with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AnimeModel> _animes = [];
  bool _isLoading = true;
  String _currentQuery = "";
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  void _loadTrending() async {
    setState(() => _isLoading = true);
    final results = await AniCore.getTrending();
    if (mounted) {
      setState(() {
        _animes = results;
        _isLoading = false;
      });
    }
  }

  void _doSearch(String query) async {
    if (query.isEmpty) {
      _currentQuery = "";
      _loadTrending();
      return;
    }
    _currentQuery = query;
    setState(() => _isLoading = true);
    final results = await AniCore.search(query);
    if (mounted) {
      setState(() {
        _animes = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 50),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
          child: Row(
            children: [
              if (_currentQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 15),
                  child: IconButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      _currentQuery = "";
                      _doSearch("");
                    },
                    icon: const Icon(LucideIcons.arrowLeftCircle,
                                     color: kColorCoral, size: 32))
                  .animate()
                  .scale()
                  .fadeIn(),
                ),
                Expanded(
                  child: LiquidGlassContainer(
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                          color: kColorDarkText, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: "Search Anime...",
                            hintStyle: TextStyle(color: Colors.black38),
                            border: InputBorder.none,
                            icon: Icon(LucideIcons.search, color: kColorCoral),
                          ),
                          onSubmitted: _doSearch,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuart,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale:
                      Tween<double>(begin: 0.98, end: 1.0).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: kColorCoral))
                : KeyedSubtree(
                  key:
                  ValueKey(_currentQuery.isEmpty ? "Trending" : "Search"),
                  child: _animes.isEmpty
                  ? Center(
                    child: Text("No results found.",
                                style:
                                GoogleFonts.inter(color: Colors.black26)))
                  : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentQuery.isEmpty &&
                          _animes.length > 5) ...[
                            Padding(
                              padding: EdgeInsets.only(
                                left: isMobile ? 20 : 40, bottom: 15),
                                child: Text("Spotlight",
                                            style: GoogleFonts.inter(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: kColorCoral))
                                .animate()
                                .fadeIn(delay: 200.ms),
                            ),
                            FeaturedCarousel(
                              animes: _animes.take(5).toList(),
                              onTap: widget.onAnimeTap),
                              const SizedBox(height: 30),
                          ],
                          Padding(
                            padding: EdgeInsets.only(
                              left: isMobile ? 20 : 40, bottom: 15),
                              child: Text(
                                _currentQuery.isEmpty
                                ? "Trending Now"
                                : "Search Results",
                                style: GoogleFonts.inter(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: kColorDarkText,
                                ),
                              ).animate().fadeIn(delay: 200.ms),
                          ),
                          AnimeGrid(
                            animes: _animes,
                            onTap: widget.onAnimeTap,
                            tagPrefix: "browse",
                          ),
                          const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

class HistoryView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  const HistoryView({super.key, required this.onAnimeTap});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView>
with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final history = context.watch<UserProvider>().history;
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Column(
      children: [
        const SizedBox(height: 60),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Watch History",
                 style: GoogleFonts.inter(
                   fontSize: 32,
                   fontWeight: FontWeight.bold,
                   color: kColorCoral)),
            if (history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: IconButton(
                  icon: const Icon(LucideIcons.trash2,
                                   size: 20, color: kColorDarkText),
                                  onPressed: () => context.read<UserProvider>().clearHistory(),
                ),
              ).animate().scale()
          ],
        ).animate().fadeIn().slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: history.isEmpty
          ? Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.ghost,
                   size: 60, color: kColorCoral.withOpacity(0.5))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .slideY(begin: -0.1, end: 0.1, duration: 2.seconds),
              const SizedBox(height: 10),
              Text("Nothing here yet...",
                   style: GoogleFonts.inter(
                     color: Colors.black45, fontSize: 16)),
            ]),
          )
          : ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 40, vertical: 10),
              physics: const BouncingScrollPhysics(),
              itemCount: history.length,
              itemBuilder: (ctx, i) {
                final item = history[i];
                return HistoryCard(
                  item: item,
                  onTap: () => widget.onAnimeTap(
                    item.anime, "history_${item.anime.id}"),
                )
                .animate(delay: (i * 100).ms)
                .slideX(
                  begin: 0.2,
                  end: 0,
                  curve: Curves.easeOutCubic,
                  duration: 500.ms,
                )
                .fadeIn(duration: 400.ms);
              },
          ),
        ),
      ],
    );
  }
}

class FavoritesView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  const FavoritesView({super.key, required this.onAnimeTap});
  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView>
with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final favorites = context.watch<UserProvider>().favorites;
    return Column(
      children: [
        const SizedBox(height: 60),
        Text("Favorites",
             style: GoogleFonts.inter(
               fontSize: 32,
               fontWeight: FontWeight.bold,
               color: kColorCoral))
        .animate()
        .fadeIn()
        .slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: favorites.isEmpty
          ? Center(
            child: Text("No favorites yet!",
                        style: GoogleFonts.inter(color: Colors.black26)),
          )
          : AnimeGrid(
            animes: favorites,
            onTap: widget.onAnimeTap,
            physics: const BouncingScrollPhysics(),
            shrinkWrap: false,
            tagPrefix: "fav",
          ),
        ),
      ],
    );
  }
}

// --- SETTINGS VIEW ---
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  int _tapCount = 0;
  final String _githubUrl = "https://github.com/minhmc2007/AniCli-Flutter";
  final String _rickRollUrl = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not launch $url"),
            backgroundColor: kColorCoral,
          ),
        );
      }
    }
  }

  void _handleEasterEgg() {
    setState(() {
      _tapCount++;
    });

    if (_tapCount >= 7) {
      _tapCount = 0;
      _launchUrl(_rickRollUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🎵 Never gonna give you up..."),
          backgroundColor: kColorCoral,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final settingsProvider = context.watch<SettingsProvider>();

    final List<Widget> settingsItems = [
      _buildSectionTitle("General"),
      // Check for Updates
      _buildSettingCard(
        icon: LucideIcons.downloadCloud,
        title: "Check for Updates",
        subtitle: "Version Check via GitHub Releases",
        onTap: () => UpdaterService.checkAndUpdate(context),
      ),
      const SizedBox(height: 10),
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
        _buildSwitchTile(
          icon: LucideIcons.playCircle,
          title: "Use Internal Player",
          subtitle: "Use built-in player instead of System MPV (Debug)",
          value: settingsProvider.useInternalPlayer,
          onChanged: (val) => settingsProvider.toggleInternalPlayer(val),
        ),

        const SizedBox(height: 15),

        _buildSectionTitle("Development"),
        _buildSettingCard(
          icon: LucideIcons.user,
          title: "Developer",
          subtitle: "minhmc2007",
          onTap: () {},
        ),
        const SizedBox(height: 10),
        _buildSettingCard(
          icon: LucideIcons.github,
          title: "GitHub Repository",
          subtitle: "minhmc2007/AniCli-Flutter",
          trailing:
          const Icon(LucideIcons.externalLink, size: 16, color: kColorCoral),
          onTap: () => _launchUrl(_githubUrl),
        ),

        const SizedBox(height: 30),

        _buildSectionTitle("About"),
        LiquidGlassContainer(
          opacity: 0.6,
          child: Column(
            children: [
              _buildListTile(
                icon: LucideIcons.info,
                title: "Version",
                subtitle: "v$kAppVersion",
              ),
              Divider(
                height: 1,
                color: Colors.white.withOpacity(0.5),
                indent: 20,
                endIndent: 20),
                _buildListTile(
                  icon: LucideIcons.hash,
                  title: "Build Number",
                  subtitle: kBuildNumber,
                  onTap: _handleEasterEgg,
                ),
            ],
          ),
        ),
        const SizedBox(height: 100),
    ];

    return Column(
      children: [
        const SizedBox(height: 60),
        Text("Settings",
             style: GoogleFonts.inter(
               fontSize: 32,
               fontWeight: FontWeight.bold,
               color: kColorCoral))
        .animate()
        .fadeIn()
        .slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 40, vertical: 10),
              itemCount: settingsItems.length,
              itemBuilder: (context, index) {
                return settingsItems[index]
                .animate(delay: (index * 100).ms)
                .slideX(
                  begin: 0.2,
                  end: 0,
                  curve: Curves.easeOutCubic,
                  duration: 500.ms,
                )
                .fadeIn(duration: 400.ms);
              },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 10, top: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: kColorDarkText.withOpacity(0.6),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return LiquidGlassContainer(
      opacity: 0.6,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: kColorCoral,
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kColorCoral.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: kColorCoral, size: 24),
        ),
        title: Text(title,
                    style:
                    GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(subtitle,
                                   style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
                                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kColorCoral.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kColorCoral, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                         style: GoogleFonts.inter(
                           fontWeight: FontWeight.bold, fontSize: 16)),
                           Text(subtitle,
                                style: GoogleFonts.inter(
                                  color: Colors.black54, fontSize: 13)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: kColorDarkText.withOpacity(0.7), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            Text(subtitle,
                 style: GoogleFonts.inter(
                   color: kColorCoral,
                   fontWeight: FontWeight.bold,
                   fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// --- RESPONSIVE DETAIL VIEW ---
class AnimeDetailView extends StatefulWidget {
  final AnimeModel anime;
  final String heroTag;

  const AnimeDetailView(
    {super.key, required this.anime, required this.heroTag});

  @override
  State<AnimeDetailView> createState() => _AnimeDetailViewState();
}

class _AnimeDetailViewState extends State<AnimeDetailView> {
  List<String> _episodes = [];
  bool _isLoading = true;
  String? _loadingStatus;
  bool _isDownloadMode = false;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  void _loadEpisodes() async {
    final eps = await AniCore.getEpisodes(widget.anime.id);
    if (mounted) {
      setState(() {
        _episodes = eps;
        _isLoading = false;
      });
    }
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  Future<void> _handleEpisodeTap(String epNum) async {
    if (_isDownloadMode) {
      if (Platform.isAndroid || Platform.isIOS) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Download unavailable on mobile yet.")));
        }
        return;
      }
      setState(() => _loadingStatus = "Preparing Download...");
      final url = await AniCore.getStreamUrl(widget.anime.id, epNum);
      setState(() => _loadingStatus = null);
      if (url != null) {
        String safeName = "${widget.anime.name}-EP$epNum"
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
        AniCore.downloadEpisode(url, safeName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Downloading Episode $epNum via Aria2c..."),
            backgroundColor: kColorCoral));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Download link not found")));
        }
      }
    } else {
      setState(() => _loadingStatus = "Fetching Stream...");
      context.read<UserProvider>().addToHistory(widget.anime, epNum);
      final url = await AniCore.getStreamUrl(widget.anime.id, epNum);
      setState(() => _loadingStatus = null);

      if (url != null) {
        final useInternal = context.read<SettingsProvider>().useInternalPlayer;
        if (!useInternal && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
          final savedSeconds = context.read<ProgressProvider>().getProgress(widget.anime.id, epNum);
          bool shouldResume = false;

          if (savedSeconds > 10) {
            shouldResume = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: kColorCream,
                title: const Text("Resume Watching?", style: TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)),
                content: Text("Continue from ${Duration(seconds: savedSeconds).toString().split('.').first}?"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Start Over", style: TextStyle(color: Colors.black54))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Resume")
                  ),
                ],
              ),
            ) ?? false;
          }

          final args = [
            url,
            '--http-header-fields=Referer: ${AniCore.referer}',
            '--force-media-title=${widget.anime.name} - Ep $epNum',
            '--save-position-on-quit',
          ];

          if (shouldResume) {
            args.add('--start=$savedSeconds');
          }

          try {
            await Process.start('mpv', args, mode: ProcessStartMode.detached);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not launch external MPV: $e")));
            }
          }
        }
        else {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, anim, secAnim) => InternalPlayerScreen(
                streamUrl: url,
                title: "${widget.anime.name} - Ep $epNum",
                animeId: widget.anime.id,
                epNum: epNum,
              ),
              transitionsBuilder: (context, anim, secAnim, child) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                );
              },
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Stream not found")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      body: LiveGradientBackground(
        child: Stack(
          children: [
            isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
            if (_loadingStatus != null)
              Positioned.fill(
                child: LiquidGlassContainer(
                  blur: 20,
                  opacity: 0.8,
                  borderRadius: BorderRadius.zero,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: kColorCoral),
                      const SizedBox(height: 20),
                      Text(_loadingStatus!,
                           style: const TextStyle(
                             fontSize: 18,
                             color: kColorCoral,
                             fontWeight: FontWeight.bold))
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 350,
          height: double.infinity,
          padding: const EdgeInsets.all(40),
          child: Column(children: [
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircleBtn(LucideIcons.arrowLeft, _onBack),
                _buildCircleBtn(
                  isFav ? LucideIcons.heart : LucideIcons.heart,
                  () => context
                  .read<UserProvider>()
                  .toggleFavorite(widget.anime),
                  color: isFav ? kColorCoral : Colors.black26,
                  fill: isFav,
                ),
              ]),
              const SizedBox(height: 30),
              CozyHeroImage(
                heroTag: widget.heroTag,
                imageUrl: widget.anime.fullImageUrl,
                radius: 25,
              ),
              const SizedBox(height: 25),
              // Title Hero Text
              Hero(
                tag: "title_${widget.heroTag}",
                child: Material(
                  color: Colors.transparent,
                  child: Text(widget.anime.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: kColorDarkText)),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 80, right: 40, bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Episodes",
                         style: GoogleFonts.inter(
                           fontSize: 32,
                           fontWeight: FontWeight.bold,
                           color: kColorCoral))
                    .animate()
                    .fadeIn()
                    .slideY(begin: -0.5, end: 0),
                    MorphingDownloadButton(
                      isDownloading: _isDownloadMode,
                      onToggle: () => setState(
                        () => _isDownloadMode = !_isDownloadMode),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Expanded(child: _buildEpisodeGrid()),
              ]),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id);
    // FIX: Fixed height for mobile header to ensure consistency across all image sizes
    final headerHeight = MediaQuery.of(context).size.height * 0.55;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: headerHeight,
            child: Stack(
              fit: StackFit.expand, // Force children to fill the height
              children: [
                CozyHeroImage(
                  heroTag: widget.heroTag,
                  imageUrl: widget.anime.fullImageUrl,
                  radius: 0,
                  boxFit: BoxFit.cover, // Ensure image zooms to fill
                ),
                // Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildCircleBtn(LucideIcons.arrowLeft, _onBack),
                      _buildCircleBtn(
                        isFav ? LucideIcons.heart : LucideIcons.heart,
                        () => context
                        .read<UserProvider>()
                        .toggleFavorite(widget.anime),
                        color: isFav ? kColorCoral : Colors.black26,
                        fill: isFav,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Hero(
                    tag: "title_${widget.heroTag}",
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.anime.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // Ensure white text on gradient
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Colors.black.withOpacity(0.5),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Episodes",
                     style: GoogleFonts.inter(
                       fontSize: 28,
                       fontWeight: FontWeight.bold,
                       color: kColorCoral)),
                       MorphingDownloadButton(
                         isDownloading: _isDownloadMode,
                         onToggle: () =>
                         setState(() => _isDownloadMode = !_isDownloadMode),
                       ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
          sliver: _isLoading
          ? const SliverToBoxAdapter(
            child: Center(
              child: CircularProgressIndicator(color: kColorCoral)),
          )
          : SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 90,
              childAspectRatio: 1.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                return EpisodeChip(
                  epNum: _episodes[i],
                  isDownloadMode: _isDownloadMode,
                  onTap: () => _handleEpisodeTap(_episodes[i]),
                ).animate().scale(delay: (i * 10).ms, duration: 200.ms);
              },
              childCount: _episodes.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeGrid() {
    return _isLoading
    ? const Center(child: CircularProgressIndicator(color: kColorCoral))
    : GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100,
        childAspectRatio: 1.5,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15),
        itemCount: _episodes.length,
        itemBuilder: (ctx, i) {
          return EpisodeChip(
            epNum: _episodes[i],
            isDownloadMode: _isDownloadMode,
            onTap: () => _handleEpisodeTap(_episodes[i]),
          ).animate().scale(delay: (i * 20).ms, duration: 200.ms);
        },
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap,
                         {Color color = kColorCoral, bool fill = false}) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassContainer(
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, fill: fill ? 1.0 : 0.0),
        ),
      ),
    );
                         }
}

// --- SHARED WIDGETS ---

class MorphingDownloadButton extends StatelessWidget {
  final bool isDownloading;
  final VoidCallback onToggle;

  const MorphingDownloadButton({
    super.key,
    required this.isDownloading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0.0, end: isDownloading ? 1.0 : 0.0),
      builder: (context, t, child) {
        final width = lerpDouble(50, 240, t)!;
        return GestureDetector(
          onTap: onToggle,
          child: Container(
            width: width,
            height: 50,
            decoration: BoxDecoration(
              color: Color.lerp(Colors.white, kColorCoral, t)!,
              borderRadius: BorderRadius.circular(lerpDouble(25, 15, t)!),
              boxShadow: [
                BoxShadow(
                  color: kColorCoral.withOpacity(0.2 + (t * 0.2)),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ],
            ),
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(-20 * t, 0),
                      child: Icon(
                        LucideIcons.download,
                        color: Color.lerp(kColorCoral, Colors.white, t)!,
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(20 * (1.0 - t), 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Container(
                          width: 240,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(LucideIcons.downloadCloud,
                                   color: Colors.white, size: 18),
                                   SizedBox(width: 8),
                                   Text(
                                     "Select Ep to Download",
                                     style: TextStyle(
                                       color: Colors.white,
                                       fontWeight: FontWeight.bold,
                                       fontSize: 13,
                                     ),
                                   ),
                                   SizedBox(width: 5),
                                   Icon(LucideIcons.x,
                                        color: Colors.white70, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimeGrid extends StatelessWidget {
  final List<AnimeModel> animes;
  final Function(AnimeModel, String) onTap;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final String tagPrefix;

  const AnimeGrid({
    super.key,
    required this.animes,
    required this.onTap,
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = true,
    required this.tagPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
      child: GridView.builder(
        physics: physics,
        shrinkWrap: shrinkWrap,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isMobile ? 150 : 180,
          childAspectRatio: 0.7,
          crossAxisSpacing: isMobile ? 15 : 20,
          mainAxisSpacing: isMobile ? 15 : 20,
        ),
        itemCount: animes.length,
        itemBuilder: (ctx, i) {
          final tag = "${tagPrefix}_${animes[i].id}";
          return AnimeCard(
            anime: animes[i],
            heroTag: tag,
            onTap: () => onTap(animes[i], tag),
          )
          .animate(delay: (i * 50).ms)
          .scale(
            begin: const Offset(0.8, 0.8),
            curve: Curves.easeOutBack,
            duration: 400.ms,
          )
          .fadeIn(duration: 300.ms);
        },
      ),
    );
  }
}

// --- ANIME CARD (FIXED: Title Pop & Shadow) ---
class AnimeCard extends StatefulWidget {
  final AnimeModel anime;
  final String heroTag;
  final VoidCallback onTap;

  const AnimeCard({
    super.key,
    required this.anime,
    required this.heroTag,
    required this.onTap,
  });

  @override
  State<AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<AnimeCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        // We do NOT put the hero here, we put it inside the scale logic
        // OR we put the scale logic inside the Hero?
        // Hero can't animate scale transform easily, so we keep AnimatedContainer outside.
        child: AnimatedContainer(
          duration: 200.ms,
          transform: Matrix4.identity()..scale(isHovered ? 1.05 : 1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. IMAGE HERO (with Shadow inside)
              CozyHeroImage(
                heroTag: widget.heroTag,
                imageUrl: widget.anime.fullImageUrl,
                radius: 20,
                // Shadow is handled inside CozyHeroImage to participate in flight
                withShadow: isHovered,
              ),

              // 2. Gradient (Crossfades, not Hero-ed to avoid complex shading issues)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      kColorDarkText.withOpacity(0.8)
                    ],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // 3. TITLE HERO (Prevents text pop)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Hero(
                  tag: "title_${widget.heroTag}",
                  child: Material(
                    color: Colors.transparent,
                    child: Text(
                      widget.anime.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class EpisodeChip extends StatefulWidget {
  final String epNum;
  final bool isDownloadMode;
  final VoidCallback onTap;

  const EpisodeChip({
    super.key,
    required this.epNum,
    required this.isDownloadMode,
    required this.onTap,
  });

  @override
  State<EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<EpisodeChip> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: 150.ms,
          decoration: BoxDecoration(
            color: isHovered ? kColorCoral : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered
              ? kColorCoral
              : (widget.isDownloadMode ? kColorCoral : kColorSoftPink),
              width: widget.isDownloadMode ? 2 : 1,
            ),
            boxShadow: isHovered
            ? [
              BoxShadow(
                color: kColorCoral.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ]
            : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.epNum,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isHovered ? Colors.white : kColorCoral,
                ),
              ),
              if (widget.isDownloadMode && isHovered)
                const Positioned(
                  right: 8,
                  child:
                  Icon(LucideIcons.download, size: 12, color: Colors.white),
                )
            ],
          ),
        ),
      ),
    );
  }
}

// --- HISTORY CARD (FIXED: Rounded Corners) ---
class HistoryCard extends StatefulWidget {
  final HistoryItem item;
  final VoidCallback onTap;

  const HistoryCard({super.key, required this.item, required this.onTap});

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 15),
          height: 90,
          transform: Matrix4.identity()..scale(isHovered ? 1.02 : 1.0),
          child: LiquidGlassContainer(
            opacity: isHovered ? 0.9 : 0.6,
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  // FIX: Set radius to 15 to ensure smooth transition to Detail View
                  child: CozyHeroImage(
                    heroTag: "history_${widget.item.anime.id}",
                    imageUrl: widget.item.anime.fullImageUrl,
                    radius: 15, // Changed from 0 to 15
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.anime.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Episode ${widget.item.episode}",
                        style: GoogleFonts.inter(
                          color: kColorCoral,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(LucideIcons.playCircle,
                              color: kColorCoral, size: 30),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FeaturedCarousel extends StatelessWidget {
  final List<AnimeModel> animes;
  final Function(AnimeModel, String) onTap;

  const FeaturedCarousel(
    {super.key, required this.animes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        scrollDirection: Axis.horizontal,
        itemCount: animes.length,
        itemBuilder: (context, index) {
          final anime = animes[index];
          final tag = "carousel_${anime.id}";

          return GestureDetector(
            onTap: () => onTap(anime, tag),
            child: Container(
              width: 300,
              margin: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: kColorCoral.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CozyHeroImage(
                    heroTag: tag,
                    imageUrl: anime.fullImageUrl,
                    radius: 20,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          kColorDarkText.withOpacity(0.9)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: SizedBox(
                      width: 260,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: kColorCoral,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "HOT",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            anime.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().slideX(
            begin: 0.2,
            end: 0,
            delay: (index * 100).ms,
            curve: Curves.easeOut);
        },
      ),
    );
  }
}

class GlassDock extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const GlassDock({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    final items = [
      (LucideIcons.search, "Browse"),
      (LucideIcons.history, "History"),
      (LucideIcons.heart, "Favorites"),
      (LucideIcons.settings, "Settings")
    ];
    return LiquidGlassContainer(
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(items.length, (index) {
              final isSelected = selectedIndex == index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: IconButton(
                  icon: Icon(
                    items[index].$1,
                    color: isSelected ? kColorCoral : Colors.black38,
                    size: isMobile ? 20 : 24,
                  ),
                  onPressed: () => onItemSelected(index),
                  tooltip: items[index].$2,
                ),
              );
            }),
          ),
      ),
    );
  }
}
