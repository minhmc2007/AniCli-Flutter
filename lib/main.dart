import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:animeclient/api/ani_core.dart';
import 'package:animeclient/user_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
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
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// --- APP CONSTANTS ---
const String kAppVersion = "1.7.4"; // Bumped version for fix
const String kBuildNumber = "174";

// --- THEME COLORS ---
const kColorCream = Color(0xFFFEEAC9);
const kColorPeach = Color(0xFFFFCDC9);
const kColorSoftPink = Color(0xFFFDACAC);
const kColorCoral = Color(0xFFFD7979);
const kColorDarkText = Color(0xFF4A2B2B);

// --- MAIN ENTRY POINT ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final bool isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
      ],
      child: AniCliApp(isFirstLaunch: isFirstLaunch),
    ),
  );
}

// --- APP ROOT ---
class AniCliApp extends StatelessWidget {
  final bool isFirstLaunch;

  const AniCliApp({super.key, required this.isFirstLaunch});

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
      home: isFirstLaunch ? const OnboardingScreen() : const MainScreen(),
    );
  }
}

// ==========================================
//      ONBOARDING SCREEN
// ==========================================
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final List<String> _greetings = ["Welcome", "こんにちは", "AniCli"];
  int _currentIndex = 0;
  Timer? _timer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _startGreetingCycle();
  }

  void _startGreetingCycle() {
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_currentIndex < _greetings.length - 1) {
        setState(() => _currentIndex++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isFinished = true);
    await Future.delayed(const Duration(milliseconds: 2000));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainScreen(),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(opacity: anim, child: child);
          },
          transitionDuration: const Duration(milliseconds: 1000),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8F0), Color(0xFFFEEAC9)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const FloatingOrbsBackground(),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInBack,
                    child: _isFinished ? _buildSetupLoader() : _buildWelcomeContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupLoader() {
    return Column(
      key: const ValueKey("setup"),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            strokeWidth: 5,
            valueColor: const AlwaysStoppedAnimation<Color>(kColorCoral),
            backgroundColor: kColorPeach.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 30),
        Text(
          "Getting things ready...",
          style: GoogleFonts.inter(fontSize: 22, color: kColorDarkText, fontWeight: FontWeight.w600),
        ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
      ],
    );
  }

  Widget _buildWelcomeContent() {
    return Column(
      key: const ValueKey("welcome"),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 100,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
                  child: child,
                ),
              );
            },
            child: Text(
              _greetings[_currentIndex],
              key: ValueKey(_currentIndex),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: kColorDarkText,
                height: 1.0,
                letterSpacing: -1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 50),
        AnimatedOpacity(
          opacity: _currentIndex == _greetings.length - 1 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 800),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            transform: Matrix4.identity()..scale(_currentIndex == _greetings.length - 1 ? 1.0 : 0.9),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: kColorCoral.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _currentIndex == _greetings.length - 1 ? _completeOnboarding : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kColorCoral,
                  foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 22),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Get Started", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const Icon(LucideIcons.arrowRight, size: 20),
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

class FloatingOrbsBackground extends StatelessWidget {
  const FloatingOrbsBackground({super.key});
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: _buildOrb(400, kColorPeach)
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 6.seconds)
          .rotate(begin: 0, end: 0.1, duration: 8.seconds),
        ),
        Positioned(
          bottom: -150,
          left: -100,
          child: _buildOrb(450, kColorCoral.withOpacity(0.4))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 7.seconds)
          .move(begin: Offset.zero, end: const Offset(20, -20), duration: 5.seconds),
        ),
        Align(
          alignment: const Alignment(0, -0.3),
          child: _buildOrb(300, kColorSoftPink.withOpacity(0.3))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1), duration: 5.seconds)
          .fadeIn(),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.transparent),
          ),
        ),
      ],
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
          stops: const [0.4, 1.0],
        ),
      ),
    );
  }
}

// ==========================================
//      SERVICES & PROVIDERS
// ==========================================

class UpdaterService {
  static const String _releaseUrl = "https://api.github.com/repos/minhmc2007/AniCli-Flutter/releases/latest";

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking for updates...")));

