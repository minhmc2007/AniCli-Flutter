import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:animeclient/api/anime.dart';
import 'package:animeclient/api/manga.dart';
import 'package:animeclient/user_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
const String kAppVersion = "1.8.0";
const String kBuildNumber = "180";
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
  runApp(MultiProvider(providers:[
    ChangeNotifierProvider(create: (_) => UserProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => SourceProvider()),
    ChangeNotifierProvider(create: (_) => MangaSourceProvider()),
    ChangeNotifierProvider(create: (_) => ProgressProvider()),
  ], child: AniCliApp(isFirstLaunch: prefs.getBool('is_first_launch') ?? true)));
}

class AniCliApp extends StatelessWidget {
  final bool isFirstLaunch;
  const AniCliApp({super.key, required this.isFirstLaunch});
  @override Widget build(BuildContext context) {
    context.read<SettingsProvider>().initPerformanceMode();
    return MaterialApp(
      title: 'AniCli Flutter', debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light, scaffoldBackgroundColor: kColorCream,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(bodyColor: kColorDarkText, displayColor: kColorDarkText),
        useMaterial3: true, iconTheme: const IconThemeData(color: kColorDarkText),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: ZoomPageTransitionsBuilder(), TargetPlatform.iOS: CupertinoPageTransitionsBuilder(), TargetPlatform.windows: ZoomPageTransitionsBuilder(), TargetPlatform.linux: ZoomPageTransitionsBuilder(), TargetPlatform.macOS: ZoomPageTransitionsBuilder()})),
        home: isFirstLaunch ? const OnboardingScreen() : const MainScreen(),
    );
  }
}

// ==========================================
// UTILS & EXTENSIONS
// ==========================================
class MemoryUtils {
  static Future<double> getTotalRamGB() async {
    try {
      if (Platform.isLinux) {
        final res = await Process.run('grep',['MemTotal', '/proc/meminfo']);
        final parts = res.stdout.toString().trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) return (int.tryParse(parts[1]) ?? 0) / 1024 / 1024;
      } else if (Platform.isWindows) {
        final res = await Process.run('wmic',['computersystem', 'get', 'totalphysicalmemory']);
        final lines = res.stdout.toString().trim().split('\n');
        if (lines.length >= 2) return (int.tryParse(lines[1].trim()) ?? 0) / 1024 / 1024 / 1024;
      } else if (Platform.isMacOS) {
        final res = await Process.run('sysctl', ['-n', 'hw.memsize']);
        return (int.tryParse(res.stdout.toString().trim()) ?? 0) / 1024 / 1024 / 1024;
      }
    } catch (_) {}
    return -1;
  }
}

extension AnimExt on Widget {
  Widget adapt(PerformanceTier t, {int delay = 0, bool slideY = false, bool isScale = false, double slideBegin = 0.2, int duration = 400}) {
    if (t == PerformanceTier.low) return this;
    var a = animate(delay: delay.ms).fadeIn(duration: (duration == 600 ? 600 : 300).ms);
    if (t == PerformanceTier.mid) return a;
    if (isScale) return a.scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack, duration: duration.ms);
    return slideY ? a.slideY(begin: slideBegin, end: 0, curve: Curves.easeOutCubic, duration: duration.ms) : a.slideX(begin: slideBegin, end: 0, curve: Curves.easeOutCubic, duration: duration.ms);
  }

  Widget simpleDrop(PerformanceTier t, {int delay = 0}) {
    if (t == PerformanceTier.low) return this;
    return animate(delay: delay.ms)
    .fadeIn(duration: 300.ms)
    .slideY(begin: -0.15, end: 0, curve: Curves.easeOut, duration: 300.ms);
  }
}

extension LetExt<T> on T { R let<R>(R Function(T) cb) => cb(this); }

// ==========================================
// PROVIDERS
// ==========================================
enum PerformanceMode { auto, bestLooking, balanced, bestPerformance }
enum PerformanceTier { high, mid, low }

class SettingsProvider extends ChangeNotifier {
  bool _useInternalPlayer = false;
  PerformanceMode _perfMode = PerformanceMode.auto;
  PerformanceTier _currentTier = PerformanceTier.high;
  double _detectedRamGB = -1;

  bool get useInternalPlayer => _useInternalPlayer;
  PerformanceMode get perfMode => _perfMode;
  PerformanceTier get tier => _currentTier;
  String get ramDebugInfo => _detectedRamGB == -1 ? "Unknown" : "${_detectedRamGB.toStringAsFixed(1)} GB";

  SettingsProvider() { _loadSettings(); }
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _useInternalPlayer = prefs.getBool('use_internal_player') ?? false;
    _perfMode = PerformanceMode.values[prefs.getInt('perf_mode') ?? 0];
    await initPerformanceMode();
  }
  Future<void> initPerformanceMode() async {
    if (_detectedRamGB == -1) _detectedRamGB = await MemoryUtils.getTotalRamGB();
    _calculateTier(); notifyListeners();
  }
  void _calculateTier() {
    if (_perfMode == PerformanceMode.bestLooking) _currentTier = PerformanceTier.high;
    else if (_perfMode == PerformanceMode.balanced) _currentTier = PerformanceTier.mid;
    else if (_perfMode == PerformanceMode.bestPerformance) _currentTier = PerformanceTier.low;
    else {
      if (_detectedRamGB == -1) _currentTier = (Platform.isAndroid || Platform.isIOS) ? PerformanceTier.mid : PerformanceTier.high;
      else if (_detectedRamGB > 8.0) _currentTier = PerformanceTier.high;
      else if (_detectedRamGB >= 4.0) _currentTier = PerformanceTier.mid;
      else _currentTier = PerformanceTier.low;
    }
  }
  void toggleInternalPlayer(bool v) async { _useInternalPlayer = v; final p = await SharedPreferences.getInstance(); await p.setBool('use_internal_player', v); notifyListeners(); }
  void setPerformanceMode(PerformanceMode m) async { _perfMode = m; _calculateTier(); final p = await SharedPreferences.getInstance(); await p.setInt('perf_mode', m.index); notifyListeners(); }
}

class ProgressProvider extends ChangeNotifier {
  Map<String, int> _progress = {};
  ProgressProvider() { _loadProgress(); }
  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('watch_progress');
    if (stored != null) { _progress = Map<String, int>.from(jsonDecode(stored)); notifyListeners(); }
  }
  Future<void> saveProgress(String animeId, String epNum, int seconds) async {
    _progress["${animeId}_$epNum"] = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_progress', jsonEncode(_progress));
  }
  int getProgress(String animeId, String epNum) => _progress["${animeId}_$epNum"] ?? 0;
}