      final response = await http.get(Uri.parse(_releaseUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String remoteTag = data['tag_name'];
        String body = data['body'];
        List assets = data['assets'];

        String? cleanCurrent = _extractSemVer(kAppVersion);
        String? cleanRemote = _extractSemVer(remoteTag);

        if (cleanCurrent != null && cleanRemote != null && _isNewer(cleanCurrent, cleanRemote)) {
          if (context.mounted) {
            _showCozyUpdateDialog(context, remoteTag, body, assets);
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("You are up to date! ($kAppVersion)"), backgroundColor: Colors.green));
          }
        }
      } else {
        throw Exception("GitHub API returned ${response.statusCode}");
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Update check failed: $e"), backgroundColor: kColorCoral));
      }
    }
  }

  // Silent check for startup
  static Future<void> checkSilent(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(_releaseUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String remoteTag = data['tag_name'];
        String body = data['body'];
        List assets = data['assets'];

        String? cleanCurrent = _extractSemVer(kAppVersion);
        String? cleanRemote = _extractSemVer(remoteTag);

        if (cleanCurrent != null && cleanRemote != null && _isNewer(cleanCurrent, cleanRemote)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("New Update Available: $remoteTag"),
              backgroundColor: kColorCoral,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: "Update", // Triggers internal dialog
                textColor: Colors.white,
                onPressed: () => _showCozyUpdateDialog(context, remoteTag, body, assets),
              ),
            ));
          }
        }
      }
    } catch (_) {}
  }

  static void _showCozyUpdateDialog(BuildContext context, String version, String notes, List assets) {
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                    spreadRadius: 5,
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
                        decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(LucideIcons.sparkles, color: kColorCoral, size: 24),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("New Version Available",
                                 style: GoogleFonts.inter(
                                   fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)),
                                   Text(version,
                                        style: GoogleFonts.inter(
                                          fontSize: 14, color: kColorCoral, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ).animate().slideY(begin: -0.2, end: 0, duration: 400.ms).fadeIn(),
                  const SizedBox(height: 20),
                  Divider(color: Colors.grey.withOpacity(0.2)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: MarkdownBody(
                        data: notes,
                        styleSheet: MarkdownStyleSheet(
                          p: GoogleFonts.inter(color: kColorDarkText, fontSize: 14),
                          h1: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 20),
                          h2: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 18),
                          h3: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 16),
                          listBullet: GoogleFonts.inter(color: kColorCoral),
                          strong: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kColorCoral),
                          code: GoogleFonts.jetBrainsMono(backgroundColor: Colors.grey.shade100, color: kColorDarkText),
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
                                    style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kColorCoral,
                          foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _performUpdate(context, assets, version);
                        },
                        icon: const Icon(LucideIcons.downloadCloud, size: 18),
                        label: Text("Update Now", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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

  static Future<void> _performUpdate(BuildContext context, List assets, String version) async {
    String? downloadUrl;
    String fileName = "";

    // Platform Specific Asset Matching
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        await Permission.storage.request();
      }

      var installStatus = await Permission.requestInstallPackages.status;
      if (!installStatus.isGranted) {
        installStatus = await Permission.requestInstallPackages.request();
        if (!installStatus.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Permission denied. Cannot install updates without 'Install Unknown Apps' permission.")));
          }
          return;
        }
      }

      final asset = assets.firstWhere((a) => a['name'].toString().endsWith('.apk'), orElse: () => null);
      downloadUrl = asset?['browser_download_url'];
      fileName = "AniCli_$version.apk";
    } else if (Platform.isWindows) {
      final asset = assets.firstWhere(
        (a) => a['name'].toString().endsWith('.zip') || a['name'].toString().endsWith('.exe'),
        orElse: () => null);
      downloadUrl = asset?['browser_download_url'];
      fileName = "AniCli_$version.zip";
    } else if (Platform.isLinux) {
      final asset = assets.firstWhere(
        (a) => a['name'].toString().endsWith('.tar.gz') || a['name'].toString().endsWith('.AppImage'),
        orElse: () => null);
      downloadUrl = asset?['browser_download_url'];
      fileName = "AniCli_$version.tar.gz";
    } else {
      launchUrl(Uri.parse("https://github.com/minhmc2007/AniCli-Flutter/releases/latest"),
      mode: LaunchMode.externalApplication);
      return;
    }

    if (downloadUrl == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No compatible asset found.")));
      }
      return;
    }

    if (!context.mounted) return;

    // Show Custom Download Dialog
    final File? downloadedFile = await showDialog<File?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDownloadingDialog(
        downloadUrl: downloadUrl!,
        fileName: fileName,
      ),
    );

    if (downloadedFile != null) {
      if (Platform.isAndroid) {
        final result = await OpenFile.open(downloadedFile.path, type: "application/vnd.android.package-archive");

        if (result.type != ResultType.done) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Install Error: ${result.message}")));
          }
        }
      } else {
        if (Platform.isWindows || Platform.isLinux) {
          // Open the directory so user can extract/run
          await launchUrl(Uri.directory(downloadedFile.parent.path));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Update downloaded. Please extract/install manually."), duration: Duration(seconds: 5)));
          }
        }
      }
    }
  }
}

// --- SMOOTH DOWNLOAD DIALOG ---
class UpdateDownloadingDialog extends StatefulWidget {
  final String downloadUrl;
  final String fileName;

  const UpdateDownloadingDialog({
    super.key,
    required this.downloadUrl,
    required this.fileName,
  });

  @override
  State<UpdateDownloadingDialog> createState() => _UpdateDownloadingDialogState();
}

class _UpdateDownloadingDialogState extends State<UpdateDownloadingDialog> {
  double _progress = 0.0;
  String _status = "Initializing...";
  String _sizeInfo = "";
  final http.Client _client = http.Client();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      String savePath = "${dir.path}/${widget.fileName}";

      if (Platform.isAndroid) {
        final tempDir = await getExternalStorageDirectory();
        if (tempDir != null) savePath = "${tempDir.path}/${widget.fileName}";
      }

      final file = File(savePath);
      final request = http.Request('GET', Uri.parse(widget.downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception("Server responded with ${response.statusCode}");
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      final List<int> bytes = [];
      response.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          received += newBytes.length;
          if (contentLength > 0) {
            setState(() {
              _progress = received / contentLength;
              _status = "Downloading...";
              _sizeInfo =
              "${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(contentLength / 1024 / 1024).toStringAsFixed(1)} MB";
            });
          }
        },
        onDone: () async {
          await file.writeAsBytes(bytes);
          if (mounted) {
            Navigator.pop(context, file);
          }
        },
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download error: $e")));
            Navigator.pop(context, null);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Download failed: $e"), backgroundColor: kColorCoral));
        Navigator.pop(context, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kColorCoral.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.download, color: kColorCoral, size: 32)
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 1500.ms, color: Colors.white)
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.1, 1.1),
                    duration: 1000.ms,
                    curve: Curves.easeInOut)
                  .then()
                  .scale(
                    begin: const Offset(1.1, 1.1),
                    end: const Offset(1, 1),
                    curve: Curves.easeInOut),
                ),
                const SizedBox(height: 20),
                Text("Updating App",
                     style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)),
                     const SizedBox(height: 5),
                     Text(_status, style: GoogleFonts.inter(fontSize: 14, color: Colors.black54)),
                     const SizedBox(height: 20),
                     TweenAnimationBuilder<double>(
                       tween: Tween<double>(begin: 0, end: _progress),
                       duration: const Duration(milliseconds: 200),
                       curve: Curves.easeInOut,
                       builder: (context, value, _) {
                         return Column(
                           children: [
                             ClipRRect(
                               borderRadius: BorderRadius.circular(10),
                               child: LinearProgressIndicator(
                                 value: value,
                                 backgroundColor: Colors.grey.shade200,
                                 valueColor: const AlwaysStoppedAnimation<Color>(kColorCoral),
                                 minHeight: 8,
                               ),
                             ),
                             const SizedBox(height: 10),
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 Text("${(value * 100).toInt()}%",
                                 style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: kColorCoral)),
                                 Text(_sizeInfo, style: GoogleFonts.inter(fontSize: 12, color: Colors.black45)),
                               ],
                             )
                           ],
                         );
                       },
                     ),
                     const SizedBox(height: 25),
                     SizedBox(
                       width: double.infinity,
                       child: OutlinedButton(
                         style: OutlinedButton.styleFrom(
                           side: const BorderSide(color: kColorCoral),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           foregroundColor: kColorCoral,
                         ),
                         onPressed: () {
                           _client.close();
                           Navigator.pop(context, null);
                         },
                         child: const Text("Cancel"),
                       ),
                     ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn().scale(curve: Curves.easeOutBack),
    );
  }
}

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