// ==========================================
// SERVICES & GENERIC DIALOGS
// ==========================================
class UpdaterService {
  static const String _releaseUrl = "https://api.github.com/repos/minhmc2007/AniCli-Flutter/releases/latest";
  static String? _extractSemVer(String raw) => RegExp(r'(\d+)\.(\d+)(\.(\d+))?').firstMatch(raw)?.let((m) => "${m.group(1) ?? '0'}.${m.group(2) ?? '0'}.${m.group(4) ?? '0'}");
  static bool _isNewer(String cur, String rem) {
    try {
      var c = cur.split('.').map(int.parse).toList(), r = rem.split('.').map(int.parse).toList();
      for (int i=0; i<3; i++) { if ((i<r.length?r[i]:0) > (i<c.length?c[i]:0)) return true; if ((i<r.length?r[i]:0) < (i<c.length?c[i]:0)) return false; }
    } catch (_) {} return false;
  }
  static Future<void> checkAndUpdate(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking for updates...")));
      final res = await http.get(Uri.parse(_releaseUrl));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body); String rem = data['tag_name'];
        if (_isNewer(_extractSemVer(kAppVersion) ?? "", _extractSemVer(rem) ?? "") && context.mounted) {
          _showDialog(context, rem, data['body'], data['assets']);
        } else if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You are up to date! ($kAppVersion)"), backgroundColor: Colors.green));
      }
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update check failed: $e"), backgroundColor: kColorCoral)); }
  }
  static Future<void> checkSilent(BuildContext context) async {
    try {
      final res = await http.get(Uri.parse(_releaseUrl));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body); String rem = data['tag_name'];
        if (_isNewer(_extractSemVer(kAppVersion) ?? "", _extractSemVer(rem) ?? "") && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("New Update Available: $rem"), backgroundColor: kColorCoral, duration: const Duration(seconds: 10), action: SnackBarAction(label: "Update", textColor: Colors.white, onPressed: () => _showDialog(context, rem, data['body'], data['assets']))));
        }
      }
    } catch (_) {}
  }
  static void _showDialog(BuildContext context, String ver, String notes, List assets) {
    showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: "Dismiss", barrierColor: Colors.black.withOpacity(0.6), transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (ctx, a1, a2, child) => Transform.scale(scale: Curves.easeOutBack.transform(a1.value), child: Opacity(opacity: a1.value, child: child)),
    pageBuilder: (ctx, a1, a2) => Center(child: Material(color: Colors.transparent, child: Container(
      width: MediaQuery.of(context).size.width * 0.85, constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600), padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 20), spreadRadius: 5)]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        Row(children:[
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(LucideIcons.sparkles, color: kColorCoral, size: 24)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text("New Version Available", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)), Text(ver, style: GoogleFonts.inter(fontSize: 14, color: kColorCoral, fontWeight: FontWeight.bold))])),
        ]).animate().slideY(begin: -0.2, end: 0, duration: 400.ms).fadeIn(),
        const SizedBox(height: 20), Divider(color: Colors.grey.withOpacity(0.2)), const SizedBox(height: 10),
        Flexible(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: MarkdownBody(data: notes, styleSheet: MarkdownStyleSheet(p: GoogleFonts.inter(color: kColorDarkText, fontSize: 14), h1: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 20), h2: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 18), h3: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 16), listBullet: GoogleFonts.inter(color: kColorCoral), strong: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kColorCoral), code: GoogleFonts.jetBrainsMono(backgroundColor: Colors.grey.shade100, color: kColorDarkText))))).animate(delay: 200.ms).fadeIn().slideX(begin: 0.1, end: 0),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.end, children:[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Later", style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w600))), const SizedBox(width: 10),
          ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), elevation: 0), onPressed: () { Navigator.pop(ctx); _performUpdate(context, assets, ver); }, icon: const Icon(LucideIcons.downloadCloud, size: 18), label: Text("Update Now", style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
        ]).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
      ])))));
  }
  static Future<void> _performUpdate(BuildContext context, List assets, String ver) async {
    String? url, fn;
    if (Platform.isAndroid) {
      if (!(await Permission.storage.request().isGranted)) return;
      if (!(await Permission.requestInstallPackages.request().isGranted)) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot install without permission."))); return; }
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.apk'), orElse: () => null)?['browser_download_url']; fn = "AniCli_$ver.apk";
    } else if (Platform.isWindows) {
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.zip') || a['name'].toString().endsWith('.exe'), orElse: () => null)?['browser_download_url']; fn = "AniCli_$ver.zip";
    } else if (Platform.isLinux) {
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.tar.gz') || a['name'].toString().endsWith('.AppImage'), orElse: () => null)?['browser_download_url']; fn = "AniCli_$ver.tar.gz";
    } else { launchUrl(Uri.parse("https://github.com/minhmc2007/AniCli-Flutter/releases/latest"), mode: LaunchMode.externalApplication); return; }

      if (url == null) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No compatible asset found."))); return; }
      if (!context.mounted) return;

      final file = await showDialog<File?>(context: context, barrierDismissible: false, builder: (ctx) => GenericDownloadDialog(url: url!, fileName: fn!, title: "Updating App", icon: LucideIcons.download, isUpdate: true));
    if (file != null && context.mounted) {
      if (Platform.isAndroid) { final res = await OpenFile.open(file.path, type: "application/vnd.android.package-archive"); if (res.type != ResultType.done) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Install Error: ${res.message}"))); }
      else if (Platform.isWindows || Platform.isLinux) { await launchUrl(Uri.directory(file.parent.path)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Downloaded. Please extract manually."), duration: Duration(seconds: 5))); }
    }
  }
}

class GenericDownloadDialog extends StatefulWidget {
  final String url, fileName, referer, title; final IconData icon; final bool isUpdate;
  const GenericDownloadDialog({super.key, required this.url, required this.fileName, this.referer = '', required this.title, required this.icon, this.isUpdate = false});
  @override State<GenericDownloadDialog> createState() => _GenericDownloadDialogState();
}
class _GenericDownloadDialogState extends State<GenericDownloadDialog> {
  double _prog = 0.0; String _status = "Starting...", _sizeInfo = ""; final http.Client _client = http.Client();
  @override void initState() { super.initState(); _start(); }
  @override void dispose() { _client.close(); super.dispose(); }

  Future<void> _start() async {
    try {
      Directory? dir = widget.isUpdate ? (Platform.isAndroid ? await getExternalStorageDirectory() : await getApplicationDocumentsDirectory()) : ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) ? await getDownloadsDirectory() : await getApplicationDocumentsDirectory());
      final file = File("${dir!.path}/${widget.fileName}");
      final req = http.Request('GET', Uri.parse(widget.url));
      if (widget.referer.isNotEmpty) req.headers['Referer'] = widget.referer;
      final res = await _client.send(req);
      if (res.statusCode != 200) throw Exception("HTTP ${res.statusCode}");
      final total = res.contentLength ?? 0; int rec = 0; final bytes = <int>[];
      res.stream.listen((b) {
        bytes.addAll(b); rec += b.length;
        setState(() { _prog = total > 0 ? rec / total : 0; _status = "Downloading..."; _sizeInfo = "${(rec/1024/1024).toStringAsFixed(1)} MB" + (total > 0 ? " / ${(total/1024/1024).toStringAsFixed(1)} MB" : ""); });
      }, onDone: () async {
        await file.writeAsBytes(bytes);
        if (mounted) { Navigator.pop(context, widget.isUpdate ? file : null); if (!widget.isUpdate) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved to: ${file.path}"), backgroundColor: Colors.green)); }
      }, onError: (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); } });
    } catch (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: kColorCoral)); } }
  }

  @override Widget build(BuildContext context) => PopScope(canPop: false, child: Center(child: Material(color: Colors.transparent, child: Container(
    width: MediaQuery.of(context).size.width * 0.85, constraints: const BoxConstraints(maxWidth: 400), padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 15))]),
    child: Column(mainAxisSize: MainAxisSize.min, children:[
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: Icon(widget.icon, color: kColorCoral, size: 32).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, color: Colors.white).scale(begin: const Offset(1,1), end: const Offset(1.1,1.1), duration: 1000.ms, curve: Curves.easeInOut).then().scale(begin: const Offset(1.1,1.1), end: const Offset(1,1), curve: Curves.easeInOut)),
      const SizedBox(height: 20), Text(widget.title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 5), Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: Colors.black54)), const SizedBox(height: 5), Text(_status, style: GoogleFonts.inter(fontSize: 14, color: kColorDarkText)), const SizedBox(height: 20),
      TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: _prog), duration: const Duration(milliseconds: 200), builder: (ctx, val, _) => Column(children:[ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: val > 0 ? val : null, backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation<Color>(kColorCoral), minHeight: 8)), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text("${(val * 100).toInt()}%", style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: kColorCoral)), Text(_sizeInfo, style: GoogleFonts.inter(fontSize: 12, color: Colors.black45))])])),
      const SizedBox(height: 25), SizedBox(width: double.infinity, child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: kColorCoral), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), foregroundColor: kColorCoral), onPressed: () { _client.close(); Navigator.pop(context); }, child: const Text("Cancel")))
    ])
  ))).animate().fadeIn().scale(curve: Curves.easeOutBack));
}

// ==========================================
// COMMON UI WIDGETS
// ==========================================
class LiquidGlassContainer extends StatelessWidget {
  final Widget child; final double blur, opacity; final BorderRadius? borderRadius; final Border? border;
  const LiquidGlassContainer({super.key, required this.child, this.blur=15, this.opacity=0.4, this.borderRadius, this.border});
  @override Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20);
    return context.select<SettingsProvider, PerformanceTier>((p) => p.tier) == PerformanceTier.low
    ? Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: br, border: border ?? Border.all(color: Colors.black12, width: 1)), child: child)
    : ClipRRect(borderRadius: br, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: Container(decoration: BoxDecoration(color: Colors.white.withOpacity(opacity), borderRadius: br, border: border ?? Border.all(color: Colors.white.withOpacity(0.6), width: 1.5), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors:[Colors.white.withOpacity(0.6), Colors.white.withOpacity(0.1)])), child: child)));
  }
}

class CozyHeroImage extends StatefulWidget {
  final String heroTag, imageUrl; final double radius; final bool withShadow; final BoxFit boxFit;
  final String? fallbackTitle;
  const CozyHeroImage({super.key, required this.heroTag, required this.imageUrl, this.radius=20, this.withShadow=true, this.boxFit=BoxFit.cover, this.fallbackTitle});
  @override State<CozyHeroImage> createState() => _CozyHeroImageState();
}
class _CozyHeroImageState extends State<CozyHeroImage> {
  String? _displayUrl; bool _fallbackTried = false;
  @override void initState() { super.initState(); _displayUrl = widget.imageUrl; }
  @override void didUpdateWidget(covariant CozyHeroImage old) { super.didUpdateWidget(old); if (old.imageUrl != widget.imageUrl) { _displayUrl = widget.imageUrl; _fallbackTried = false; } }

  Map<String, String>? _getHeaders(String url) {
    if (url.contains('youtu-chan') || url.contains('fast4speed')) return AllMangaCore.pageHeaders;
    else if (url.contains('wp.youtube-anime.com') || url.contains('allanime') || url.contains('allmanga')) return AllMangaCore.coverHeaders;
    return null;
  }

  @override Widget build(BuildContext context) {
    return Hero(tag: widget.heroTag, child: Material(color: Colors.transparent, child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.radius), boxShadow: (widget.withShadow && context.select<SettingsProvider, PerformanceTier>((p) => p.tier) != PerformanceTier.low) ?[BoxShadow(color: kColorCoral.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))] :[]),
      child: ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: CachedNetworkImage(
        imageUrl: _displayUrl!, fit: widget.boxFit, httpHeaders: _getHeaders(_displayUrl!),
        placeholder: (_,__) => Container(color: kColorPeach),
        errorWidget: (ctx, url, err) {
          if (!_fallbackTried && widget.fallbackTitle != null) {
            _fallbackTried = true;
            Future.delayed(Duration.zero, () async {
              final fb = await MangaCore.findMangaDexCover(widget.fallbackTitle!);
              if (fb != null && mounted) setState(() => _displayUrl = fb);
            });
              return Container(color: kColorPeach);
          }
          return Container(color: kColorPeach, child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)));
        }
      )))));
  }
}

class LiveGradientBackground extends StatefulWidget {
  final Widget child; const LiveGradientBackground({super.key, required this.child});
  @override State<LiveGradientBackground> createState() => _LiveGradientBackgroundState();
}
class _LiveGradientBackgroundState extends State<LiveGradientBackground> with SingleTickerProviderStateMixin {
  late AnimationController _c; late Animation<Alignment> _tA, _bA;
  @override void initState() {
    super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 15));
    _tA = TweenSequence<Alignment>([TweenSequenceItem(tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1)]).animate(_c);
    _bA = TweenSequence<Alignment>([TweenSequenceItem(tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1), TweenSequenceItem(tween: Tween(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1)]).animate(_c);
    _check();
  }
  void _check() { WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) context.read<SettingsProvider>().tier == PerformanceTier.low ? _c.stop() : _c.repeat(reverse: true); }); }
  @override void didChangeDependencies() { super.didChangeDependencies(); _check(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (ctx, _) => Container(width: double.infinity, height: double.infinity, decoration: BoxDecoration(gradient: LinearGradient(colors: const[kColorCream, kColorPeach], begin: _tA.value, end: _bA.value)), child: widget.child));
}

class FloatingOrbsBackground extends StatelessWidget {
  const FloatingOrbsBackground({super.key});
  Widget _orb(double s, Color c) => Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors:[c, c.withOpacity(0)], stops: const[0.4, 1.0])));
  @override Widget build(BuildContext context) {
    if (context.select<SettingsProvider, PerformanceTier>((p) => p.tier) == PerformanceTier.low) return Container(color: Colors.transparent);
    return Stack(children:[
      Positioned(top: -100, right: -100, child: _orb(400, kColorPeach).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2), duration: 6.seconds).rotate(begin: 0, end: 0.1, duration: 8.seconds)),
      Positioned(bottom: -150, left: -100, child: _orb(450, kColorCoral.withOpacity(0.4)).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.3,1.3), duration: 7.seconds).move(begin: Offset.zero, end: const Offset(20,-20), duration: 5.seconds)),
      Align(alignment: const Alignment(0, -0.3), child: _orb(300, kColorSoftPink.withOpacity(0.3)).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(0.8,0.8), end: const Offset(1.1,1.1), duration: 5.seconds).fadeIn()),
      Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(color: Colors.transparent))),
    ]);
  }
}

// ==========================================
// ONBOARDING & SETUP SCREENS
// ==========================================
class OnboardingScreen extends StatefulWidget { const OnboardingScreen({super.key}); @override State<OnboardingScreen> createState() => _OnboardingScreenState(); }
class _OnboardingScreenState extends State<OnboardingScreen> {
  final List<String> _greetings =["Welcome", "こんにちは", "AniCli"]; int _idx = 0; Timer? _timer; bool _isFinished = false;
  @override void initState() { super.initState(); _timer = Timer.periodic(const Duration(seconds: 2), (t) { if (_idx < _greetings.length - 1) setState(() => _idx++); else t.cancel(); }); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  Future<void> _complete() async {
    setState(() => _isFinished = true); await Future.delayed(const Duration(milliseconds: 2000));
    final prefs = await SharedPreferences.getInstance(); await prefs.setBool('is_first_launch', false);
    if (mounted) Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_,__,___) => const SourceSelectScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 1000)));
  }
  @override Widget build(BuildContext context) => Scaffold(body: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors:[Color(0xFFFFF8F0), kColorCream])), child: Stack(fit: StackFit.expand, children:[
    const FloatingOrbsBackground(),
    Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 800), switchInCurve: Curves.easeOutBack, switchOutCurve: Curves.easeInBack, child: _isFinished ? _buildLoader() : _buildWelcome())),
  ])));
  Widget _buildLoader() => Column(key: const ValueKey("setup"), mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children:[
    SizedBox(width: 60, height: 60, child: CircularProgressIndicator(strokeWidth: 5, valueColor: const AlwaysStoppedAnimation(kColorCoral), backgroundColor: kColorPeach.withOpacity(0.5))), const SizedBox(height: 30), Text("Getting things ready...", style: GoogleFonts.inter(fontSize: 22, color: kColorDarkText, fontWeight: FontWeight.w600)).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0)
  ]);
  Widget _buildWelcome() => Column(key: const ValueKey("welcome"), mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children:[
    SizedBox(height: 100, child: AnimatedSwitcher(duration: const Duration(milliseconds: 600), transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: c)), child: Text(_greetings[_idx], key: ValueKey(_idx), textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 56, fontWeight: FontWeight.w800, color: kColorDarkText, height: 1.0, letterSpacing: -1.5)))), const SizedBox(height: 50),
    AnimatedOpacity(opacity: _idx == _greetings.length - 1 ? 1.0 : 0.0, duration: const Duration(milliseconds: 800), child: AnimatedContainer(duration: const Duration(milliseconds: 300), curve: Curves.easeOut, transform: Matrix4.identity()..scale(_idx == _greetings.length - 1 ? 1.0 : 0.9), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow:[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10), spreadRadius: 2)]), child: ElevatedButton(onPressed: _idx == _greetings.length - 1 ? _complete : null, style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 22), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 0), child: Row(mainAxisSize: MainAxisSize.min, children:[Text("Get Started", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 8), const Icon(LucideIcons.arrowRight, size: 20)])))))
  ]);
}

class SourceSelectScreen extends StatelessWidget { const SourceSelectScreen({super.key});
Future<void> _go(BuildContext context, AnimeSource source) async {
  await context.read<SourceProvider>().setSource(source);
  if (context.mounted) Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_,__,___) => const MainScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 600)));
}
@override Widget build(BuildContext context) => Scaffold(body: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors:[Color(0xFFFFF8F0), kColorCream])), child: Stack(fit: StackFit.expand, children:[
  const FloatingOrbsBackground(), SafeArea(child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(mainAxisSize: MainAxisSize.min, children:[
    Text("Choose Anime Source", style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 12), Text("Select your preferred anime content language", style: GoogleFonts.inter(fontSize: 16, color: kColorDarkText.withOpacity(0.7))), const SizedBox(height: 40),
    _SourceOpt(title: "English", subtitle: "AllAnime · Sub", flag: "🇺🇸", onTap: () => _go(context, AnimeSource.en)), const SizedBox(height: 16), _SourceOpt(title: "Tiếng Việt", subtitle: "PhimAPI · Vietsub", flag: "🇻🇳", onTap: () => _go(context, AnimeSource.vi)),
  ])))),
])));
}

class _SourceOpt extends StatelessWidget {
  final String title, subtitle, flag; final VoidCallback onTap; const _SourceOpt({required this.title, required this.subtitle, required this.flag, required this.onTap});
  @override Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: LiquidGlassContainer(borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: Row(children:[
    Container(width: 56, height: 56, alignment: Alignment.center, decoration: BoxDecoration(color: kColorCoral.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: Text(flag, style: const TextStyle(fontSize: 28))), const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 4), Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: kColorCoral, fontWeight: FontWeight.w600))])), const Icon(LucideIcons.chevronRight, color: kColorCoral),
  ])))));
}

// ==========================================
// MAIN APP NAVIGATION
// ==========================================
class MainScreen extends StatefulWidget { const MainScreen({super.key}); @override State<MainScreen> createState() => _MainScreenState(); }
class _MainScreenState extends State<MainScreen> {
  int _idx = 0; final GlobalKey _hKey = GlobalKey(), _fKey = GlobalKey(), _sKey = GlobalKey();
  void _openDetail(AnimeModel anime, String heroTag) {
    Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, s) => AnimeDetailView(anime: anime, heroTag: heroTag), transitionsBuilder: (c, a, s, child) => context.read<SettingsProvider>().tier == PerformanceTier.low ? child : FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 600)));
  }
  @override void initState() { super.initState(); UpdaterService.checkSilent(context); }
  @override Widget build(BuildContext context) {
    Widget activePage; Key activeKey;
    switch (_idx) {
      case 0: final src = context.watch<SourceProvider>().source; activePage = BrowseView(key: ValueKey("Browse_${src.name}"), onAnimeTap: _openDetail); activeKey = ValueKey("BrowseTab_${src.name}"); break;
      case 1: activePage = HistoryView(key: _hKey, onAnimeTap: _openDetail); activeKey = const ValueKey("HistoryTab"); break;
      case 2: activePage = FavoritesView(key: _fKey, onAnimeTap: _openDetail); activeKey = const ValueKey("FavTab"); break;
      default: activePage = SettingsView(key: _sKey); activeKey = const ValueKey("SettingsTab"); break;
    }
    final tier = context.watch<SettingsProvider>().tier;
    return Scaffold(body: LiveGradientBackground(child: Stack(fit: StackFit.expand, children:[
      AnimatedSwitcher(duration: tier == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 500), switchInCurve: Curves.easeOutQuart, switchOutCurve: Curves.easeInQuart, transitionBuilder: (child, animation) => tier == PerformanceTier.low ? child : FadeTransition(opacity: animation, child: tier == PerformanceTier.high ? SlideTransition(position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation), child: child) : child), child: KeyedSubtree(key: activeKey, child: activePage)),
      Positioned(bottom: 30, left: 0, right: 0, child: Center(child: GlassDock(selectedIndex: _idx, onItemSelected: (i) => setState(() => _idx = i)))),
    ])));
  }
}