// ==========================================
//      COMMON WIDGETS
// ==========================================

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
            border: border ?? Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: boxFit,
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

class LiveGradientBackground extends StatefulWidget {
  final Widget child;
  const LiveGradientBackground({super.key, required this.child});
  @override
  State<LiveGradientBackground> createState() => _LiveGradientBackgroundState();
}

class _LiveGradientBackgroundState extends State<LiveGradientBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Alignment> _topAlignmentAnimation;
  late Animation<Alignment> _bottomAlignmentAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(reverse: true);

    _topAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1),
    ]).animate(_controller);

    _bottomAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1),
      TweenSequenceItem(tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1),
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

// ==========================================
//      MAIN SCREEN LOGIC
// ==========================================
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
        pageBuilder: (context, animation, secondaryAnimation) => AnimeDetailView(anime: anime, heroTag: heroTag),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Check for updates silently on startup
    UpdaterService.checkSilent(context);
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
                        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
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

// ==========================================
//      MANGA READER SCREEN (IMPROVED ZOOM & SCROLL & HISTORY)
// ==========================================
class MangaReaderScreen extends StatefulWidget {
  final AnimeModel anime; // Changed to accept full AnimeModel for history
  final String chapterNum;
  final List<String> allChapters;

  const MangaReaderScreen({
    super.key,
    required this.anime,
    required this.chapterNum,
    required this.allChapters,
  });

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  bool _isLoading = true;
  List<String> _pages = [];
  final TransformationController _transformController = TransformationController();
  final ScrollController _scrollController = ScrollController();
  bool _showControls = true;
  bool _isCtrlPressed = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    setState(() => _isLoading = true);
    final pages = await MangaCore.getPages(widget.chapterNum);
    if (mounted) {
      setState(() {
        _pages = pages;
        _isLoading = false;
      });
    }
  }

  void _navigateToChapter(String newChap) {
    // FIX: Update history before navigating
    context.read<UserProvider>().addToHistory(widget.anime, newChap);

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MangaReaderScreen(
          anime: widget.anime,
          chapterNum: newChap,
          allChapters: widget.allChapters,
        ),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ));
  }

  Future<void> _downloadImage(String url, int index) async {
    try {
      final response = await http.get(Uri.parse(url), headers: {"User-Agent": "AniCli/1.0"});
      if (response.statusCode == 200) {
        Directory? dir;
        if (Platform.isAndroid) {
          dir = await getExternalStorageDirectory();
        } else {
          dir = await getDownloadsDirectory();
        }

        final safeTitle = widget.anime.name.replaceAll(RegExp(r'[^\w\s]+'), '');
        final savePath = "${dir?.path}/$safeTitle/Ch${widget.chapterNum}/page_$index.jpg";
        final file = File(savePath);
        await file.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved page $index to $savePath")));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving image: $e")));
      }
    }
  }

  String _displayChapter(String raw) {
    if (raw.contains("|")) return raw.split("|")[1];
    return raw;
  }

  void _handleKey(KeyEvent event) {
    final bool isCtrl = event.logicalKey == LogicalKeyboardKey.controlLeft ||
    event.logicalKey == LogicalKeyboardKey.controlRight;

    if (isCtrl) {
      setState(() {
        _isCtrlPressed = event is KeyDownEvent || event is KeyRepeatEvent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.allChapters.indexOf(widget.chapterNum);
    final hasNext = currentIndex > 0;
    final hasPrev = currentIndex < widget.allChapters.length - 1;

    // Enable InteractiveViewer's scaling IF:
    // 1. Control key is pressed (for mouse wheel zoom)
    // 2. OR pointer count > 1 (for touch pinch zoom)
    final bool enableScaling = _isCtrlPressed || _pointerCount > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            // MAIN READER AREA
            Listener(
              onPointerDown: (_) => setState(() => _pointerCount++),
              onPointerUp: (_) => setState(() => _pointerCount--),
              onPointerCancel: (_) => setState(() => _pointerCount = 0),
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  debugPrint("[MangaReader] Event caught: ${event.scrollDelta}");
                  debugPrint("[MangaReader] Ctrl Pressed: $_isCtrlPressed");

                  if (_isCtrlPressed) {
                    debugPrint("[MangaReader] Mode: ZOOMING (Ctrl held)");

                    // --- CENTERED ZOOM LOGIC ---
                    // This calculates the zoom relative to the center of the screen
                    // preventing the content from drifting to the left/top-left corner.

                    final double scaleFactor = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
                    final Matrix4 currentMatrix = _transformController.value;
                    final double currentScale = currentMatrix.getMaxScaleOnAxis();
                    final double newScale = (currentScale * scaleFactor).clamp(0.1, 5.0);

                    if (newScale >= 0.1 && newScale <= 5.0) {
                      final Size screenSize = MediaQuery.of(context).size;
                      final Offset center = Offset(screenSize.width / 2, screenSize.height / 2);

                      // Create a matrix that scales around the center point
                      // T_new = Translate(C) * Scale(S) * Translate(-C) * T_old
                      final Matrix4 zoomMatrix = Matrix4.identity()
                      ..translate(center.dx, center.dy)
                      ..scale(scaleFactor)
                      ..translate(-center.dx, -center.dy);

                      _transformController.value = zoomMatrix * currentMatrix;
                    }
                  } else {
                    debugPrint("[MangaReader] Mode: SCROLLING (No Ctrl)");
                    // MANUAL SCROLL LOGIC
                    if (_scrollController.hasClients) {
                      final double newOffset = _scrollController.offset + event.scrollDelta.dy;
                      final double validOffset = newOffset.clamp(
                        _scrollController.position.minScrollExtent,
                        _scrollController.position.maxScrollExtent
                      );
                      _scrollController.jumpTo(validOffset);
                    }
                  }
                }
              },
              child: GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kColorCoral))
                : InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.1,
                  maxScale: 5.0,
                  scaleEnabled: enableScaling,
                  panEnabled: true,
                  trackpadScrollCausesScale: false,
                  interactionEndFrictionCoefficient: 0.00001,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    cacheExtent: 3000,
                    itemCount: _pages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _pages.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (hasPrev)
                                ElevatedButton(
                                  onPressed: () => _navigateToChapter(widget.allChapters[currentIndex + 1]),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                                  child: const Text("Previous Chapter", style: TextStyle(color: Colors.white)),
                                ),
                                if (hasNext)
                                  ElevatedButton(
                                    onPressed: () => _navigateToChapter(widget.allChapters[currentIndex - 1]),
                                    style: ElevatedButton.styleFrom(backgroundColor: kColorCoral),
                                    child: const Text("Next Chapter", style: TextStyle(color: Colors.white)),
                                  ),
                            ],
                          ),
                        );
                      }
                      return GestureDetector(
                        onLongPress: () => _downloadImage(_pages[index], index + 1), // Mobile
                        onSecondaryTap: () => _downloadImage(_pages[index], index + 1), // PC
                        child: Container(
                          // Explicitly Center content to fix "Left Align" issue
                          alignment: Alignment.center,
                          color: Colors.black, // Fill void with black
                          child: CachedNetworkImage(
                            imageUrl: _pages[index],
                            fit: BoxFit.contain,
                            width: double.infinity,
                            // Ensure image itself is centered in its container
                            alignment: Alignment.center,
                            placeholder: (context, url) => const SizedBox(
                              height: 300, child: Center(child: CircularProgressIndicator(color: kColorCoral, strokeWidth: 2))),
                              errorWidget: (context, url, error) => const SizedBox(
                                height: 200, child: Center(child: Icon(Icons.broken_image, color: Colors.white54))),
                                httpHeaders: const {"User-Agent": "AniCli/1.0"},
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.anime.name,
                                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1),
                                 Text("Chapter ${_displayChapter(widget.chapterNum)}",
                                 style: const TextStyle(color: kColorCoral, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
//      VIDEO PLAYER SCREEN (UPDATED)
// ==========================================
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
  late ProgressProvider _progressProvider;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  StreamSubscription? _durationSubscription;
  bool _showForward = false;
  bool _showRewind = false;
  bool _resumeChecked = false;

  @override
  void initState() {
    super.initState();
    player = Player(configuration: const PlayerConfiguration(vo: 'gpu'));

    controller = VideoController(player,
                                 configuration: const VideoControllerConfiguration(
                                   enableHardwareAcceleration: true,
                                   androidAttachSurfaceAfterVideoParameters: true,
                                 ));

    _durationSubscription = player.stream.duration.listen((duration) {
      if (!_resumeChecked && duration.inSeconds > 0) {
        _resumeChecked = true;
        _checkResume();
      }
    });

    player.open(Media(widget.streamUrl, httpHeaders: {'Referer': AniCore.referer}));
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final pos = player.state.position.inSeconds;
      if (pos > 10) {
        context.read<ProgressProvider>().saveProgress(widget.animeId, widget.epNum, pos);
      }
    });

    player.play();
    player.setVolume(100);
    _startHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progressProvider = Provider.of<ProgressProvider>(context, listen: false);
  }

  Future<void> _checkResume() async {
    if (!mounted) return;
    final savedSeconds = _progressProvider.getProgress(widget.animeId, widget.epNum);

    if (savedSeconds > 10) {
      await player.pause();
      if (!mounted) return;
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

      if (!mounted) return;
      if (shouldResume == true) {
        await player.seek(Duration(seconds: savedSeconds));
      }
      await player.play();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
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
    final newPos = isForward ? current + const Duration(seconds: 10) : current - const Duration(seconds: 10);
    player.seek(newPos);
    setState(() {
      if (isForward)
        _showForward = true;
      else
        _showRewind = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showForward = false;
          _showRewind = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    player.stop();
    try {
      final pos = player.state.position.inSeconds;
      if (pos > 10) {
        _progressProvider.saveProgress(widget.animeId, widget.epNum, pos);
      }
    } catch (e) {
      debugPrint("Error saving progress in dispose: $e");
    }
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
            Video(
              controller: controller,
              controls: NoVideoControls,
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _handleDoubleTap(false),
                    child: Container(color: Colors.transparent))),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _handleDoubleTap(true),
                        child: Container(color: Colors.transparent))),
              ],
            ),
            if (_showRewind)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 50), child: _buildFeedbackIcon(LucideIcons.rewind, "-10s"))),
                  if (_showForward)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 50),
                        child: _buildFeedbackIcon(LucideIcons.fastForward, "+10s"))),
                        if (_showControls)
                          CustomMobileControls(
                            controller: controller,
                            title: widget.title,
                            onClose: () => Navigator.pop(context),
                            formatDuration: _formatDuration),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackIcon(IconData icon, String text) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white.withOpacity(0.8), size: 40),
      Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
    ]).animate().scale(duration: 200.ms, curve: Curves.easeOutBack).fadeOut(delay: 300.ms, duration: 300.ms);
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
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onClose),
                Expanded(
                  child: Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
          ),
          const Expanded(child: SizedBox()),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    StreamBuilder<Duration>(
                      stream: widget.controller.player.stream.position,
                      initialData: widget.controller.player.state.position,
                      builder: (context, snapshot) {
                        final pos = _isDragging ? Duration(seconds: _dragValue.toInt()) : (snapshot.data ?? Duration.zero);
                        return Text(widget.formatDuration(pos), style: const TextStyle(color: Colors.white, fontSize: 12));
                      },
                    ),
                    const SizedBox(width: 10),
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
                                  onChanged: isValid
                                  ? (v) {
                                    setState(() {
                                      _isDragging = true;
                                      _dragValue = v;
                                    });
                                  }
                                  : null,
                                  onChangeEnd: isValid
                                  ? (v) {
                                    widget.controller.player.seek(Duration(seconds: v.toInt()));
                                    setState(() {
                                      _isDragging = false;
                                    });
                                  }
                                  : null,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    StreamBuilder<Duration>(
                      stream: widget.controller.player.stream.duration,
                      initialData: widget.controller.player.state.duration,
                      builder: (context, snapshot) => Text(widget.formatDuration(snapshot.data ?? Duration.zero),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                      onPressed: () => widget.controller.player
                      .seek(widget.controller.player.state.position - const Duration(seconds: 10))),
                      StreamBuilder<bool>(
                        stream: widget.controller.player.stream.playing,
                        initialData: widget.controller.player.state.playing,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data ?? false;
                          return CenterPlayButton(
                            isPlaying: isPlaying,
                            onPressed: () =>
                            isPlaying ? widget.controller.player.pause() : widget.controller.player.play(),
                          );
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                      onPressed: () => widget.controller.player
                      .seek(widget.controller.player.state.position + const Duration(seconds: 10))),
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
            if (!widget.isPlaying)
              FadeTransition(
                opacity: TweenSequence([
                  TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.5), weight: 50),
                  TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.0), weight: 50),
                ]).animate(_pulseCtrl),
                child: ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.5).animate(_pulseCtrl),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kColorCoral.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
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