// ==========================================
// MANGA READER & INTERNAL PLAYER
// ==========================================
class MangaReaderScreen extends StatefulWidget {
  final AnimeModel anime; final String chapterNum; final List<String> allChapters;
  const MangaReaderScreen({super.key, required this.anime, required this.chapterNum, required this.allChapters});
  @override State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}
class _MangaReaderScreenState extends State<MangaReaderScreen> {
  bool _isLoading = true, _showControls = true, _isCtrlPressed = false; List<String> _pages =[]; int _pointerCount = 0;
  final TransformationController _tCtrl = TransformationController(); final ScrollController _sCtrl = ScrollController();
  @override void initState() { super.initState(); _loadPages(); }
  Future<void> _loadPages() async {
    setState(() => _isLoading = true);
    final pages = widget.anime.sourceId == 'allanime'
? await AllMangaCore.getPages(widget.anime.id, widget.chapterNum)
: await MangaCore.getPages(widget.chapterNum);
if (mounted) setState(() { _pages = pages; _isLoading = false; });
  }
  void _nav(String newChap) {
    context.read<UserProvider>().addToHistory(widget.anime, newChap);
    Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_,__,___) => MangaReaderScreen(anime: widget.anime, chapterNum: newChap, allChapters: widget.allChapters), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));
  }
  Future<void> _downloadImage(String url, int index) async {
    try {
      final headers = widget.anime.sourceId == 'allanime' ? AllMangaCore.pageHeaders : const {"User-Agent": "AniCli/1.0"};
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode == 200) {
        final dir = Platform.isAndroid ? await getExternalStorageDirectory() : await getDownloadsDirectory();
        final safeTitle = widget.anime.name.replaceAll(RegExp(r'[^\w\s]+'), '');
        final file = File("${dir?.path}/$safeTitle/Ch${widget.chapterNum}/page_$index.jpg");
        await file.create(recursive: true); await file.writeAsBytes(res.bodyBytes);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved page $index to ${file.path}")));
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving image: $e"))); }
  }

  @override Widget build(BuildContext context) {
    final idx = widget.allChapters.indexOf(widget.chapterNum);
    return Scaffold(backgroundColor: Colors.black, body: KeyboardListener(focusNode: FocusNode()..requestFocus(), onKeyEvent: (e) { if (e.logicalKey == LogicalKeyboardKey.controlLeft || e.logicalKey == LogicalKeyboardKey.controlRight) setState(() => _isCtrlPressed = e is KeyDownEvent || e is KeyRepeatEvent); }, child: Stack(children:[
      Listener(
        onPointerDown: (_) => setState(() => _pointerCount++), onPointerUp: (_) => setState(() => _pointerCount--), onPointerCancel: (_) => setState(() => _pointerCount = 0),
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            if (_isCtrlPressed) {
              final scale = e.scrollDelta.dy < 0 ? 1.1 : 0.9; final currentMatrix = _tCtrl.value;
              final newScale = (currentMatrix.getMaxScaleOnAxis() * scale).clamp(0.01, 10.0);
              if (newScale >= 0.01 && newScale <= 10.0) {
                final c = Offset(MediaQuery.of(context).size.width/2, MediaQuery.of(context).size.height/2);
                _tCtrl.value = (Matrix4.identity()..translate(c.dx, c.dy)..scale(scale)..translate(-c.dx, -c.dy)) * currentMatrix;
              }
            } else if (_sCtrl.hasClients) _sCtrl.jumpTo((_sCtrl.offset + e.scrollDelta.dy).clamp(_sCtrl.position.minScrollExtent, _sCtrl.position.maxScrollExtent));
          }
        },
        child: GestureDetector(onTap: () => setState(() => _showControls = !_showControls), child: _isLoading ? const Center(child: CircularProgressIndicator(color: kColorCoral)) : InteractiveViewer(transformationController: _tCtrl, minScale: 0.01, maxScale: 10.0, scaleEnabled: _isCtrlPressed || _pointerCount > 1, panEnabled: true, trackpadScrollCausesScale: false, interactionEndFrictionCoefficient: 0.00001, child: ListView.builder(controller: _sCtrl, physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()), cacheExtent: 3000, itemCount: _pages.length + 1, itemBuilder: (ctx, i) {
          if (i == _pages.length) return Padding(padding: const EdgeInsets.symmetric(vertical: 60), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children:[
            if (idx < widget.allChapters.length - 1) ElevatedButton(onPressed: () => _nav(widget.allChapters[idx + 1]), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]), child: const Text("Previous Chapter", style: TextStyle(color: Colors.white))),
              if (idx > 0) ElevatedButton(onPressed: () => _nav(widget.allChapters[idx - 1]), style: ElevatedButton.styleFrom(backgroundColor: kColorCoral), child: const Text("Next Chapter", style: TextStyle(color: Colors.white)))
          ]));
          return GestureDetector(onLongPress: () => _downloadImage(_pages[i], i+1), onSecondaryTap: () => _downloadImage(_pages[i], i+1), child: Container(alignment: Alignment.center, color: Colors.black, child: CachedNetworkImage(imageUrl: _pages[i], fit: BoxFit.contain, width: double.infinity, placeholder: (_,__) => const SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: kColorCoral, strokeWidth: 2))), errorWidget: (_,__,___) => const SizedBox(height: 200, child: Center(child: Icon(Icons.broken_image, color: Colors.white54))), httpHeaders: widget.anime.sourceId == 'allanime' ? AllMangaCore.pageHeaders : const {"User-Agent": "AniCli/1.0"})));
        })))),
        AnimatedPositioned(duration: const Duration(milliseconds: 300), top: _showControls ? 0 : -100, left: 0, right: 0, child: Container(color: Colors.black.withOpacity(0.8), padding: const EdgeInsets.all(10), child: SafeArea(bottom: false, child: Row(children:[IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(widget.anime.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1), Text("Chapter ${widget.chapterNum.contains('|') ? widget.chapterNum.split('|')[1] : widget.chapterNum}", style: const TextStyle(color: kColorCoral, fontSize: 12))]))]))))
    ])));
  }
}

class InternalPlayerScreen extends StatefulWidget {
  final String streamUrl, title, animeId, epNum, referer;
  const InternalPlayerScreen({super.key, required this.streamUrl, required this.title, required this.animeId, required this.epNum, this.referer=''});
  @override State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}
class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late final Player _p; late final VideoController _c; late ProgressProvider _prog;
  bool _showControls = true, _showFwd = false, _showRwd = false, _resumeChecked = false;
  Timer? _hideT, _progT; StreamSubscription? _durSub;

  @override void initState() {
    super.initState(); _p = Player(configuration: const PlayerConfiguration(vo: 'gpu'));
    _c = VideoController(_p, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true, androidAttachSurfaceAfterVideoParameters: true));
    _durSub = _p.stream.duration.listen((d) { if (!_resumeChecked && d.inSeconds > 0) { _resumeChecked = true; _checkResume(); } });
    _p.open(Media(widget.streamUrl, httpHeaders: {'Referer': widget.referer.isNotEmpty ? widget.referer : AniCore.referer}));
    _progT = Timer.periodic(const Duration(seconds: 5), (_) { if (mounted && _p.state.position.inSeconds > 10) context.read<ProgressProvider>().saveProgress(widget.animeId, widget.epNum, _p.state.position.inSeconds); });
    _p.play(); _p.setVolume(100); _startHide();
  }
  @override void didChangeDependencies() { super.didChangeDependencies(); _prog = context.read<ProgressProvider>(); }
  Future<void> _checkResume() async {
    if (!mounted) return;
    final saved = _prog.getProgress(widget.animeId, widget.epNum);
    if (saved > 10) {
      await _p.pause(); if (!mounted) return;
      final res = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(backgroundColor: kColorCream, title: const Text("Resume?", style: TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)), content: Text("Left off at ${_fmt(Duration(seconds: saved))}. Continue?"), actions:[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Start Over", style: TextStyle(color: Colors.black54))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text("Resume"))]));
      if (mounted && res == true) await _p.seek(Duration(seconds: saved));
      await _p.play();
    }
  }
  void _startHide() { _hideT?.cancel(); _hideT = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => _showControls = false); }); }
  void _toggle() { setState(() => _showControls = !_showControls); _showControls ? _startHide() : _hideT?.cancel(); }
  void _doubleTap(bool isFwd) {
    _p.seek(_p.state.position + Duration(seconds: isFwd ? 10 : -10));
    setState(() { if (isFwd) _showFwd = true; else _showRwd = true; });
    Future.delayed(const Duration(milliseconds: 600), () { if (mounted) setState(() { _showFwd = false; _showRwd = false; }); });
  }
  @override void dispose() { _durSub?.cancel(); _progT?.cancel(); _hideT?.cancel(); _p.stop(); try { if (_p.state.position.inSeconds > 10) _prog.saveProgress(widget.animeId, widget.epNum, _p.state.position.inSeconds); } catch (_) {} _p.dispose(); super.dispose(); }
  String _fmt(Duration d) => d.inHours > 0 ? '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}' : '${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';

@override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Stack(alignment: Alignment.center, children:[
  Video(controller: _c, controls: NoVideoControls),
  Row(children:[Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggle, onDoubleTap: () => _doubleTap(false), child: Container(color: Colors.transparent))), Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggle, onDoubleTap: () => _doubleTap(true), child: Container(color: Colors.transparent)))]),
  if (_showRwd) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 50), child: _buildFb(LucideIcons.rewind, "-10s"))),
    if (_showFwd) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 50), child: _buildFb(LucideIcons.fastForward, "+10s"))),
      if (_showControls) CustomMobileControls(c: _c, title: widget.title, onClose: () => Navigator.pop(context), fmt: _fmt),
])));
Widget _buildFb(IconData icon, String text) => Column(mainAxisSize: MainAxisSize.min, children:[Icon(icon, color: Colors.white.withOpacity(0.8), size: 40), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]).animate().scale(duration: 200.ms, curve: Curves.easeOutBack).fadeOut(delay: 300.ms, duration: 300.ms);
}

class CustomMobileControls extends StatefulWidget {
  final VideoController c; final String title; final VoidCallback onClose; final String Function(Duration) fmt;
  const CustomMobileControls({super.key, required this.c, required this.title, required this.onClose, required this.fmt});
  @override State<CustomMobileControls> createState() => _CustomMobileControlsState();
}
class _CustomMobileControlsState extends State<CustomMobileControls> {
  bool _isDrag = false; double _val = 0.0;
  @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(colors:[Colors.black54, Colors.transparent, Colors.black54], begin: Alignment.topCenter, end: Alignment.bottomCenter, stops:[0.0, 0.5, 1.0])), child: Column(children:[
    Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children:[IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onClose), Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))])), const Expanded(child: SizedBox()),
    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(children: [
      Row(children:[
        StreamBuilder<Duration>(stream: widget.c.player.stream.position, initialData: widget.c.player.state.position, builder: (ctx, s) => Text(widget.fmt(_isDrag ? Duration(seconds: _val.toInt()) : (s.data ?? Duration.zero)), style: const TextStyle(color: Colors.white, fontSize: 12))), const SizedBox(width: 10),
        Expanded(child: StreamBuilder<Duration>(stream: widget.c.player.stream.position, initialData: widget.c.player.state.position, builder: (ctx, ps) => StreamBuilder<Duration>(stream: widget.c.player.stream.duration, initialData: widget.c.player.state.duration, builder: (ctx, ds) {
          final max = (ds.data ?? Duration.zero).inSeconds.toDouble(), pos = (ps.data ?? Duration.zero).inSeconds.toDouble();
          return SliderTheme(data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), overlayShape: const RoundSliderOverlayShape(overlayRadius: 20), activeTrackColor: kColorCoral, inactiveTrackColor: Colors.white24, thumbColor: kColorCoral, overlayColor: kColorCoral.withOpacity(0.2)), child: Slider(value: max>0 ? (_isDrag?_val:pos).clamp(0.0, max) : 0.0, min: 0.0, max: max>0?max:1.0, onChanged: max>0 ? (v) => setState((){_isDrag=true; _val=v;}) : null, onChangeEnd: max>0 ? (v) { widget.c.player.seek(Duration(seconds: v.toInt())); setState(() => _isDrag=false); } : null));
        }))), const SizedBox(width: 10),
        StreamBuilder<Duration>(stream: widget.c.player.stream.duration, initialData: widget.c.player.state.duration, builder: (ctx, s) => Text(widget.fmt(s.data ?? Duration.zero), style: const TextStyle(color: Colors.white, fontSize: 12))),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children:[
        IconButton(icon: const Icon(Icons.replay_10, color: Colors.white, size: 32), onPressed: () => widget.c.player.seek(widget.c.player.state.position - const Duration(seconds: 10))),
        StreamBuilder<bool>(stream: widget.c.player.stream.playing, initialData: widget.c.player.state.playing, builder: (ctx, s) => CenterPlayButton(isPlaying: s.data ?? false, onPressed: () => (s.data ?? false) ? widget.c.player.pause() : widget.c.player.play())),
        IconButton(icon: const Icon(Icons.forward_10, color: Colors.white, size: 32), onPressed: () => widget.c.player.seek(widget.c.player.state.position + const Duration(seconds: 10))),
      ])
    ]))
  ]));
}

class CenterPlayButton extends StatefulWidget {
  final bool isPlaying; final VoidCallback onPressed;
  const CenterPlayButton({super.key, required this.isPlaying, required this.onPressed});
  @override State<CenterPlayButton> createState() => _CenterPlayButtonState();
}
class _CenterPlayButtonState extends State<CenterPlayButton> with TickerProviderStateMixin {
  late AnimationController _pC, _iC; bool _isPressed = false;
  @override void initState() { super.initState(); _pC = AnimationController(vsync: this, duration: const Duration(seconds: 2)); _iC = AnimationController(vsync: this, duration: const Duration(milliseconds: 300)); if (widget.isPlaying) _iC.forward(); WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted && context.read<SettingsProvider>().tier != PerformanceTier.low && !widget.isPlaying) _pC.repeat(); }); }
  @override void didUpdateWidget(CenterPlayButton old) { super.didUpdateWidget(old); if (widget.isPlaying != old.isPlaying) { if (widget.isPlaying) { _iC.forward(); _pC.stop(); } else { _iC.reverse(); if(context.read<SettingsProvider>().tier != PerformanceTier.low) _pC.repeat(); } } }
  @override void dispose() { _pC.dispose(); _iC.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => GestureDetector(onTap: widget.onPressed, onTapDown: (_) => setState(() => _isPressed=true), onTapUp: (_) => setState(() => _isPressed=false), onTapCancel: () => setState(() => _isPressed=false), child: AnimatedScale(scale: _isPressed ? 0.9 : 1.0, duration: const Duration(milliseconds: 100), child: Stack(alignment: Alignment.center, children:[
    if (!widget.isPlaying) FadeTransition(opacity: TweenSequence([TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.5), weight: 50), TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.0), weight: 50)]).animate(_pC), child: ScaleTransition(scale: Tween(begin: 1.0, end: 1.5).animate(_pC), child: Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: kColorCoral.withOpacity(0.4))))),
      Container(width: 70, height: 70, decoration: BoxDecoration(color: kColorCoral, shape: BoxShape.circle, boxShadow:[BoxShadow(color: kColorCoral.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)]), child: Center(child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _iC, color: Colors.white, size: 40)))
  ])));
}

// ==========================================
// VIEWS
// ==========================================
class BrowseView extends StatefulWidget { final Function(AnimeModel, String) onAnimeTap; const BrowseView({super.key, required this.onAnimeTap}); @override State<BrowseView> createState() => _BrowseViewState(); }
class _BrowseViewState extends State<BrowseView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _sCtrl = TextEditingController(); List<AnimeModel> _items =[];
  bool _isLoading = true, _isMangaMode = false; String _query = "";
  @override bool get wantKeepAlive => true;
  @override void initState() { super.initState(); _loadData(); }
  void _loadData() async {
    setState(() => _isLoading = true);
    final useVi = context.read<SourceProvider>().isVi;
    final mangaSrc = context.read<MangaSourceProvider>().source;
    final res = _isMangaMode
    ? (_query.isEmpty
    ? (mangaSrc == MangaSource.allanime ? await AllMangaCore.getTrending() : await MangaCore.getTrending())
    : (mangaSrc == MangaSource.allanime ? await AllMangaCore.search(_query) : await MangaCore.search(_query)))
    : (_query.isEmpty
    ? (useVi ? await ViAnimeCore.getTrending() : await AniCore.getTrending())
    : (useVi ? await ViAnimeCore.search(_query) : await AniCore.search(_query)));
    if (mounted) setState(() { _items = res; _isLoading = false; });
  }
  void _doSearch(String q) { _query = q; _loadData(); }
  void _toggleMode(bool m) { if (_isMangaMode == m) return; setState(() { _isMangaMode = m; _items.clear(); _query = ""; _sCtrl.clear(); }); _loadData(); }

  @override Widget build(BuildContext context) {
    super.build(context);
    final isMobile = MediaQuery.of(context).size.width < 900; final t = context.watch<SettingsProvider>().tier;
    final mangaSrc = context.watch<MangaSourceProvider>().source;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          const SizedBox(height: 50),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
            child: Row(
              children:[
                GestureDetector(onTap: () => _toggleMode(false), child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: !_isMangaMode ? kColorCoral : Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(20), boxShadow: !_isMangaMode ?[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 10)] :[]), child: Text("Anime", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: !_isMangaMode ? Colors.white : kColorDarkText.withOpacity(0.6))))),
                const SizedBox(width: 15),
                GestureDetector(onTap: () => _toggleMode(true), child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: _isMangaMode ? kColorCoral : Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(20), boxShadow: _isMangaMode ?[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 10)] :[]), child: Text("Manga", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _isMangaMode ? Colors.white : kColorDarkText.withOpacity(0.6))))),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
            child: Row(
              children:[
                if (_query.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 15), child: IconButton(onPressed: () { _sCtrl.clear(); _doSearch(""); }, icon: const Icon(LucideIcons.arrowLeftCircle, color: kColorCoral, size: 32))),
                  Expanded(child: LiquidGlassContainer(borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(controller: _sCtrl, style: const TextStyle(color: kColorDarkText, fontWeight: FontWeight.w600), decoration: InputDecoration(hintText: _isMangaMode ? "Search Manga..." : "Search Anime...", hintStyle: const TextStyle(color: Colors.black38), border: InputBorder.none, icon: const Icon(LucideIcons.search, color: kColorCoral)), onSubmitted: _doSearch)))),
              ],
            ),
          ).adapt(t, delay: 200, slideY: true),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: t == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuart,
                child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kColorCoral))
                : KeyedSubtree(
                  key: ValueKey("Grid_$_isMangaMode$_query"),
                  child: _items.isEmpty
                  ? Center(child: Text("No results found.", style: GoogleFonts.inter(color: Colors.black26)))
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_query.isEmpty) ...[
                        if (!_isMangaMode && _items.length > 5) ...[
                          Padding(padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15), child: Text("Spotlight", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorCoral))).adapt(t, delay: 200, slideY: true),
                          FeaturedCarousel(animes: _items.take(5).toList(), onTap: widget.onAnimeTap),
                          const SizedBox(height: 30),
                        ] else if (_isMangaMode) ...[
                          SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: Stack(
                              children:[
                                const Positioned.fill(child: FloatingOrbsBackground()),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children:[
                                      Text(
                                        mangaSrc == MangaSource.mangadex ? "MangaDex" : "AllManga",
                                        style: GoogleFonts.outfit(fontSize: 40, fontWeight: FontWeight.bold, color: kColorDarkText),
                                      ),
                                      Text(
                                        mangaSrc == MangaSource.mangadex ? "Read the world's library" : "The best manga reader",
                                        style: GoogleFonts.inter(fontSize: 16, color: kColorDarkText.withOpacity(0.6)),
                                      ),
                                    ],
                                  ).adapt(t),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                      Padding(padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15), child: Text(_query.isEmpty ? (_isMangaMode ? "Popular Updates" : "Trending Anime") : "Results", style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorDarkText))).adapt(t, delay: 200, slideY: true),
                      AnimeGrid(animes: _items, onTap: widget.onAnimeTap, tagPrefix: "browse"),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class HistoryView extends StatefulWidget { final Function(AnimeModel, String) onAnimeTap; const HistoryView({super.key, required this.onAnimeTap}); @override State<HistoryView> createState() => _HistoryViewState(); }