// ==========================================
//      VIEWS
// ==========================================

class BrowseView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  const BrowseView({super.key, required this.onAnimeTap});
  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AnimeModel> _items = [];
  bool _isLoading = true;
  String _currentQuery = "";

  // -- MANGA TOGGLE --
  bool _isMangaMode = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    setState(() => _isLoading = true);
    List<AnimeModel> results;

    if (_isMangaMode) {
      if (_currentQuery.isEmpty) {
        results = await MangaCore.getTrending();
      } else {
        results = await MangaCore.search(_currentQuery);
      }
    } else {
      if (_currentQuery.isEmpty) {
        results = await AniCore.getTrending();
      } else {
        results = await AniCore.search(_currentQuery);
      }
    }

    if (mounted) {
      setState(() {
        _items = results;
        _isLoading = false;
      });
    }
  }

  void _doSearch(String query) {
    _currentQuery = query;
    _loadData();
  }

  void _toggleMode(bool isManga) {
    if (_isMangaMode == isManga) return;
    setState(() {
      _isMangaMode = isManga;
      _items.clear();
      _currentQuery = "";
      _searchCtrl.clear();
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 50),

        // --- TOGGLE BUTTONS ---
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
          child: Row(
            children: [
              _buildTypeToggle("Anime", false),
              const SizedBox(width: 15),
              _buildTypeToggle("Manga", true),
            ],
          ),
        ),

        const SizedBox(height: 15),

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
                      _doSearch("");
                    },
                    icon: const Icon(LucideIcons.arrowLeftCircle, color: kColorCoral, size: 32)
                  ).animate().scale().fadeIn(),
                ),
                Expanded(
                  child: LiquidGlassContainer(
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: kColorDarkText, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: _isMangaMode ? "Search Manga..." : "Search Anime...",
                          hintStyle: const TextStyle(color: Colors.black38),
                          border: InputBorder.none,
                          icon: const Icon(LucideIcons.search, color: kColorCoral),
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
                      scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kColorCoral))
                : KeyedSubtree(
                  key: ValueKey("Grid_$_isMangaMode$_currentQuery"),
                  child: _items.isEmpty
                  ? Center(child: Text("No results found.", style: GoogleFonts.inter(color: Colors.black26)))
                  : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentQuery.isEmpty) ...[
                          if (!_isMangaMode && _items.length > 5) ...[
                            Padding(
                              padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15),
                              child: Text("Spotlight", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorCoral)).animate().fadeIn(delay: 200.ms),
                            ),
                            FeaturedCarousel(animes: _items.take(5).toList(), onTap: widget.onAnimeTap),
                            const SizedBox(height: 30),
                          ] else if (_isMangaMode) ...[
                            SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: Stack(
                                children: [
                                  const Positioned.fill(child: FloatingOrbsBackground()),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text("MangaDex", style: GoogleFonts.outfit(fontSize: 40, fontWeight: FontWeight.bold, color: kColorDarkText)),
                                        Text("Read the world's library", style: GoogleFonts.inter(fontSize: 16, color: kColorDarkText.withOpacity(0.6))),
                                      ],
                                    ).animate().slideY(begin: 0.2, end: 0).fadeIn(),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ],

                        Padding(
                          padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15),
                          child: Text(
                            _currentQuery.isEmpty
                            ? (_isMangaMode ? "Popular Updates" : "Trending Anime")
                            : "Results",
                            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorDarkText),
                          ).animate().fadeIn(delay: 200.ms),
                        ),
                        AnimeGrid(animes: _items, onTap: widget.onAnimeTap, tagPrefix: "browse"),
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

  Widget _buildTypeToggle(String label, bool isMangaBtn) {
    final isActive = _isMangaMode == isMangaBtn;
    return GestureDetector(
      onTap: () => _toggleMode(isMangaBtn),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? kColorCoral : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive ? [BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 10)] : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : kColorDarkText.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

class HistoryView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  const HistoryView({super.key, required this.onAnimeTap});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> with AutomaticKeepAliveClientMixin {
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
            Text("History",
                 style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)),
                 if (history.isNotEmpty)
                   Padding(
                     padding: const EdgeInsets.only(left: 10),
                     child: IconButton(
                       icon: const Icon(LucideIcons.trash2, size: 20, color: kColorDarkText),
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
              Icon(LucideIcons.ghost, size: 60, color: kColorCoral.withOpacity(0.5))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .slideY(begin: -0.1, end: 0.1, duration: 2.seconds),
              const SizedBox(height: 10),
              Text("Nothing here yet...", style: GoogleFonts.inter(color: Colors.black45, fontSize: 16)),
            ]),
          )
          : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: history.length,
            itemBuilder: (ctx, i) {
              final item = history[i];
              return HistoryCard(
                item: item,
                onTap: () => widget.onAnimeTap(item.anime, "history_${item.anime.id}"),
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

class _FavoritesViewState extends State<FavoritesView> with AutomaticKeepAliveClientMixin {
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
             style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral))
        .animate()
        .fadeIn()
        .slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: favorites.isEmpty
          ? Center(
            child: Text("No favorites yet!", style: GoogleFonts.inter(color: Colors.black26)),
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

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final String _githubUrl = "https://github.com/minhmc2007/AniCli-Flutter";

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not launch $url"), backgroundColor: kColorCoral),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final settingsProvider = context.watch<SettingsProvider>();

    final List<Widget> settingsItems = [
      _buildSectionTitle("General"),
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
          icon: LucideIcons.github,
          title: "GitHub Repository",
          subtitle: "minhmc2007/AniCli-Flutter",
          trailing: const Icon(LucideIcons.externalLink, size: 16, color: kColorCoral),
          onTap: () => _launchUrl(_githubUrl),
        ),
        const SizedBox(height: 10),
        _buildSettingCard(
          icon: LucideIcons.rotateCcw,
          title: "Reset Welcome Screen",
          subtitle: "Reset OOBE flag for testing",
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('is_first_launch');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Reset! Restart the app to see the Welcome Screen."), backgroundColor: kColorCoral));
            }
          },
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
              Divider(height: 1, color: Colors.white.withOpacity(0.5), indent: 20, endIndent: 20),
              _buildListTile(
                icon: LucideIcons.hash,
                title: "Build Number",
                subtitle: kBuildNumber,
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
             style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral))
        .animate()
        .fadeIn()
        .slideY(begin: -0.5, end: 0),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 10),
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
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
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
                    Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
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
              child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            Text(subtitle,
                 style: GoogleFonts.inter(color: kColorCoral, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
//      DETAIL VIEW
// ==========================================
class AnimeDetailView extends StatefulWidget {
  final AnimeModel anime;
  final String heroTag;

  const AnimeDetailView({super.key, required this.anime, required this.heroTag});

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
    _loadData();
  }

  void _loadData() async {
    List<String> items;
    if (widget.anime.isManga) {
      items = await MangaCore.getChapters(widget.anime.id);
    } else {
      items = await AniCore.getEpisodes(widget.anime.id);
    }

    if (mounted) {
      setState(() {
        _episodes = items;
        _isLoading = false;
      });
    }
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  Future<void> _handleItemTap(String idNum) async {
    // --- MANGA LOGIC ---
    if (widget.anime.isManga) {
      context.read<UserProvider>().addToHistory(widget.anime, idNum);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => MangaReaderScreen(
            anime: widget.anime, // Pass full object for history to work on next/prev
            chapterNum: idNum,
            allChapters: _episodes,
          )));
      return;
    }

    // --- ANIME LOGIC ---
    if (_isDownloadMode) {
      if (Platform.isAndroid || Platform.isIOS) {
        if (mounted) {
          ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Download unavailable on mobile yet.")));
        }
        return;
      }
      setState(() => _loadingStatus = "Preparing Download...");
      final url = await AniCore.getStreamUrl(widget.anime.id, idNum);
      setState(() => _loadingStatus = null);
      if (url != null) {
        String safeName = "${widget.anime.name}-EP$idNum.mp4".replaceAll(RegExp(r'[<>:"/\\|?*]'), '');

        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => EpisodeDownloadDialog(url: url, fileName: safeName),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download link not found")));
        }
      }
    } else {
      setState(() => _loadingStatus = "Fetching Stream...");
      context.read<UserProvider>().addToHistory(widget.anime, idNum);
      final url = await AniCore.getStreamUrl(widget.anime.id, idNum);
      setState(() => _loadingStatus = null);

      if (url != null) {
        final useInternal = context.read<SettingsProvider>().useInternalPlayer;
        final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

        // HELPER TO OPEN INTERNAL PLAYER
        void _openInternalPlayer() {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, anim, secAnim) => InternalPlayerScreen(
                streamUrl: url,
                title: "${widget.anime.name} - Ep $idNum",
                animeId: widget.anime.id,
                epNum: idNum,
              ),
              transitionsBuilder: (context, anim, secAnim, child) {
                return FadeTransition(opacity: anim, child: child);
              },
            ),
          );
        }

        // DESKTOP SYSTEM MPV CHECK
        if (isDesktop && !useInternal) {
          final savedSeconds = context.read<ProgressProvider>().getProgress(widget.anime.id, idNum);
          bool shouldResume = false;

          if (savedSeconds > 10) {
            shouldResume = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: kColorCream,
                title: const Text("Resume?", style: TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)),
                content: Text("Continue from ${Duration(seconds: savedSeconds).toString().split('.').first}?"),
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
            ) ?? false;
          }

          final List<String> args = [
            url,
            '--http-header-fields=Referer: ${AniCore.referer}',
            '--force-media-title=${widget.anime.name} - Ep $idNum',
            '--save-position-on-quit',
          ];
          if (shouldResume) args.add('--start=$savedSeconds');

          try {
            // Attempt to start system MPV
            await Process.start('mpv', args, mode: ProcessStartMode.detached);
          } catch (e) {
            // FALLBACK TO INTERNAL IF MPV NOT FOUND
            debugPrint("System MPV failed: $e. Falling back to libmpv.");
            if (mounted) {
              _openInternalPlayer();
            }
          }
        } else {
          // MOBILE OR INTERNAL MODE FORCED
          _openInternalPlayer();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream not found")));
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
                           style: const TextStyle(fontSize: 18, color: kColorCoral, fontWeight: FontWeight.bold))
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
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _buildCircleBtn(LucideIcons.arrowLeft, _onBack),
              _buildCircleBtn(
                isFav ? LucideIcons.heart : LucideIcons.heart,
                () => context.read<UserProvider>().toggleFavorite(widget.anime),
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
            Hero(
              tag: "title_${widget.heroTag}",
              child: Material(
                color: Colors.transparent,
                child: Text(widget.anime.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorDarkText)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 80, right: 40, bottom: 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(widget.anime.isManga ? "Chapters" : "Episodes",
                     style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral))
                .animate()
                .fadeIn()
                .slideY(begin: -0.5, end: 0),
                if (!widget.anime.isManga)
                  MorphingDownloadButton(
                    isDownloading: _isDownloadMode,
                    onToggle: () => setState(() => _isDownloadMode = !_isDownloadMode),
                  ),
              ]),
              const SizedBox(height: 20),
              // CHANGED TO LIST WITH KEEPALIVE
              Expanded(child: _buildEpisodeList()),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id);
    final headerHeight = MediaQuery.of(context).size.height * 0.55;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: headerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CozyHeroImage(
                  heroTag: widget.heroTag,
                  imageUrl: widget.anime.fullImageUrl,
                  radius: 0,
                  boxFit: BoxFit.cover,
                ),
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
                        () => context.read<UserProvider>().toggleFavorite(widget.anime),
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
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 10, color: Colors.black.withOpacity(0.5))],
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
                Text(widget.anime.isManga ? "Chapters" : "Episodes",
                     style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: kColorCoral)),
                     if (!widget.anime.isManga)
                       MorphingDownloadButton(
                         isDownloading: _isDownloadMode,
                         onToggle: () => setState(() => _isDownloadMode = !_isDownloadMode),
                       ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
          sliver: _isLoading
          ? const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator(color: kColorCoral)),
          )
          : SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                return EpisodeRowCard(
                  epNum: _displayChapter(_episodes[i]),
                  isDownloadMode: _isDownloadMode,
                  isManga: widget.anime.isManga,
                  onTap: () => _handleItemTap(_episodes[i]),
                )
                // --- STAGGERED ANIMATION FIX ---
                .animate(delay: Duration(milliseconds: (i % 15) * 80))
                .slideX(begin: 0.1, end: 0, duration: 600.ms, curve: Curves.easeOutCubic)
                .fadeIn(duration: 600.ms);
              },
              childCount: _episodes.length,
            ),
          ),
        ),
      ],
    );
  }

  String _displayChapter(String raw) {
    if (raw.contains("|")) return raw.split("|")[1];
    return raw;
  }

  // REPLACED GRID WITH LISTVIEW
  Widget _buildEpisodeList() {
    return _isLoading
    ? const Center(child: CircularProgressIndicator(color: kColorCoral))
    : ListView.builder(
      physics: const BouncingScrollPhysics(),
      // Important for keep-alive performance
      addAutomaticKeepAlives: true,
      itemCount: _episodes.length,
      itemBuilder: (ctx, i) {
        return EpisodeRowCard(
          epNum: _displayChapter(_episodes[i]),
          isDownloadMode: _isDownloadMode,
          isManga: widget.anime.isManga,
          onTap: () => _handleItemTap(_episodes[i]),
        )
        // --- STAGGERED ANIMATION FIX ---
        .animate(delay: Duration(milliseconds: (i % 15) * 80))
        .slideX(
          begin: 0.1,
          end: 0,
          duration: 600.ms,
          curve: Curves.easeOutCubic
        )
        .fadeIn(duration: 600.ms);
      },
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, {Color color = kColorCoral, bool fill = false}) {
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

// NEW: REPLACES EPISODE CHIP WITH ROW CARD + KEEPALIVE
class EpisodeRowCard extends StatefulWidget {
  final String epNum;
  final bool isDownloadMode;
  final bool isManga;
  final VoidCallback onTap;

  const EpisodeRowCard({
    super.key,
    required this.epNum,
    required this.isDownloadMode,
    required this.isManga,
    required this.onTap,
  });

  @override
  State<EpisodeRowCard> createState() => _EpisodeRowCardState();
}

class _EpisodeRowCardState extends State<EpisodeRowCard> with AutomaticKeepAliveClientMixin {
  bool isHovered = false;

  // This ensures the widget stays in memory when scrolled off-screen,
  // preventing the animation from re-playing and causing bugs.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by Mixin

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 12),
          height: 70, // Fixed height for consistency
          transform: Matrix4.identity()..scale(isHovered ? 1.01 : 1.0),
          child: LiquidGlassContainer(
            opacity: isHovered ? 0.9 : 0.6,
            // Highlight color when downloading
            child: Container(
              decoration: widget.isDownloadMode && isHovered
              ? BoxDecoration(
                border: Border.all(color: kColorCoral, width: 2),
                borderRadius: BorderRadius.circular(20))
              : null,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Number Badge
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kColorCoral.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        "#",
                        style: GoogleFonts.jetBrainsMono(
                          color: kColorCoral,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Title Text
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isManga ? "Chapter ${widget.epNum}" : "Episode ${widget.epNum}",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: kColorDarkText,
                          ),
                        ),
                        Text(
                          widget.isDownloadMode ? "Tap to download" : "Tap to play",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Icon
                  Icon(
                    widget.isDownloadMode
                    ? LucideIcons.download
                    : (widget.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle),
                    color: kColorCoral,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                              Icon(LucideIcons.downloadCloud, color: Colors.white, size: 18),
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
                              Icon(LucideIcons.x, color: Colors.white70, size: 16),
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

class EpisodeDownloadDialog extends StatefulWidget {
  final String url;
  final String fileName;

  const EpisodeDownloadDialog({
    super.key,
    required this.url,
    required this.fileName,
  });

  @override
  State<EpisodeDownloadDialog> createState() => _EpisodeDownloadDialogState();
}

class _EpisodeDownloadDialogState extends State<EpisodeDownloadDialog> {
  double _progress = 0.0;
  String _status = "Starting...";
  String _sizeInfo = "";
  final http.Client _client = http.Client();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      Directory? dir;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        dir = await getDownloadsDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();

      String savePath = "${dir.path}/${widget.fileName}";

      final file = File(savePath);
      final request = http.Request('GET', Uri.parse(widget.url));
      request.headers['Referer'] = AniCore.referer;

      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception("Server responded with ${response.statusCode}");
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      final List<int> bytes = [];
      response.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          received += newBytes.length;
          if (contentLength > 0) {
            setState(() {
              _progress = received / contentLength;
              _status = "Downloading...";
              _sizeInfo =
              "${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(contentLength / 1024 / 1024).toStringAsFixed(1)} MB";
            });
          } else {
            setState(() {
              _status = "Downloading (Unknown size)...";
              _sizeInfo = "${(received / 1024 / 1024).toStringAsFixed(1)} MB downloaded";
            });
          }
        },
        onDone: () async {
          await file.writeAsBytes(bytes);
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Saved to: $savePath"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ));
          }
        },
        onError: (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Download Failed: $e"), backgroundColor: kColorCoral));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kColorCoral.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.video, color: kColorCoral, size: 32)
                  .animate(onPlay: (c) => c.repeat())
                  .shimmer(duration: 1500.ms, color: Colors.white)
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.1, 1.1),
                    duration: 1000.ms,
                    curve: Curves.easeInOut)
                  .then()
                  .scale(
                    begin: const Offset(1.1, 1.1),
                    end: const Offset(1, 1),
                    curve: Curves.easeInOut),
                ),
                const SizedBox(height: 20),
                Text("Downloading",
                     style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)),
                     const SizedBox(height: 5),
                     Text(widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.black54)),
                          const SizedBox(height: 5),
                          Text(_status, style: GoogleFonts.inter(fontSize: 14, color: kColorDarkText)),
                          const SizedBox(height: 20),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: _progress),
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            builder: (context, value, _) {
                              return Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: value > 0 ? value : null,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: const AlwaysStoppedAnimation<Color>(kColorCoral),
                                      minHeight: 8,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("${(value * 100).toInt()}%",
                                      style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: kColorCoral)),
                                      Text(_sizeInfo, style: GoogleFonts.inter(fontSize: 12, color: Colors.black45)),
                                    ],
                                  )
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 25),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: kColorCoral),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                foregroundColor: kColorCoral,
                              ),
                              onPressed: () {
                                _client.close();
                                Navigator.pop(context);
                              },
                              child: const Text("Cancel"),
                            ),
                          ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn().scale(curve: Curves.easeOutBack),
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
        child: AnimatedContainer(
          duration: 200.ms,
          transform: Matrix4.identity()..scale(isHovered ? 1.05 : 1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CozyHeroImage(
                heroTag: widget.heroTag,
                imageUrl: widget.anime.fullImageUrl,
                radius: 20,
                withShadow: isHovered,
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [Colors.transparent, kColorDarkText.withOpacity(0.8)],
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
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
              ),
              if (widget.anime.isManga)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(4)),
                    child: const Text("MANGA",
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}

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
                  child: CozyHeroImage(
                    heroTag: "history_${widget.item.anime.id}",
                    imageUrl: widget.item.anime.fullImageUrl,
                    radius: 15,
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
                        widget.item.anime.isManga
                        ? "Chapter ${widget.item.displayEpisode}"
                        : "Episode ${widget.item.displayEpisode}",
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
                  child: Icon(
                    widget.item.anime.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle,
                    color: kColorCoral,
                    size: 30,
                  ),
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

  const FeaturedCarousel({super.key, required this.animes, required this.onTap});

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
                        colors: [Colors.transparent, kColorDarkText.withOpacity(0.9)],
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ).animate().slideX(begin: 0.2, end: 0, delay: (index * 100).ms, curve: Curves.easeOut);
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
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: 12),
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