class _HistoryViewState extends State<HistoryView> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context); final history = context.watch<UserProvider>().history; final isMobile = MediaQuery.of(context).size.width < 900; final t = context.watch<SettingsProvider>().tier;
    return Column(children:[const SizedBox(height: 60), Row(mainAxisAlignment: MainAxisAlignment.center, children:[Text("History", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)), if (history.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 10), child: IconButton(icon: const Icon(LucideIcons.trash2, size: 20, color: kColorDarkText), onPressed: () => context.read<UserProvider>().clearHistory()))]).adapt(t), const SizedBox(height: 20), Expanded(child: history.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children:[Icon(LucideIcons.ghost, size: 60, color: kColorCoral.withOpacity(0.5)), const SizedBox(height: 10), Text("Nothing here yet...", style: GoogleFonts.inter(color: Colors.black45, fontSize: 16))])) : ListView.builder(padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 10), physics: const BouncingScrollPhysics(), itemCount: history.length, itemBuilder: (ctx, i) => HistoryCard(item: history[i], onTap: () => widget.onAnimeTap(history[i].anime, "history_${history[i].anime.id}")).simpleDrop(t, delay: i > 8 ? 0 : i * 50)))]);
  }
}

class FavoritesView extends StatefulWidget { final Function(AnimeModel, String) onAnimeTap; const FavoritesView({super.key, required this.onAnimeTap}); @override State<FavoritesView> createState() => _FavoritesViewState(); }
class _FavoritesViewState extends State<FavoritesView> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context); final favorites = context.watch<UserProvider>().favorites; final t = context.watch<SettingsProvider>().tier;
    return Column(children:[const SizedBox(height: 60), Text("Favorites", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)).adapt(t, slideY: true, slideBegin: -0.5), const SizedBox(height: 20), Expanded(child: favorites.isEmpty ? Center(child: Text("No favorites yet!", style: GoogleFonts.inter(color: Colors.black26))) : AnimeGrid(animes: favorites, onTap: widget.onAnimeTap, physics: const BouncingScrollPhysics(), shrinkWrap: false, tagPrefix: "fav"))]);
  }
}

class SettingsView extends StatefulWidget { const SettingsView({super.key}); @override State<SettingsView> createState() => _SettingsViewState(); }
class _SettingsViewState extends State<SettingsView> {
  Future<void> _url(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not launch $url"), backgroundColor: kColorCoral));
    }
  }

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 10, top: 10),
    child: Text(
      t.toUpperCase(),
      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: kColorDarkText.withOpacity(0.6), letterSpacing: 1.2)
    )
  );

  Widget _sw(IconData i, String t, String s, bool v, ValueChanged<bool> o) => LiquidGlassContainer(
    opacity: 0.6,
    child: SwitchListTile(
      value: v,
      onChanged: o,
      activeColor: kColorCoral,
      secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: kColorCoral, size: 24)),
      title: Text(t, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Text(s, style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
    )
  );

  Widget _cd(IconData i, String t, String s, {Widget? tr, VoidCallback? onTap}) => GestureDetector(
    onTap: onTap,
    child: LiquidGlassContainer(
      opacity: 0.6,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children:[
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: kColorCoral, size: 24)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(t, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)), Text(s, style: GoogleFonts.inter(color: Colors.black54, fontSize: 13))])),
            if (tr != null) tr
          ]
        )
      )
    )
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final sp = context.watch<SettingsProvider>();
    final tp = context.watch<SourceProvider>();
    final mp = context.watch<MangaSourceProvider>();
    final t = sp.tier;

    final items =[
      _sec("Content"),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const[Icon(LucideIcons.globe, color: kColorCoral), SizedBox(width: 10), Text("Anime Source", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<AnimeSource>(
                value: tp.source,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: const[
                  DropdownMenuItem(value: AnimeSource.en, child: Text("English (AllAnime · Sub)")),
                  DropdownMenuItem(value: AnimeSource.vi, child: Text("Tiếng Việt (PhimAPI · Vietsub)"))
                ],
                onChanged: (v) { if (v != null) tp.setSource(v); }
              )
            ]
          )
        )
      ),
      const SizedBox(height: 15),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(children: const[Icon(LucideIcons.bookOpen, color: kColorCoral), SizedBox(width: 10), Text("Manga Source", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<MangaSource>(
                value: mp.source,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: const[
                  DropdownMenuItem(value: MangaSource.allanime, child: Text("AllManga (allanime.day · Default)")),
                  DropdownMenuItem(value: MangaSource.mangadex, child: Text("MangaDex (Multi-lang · R18)")),
                ],
                onChanged: (v) { if (v != null) mp.setSource(v); }
              )
            ]
          )
        )
      ),
      const SizedBox(height: 15),
      _sec("General"),
      _cd(LucideIcons.downloadCloud, "Check for Updates", "Version Check via GitHub Releases", onTap: () => UpdaterService.checkAndUpdate(context)),
      const SizedBox(height: 10),
      _cd(LucideIcons.trash2, "Clear Image Cache", "Fixes broken covers by removing old cached 404s", onTap: () async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        try { await DefaultCacheManager().emptyCache(); } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image cache cleared!"), backgroundColor: Colors.green));
      }),
      const SizedBox(height: 10),
      _sec("Performance"),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const[Icon(LucideIcons.zap, color: kColorCoral), SizedBox(width: 10), Text("Visual Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<PerformanceMode>(
                value: sp.perfMode,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: const[
                  DropdownMenuItem(value: PerformanceMode.auto, child: Text("Auto (Detect RAM)")),
                  DropdownMenuItem(value: PerformanceMode.bestLooking, child: Text("Best Looking (High)")),
                  DropdownMenuItem(value: PerformanceMode.balanced, child: Text("Balanced (Mid)")),
                  DropdownMenuItem(value: PerformanceMode.bestPerformance, child: Text("Best Performance (Low)"))
                ],
                onChanged: (v) { if (v != null) sp.setPerformanceMode(v); }
              ),
              const SizedBox(height: 5),
              Text("Current Tier: ${sp.tier.name.toUpperCase()}  •  Detected RAM: ${sp.ramDebugInfo}", style: const TextStyle(fontSize: 12, color: Colors.black54))
            ]
          )
        )
      ),
      const SizedBox(height: 15),
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) ...[
        _sw(LucideIcons.playCircle, "Use Internal Player", "Use built-in player instead of System MPV", sp.useInternalPlayer, (v) => sp.toggleInternalPlayer(v)),
        const SizedBox(height: 15)
      ],
      _sec("Development"),
      _cd(LucideIcons.github, "GitHub Repository", "minhmc2007/AniCli-Flutter", tr: const Icon(LucideIcons.externalLink, size: 16, color: kColorCoral), onTap: () => _url("https://github.com/minhmc2007/AniCli-Flutter")),
      const SizedBox(height: 10),
      _cd(LucideIcons.rotateCcw, "Reset Welcome Screen", "Reset OOBE flag for testing", onTap: () async {
        await (await SharedPreferences.getInstance()).remove('is_first_launch');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reset! Restart app to see the Welcome Screen."), backgroundColor: kColorCoral));
      }),
      const SizedBox(height: 30),
      _sec("About"),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Column(
          children:[
            InkWell(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children:[
                    Icon(LucideIcons.info, color: kColorDarkText.withOpacity(0.7), size: 20),
                    const SizedBox(width: 16),
                    Expanded(child: Text("Version", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15))),
                    Text("v$kAppVersion", style: GoogleFonts.inter(color: kColorCoral, fontWeight: FontWeight.bold, fontSize: 14))
                  ]
                )
              )
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.5), indent: 20, endIndent: 20),
            InkWell(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children:[
                    Icon(LucideIcons.hash, color: kColorDarkText.withOpacity(0.7), size: 20),
                    const SizedBox(width: 16),
                    Expanded(child: Text("Build Number", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15))),
                    Text(kBuildNumber, style: GoogleFonts.inter(color: kColorCoral, fontWeight: FontWeight.bold, fontSize: 14))
                  ]
                )
              )
            )
          ]
        )
      )
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:[
            const SizedBox(height: 60),
            Center(
              child: Text("Settings", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral))
              .adapt(t, slideY: true, slideBegin: -0.5)
            ),
            const SizedBox(height: 20),
            ...items.map((e) => e.adapt(t, delay: 50))
          ]
        )
      )
    );
  }
}
// ==========================================
// DETAILS
// ==========================================
class AnimeDetailView extends StatefulWidget { final AnimeModel anime; final String heroTag; const AnimeDetailView({super.key, required this.anime, required this.heroTag}); @override State<AnimeDetailView> createState() => _AnimeDetailViewState(); }
class _AnimeDetailViewState extends State<AnimeDetailView> {
  List<String> _episodes =[]; bool _isLoading = true, _isDownloadMode = false; String? _loadingStatus;
  bool _isTitleExpanded = false;
  @override void initState() { super.initState(); _loadData(); }
  void _loadData() async {
    final useVi = widget.anime.sourceId == 'vi';

// REMOVED: Self-Healing Logic (It was overwriting the good thumbnail with a bad one)

final items = widget.anime.isManga
? (widget.anime.sourceId == 'allanime'
? await AllMangaCore.getChapters(widget.anime.id)
: await MangaCore.getChapters(widget.anime.id))
: (useVi ? await ViAnimeCore.getEpisodes(widget.anime.id) : await AniCore.getEpisodes(widget.anime.id));
if (mounted) setState(() { _episodes = items; _isLoading = false; });
  }
  Future<void> _handleItemTap(String idNum) async {
    if (widget.anime.isManga) {
      context.read<UserProvider>().addToHistory(widget.anime, idNum);
      Navigator.push(context, MaterialPageRoute(builder: (ctx) => MangaReaderScreen(anime: widget.anime, chapterNum: idNum, allChapters: _episodes))); return;
    }
    final useVi = widget.anime.sourceId == 'vi'; final referer = useVi ? ViAnimeCore.referer : AniCore.referer;
    if (_isDownloadMode) {
      if (Platform.isAndroid || Platform.isIOS) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download unavailable on mobile yet."))); return; }
      setState(() => _loadingStatus = "Preparing Download..."); final url = useVi ? await ViAnimeCore.getStreamUrl(widget.anime.id, idNum) : await AniCore.getStreamUrl(widget.anime.id, idNum); setState(() => _loadingStatus = null);
      if (url != null) {
        if (mounted) await showDialog(context: context, barrierDismissible: false, builder: (ctx) => GenericDownloadDialog(url: url, fileName: "${widget.anime.name}-EP$idNum.mp4".replaceAll(RegExp(r'[<>:"/\\|?*]'), ''), referer: referer, title: "Downloading", icon: LucideIcons.video));
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download link not found"))); }
    } else {
      setState(() => _loadingStatus = "Fetching Stream..."); context.read<UserProvider>().addToHistory(widget.anime, idNum); final url = useVi ? await ViAnimeCore.getStreamUrl(widget.anime.id, idNum) : await AniCore.getStreamUrl(widget.anime.id, idNum); setState(() => _loadingStatus = null);
      if (url != null) {
        void openInternal() => Navigator.of(context).push(PageRouteBuilder(pageBuilder: (_, a, __) => InternalPlayerScreen(streamUrl: url, title: "${widget.anime.name} - Ep $idNum", animeId: widget.anime.id, epNum: idNum, referer: referer), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));
        if ((Platform.isLinux || Platform.isWindows || Platform.isMacOS) && !context.read<SettingsProvider>().useInternalPlayer) {
          final saved = context.read<ProgressProvider>().getProgress(widget.anime.id, idNum); bool resume = false;
          if (saved > 10) resume = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: kColorCream, title: const Text("Resume?", style: TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)), content: Text("Continue from ${Duration(seconds: saved).toString().split('.').first}?"), actions:[TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Start Over", style: TextStyle(color: Colors.black54))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text("Resume"))])) ?? false;
          final args =[url, '--http-header-fields=Referer: $referer', '--force-media-title=${widget.anime.name} - Ep $idNum', '--save-position-on-quit']; if (resume) args.add('--start=$saved');
          try { await Process.start('mpv', args, mode: ProcessStartMode.detached); } catch (e) { if (mounted) openInternal(); }
        } else openInternal();
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream not found"))); }
    }
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, {Color color = kColorCoral, bool fill = false}) => GestureDetector(onTap: onTap, child: LiquidGlassContainer(borderRadius: BorderRadius.circular(50), child: Container(padding: const EdgeInsets.all(12), child: Icon(icon, color: color, fill: fill ? 1.0 : 0.0))));
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id); final t = context.watch<SettingsProvider>().tier;
    return Scaffold(body: LiveGradientBackground(child: Stack(fit: StackFit.expand, children:[
      isMobile ? CustomScrollView(physics: const BouncingScrollPhysics(), slivers:[
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).size.height * 0.55, child: Stack(fit: StackFit.expand, children:[
          CozyHeroImage(heroTag: widget.heroTag, imageUrl: widget.anime.fullImageUrl, radius: 0, boxFit: BoxFit.cover, fallbackTitle: widget.anime.name),
          Container(decoration: BoxDecoration(gradient: LinearGradient(colors:[Colors.transparent, Colors.black.withOpacity(0.7)], begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const[0.6, 1.0]))),
          Positioned(top: 50, left: 20, right: 20, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[_buildCircleBtn(LucideIcons.arrowLeft, () => Navigator.pop(context)), _buildCircleBtn(LucideIcons.heart, () => context.read<UserProvider>().toggleFavorite(widget.anime), color: isFav ? kColorCoral : Colors.black26, fill: isFav)])),
          Positioned(bottom: 20, left: 20, right: 20, child: Hero(tag: "title_${widget.heroTag}", child: Material(color: Colors.transparent, child: GestureDetector(onTap: () => setState(() => _isTitleExpanded = !_isTitleExpanded), child: Text(widget.anime.name, textAlign: TextAlign.center, maxLines: _isTitleExpanded ? null : 2, overflow: _isTitleExpanded ? null : TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, shadows:[Shadow(blurRadius: 10, color: Colors.black.withOpacity(0.5))]))))))
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text(widget.anime.isManga ? "Chapters" : "Episodes", style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: kColorCoral)), if (!widget.anime.isManga) MorphingDownloadButton(isDownloading: _isDownloadMode, onToggle: () => setState(() => _isDownloadMode = !_isDownloadMode))]))),
        SliverPadding(padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100), sliver: _isLoading ? const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: kColorCoral))) : SliverList(delegate: SliverChildBuilderDelegate((ctx, i) => EpisodeRowCard(epNum: _episodes[i].contains("|") ? _episodes[i].split("|")[1] : _episodes[i], isDownloadMode: _isDownloadMode, isManga: widget.anime.isManga, onTap: () => _handleItemTap(_episodes[i])).simpleDrop(t, delay: i > 8 ? 0 : i * 50), childCount: _episodes.length)))
      ])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children:[
        SizedBox(width: 350, height: MediaQuery.of(context).size.height, child: SingleChildScrollView(padding: const EdgeInsets.all(40), physics: const BouncingScrollPhysics(), child: Column(children:[
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[_buildCircleBtn(LucideIcons.arrowLeft, () => Navigator.pop(context)), _buildCircleBtn(LucideIcons.heart, () => context.read<UserProvider>().toggleFavorite(widget.anime), color: isFav ? kColorCoral : Colors.black26, fill: isFav)]),
          const SizedBox(height: 30),
          CozyHeroImage(heroTag: widget.heroTag, imageUrl: widget.anime.fullImageUrl, radius: 25, fallbackTitle: widget.anime.name),
          const SizedBox(height: 25),
          Hero(tag: "title_${widget.heroTag}", child: Material(color: Colors.transparent, child: GestureDetector(onTap: () => setState(() => _isTitleExpanded = !_isTitleExpanded), child: Text(widget.anime.name, textAlign: TextAlign.center, maxLines: _isTitleExpanded ? null : 2, overflow: _isTitleExpanded ? null : TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorDarkText)))))
        ]))),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 80, right: 40, bottom: 40), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
            Text(widget.anime.isManga ? "Chapters" : "Episodes", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)).animate().fadeIn().slideY(begin: -0.5, end: 0),
            if (!widget.anime.isManga) MorphingDownloadButton(isDownloading: _isDownloadMode, onToggle: () => setState(() => _isDownloadMode = !_isDownloadMode))
          ]),
          const SizedBox(height: 20),
          Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator(color: kColorCoral)) : ListView.builder(physics: const BouncingScrollPhysics(), itemCount: _episodes.length, itemBuilder: (ctx, i) => EpisodeRowCard(epNum: _episodes[i].contains("|") ? _episodes[i].split("|")[1] : _episodes[i], isDownloadMode: _isDownloadMode, isManga: widget.anime.isManga, onTap: () => _handleItemTap(_episodes[i])).simpleDrop(t, delay: i > 8 ? 0 : i * 50)))
        ])))
      ]),
      if (_loadingStatus != null) Positioned.fill(child: LiquidGlassContainer(blur: 20, opacity: 0.8, borderRadius: BorderRadius.zero, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children:[const CircularProgressIndicator(color: kColorCoral), const SizedBox(height: 20), Text(_loadingStatus!, style: const TextStyle(fontSize: 18, color: kColorCoral, fontWeight: FontWeight.bold))]))))
    ])));
  }
}

class EpisodeRowCard extends StatefulWidget { final String epNum; final bool isDownloadMode, isManga; final VoidCallback onTap; const EpisodeRowCard({super.key, required this.epNum, required this.isDownloadMode, required this.isManga, required this.onTap}); @override State<EpisodeRowCard> createState() => _EpisodeRowCardState(); }
class _EpisodeRowCardState extends State<EpisodeRowCard> with AutomaticKeepAliveClientMixin {
  bool isH = false; @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context); final t = context.read<SettingsProvider>().tier;
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: t == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 200), curve: Curves.easeOut, margin: const EdgeInsets.only(bottom: 12), height: 70, transform: Matrix4.identity()..scale(isH && t != PerformanceTier.low ? 1.01 : 1.0), child: LiquidGlassContainer(opacity: isH ? 0.9 : 0.6, child: Container(decoration: widget.isDownloadMode && isH ? BoxDecoration(border: Border.all(color: kColorCoral, width: 2), borderRadius: BorderRadius.circular(20)) : null, padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children:[Container(width: 40, height: 40, decoration: BoxDecoration(color: kColorCoral.withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text("#", style: GoogleFonts.jetBrainsMono(color: kColorCoral, fontWeight: FontWeight.bold)))), const SizedBox(width: 20), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children:[Text(widget.isManga ? "Chapter ${widget.epNum}" : "Episode ${widget.epNum}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: kColorDarkText)), Text(widget.isDownloadMode ? "Tap to download" : "Tap to play", style: GoogleFonts.inter(fontSize: 12, color: Colors.black45))])), Icon(widget.isDownloadMode ? LucideIcons.download : (widget.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle), color: kColorCoral, size: 28)]))))));
  }
}

class MorphingDownloadButton extends StatelessWidget {
  final bool isDownloading; final VoidCallback onToggle; const MorphingDownloadButton({super.key, required this.isDownloading, required this.onToggle});
  @override Widget build(BuildContext context) {
    if (context.read<SettingsProvider>().tier == PerformanceTier.low) return IconButton(onPressed: onToggle, icon: Icon(isDownloading ? LucideIcons.check : LucideIcons.download, color: kColorCoral), style: IconButton.styleFrom(backgroundColor: Colors.white));
    return TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), curve: Curves.easeOutBack, tween: Tween(begin: 0.0, end: isDownloading ? 1.0 : 0.0), builder: (c, t, child) => GestureDetector(onTap: onToggle, child: Container(width: lerpDouble(50, 240, t)!, height: 50, decoration: BoxDecoration(color: Color.lerp(Colors.white, kColorCoral, t)!, borderRadius: BorderRadius.circular(lerpDouble(25, 15, t)!), boxShadow:[BoxShadow(color: kColorCoral.withOpacity(0.2 + (t * 0.2)), blurRadius: 15, offset: const Offset(0, 5))]), child: ClipRect(child: Stack(alignment: Alignment.center, children:[Opacity(opacity: (1.0 - t).clamp(0.0, 1.0), child: Transform.translate(offset: Offset(-20 * t, 0), child: Icon(LucideIcons.download, color: Color.lerp(kColorCoral, Colors.white, t)!))), Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(20 * (1.0 - t), 0), child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: Container(width: 240, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(LucideIcons.downloadCloud, color: Colors.white, size: 18), SizedBox(width: 8), Text("Select Ep to Download", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), SizedBox(width: 5), Icon(LucideIcons.x, color: Colors.white70, size: 16)])))))])))));
  }
}

class AnimeGrid extends StatelessWidget {
  final List<AnimeModel> animes; final Function(AnimeModel, String) onTap; final ScrollPhysics? physics; final bool shrinkWrap; final String tagPrefix;
  const AnimeGrid({super.key, required this.animes, required this.onTap, this.physics = const NeverScrollableScrollPhysics(), this.shrinkWrap = true, required this.tagPrefix});
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final t = context.watch<SettingsProvider>().tier;
    return Padding(padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40), child: GridView.builder(physics: physics, shrinkWrap: shrinkWrap, gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: isMobile ? 150 : 180, childAspectRatio: 0.7, crossAxisSpacing: isMobile ? 15 : 20, mainAxisSpacing: isMobile ? 15 : 20), itemCount: animes.length, itemBuilder: (ctx, i) => AnimeCard(anime: animes[i], heroTag: "${tagPrefix}_${animes[i].id}", onTap: () => onTap(animes[i], "${tagPrefix}_${animes[i].id}")).adapt(t, delay: i * 50, isScale: true)));
  }
}

class AnimeCard extends StatefulWidget { final AnimeModel anime; final String heroTag; final VoidCallback onTap; const AnimeCard({super.key, required this.anime, required this.heroTag, required this.onTap}); @override State<AnimeCard> createState() => _AnimeCardState(); }
class _AnimeCardState extends State<AnimeCard> with AutomaticKeepAliveClientMixin {
  bool isH = false; @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: 200.ms, transform: Matrix4.identity()..scale(isH && context.watch<SettingsProvider>().tier != PerformanceTier.low ? 1.05 : 1.0), child: Stack(fit: StackFit.expand, children:[CozyHeroImage(heroTag: widget.heroTag, imageUrl: widget.anime.fullImageUrl, radius: 20, withShadow: isH, fallbackTitle: widget.anime.name), Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors:[Colors.transparent, kColorDarkText.withOpacity(0.8)], begin: Alignment.center, end: Alignment.bottomCenter))), Positioned(bottom: 12, left: 12, right: 12, child: Hero(tag: "title_${widget.heroTag}", child: Material(color: Colors.transparent, child: Text(widget.anime.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))))), if (widget.anime.isManga) Positioned(top: 10, right: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(4)), child: const Text("MANGA", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))]))));
  }
}

class HistoryCard extends StatefulWidget { final HistoryItem item; final VoidCallback onTap; const HistoryCard({super.key, required this.item, required this.onTap}); @override State<HistoryCard> createState() => _HistoryCardState(); }
class _HistoryCardState extends State<HistoryCard> with AutomaticKeepAliveClientMixin {
  bool isH = false; @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), curve: Curves.easeOut, margin: const EdgeInsets.only(bottom: 15), height: 90, transform: Matrix4.identity()..scale(isH && context.watch<SettingsProvider>().tier != PerformanceTier.low ? 1.02 : 1.0), child: LiquidGlassContainer(opacity: isH ? 0.9 : 0.6, child: Row(children:[SizedBox(width: 90, height: 90, child: CozyHeroImage(heroTag: "history_${widget.item.anime.id}", imageUrl: widget.item.anime.fullImageUrl, radius: 15, fallbackTitle: widget.item.anime.name)), const SizedBox(width: 20), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children:[Text(widget.item.anime.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)), Text(widget.item.anime.isManga ? "Chapter ${widget.item.displayEpisode}" : "Episode ${widget.item.displayEpisode}", style: GoogleFonts.inter(color: kColorCoral, fontWeight: FontWeight.w600, fontSize: 14))])), Padding(padding: const EdgeInsets.only(right: 20), child: Icon(widget.item.anime.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle, color: kColorCoral, size: 30))])))));
  }
}

class FeaturedCarousel extends StatelessWidget {
  final List<AnimeModel> animes; final Function(AnimeModel, String) onTap; const FeaturedCarousel({super.key, required this.animes, required this.onTap});
  @override Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().tier;
    return SizedBox(height: 220, child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 40), scrollDirection: Axis.horizontal, itemCount: animes.length, itemBuilder: (c, i) => GestureDetector(onTap: () => onTap(animes[i], "carousel_${animes[i].id}"), child: Container(width: 300, margin: const EdgeInsets.only(right: 20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: t != PerformanceTier.low ?[BoxShadow(color: kColorCoral.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))] :[]), child: Stack(fit: StackFit.expand, children:[CozyHeroImage(heroTag: "carousel_${animes[i].id}", imageUrl: animes[i].fullImageUrl, radius: 20, fallbackTitle: animes[i].name), Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors:[Colors.transparent, kColorDarkText.withOpacity(0.9)], begin: Alignment.topCenter, end: Alignment.bottomCenter))), Positioned(bottom: 20, left: 20, child: SizedBox(width: 260, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children:[Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(8)), child: const Text("HOT", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))), const SizedBox(height: 5), Text(animes[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])))]))).adapt(t, delay: i * 100)));
  }
}

class GlassDock extends StatelessWidget {
  final int selectedIndex; final Function(int) onItemSelected; const GlassDock({super.key, required this.selectedIndex, required this.onItemSelected});
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final items =[(LucideIcons.search, "Browse"), (LucideIcons.history, "History"), (LucideIcons.heart, "Favorites"), (LucideIcons.settings, "Settings")];
    return LiquidGlassContainer(borderRadius: BorderRadius.circular(30), child: Padding(padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: 12), child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(items.length, (i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: IconButton(icon: Icon(items[i].$1, color: selectedIndex == i ? kColorCoral : Colors.black38, size: isMobile ? 20 : 24), onPressed: () => onItemSelected(i), tooltip: items[i].$2))))));
  }
}
