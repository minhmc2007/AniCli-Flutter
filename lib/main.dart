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
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:animeclient/api/providers/hls_proxy.dart';
import 'package:animeclient/api/providers/ytdl_proxy.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'i18n.dart';

// Global Definitions & App State
const String kAppVersion = "1.9.0 Developer Preview";
const String kBuildNumber = "190";
const kColorCream = Color(0xFFFEEAC9);
const kColorPeach = Color(0xFFFFCDC9);
const kColorSoftPink = Color(0xFFFDACAC);
const kColorCoral = Color(0xFFFD7979);
const kColorDarkText = Color(0xFF4A2B2B);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await UpdaterService.cleanupOldUpdates(); // Delete stale Android APKs
  
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
      title: 'AniCli Flutter',
      debugShowCheckedModeBanner: false,
      locale: context.watch<SettingsProvider>().locale == AppLocale.vi ? const Locale('vi') : null,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US'), Locale('vi')],
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: kColorCream,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).apply(bodyColor: kColorDarkText, displayColor: kColorDarkText),
        useMaterial3: true,
        iconTheme: const IconThemeData(color: kColorDarkText),
        pageTransitionsTheme: PageTransitionsTheme(builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder()
        })
      ),
      home: isFirstLaunch ? const OnboardingScreen() : const MainScreen(),
    );
  }
}

// Providers
enum AnimeSource { en, vi, hentaivietsub }

extension AnimeSourceX on AnimeSource {
  String get label {
    if (this == AnimeSource.en) return 'English';
    if (this == AnimeSource.vi) return 'Tiếng Việt';
    return 'NSFW (18+)';
  }
  String get description {
    if (this == AnimeSource.en) return 'Senshi · Anipub · Anineko · AllAnime · Animepahe';
    if (this == AnimeSource.vi) return 'PhimAPI · Vietsub';
    return 'HentaiVietsub · Vietsub';
  }
}

class SourceProvider extends ChangeNotifier {
  AnimeSource _source = AnimeSource.en;
  AnimeSource get source => _source;
  bool get isVi => _source == AnimeSource.vi;
  bool get isNSFW => _source == AnimeSource.hentaivietsub;
  bool get isProvider => _source == AnimeSource.en;
  bool _loaded = false;

  SourceProvider() { _loadSource(); }

  Future<void> _loadSource() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (_loaded) return;
    final saved = prefs.getString('anime_source');
    debugPrint('[DEBUG] SourceProvider._loadSource: saved="$saved"');
    if (_loaded) return;
    if (saved != null) {
      if (saved == 'vi') _source = AnimeSource.vi;
      else if (saved == 'hentaivietsub') _source = AnimeSource.hentaivietsub;
      else if (saved == 'provider' || saved == 'en') _source = AnimeSource.en;
    }
    _loaded = true;
    debugPrint('[DEBUG] SourceProvider._loadSource: _source=$_source');
    notifyListeners();
  }

  Future<void> setSource(AnimeSource s) async {
    debugPrint('[DEBUG] SourceProvider.setSource($s) called');
    _source = s;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anime_source', s.name);
    debugPrint('[DEBUG] SourceProvider.setSource: saved "${s.name}" to prefs');
    notifyListeners();
  }
  Future<void> reload() async { _loaded = false; _loadSource(); }
}



enum PerformanceMode { auto, bestLooking, balanced, bestPerformance }
enum PerformanceTier { high, mid, low }

class SettingsProvider extends ChangeNotifier {
  bool _useInternalPlayer = false;
  double _cacheSecs = 120;
  PerformanceMode _perfMode = PerformanceMode.auto;
  PerformanceTier _currentTier = PerformanceTier.high;
  double _detectedRamGB = -1;
  AppLocale _locale = AppLocale.en;

  bool get useInternalPlayer => _useInternalPlayer;
  double get cacheSecs => _cacheSecs;
  PerformanceMode get perfMode => _perfMode;
  PerformanceTier get tier => _currentTier;
  AppLocale get locale => _locale;
  String get ramDebugInfo => _detectedRamGB == -1 ? "Unknown" : "${_detectedRamGB.toStringAsFixed(1)} GB";

  SettingsProvider() { _loadSettings(); }
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _useInternalPlayer = prefs.getBool('use_internal_player') ?? false;
    _cacheSecs = prefs.getDouble('cache_secs') ?? 120.0;
    _perfMode = PerformanceMode.values[prefs.getInt('perf_mode') ?? 0];
    _locale = prefs.getString('app_locale') == 'vi' ? AppLocale.vi : AppLocale.en;
    await initPerformanceMode();
  }
  Future<void> initPerformanceMode() async {
    if (_detectedRamGB == -1) _detectedRamGB = await MemoryUtils.getTotalRamGB();
    _calculateTier(); notifyListeners();
  }
  void setLocale(AppLocale l) async { _locale = l; final p = await SharedPreferences.getInstance(); await p.setString('app_locale', l == AppLocale.vi ? 'vi' : 'en'); notifyListeners(); }
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
  void setCacheSecs(double v) async { _cacheSecs = v; final p = await SharedPreferences.getInstance(); await p.setDouble('cache_secs', v); notifyListeners(); }
  void setPerformanceMode(PerformanceMode m) async { _perfMode = m; _calculateTier(); final p = await SharedPreferences.getInstance(); await p.setInt('perf_mode', m.index); notifyListeners(); }
  Future<void> reload() async { await _loadSettings(); }
}

class ProgressProvider extends ChangeNotifier {
  Map<String, int> _progress = {};
  Map<String, int> _mangaPage = {};
  ProgressProvider() { _loadProgress(); }
  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('watch_progress');
    if (stored != null) { _progress = Map<String, int>.from(jsonDecode(stored)); }
    final mangaStored = prefs.getString('manga_page_progress');
    if (mangaStored != null) { _mangaPage = Map<String, int>.from(jsonDecode(mangaStored)); }
    notifyListeners();
  }
  Future<void> saveProgress(String animeId, String epNum, int seconds) async {
    _progress["${animeId}_$epNum"] = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('watch_progress', jsonEncode(_progress));
  }
  int getProgress(String animeId, String epNum) => _progress["${animeId}_$epNum"] ?? 0;

  Future<void> saveMangaPage(String mangaId, String chapterNum, int pageIndex) async {
    _mangaPage["${mangaId}_$chapterNum"] = pageIndex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manga_page_progress', jsonEncode(_mangaPage));
  }
  int getMangaPage(String mangaId, String chapterNum) => _mangaPage["${mangaId}_$chapterNum"] ?? 0;
  Future<void> reload() async { _progress.clear(); _mangaPage.clear(); await _loadProgress(); }
}

class BackupService {
  static const _keys = ['anime_source', 'manga_source', 'use_internal_player', 'cache_secs', 'perf_mode', 'app_locale', 'favorites', 'nsfw_favorites', 'history', 'nsfw_history', 'watch_progress', 'manga_page_progress'];

  static Future<String> exportData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in _keys) {
      final v = prefs.get(key);
      if (v != null) data[key] = v is double ? v : (v is int ? v : v.toString());
    }
    const version = kAppVersion;
    return jsonEncode({'version': version, 'data': data, 'exportedAt': DateTime.now().toIso8601String()});
  }

  static Future<bool> importData(String jsonStr) async {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = map['data'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      for (final key in _keys) {
        final v = data[key];
        if (v == null) continue;
        if (v is String) { await prefs.setString(key, v); }
        else if (v is double) { await prefs.setDouble(key, v); }
        else if (v is int) { await prefs.setInt(key, v); }
        else if (v is bool) { await prefs.setBool(key, v); }
      }
      return true;
    } catch (e) {
      debugPrint('Backup import error: $e');
      return false;
    }
  }
}

// Utilities & Extensions
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
        final res = await Process.run('sysctl',['-n', 'hw.memsize']);
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
    return animate(delay: delay.ms).fadeIn(duration: 300.ms).slideY(begin: -0.15, end: 0, curve: Curves.easeOut, duration: 300.ms);
  }
}

extension LetExt<T> on T { R let<R>(R Function(T) cb) => cb(this); }

// Updater & Services
class UpdaterService {
  static const String _releaseUrl = "https://api.github.com/repos/minhmc2007/AniCli-Flutter/releases/latest";
  
  static String? _extractSemVer(String raw) => RegExp(r'(\d+)\.(\d+)(\.(\d+))?').firstMatch(raw)?.let((m) => "${m.group(1) ?? '0'}.${m.group(2) ?? '0'}.${m.group(4) ?? '0'}");
  
  static bool _isNewer(String cur, String rem) {
    try {
      var c = cur.split('.').map(int.parse).toList(), r = rem.split('.').map(int.parse).toList();
      for (int i=0; i<3; i++) { if ((i<r.length?r[i]:0) > (i<c.length?c[i]:0)) return true; if ((i<r.length?r[i]:0) < (i<c.length?c[i]:0)) return false; }
    } catch (_) {} return false;
  }

  static Future<void> cleanupOldUpdates() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.apk')).forEach((f) => f.deleteSync());
    } catch (_) {}
  }

  static Future<void> checkAndUpdate(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_checking'))));
      final res = await http.get(Uri.parse(_releaseUrl));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body); String rem = data['tag_name'];
        if (_isNewer(_extractSemVer(kAppVersion) ?? "", _extractSemVer(rem) ?? "") && context.mounted) {
          _showDialog(context, rem, data['body'], data['assets']);
        } else if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_up_to_date', [kAppVersion])), backgroundColor: Colors.green));
      }
    } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_check_failed', [e.toString()])), backgroundColor: kColorCoral)); }
  }

  static Future<void> checkSilent(BuildContext context) async {
    try {
      final res = await http.get(Uri.parse(_releaseUrl));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body); String rem = data['tag_name'];
        if (_isNewer(_extractSemVer(kAppVersion) ?? "", _extractSemVer(rem) ?? "") && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_available', [rem])), backgroundColor: kColorCoral, duration: const Duration(seconds: 10), action: SnackBarAction(label: context.tr('updater_update'), textColor: Colors.white, onPressed: () => _showDialog(context, rem, data['body'], data['assets']))));
        }
      }
    } catch (_) {}
  }

  static void _showDialog(BuildContext context, String ver, String notes, List assets) {
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: context.tr('updater_dismiss'), barrierColor: Colors.black.withOpacity(0.6), transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, a1, a2, child) => Transform.scale(scale: Curves.easeOutBack.transform(a1.value).clamp(0.0, 1.0), child: Opacity(opacity: a1.value.clamp(0.0, 1.0), child: child)),
      pageBuilder: (ctx, a1, a2) => Center(child: Material(color: Colors.transparent, child: Container(
        width: MediaQuery.of(context).size.width * 0.85, constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600), padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 20), spreadRadius: 5)]),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(LucideIcons.sparkles, color: kColorCoral, size: 24)),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(context.tr('updater_new_version'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)), Text(ver, style: GoogleFonts.inter(fontSize: 14, color: kColorCoral, fontWeight: FontWeight.bold))])),
          ]).animate().slideY(begin: -0.2, end: 0, duration: 400.ms).fadeIn(),
          const SizedBox(height: 20), Divider(color: Colors.grey.withOpacity(0.2)), const SizedBox(height: 10),
          Flexible(child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: MarkdownBody(data: notes, styleSheet: MarkdownStyleSheet(p: GoogleFonts.inter(color: kColorDarkText, fontSize: 14), h1: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 20), h2: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 18), h3: GoogleFonts.inter(color: kColorDarkText, fontWeight: FontWeight.bold, fontSize: 16), listBullet: GoogleFonts.inter(color: kColorCoral), strong: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kColorCoral), code: GoogleFonts.jetBrainsMono(backgroundColor: Colors.grey.shade100, color: kColorDarkText))))).animate(delay: 200.ms).fadeIn().slideX(begin: 0.1, end: 0),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children:[
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('updater_later'), style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w600))), const SizedBox(width: 10),
            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), elevation: 0), onPressed: () { Navigator.pop(ctx); _performUpdate(context, assets, ver); }, icon: const Icon(LucideIcons.downloadCloud, size: 18), label: Text(context.tr('updater_update_now'), style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
          ]).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2, end: 0),
        ])))));
  }

  static Future<void> _performUpdate(BuildContext context, List assets, String ver) async {
    String? url, fn;
    bool runSetup = false;
    String exe = Platform.resolvedExecutable.toLowerCase();

    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final res = await Permission.requestInstallPackages.request();
        if (!res.isGranted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_allow_install')), backgroundColor: kColorCoral, action: SnackBarAction(label: context.tr('updater_settings'), textColor: Colors.white, onPressed: () => openAppSettings())));
          return;
        }
      }
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.apk'), orElse: () => null)?['browser_download_url'];
      fn = "app-release.apk";
    } else if (Platform.isIOS) {
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.ipa'), orElse: () => null)?['browser_download_url'];
      fn = "anicli-unsigned.ipa";
    } else if (Platform.isWindows) {
      if (exe.contains('program files') || exe.contains('appdata\\local\\programs')) {
        url = assets.firstWhere((a) => a['name'].toString().endsWith('-setup.exe'), orElse: () => null)?['browser_download_url'];
        fn = "anicli-windows-setup.exe";
        runSetup = true;
      } else {
        url = assets.firstWhere((a) => a['name'].toString().endsWith('-portable.zip'), orElse: () => null)?['browser_download_url'];
        fn = "anicli-windows-portable.zip";
      }
    } else if (Platform.isLinux) {
      if (exe.startsWith('/usr/') || exe.startsWith('/opt/')) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_package_manager'))));
        return;
      }
      if (exe.endsWith('.appimage')) {
        url = assets.firstWhere((a) => a['name'].toString().endsWith('.AppImage'), orElse: () => null)?['browser_download_url'];
        fn = "anicli-linux-x64.AppImage";
      } else {
        url = assets.firstWhere((a) => a['name'].toString().endsWith('-portable.tar.gz'), orElse: () => null)?['browser_download_url'];
        fn = "anicli-linux-portable.tar.gz";
      }
    } else if (Platform.isMacOS) {
      url = assets.firstWhere((a) => a['name'].toString().endsWith('.zip'), orElse: () => null)?['browser_download_url'];
      fn = "anicli-macos.zip";
    }

    if (url == null) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_no_asset'))));
      return;
    }

    if (!context.mounted) return;
    final file = await showDialog<File?>(
      context: context, barrierDismissible: false,
      builder: (ctx) => GenericDownloadDialog(url: url!, fileName: fn!, title: context.tr('updater_downloading_title'), icon: LucideIcons.download, isUpdate: true),
    );

    if (file != null && context.mounted) {
      if (Platform.isAndroid) {
        if (!await file.exists() && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_apk_removed')), backgroundColor: kColorCoral));
          return;
        }
        final res = await OpenFile.open(file.path, type: "application/vnd.android.package-archive");
        if (res.type != ResultType.done && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_install_error', [res.message])), backgroundColor: kColorCoral));
      } else if (Platform.isWindows && runSetup) {
        await Process.start(file.path,[], mode: ProcessStartMode.detached);
        exit(0);
      } else {
        await launchUrl(Uri.directory(file.parent.path));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('updater_downloaded')), duration: Duration(seconds: 5)));
      }
    }
  }
}

class GenericDownloadDialog extends StatefulWidget {
  final String url, fileName, referer, title; final IconData icon; final bool isUpdate;
  const GenericDownloadDialog({super.key, required this.url, required this.fileName, this.referer = '', required this.title, required this.icon, this.isUpdate = false});
  @override State<GenericDownloadDialog> createState() => _GenericDownloadDialogState();
}
class _GenericDownloadDialogState extends State<GenericDownloadDialog> {
  double _prog = 0.0; String _status = "", _sizeInfo = ""; final http.Client _client = http.Client();
  @override void initState() { super.initState(); _status = context.tr('download_starting'); _start(); }
  @override void dispose() { _client.close(); super.dispose(); }

  Future<void> _start() async {
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir = await getDownloadsDirectory();
      }

      final file = File("${dir!.path}/${widget.fileName}");
      final req = http.Request('GET', Uri.parse(widget.url));
      if (widget.referer.isNotEmpty) req.headers['Referer'] = widget.referer;
      
      final res = await _client.send(req);
      if (res.statusCode != 200) throw Exception("HTTP ${res.statusCode}");
      
      final total = res.contentLength ?? 0; int rec = 0; final bytes = <int>[];
      res.stream.listen((b) {
        bytes.addAll(b); rec += b.length;
        setState(() { _prog = total > 0 ? rec / total : 0; _status = context.tr('download_downloading'); _sizeInfo = "${(rec/1024/1024).toStringAsFixed(1)} MB" + (total > 0 ? " / ${(total/1024/1024).toStringAsFixed(1)} MB" : ""); });
      }, onDone: () async {
        await file.writeAsBytes(bytes);
        if (mounted) { Navigator.pop(context, widget.isUpdate ? file : null); if (!widget.isUpdate) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('download_saved', [file.path])), backgroundColor: Colors.green)); }
      }, onError: (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('download_error', [e.toString()])))); } });
    } catch (e) { if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('download_failed_snack', [e.toString()])), backgroundColor: kColorCoral)); } }
  }

  @override Widget build(BuildContext context) => PopScope(canPop: false, child: Center(child: Material(color: Colors.transparent, child: Container(
    width: MediaQuery.of(context).size.width * 0.85, constraints: const BoxConstraints(maxWidth: 400), padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 15))]),
    child: Column(mainAxisSize: MainAxisSize.min, children:[
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: Icon(widget.icon, color: kColorCoral, size: 32).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, color: Colors.white).scale(begin: const Offset(1,1), end: const Offset(1.1,1.1), duration: 1000.ms, curve: Curves.easeInOut).then().scale(begin: const Offset(1.1,1.1), end: const Offset(1,1), curve: Curves.easeInOut)),
      const SizedBox(height: 20), Text(widget.title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 5), Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: Colors.black54)), const SizedBox(height: 5), Text(_status, style: GoogleFonts.inter(fontSize: 14, color: kColorDarkText)), const SizedBox(height: 20),
      TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: _prog), duration: const Duration(milliseconds: 200), builder: (ctx, val, _) => Column(children:[ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: val > 0 ? val : null, backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation<Color>(kColorCoral), minHeight: 8)), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text("${(val * 100).toInt()}%", style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: kColorCoral)), Text(_sizeInfo, style: GoogleFonts.inter(fontSize: 12, color: Colors.black45))])])),
      const SizedBox(height: 25), SizedBox(width: double.infinity, child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: kColorCoral), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), foregroundColor: kColorCoral), onPressed: () { _client.close(); Navigator.pop(context); }, child: Text(context.tr('download_cancel'))))
    ])
  ))).animate().fadeIn().scale(curve: Curves.easeOutBack));
}

// Shared Views & Animations
class LiquidGlassContainer extends StatelessWidget {
  final Widget child; final double blur, opacity; final BorderRadius? borderRadius; final Border? border; final bool useBlur;
  const LiquidGlassContainer({super.key, required this.child, this.blur=15, this.opacity=0.4, this.borderRadius, this.border, this.useBlur=false});
  @override Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20);
    final tier = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    if (tier == PerformanceTier.low) {
      return Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: br, border: border ?? Border.all(color: Colors.black12, width: 1)), child: child);
    }
    final isBlurHigh = useBlur && tier == PerformanceTier.high;
    final o = isBlurHigh ? opacity * 0.55 : opacity;
    final body = ClipRRect(
      borderRadius: br,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: border ?? Border.all(color: Colors.white.withOpacity(tier == PerformanceTier.high ? 0.5 : 0.3), width: 1.5),
          color: tier == PerformanceTier.high ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(o),
        ),
        child: child,
      ),
    );
    if (useBlur && tier == PerformanceTier.high) {
      const double ds = 0.5;
      final b = (blur * 0.5 * ds).clamp(2.0, 15.0);
      return ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.matrix(Matrix4.diagonal3Values(1.0 / ds, 1.0 / ds, 1.0).storage),
            inner: ImageFilter.compose(
              outer: ImageFilter.blur(sigmaX: b, sigmaY: b),
              inner: ImageFilter.matrix(Matrix4.diagonal3Values(ds, ds, 1.0).storage),
            ),
          ),
          child: body,
        ),
      );
    }
    return body;
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

  static const _cdnFallbacks = {'https://img.ophim.live': 'https://phimimg.com', 'https://phimimg.com': 'https://img.ophim.live'};
  String? _altCdnUrl(String? url) {
    if (url == null) return null;
    for (final e in _cdnFallbacks.entries) {
      if (url.startsWith(e.key)) return url.replaceFirst(e.key, e.value);
    }
    return null;
  }

  Map<String, String>? _getHeaders(String url) {
    if (url.contains('youtu-chan') || url.contains('fast4speed')) return const {'User-Agent': 'AniCli-Flutter/2.3.0', 'Referer': 'https://allanime.to/'};
    if (url.contains('zetimage.com')) return const {'referer': 'https://www.zettruyen.africa/'};
    return null;
  }

  @override Widget build(BuildContext context) {
    return Hero(tag: widget.heroTag, child: Material(color: Colors.transparent, child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.radius), boxShadow: (widget.withShadow && context.select<SettingsProvider, PerformanceTier>((p) => p.tier) != PerformanceTier.low) ?[BoxShadow(color: kColorCoral.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))] :[]),
      child: ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: CachedNetworkImage(
        imageUrl: _displayUrl!, fit: widget.boxFit, memCacheHeight: 600, httpHeaders: _getHeaders(_displayUrl!),
        placeholder: (_,__) => Container(color: kColorPeach),
        errorWidget: (ctx, url, err) {
          if (!_fallbackTried) {
            _fallbackTried = true;
            final altCdn = _altCdnUrl(_displayUrl);
            if (altCdn != null) {
              Future.microtask(() { if (mounted) setState(() => _displayUrl = altCdn); });
              return Container(color: kColorPeach);
            }
            if (widget.fallbackTitle != null) {
              Future.delayed(Duration.zero, () async {
                final fb = await MangaCore.findMangaDexCover(widget.fallbackTitle!);
                if (fb != null && mounted) setState(() => _displayUrl = fb);
              });
              return Container(color: kColorPeach);
            }
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
  void _check() { WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) { final t = context.read<SettingsProvider>().tier; if (t == PerformanceTier.low) _c.stop(); else if (t == PerformanceTier.mid) { _c.duration = const Duration(seconds: 30); _c.repeat(reverse: true); } else { _c.duration = const Duration(seconds: 15); _c.repeat(reverse: true); } } }); }
  @override void didChangeDependencies() { super.didChangeDependencies(); _check(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Stack(children:[
    AnimatedBuilder(animation: _c, builder: (ctx, _) => Container(width: double.infinity, height: double.infinity, decoration: BoxDecoration(gradient: LinearGradient(colors: const[kColorCream, kColorPeach], begin: _tA.value, end: _bA.value)))),
    NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollStartNotification) {
          _c.stop();
        } else if (notif is ScrollEndNotification) {
          final t = context.read<SettingsProvider>().tier;
          if (t != PerformanceTier.low) _c.repeat(reverse: true);
        }
        return false;
      },
      child: RepaintBoundary(child: widget.child),
    ),
  ]);
}

class FloatingOrbsBackground extends StatelessWidget {
  const FloatingOrbsBackground({super.key});
  Widget _orb(double s, Color c) => Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors:[c, c.withOpacity(0)], stops: const[0.4, 1.0])));
  @override Widget build(BuildContext context) {
    final tier = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    if (tier == PerformanceTier.low) return Container(color: Colors.transparent);
    final blurSigma = tier == PerformanceTier.high ? 25.0 : 15.0;
    final animate = tier == PerformanceTier.high;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: Stack(children:[
        if (animate)
          Positioned(top: -100, right: -100, child: _orb(400, kColorPeach).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2), duration: 6.seconds).rotate(begin: 0, end: 0.1, duration: 8.seconds))
        else
          Positioned(top: -100, right: -100, child: _orb(300, kColorPeach.withOpacity(0.6))),
        if (animate)
          Positioned(bottom: -150, left: -100, child: _orb(450, kColorCoral.withOpacity(0.4)).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.3,1.3), duration: 7.seconds).move(begin: Offset.zero, end: const Offset(20,-20), duration: 5.seconds))
        else
          Positioned(bottom: -100, left: -80, child: _orb(300, kColorCoral.withOpacity(0.25))),
        if (animate)
          Align(alignment: const Alignment(0, -0.3), child: _orb(300, kColorSoftPink.withOpacity(0.3)).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(0.8,0.8), end: const Offset(1.1,1.1), duration: 5.seconds).fadeIn()),
      ]),
    );
  }
}

// OOBE Setup Screens
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
    SizedBox(width: 60, height: 60, child: CircularProgressIndicator(strokeWidth: 5, valueColor: const AlwaysStoppedAnimation(kColorCoral), backgroundColor: kColorPeach.withOpacity(0.5))), const SizedBox(height: 30), Text(context.tr('welcome_loading'), style: GoogleFonts.inter(fontSize: 22, color: kColorDarkText, fontWeight: FontWeight.w600)).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0)
  ]);
  Widget _buildWelcome() => Column(key: const ValueKey("welcome"), mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children:[
    SizedBox(height: 100, child: AnimatedSwitcher(duration: const Duration(milliseconds: 600), transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: c)), child: Text(_greetings[_idx], key: ValueKey(_idx), textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 56, fontWeight: FontWeight.w800, color: kColorDarkText, height: 1.0, letterSpacing: -1.5)))), const SizedBox(height: 50),
    AnimatedOpacity(opacity: _idx == _greetings.length - 1 ? 1.0 : 0.0, duration: const Duration(milliseconds: 800), child: AnimatedContainer(duration: const Duration(milliseconds: 300), curve: Curves.easeOut, transform: Matrix4.identity()..scale(_idx == _greetings.length - 1 ? 1.0 : 0.9), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow:[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10), spreadRadius: 2)]), child: ElevatedButton(onPressed: _idx == _greetings.length - 1 ? _complete : null, style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 22), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 0), child: Row(mainAxisSize: MainAxisSize.min, children:[Text(context.tr('welcome_get_started'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 8), const Icon(LucideIcons.arrowRight, size: 20)])))))
  ]);
}

class SourceSelectScreen extends StatelessWidget { const SourceSelectScreen({super.key});
Future<void> _go(BuildContext context, AnimeSource source) async {
  await context.read<SourceProvider>().setSource(source);
  if (context.mounted) context.read<UserProvider>().setMode(source == AnimeSource.hentaivietsub);
  if (context.mounted) {
    final mp = context.read<MangaSourceProvider>();
    if (source == AnimeSource.en) await mp.setSource(MangaSource.en);
    else if (source == AnimeSource.vi) await mp.setSource(MangaSource.vi);
  }
  if (context.mounted) Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_,__,___) => const MainScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 600)));
}
@override Widget build(BuildContext context) => Scaffold(body: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors:[Color(0xFFFFF8F0), kColorCream])), child: Stack(fit: StackFit.expand, children:[
  const FloatingOrbsBackground(), SafeArea(child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(mainAxisSize: MainAxisSize.min, children:[
    Text(context.tr('choose_source'), style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 12), Text(context.tr('choose_source_sub'), style: GoogleFonts.inter(fontSize: 16, color: kColorDarkText.withOpacity(0.7))), const SizedBox(height: 40),
    _SourceOpt(title: context.tr('source_en_title'), subtitle: context.tr('source_en_sub'), flag: "🇺🇸", onTap: () => _go(context, AnimeSource.en)), const SizedBox(height: 16),
    _SourceOpt(title: context.tr('source_vi_title'), subtitle: context.tr('source_vi_sub'), flag: "🇻🇳", onTap: () => _go(context, AnimeSource.vi)),
  ])))),
])));
}

class _SourceOpt extends StatelessWidget {
  final String title, subtitle, flag; final VoidCallback onTap; const _SourceOpt({required this.title, required this.subtitle, required this.flag, required this.onTap});
  @override Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: LiquidGlassContainer(borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: Row(children:[
    Container(width: 56, height: 56, alignment: Alignment.center, decoration: BoxDecoration(color: kColorCoral.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: Text(flag, style: const TextStyle(fontSize: 28))), const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: kColorDarkText)), const SizedBox(height: 4), Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: kColorCoral, fontWeight: FontWeight.w600))])), const Icon(LucideIcons.chevronRight, color: kColorCoral),
  ])))));
}

// Main Shell UI
class MainScreen extends StatefulWidget { const MainScreen({super.key}); @override State<MainScreen> createState() => _MainScreenState(); }
class _MainScreenState extends State<MainScreen> {
  int _idx = 0; final GlobalKey _hKey = GlobalKey(), _fKey = GlobalKey(), _sKey = GlobalKey();
  void _openDetail(AnimeModel anime, String heroTag, {String? initialEpisode}) {
    Navigator.of(context).push(PageRouteBuilder(pageBuilder: (c, a, s) => AnimeDetailView(anime: anime, heroTag: heroTag, initialEpisode: initialEpisode), transitionsBuilder: (c, a, s, child) => context.read<SettingsProvider>().tier == PerformanceTier.low ? child : FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 600)));
  }
  void _continueAnime(AnimeModel anime, String episode) {
    if (anime.isManga) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => MangaReaderScreen(anime: anime, chapterNum: episode, allChapters: [])));
    } else {
      _openDetail(anime, "continue_${anime.id}", initialEpisode: episode);
    }
  }
  @override void initState() { super.initState(); UpdaterService.checkSilent(context); }
  @override Widget build(BuildContext context) {
    final sourceProvider = context.watch<SourceProvider>();
    final src = sourceProvider.source;

    Widget activePage; Key activeKey;
    switch (_idx) {
      case 0: activePage = BrowseView(key: ValueKey("Browse_${src.name}"), onAnimeTap: _openDetail); activeKey = ValueKey("BrowseTab_${src.name}"); break;
      case 1: activePage = HistoryView(key: _hKey, onAnimeTap: _openDetail, onContinueAnime: _continueAnime); activeKey = const ValueKey("HistoryTab"); break;
      case 2: activePage = FavoritesView(key: _fKey, onAnimeTap: _openDetail, onContinueAnime: _continueAnime); activeKey = const ValueKey("FavTab"); break;
      default: activePage = SettingsView(key: _sKey); activeKey = const ValueKey("SettingsTab"); break;
    }
    final tier = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    return Scaffold(body: LiveGradientBackground(child: Stack(fit: StackFit.expand, children:[
      AnimatedSwitcher(duration: tier == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 500), switchInCurve: Curves.easeOutQuart, switchOutCurve: Curves.easeInQuart, transitionBuilder: (child, animation) => tier == PerformanceTier.low ? child : FadeTransition(opacity: animation, child: tier == PerformanceTier.high ? SlideTransition(position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation), child: child) : child), child: KeyedSubtree(key: activeKey, child: activePage)),
      Positioned(bottom: 30, left: 0, right: 0, child: Center(child: RepaintBoundary(child: GlassDock(selectedIndex: _idx, onItemSelected: (i) => setState(() => _idx = i))))),
    ])));
  }
}

// Specialized Players
class MangaReaderScreen extends StatefulWidget {
  final AnimeModel anime; final String chapterNum; final List<String> allChapters;
  const MangaReaderScreen({super.key, required this.anime, required this.chapterNum, required this.allChapters});
  @override State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

String _mangaChapterDir(AnimeModel anime, String chapterNum) {
  final safeTitle = anime.name.replaceAll(RegExp(r'[^\w\s]+'), '');
  final safeChap = chapterNum.replaceAll(RegExp(r'[^\w\s]+'), '_');
  return "$safeTitle/Ch$safeChap";
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  bool _isLoading = true, _showControls = true, _isCtrlPressed = false;
  List<String> _pages = []; int _pointerCount = 0;
  final TransformationController _tCtrl = TransformationController();
  final ScrollController _sCtrl = ScrollController();
  bool _resumed = false;
  bool _isDownloadingChapter = false;

  @override
  void initState() {
    super.initState();
    _sCtrl.addListener(_onScroll);
    _loadPages();
  }

  @override
  void dispose() {
    _sCtrl.removeListener(_onScroll);
    _sCtrl.dispose();
    _tCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sCtrl.hasClients || _pages.isEmpty) return;
    final idx = (_sCtrl.offset / _sCtrl.position.maxScrollExtent * _pages.length).round().clamp(0, _pages.length - 1);
    context.read<ProgressProvider>().saveMangaPage(widget.anime.id, widget.chapterNum, idx);
  }

  Future<String> _localDir() async {
    final base = await getApplicationDocumentsDirectory();
    return base.path;
  }

  bool _isChapterDownloaded() {
    // We check synchronously; _checkChapterDownloaded is the async version
    return false;
  }

  Future<bool> _checkChapterDownloaded() async {
    final base = await _localDir();
    final chapDir = _mangaChapterDir(widget.anime, widget.chapterNum);
    final dir = Directory("$base/$chapDir");
    if (!await dir.exists()) return false;
    final files = await dir.list().toList();
    return files.isNotEmpty;
  }

  Future<void> _loadPages() async {
    setState(() => _isLoading = true);
    final base = await _localDir();
    final chapDir = _mangaChapterDir(widget.anime, widget.chapterNum);
    final localDir = Directory("$base/$chapDir");
    List<String> pages;

    if (await localDir.exists()) {
      final files = await localDir.list().toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      pages = files.map((f) => f.path).toList();
    } else {
      final src = widget.anime.sourceId;
      pages = src == 'zettruyen'
          ? await ZetTruyenCore.getPages(widget.anime.id, widget.chapterNum)
          : src == 'weebcentral'
              ? await WeebCentralCore.getPages(widget.anime.id, widget.chapterNum)
              : src == 'truyenqq'
                  ? await TruyenQQCore.getPages(widget.anime.id, widget.chapterNum)
                  : await MangaCore.getPages(widget.chapterNum);
    }

    if (mounted) {
      setState(() { _pages = pages; _isLoading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_resumed && _sCtrl.hasClients) {
          final saved = context.read<ProgressProvider>().getMangaPage(widget.anime.id, widget.chapterNum);
          if (saved > 0 && saved < _pages.length) {
            final target = (saved / _pages.length * _sCtrl.position.maxScrollExtent).clamp(0.0, _sCtrl.position.maxScrollExtent);
            _sCtrl.jumpTo(target);
            _resumed = true;
          }
        }
      });
    }
  }

  void _nav(String newChap) {
    context.read<UserProvider>().addToHistory(widget.anime, newChap);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MangaReaderScreen(
          anime: widget.anime, chapterNum: newChap, allChapters: widget.allChapters,
        ),
      ),
    );
  }

  Map<String, String> _sourceHeaders() {
    final src = widget.anime.sourceId;
    if (src == 'zettruyen') return {'referer': 'https://www.zettruyen.ink/'};
    if (src == 'truyenqq') return {'referer': 'https://truyenqq.com.vn/'};
    return {'User-Agent': 'AniCli/1.0'};
  }

  Future<void> _downloadChapter() async {
    setState(() => _isDownloadingChapter = true);
    try {
      final base = await _localDir();
      final chapDir = _mangaChapterDir(widget.anime, widget.chapterNum);
      final dir = Directory("$base/$chapDir");
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      final headers = _sourceHeaders();
      for (int i = 0; i < _pages.length; i++) {
        final res = await http.get(Uri.parse(_pages[i]), headers: headers);
        if (res.statusCode == 200) {
          final file = File("${dir.path}/page_${i + 1}.jpg");
          await file.writeAsBytes(res.bodyBytes);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('chapter_downloaded'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('download_failed', [e.toString()]))),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingChapter = false);
    }
  }

  Future<void> _deleteDownloadedChapter() async {
    final base = await _localDir();
    final chapDir = _mangaChapterDir(widget.anime, widget.chapterNum);
    final dir = Directory("$base/$chapDir");
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('downloaded_deleted'))),
        );
      }
    }
  }

  @override Widget build(BuildContext context) {
    final idx = widget.allChapters.indexOf(widget.chapterNum);
    final headers = _sourceHeaders();
    final displayChap = widget.chapterNum.contains('|') ? widget.chapterNum.split('|')[1] : widget.chapterNum;

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (e) {
          if (e.logicalKey == LogicalKeyboardKey.controlLeft ||
              e.logicalKey == LogicalKeyboardKey.controlRight) {
            setState(() => _isCtrlPressed = e is KeyDownEvent || e is KeyRepeatEvent);
          }
        },
        child: Stack(children: [
          Listener(
            onPointerDown: (_) => setState(() => _pointerCount++),
            onPointerUp: (_) => setState(() => _pointerCount--),
            onPointerCancel: (_) => setState(() => _pointerCount = 0),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                if (_isCtrlPressed) {
                  final scale = e.scrollDelta.dy < 0 ? 1.1 : 0.9;
                  final currentMatrix = _tCtrl.value;
                  final newScale = (currentMatrix.getMaxScaleOnAxis() * scale).clamp(0.01, 10.0);
                  if (newScale >= 0.01 && newScale <= 10.0) {
                    final c = Offset(
                      MediaQuery.of(context).size.width / 2,
                      MediaQuery.of(context).size.height / 2,
                    );
                    _tCtrl.value = (Matrix4.identity()
                          ..translate(c.dx, c.dy)
                          ..scale(scale)
                          ..translate(-c.dx, -c.dy)) *
                        currentMatrix;
                  }
                } else if (_sCtrl.hasClients) {
                  _sCtrl.jumpTo((_sCtrl.offset + e.scrollDelta.dy).clamp(
                    _sCtrl.position.minScrollExtent,
                    _sCtrl.position.maxScrollExtent,
                  ));
                }
              }
            },
            child: GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kColorCoral))
                  : InteractiveViewer(
                      transformationController: _tCtrl,
                      minScale: 0.01,
                      maxScale: 10.0,
                      scaleEnabled: _isCtrlPressed || _pointerCount > 1,
                      panEnabled: true,
                      trackpadScrollCausesScale: false,
                      interactionEndFrictionCoefficient: 0.00001,
                      child: ListView.builder(
                        controller: _sCtrl,
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        cacheExtent: 3000,
                        itemCount: _pages.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == _pages.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 60),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  if (idx < widget.allChapters.length - 1)
                                    ElevatedButton(
                                      onPressed: () =>
                                          _nav(widget.allChapters[idx + 1]),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey[800]),
                                      child: Text(context.tr('previous_chapter'), style: const TextStyle(color: Colors.white)),
                                    ),
                                  if (idx > 0)
                                    ElevatedButton(
                                      onPressed: () =>
                                          _nav(widget.allChapters[idx - 1]),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: kColorCoral),
                                      child: Text(context.tr('next_chapter'), style: const TextStyle(color: Colors.white)),
                                    ),
                                ],
                              ),
                            );
                          }
                          return Container(
                            alignment: Alignment.center,
                            color: Colors.black,
                            child: _pages[i].contains('://')
                                ? CachedNetworkImage(
                                    imageUrl: _pages[i],
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    memCacheHeight: 1200,
                                    placeholder: (_, __) => const SizedBox(
                                      height: 300,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                            color: kColorCoral,
                                            strokeWidth: 2),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => const SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: Icon(Icons.broken_image,
                                            color: Colors.white54),
                                      ),
                                    ),
                                    httpHeaders: headers,
                                  )
                                : Image.file(
                                    File(_pages[i]),
                                    fit: BoxFit.contain,
                                    width: double.infinity,
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
              padding: const EdgeInsets.all(10),
              child: SafeArea(
                bottom: false,
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.anime.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            maxLines: 1),
                        Text(context.tr('chapter_prefix', [displayChap]),
                            style: const TextStyle(
                                color: kColorCoral, fontSize: 12)),
                      ],
                    ),
                  ),
                  FutureBuilder<bool>(
                    future: _checkChapterDownloaded(),
                    builder: (ctx, snap) {
                      final downloaded = snap.data ?? false;
                      return IconButton(
                        icon: _isDownloadingChapter
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(
                                downloaded
                                    ? LucideIcons.trash2
                                    : LucideIcons.download,
                                color: Colors.white),
                        onPressed: _isDownloadingChapter
                            ? null
                            : () {
                                if (downloaded) {
                                  _deleteDownloadedChapter().then((_) =>
                                      setState(() {}));
                                } else {
                                  _downloadChapter();
                                }
                              },
                      );
                    },
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

const String _kPlayerUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

class StreamEntry {
  final String url;
  final String referer;
  final Map<String, String> extraHeaders;
  StreamEntry(this.url, {this.referer = '', Map<String, String>? extraHeaders}) : extraHeaders = extraHeaders ?? const {};
}

class InternalPlayerScreen extends StatefulWidget {
  final String title, animeId, epNum;
  final List<StreamEntry> urls;
  const InternalPlayerScreen({super.key, required this.urls, required this.title, required this.animeId, required this.epNum});
  @override State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}
class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late final Player _p; late final VideoController _c; late ProgressProvider _prog;
  bool _showControls = true, _showFwd = false, _showRwd = false, _resumeChecked = false;
  Timer? _hideT, _progT; StreamSubscription? _durSub;
  int _urlIndex = 0;

  StreamEntry get _current => widget.urls[_urlIndex];

  bool _needsYtdlp(String url) {
    // Resolved direct video URLs — let mpv handle directly
    if (url.endsWith('.mp4') || url.endsWith('.webm') || url.endsWith('.mkv') || url.endsWith('.ts')) return false;
    // Embed pages that need yt-dlp extraction
    if (url.contains('/embed') || url.contains('/e/') || url.contains('ok.ru/videoembed')) return true;
    return false;
  }

  Future<String> _resolveUrl(String url, Map<String, String> headers) async {
    if (!_needsYtdlp(url)) return url;
    await YtdlProxy.setHeaders(headers);
    return YtdlProxy.proxyUrl(url);
  }

  void _tryNextUrl() {
    if (!mounted) return;
    _urlIndex++;
    if (_urlIndex >= widget.urls.length) return;
    _openCurrent();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trying next source...'), duration: const Duration(seconds: 2)));
  }

  Future<void> _openCurrent() async {
    final headers = _buildHeaders();
    final playUrl = await _resolveUrl(_current.url, headers);
    debugPrint('[DEBUG] InternalPlayer url=$playUrl headers=$headers');
    _applyHeadersToPlayer(headers);
    _p.open(Media(playUrl));
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{};
    final ref = _current.referer.isNotEmpty ? _current.referer : AniCore.referer;
    if (ref.isNotEmpty) headers['Referer'] = ref;
    if (_current.extraHeaders.isNotEmpty) {
      headers.addAll(_current.extraHeaders);
    } else {
      headers['User-Agent'] = _kPlayerUA;
    }
    return headers;
  }

  void _applyHeadersToPlayer(Map<String, String> headers) {
    debugPrint('[DEBUG] mpv http-header-fields: $headers');
    try {
      final headerStr = headers.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      (_p.platform as dynamic).setProperty('http-header-fields', headerStr);
    } catch (e) {
      debugPrint('[DEBUG] Failed to set http-header-fields: $e');
    }
  }

  @override void initState() {
    super.initState(); _p = Player(configuration: const PlayerConfiguration(vo: 'gpu'));
    _c = VideoController(_p, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true, androidAttachSurfaceAfterVideoParameters: true));
    try { (_p.platform as dynamic).setProperty('ytdl', 'yes'); } catch (_) {}

    final cacheSecs = context.read<SettingsProvider>().cacheSecs;
    try {
      if (cacheSecs > 300) {
        (_p.platform as dynamic).setProperty('cache', 'yes');
        (_p.platform as dynamic).setProperty('demuxer-max-bytes', '2000000000');
        (_p.platform as dynamic).setProperty('demuxer-readahead-secs', '99999');
      } else {
        (_p.platform as dynamic).setProperty('demuxer-readahead-secs', cacheSecs.toString());
      }
    } catch (_) {}

    _durSub = _p.stream.duration.listen((d) { if (!_resumeChecked && d.inSeconds > 0) { _resumeChecked = true; _checkResume(); } });
    _openCurrent();
    _p.stream.error.listen((e) { debugPrint('[DEBUG] mpv error: $e'); _tryNextUrl(); });
    _p.stream.completed.listen((_) => debugPrint('[DEBUG] mpv completed'));
    _p.stream.log.listen((l) { if (l.level == 'error' || l.level == 'warn' || l.level == 'info') debugPrint('[DEBUG] mpv ${l.level}: ${l.text}'); });
    _p.stream.buffering.listen((b) { if (b) debugPrint('[DEBUG] mpv buffering...'); else debugPrint('[DEBUG] mpv done buffering'); });
    _p.stream.position.listen((p) { if (p.inSeconds % 10 == 0) debugPrint('[DEBUG] mpv position: $p'); }, onError: (e) => debugPrint('[DEBUG] mpv position error: $e'));
    _progT = Timer.periodic(const Duration(seconds: 5), (_) { if (mounted && _p.state.position.inSeconds > 10) context.read<ProgressProvider>().saveProgress(widget.animeId, widget.epNum, _p.state.position.inSeconds); });
    _p.play(); _p.setVolume(100); _startHide();
  }
  @override void didChangeDependencies() { super.didChangeDependencies(); _prog = context.read<ProgressProvider>(); }
  Future<void> _checkResume() async {
    if (!mounted) return;
    final saved = _prog.getProgress(widget.animeId, widget.epNum);
    if (saved > 10) {
      await _p.pause(); if (!mounted) return;
      final res = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(backgroundColor: kColorCream, title: Text(context.tr('resume_title'), style: const TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)), content: Text(context.tr('resume_content', [_fmt(Duration(seconds: saved))])), actions:[TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('resume_start_over'), style: const TextStyle(color: Colors.black54))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('resume_resume')))]));
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
  @override void dispose() { _durSub?.cancel(); _progT?.cancel(); _hideT?.cancel(); _p.stop(); try { if (_p.state.position.inSeconds > 10) _prog.saveProgress(widget.animeId, widget.epNum, _p.state.position.inSeconds); } catch (_) {} _p.dispose(); YtdlProxy.stop(); super.dispose(); }
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
    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(children:[
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

// Navigational Views
class BrowseView extends StatefulWidget { final Function(AnimeModel, String) onAnimeTap; const BrowseView({super.key, required this.onAnimeTap}); @override State<BrowseView> createState() => _BrowseViewState(); }
class _BrowseViewState extends State<BrowseView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _sCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<AnimeModel> _items =[];
  bool _isLoading = true, _isMangaMode = false;
  String _query = "";
  int _page = 1;

  @override bool get wantKeepAlive => true;

  @override void initState() { super.initState(); _loadData(); }

  @override void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadData() async {
    setState(() => _isLoading = true);
    final sp = context.read<SourceProvider>();
    final src = sp.source;
    final mangaSrc = context.read<MangaSourceProvider>().source;

    final useProvider = src == AnimeSource.en;
    final useVi = src == AnimeSource.vi;
    final isNSFW = src == AnimeSource.hentaivietsub;
    debugPrint('[DEBUG] _loadData src=$src useProvider=$useProvider useVi=$useVi isNSFW=$isNSFW _query="$_query" _page=$_page _isMangaMode=$_isMangaMode');

    List<AnimeModel> res =[];
    if (_isMangaMode) {
      debugPrint('[MangaBrowse] mangaSrc=$mangaSrc query="${_query}"');
      if (_query.isEmpty) {
        if (mangaSrc == MangaSource.zettruyen) { res = await ZetTruyenCore.getTrending(); }
        else if (mangaSrc == MangaSource.weebcentral) { res = await WeebCentralCore.getTrending(); }
        else if (mangaSrc == MangaSource.truyenqq) { res = await TruyenQQCore.getTrending(); }
        else if (mangaSrc == MangaSource.en) { res = await EnMangaCore.getTrending(); }
        else if (mangaSrc == MangaSource.vi) { res = await ViMangaCore.getTrending(); }
        else { res = await MangaCore.getTrending(); }
      } else {
        if (mangaSrc == MangaSource.zettruyen) { res = await ZetTruyenCore.search(_query); }
        else if (mangaSrc == MangaSource.weebcentral) { res = await WeebCentralCore.search(_query); }
        else if (mangaSrc == MangaSource.truyenqq) { res = await TruyenQQCore.search(_query); }
        else if (mangaSrc == MangaSource.en) { res = await EnMangaCore.search(_query); }
        else if (mangaSrc == MangaSource.vi) { res = await ViMangaCore.search(_query); }
        else { res = await MangaCore.search(_query); }
      }
      debugPrint('[MangaBrowse] got ${res.length} results');
    } else if (useProvider) {
      try {
        res = await ProviderCoordinator.searchAsAnimeModel(_query, 'sub');
      } catch (e) {
        debugPrint('Provider search error: $e');
      }
    } else {
      res = _query.isEmpty
      ? (useVi ? await ViAnimeCore.getTrending(page: _page) : (isNSFW ? await HentaiVietsubCore.getTrending(page: _page) : await AniCore.getTrending(page: _page)))
      : (useVi ? await ViAnimeCore.search(_query, page: _page) : (isNSFW ? await HentaiVietsubCore.search(_query, page: _page) : await AniCore.search(_query, page: _page)));
    }

    unawaited(precacheThumbnails(res));
    if (mounted) setState(() { _items = res; _isLoading = false; });
  }

  void _doSearch(String q) {
    setState(() { _query = q; _page = 1; });
    _loadData();
  }

  void _toggleMode(bool m) {
    if (_isMangaMode == m) return;
    setState(() { _isMangaMode = m; _items.clear(); _query = ""; _page = 1; _sCtrl.clear(); });
    _loadData();
  }

  void _changePage(int delta) {
    if (_page + delta < 1) return;
    setState(() { _page += delta; });
    _loadData();
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  @override Widget build(BuildContext context) {
    super.build(context);
    final isMobile = MediaQuery.of(context).size.width < 900;
    final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    final mangaSrc = context.watch<MangaSourceProvider>().source;
    final isNSFW = context.watch<SourceProvider>().isNSFW;

    String hint = isNSFW ? context.tr('search_hint_nsfw') : _isMangaMode ? context.tr('search_hint_manga') : context.tr('search_hint_anime');

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          const SizedBox(height: 50),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
            child: Row(
              children:[
                GestureDetector(onTap: () => _toggleMode(false), child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: !_isMangaMode ? kColorCoral : Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(20), boxShadow: !_isMangaMode ?[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 10)] :[]), child: Text(isNSFW ? context.tr('nsfw_badge') : context.tr('mode_anime'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: !_isMangaMode ? Colors.white : kColorDarkText.withOpacity(0.6))))),
                const SizedBox(width: 15),
                GestureDetector(onTap: () => _toggleMode(true), child: AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: _isMangaMode ? kColorCoral : Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(20), boxShadow: _isMangaMode ?[BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 10)] :[]), child: Text(context.tr('mode_manga'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _isMangaMode ? Colors.white : kColorDarkText.withOpacity(0.6))))),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
            child: Row(
              children:[
                if (_query.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 15), child: IconButton(onPressed: () { _sCtrl.clear(); _doSearch(""); }, icon: const Icon(LucideIcons.arrowLeftCircle, color: kColorCoral, size: 32))),
                  Expanded(child: LiquidGlassContainer(borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(controller: _sCtrl, style: const TextStyle(color: kColorDarkText, fontWeight: FontWeight.w600), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.black38), border: InputBorder.none, icon: const Icon(LucideIcons.search, color: kColorCoral)), onSubmitted: _doSearch)))),
              ],
            ),
          ).adapt(t, delay: 200, slideY: true),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: t == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuart,
                child: _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: kColorCoral)))
                : KeyedSubtree(
                  key: ValueKey("Grid_$_isMangaMode$_query$_page"),
                  child: _items.isEmpty
                  ? Center(child: Text(context.tr('no_results'), style: GoogleFonts.inter(color: Colors.black26)))
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_query.isEmpty && _page == 1) ...[
                        if (!_isMangaMode && _items.length > 5) ...[
                          Padding(padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15), child: Text(isNSFW ? context.tr('hot_videos') : context.tr('spotlight'), style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorCoral))).adapt(t, delay: 200, slideY: true),
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
                                        mangaSrc == MangaSource.mangadex ? context.tr('manga_mangadex') : mangaSrc == MangaSource.zettruyen ? context.tr('manga_zettruyen') : mangaSrc == MangaSource.truyenqq ? context.tr('manga_truyenqq') : mangaSrc == MangaSource.en ? context.tr('manga_en') : mangaSrc == MangaSource.vi ? context.tr('manga_vi') : context.tr('manga_weebcentral'),
                                        style: GoogleFonts.outfit(fontSize: 40, fontWeight: FontWeight.bold, color: kColorDarkText),
                                      ),
                                      Text(
                                        mangaSrc == MangaSource.mangadex ? context.tr('manga_mangadex_sub') : mangaSrc == MangaSource.zettruyen ? context.tr('manga_zettruyen_sub') : mangaSrc == MangaSource.truyenqq ? context.tr('manga_truyenqq_sub') : mangaSrc == MangaSource.en ? context.tr('manga_en_sub') : mangaSrc == MangaSource.vi ? context.tr('manga_vi_sub') : context.tr('manga_weebcentral_sub'),
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
                      Padding(padding: EdgeInsets.only(left: isMobile ? 20 : 40, bottom: 15), child: Text(_query.isEmpty ? (_isMangaMode ? context.tr('popular_updates') : (isNSFW ? context.tr('latest_updates') : context.tr('trending_anime'))) : context.tr('results'), style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kColorDarkText))).adapt(t, delay: 200, slideY: true),
                      AnimeGrid(animes: _items, onTap: widget.onAnimeTap, tagPrefix: "browse"),

                      if (!_isMangaMode)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children:[
                              if (_page > 1)
                                ElevatedButton.icon(
                                  onPressed: () => _changePage(-1),
                                  icon: const Icon(LucideIcons.chevronLeft),
                                  label: Text(context.tr('prev')),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kColorDarkText),
                                ),
                                if (_page > 1) const SizedBox(width: 20),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(20)),
                                    child: Text(context.tr('page', [_page.toString()]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 20),
                                  if (_items.isNotEmpty)
                                    ElevatedButton.icon(
                                      onPressed: () => _changePage(1),
                                      icon: const Icon(LucideIcons.chevronRight),
                                      label: Text(context.tr('next')),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kColorDarkText),
                                    ),
                            ],
                          ),
                        ),

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

class HistoryView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  final Function(AnimeModel, String)? onContinueAnime;
  const HistoryView({super.key, required this.onAnimeTap, this.onContinueAnime});
  @override State<HistoryView> createState() => _HistoryViewState();
}
class _HistoryViewState extends State<HistoryView> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    final isNSFW = context.watch<UserProvider>().isNSFW;
    final history = context.watch<UserProvider>().history;
    final isMobile = MediaQuery.of(context).size.width < 900;
    final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);

    return Column(children:[
      const SizedBox(height: 60),
      Row(mainAxisAlignment: MainAxisAlignment.center, children:[
        Text(isNSFW ? context.tr('incognito_history') : context.tr('tab_history'), style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)),
        if (history.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 10), child: IconButton(icon: const Icon(LucideIcons.trash2, size: 20, color: kColorDarkText), onPressed: () => context.read<UserProvider>().clearHistory()))
      ]).adapt(t),
      const SizedBox(height: 20),
      Expanded(child: history.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children:[Icon(isNSFW ? LucideIcons.eyeOff : LucideIcons.ghost, size: 60, color: kColorCoral.withOpacity(0.5)), const SizedBox(height: 10), Text(isNSFW ? context.tr('no_incognito_history') : context.tr('no_history'), style: GoogleFonts.inter(color: Colors.black45, fontSize: 16))]))
      : ListView.builder(padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: 10), physics: const BouncingScrollPhysics(), itemCount: history.length, itemBuilder: (ctx, i) => HistoryCard(
        item: history[i], onTap: () => widget.onAnimeTap(history[i].anime, "history_${history[i].anime.id}"),
        onContinue: widget.onContinueAnime != null ? () => widget.onContinueAnime!(history[i].anime, history[i].episode) : null,
      ).simpleDrop(t, delay: i > 8 ? 0 : i * 50)))
    ]);
  }
}

class FavoritesView extends StatefulWidget {
  final Function(AnimeModel, String) onAnimeTap;
  final Function(AnimeModel, String)? onContinueAnime;
  const FavoritesView({super.key, required this.onAnimeTap, this.onContinueAnime}); @override State<FavoritesView> createState() => _FavoritesViewState(); }
class _FavoritesViewState extends State<FavoritesView> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    final isNSFW = context.watch<UserProvider>().isNSFW;
    final favorites = context.watch<UserProvider>().favorites;
    final history = context.watch<UserProvider>().history;
    final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);

    final continueMap = <String, VoidCallback>{};
    if (widget.onContinueAnime != null) {
      for (final fav in favorites) {
        final found = history.where((h) => h.anime.id == fav.id);
        if (found.isNotEmpty) {
          final episode = found.first.episode;
          continueMap[fav.id] = () => widget.onContinueAnime!(fav, episode);
        }
      }
    }

    return Column(children:[
      const SizedBox(height: 60),
      Text(isNSFW ? context.tr('dark_favorites') : context.tr('tab_favorites'), style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)).adapt(t, slideY: true, slideBegin: -0.5),
      const SizedBox(height: 20),
      Expanded(child: favorites.isEmpty
      ? Center(child: Text(isNSFW ? context.tr('no_favorites_incognito') : context.tr('no_favorites'), style: GoogleFonts.inter(color: Colors.black26)))
      : AnimeGrid(animes: favorites, onTap: widget.onAnimeTap, physics: const BouncingScrollPhysics(), shrinkWrap: false, tagPrefix: "fav", continueCallbacks: continueMap.isNotEmpty ? continueMap : null))
    ]);
  }
}

class SettingsView extends StatefulWidget { const SettingsView({super.key}); @override State<SettingsView> createState() => _SettingsViewState(); }
class _SettingsViewState extends State<SettingsView> {
  Future<void> _url(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('url_launch_failed', [url])), backgroundColor: kColorCoral));
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
    child: Material(type: MaterialType.transparency, child: SwitchListTile(
      value: v,
      onChanged: o,
      activeColor: kColorCoral,
      secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: kColorCoral, size: 24)),
      title: Text(t, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Text(s, style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
    ))
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
      _sec(context.tr('section_content')),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(children: [Icon(LucideIcons.globe, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('setting_anime_source'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<AnimeSource>(
                value: tp.source,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: [
                  DropdownMenuItem(value: AnimeSource.en, child: Text(context.tr('source_en'))),
                  DropdownMenuItem(value: AnimeSource.vi, child: Text(context.tr('source_vi'))),
                  DropdownMenuItem(value: AnimeSource.hentaivietsub, child: Text(context.tr('source_nsfw'), style: const TextStyle(color: kColorCoral, fontWeight: FontWeight.bold))),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    if (v == AnimeSource.hentaivietsub && tp.source != AnimeSource.hentaivietsub) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: kColorCream,
                          title: Row(children:[const Icon(LucideIcons.alertTriangle, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('nsfw_warning_title'), style: const TextStyle(color: kColorCoral, fontWeight: FontWeight.bold))]),
                          content: Text(context.tr('nsfw_warning_content')),
                          actions:[
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'), style: const TextStyle(color: Colors.black54))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(context.tr('nsfw_warning_confirm')),
                            ),
                          ]
                        )
                      );
                      if (confirm == true) {
                        tp.setSource(v);
                        context.read<UserProvider>().setMode(true);
                      }
                    } else {
                      tp.setSource(v);
                      context.read<UserProvider>().setMode(v == AnimeSource.hentaivietsub);
                    }
                  }
                }
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
              Row(children: [Icon(LucideIcons.bookOpen, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('setting_manga_source'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<MangaSource>(
                value: mp.source,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: [
                  DropdownMenuItem(value: MangaSource.en, child: Text(context.tr('manga_source_en'))),
                  DropdownMenuItem(value: MangaSource.vi, child: Text(context.tr('manga_source_vi'))),
                  DropdownMenuItem(value: MangaSource.mangadex, child: Text(context.tr('manga_source_mangadex'))),
                  DropdownMenuItem(value: MangaSource.zettruyen, child: Text(context.tr('manga_source_zettruyen'))),
                  DropdownMenuItem(value: MangaSource.weebcentral, child: Text(context.tr('manga_source_weebcentral'))),
                  DropdownMenuItem(value: MangaSource.truyenqq, child: Text(context.tr('manga_source_truyenqq'))),
                ],
                onChanged: (v) { if (v != null) mp.setSource(v); }
              )
            ]
          )
        )
      ),
      const SizedBox(height: 15),
      _sec(context.tr('settings_general')),
      LiquidGlassContainer(opacity: 0.6, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Row(children: [Icon(LucideIcons.globe, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('setting_language'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 10),
        DropdownButton<AppLocale>(
          value: sp.locale,
          isExpanded: true, dropdownColor: kColorCream, underline: Container(height: 1, color: kColorCoral),
          items: [
            DropdownMenuItem(value: AppLocale.en, child: Text(context.tr('en_source'))),
            DropdownMenuItem(value: AppLocale.vi, child: Text(context.tr('vi_source'))),
          ],
          onChanged: (v) { if (v != null) sp.setLocale(v); }
        )
      ]))),
      const SizedBox(height: 10),
      _cd(LucideIcons.downloadCloud, context.tr('check_updates'), context.tr('setting_check_updates_sub'), onTap: () => UpdaterService.checkAndUpdate(context)),
      const SizedBox(height: 10),
      _cd(LucideIcons.trash2, context.tr('clear_cache'), context.tr('setting_clear_cache_sub'), onTap: () async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        try { await DefaultCacheManager().emptyCache(); } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('cache_cleared')), backgroundColor: Colors.green));
      }),
      const SizedBox(height: 10),
      _cd(LucideIcons.archive, context.tr('backup_data'), context.tr('setting_backup_sub'), onTap: () async {
        try {
          final json = await BackupService.exportData();
          final bytes = Uint8List.fromList(utf8.encode(json));
          final path = await FilePicker.saveFile(dialogTitle: context.tr('save_backup'), fileName: "anicli_backup.json", type: FileType.custom, allowedExtensions: ['json'], bytes: bytes);
          if (path != null) {
            if (!Platform.isAndroid && !Platform.isIOS) {
              await File(path).writeAsString(json);
            }
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('backup_saved')), backgroundColor: Colors.green));
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('backup_failed', [e.toString()])), backgroundColor: Colors.red));
        }
      }),
      const SizedBox(height: 10),
      _cd(LucideIcons.upload, context.tr('restore_data'), context.tr('setting_restore_sub'), onTap: () async {
        try {
          final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
          if (result == null || result.files.isEmpty) return;
          final json = await File(result.files.first.path!).readAsString();
          final ok = await BackupService.importData(json);
          if (mounted) {
            if (ok) {
              await context.read<UserProvider>().reload();
              await context.read<SourceProvider>().reload();
              await context.read<MangaSourceProvider>().reload();
              await context.read<SettingsProvider>().reload();
              await context.read<ProgressProvider>().reload();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('data_restored')), backgroundColor: Colors.green));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('invalid_backup')), backgroundColor: Colors.red));
            }
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('restore_failed', [e.toString()])), backgroundColor: Colors.red));
        }
      }),
      const SizedBox(height: 10),
      _sec(context.tr('section_performance')),
      LiquidGlassContainer(
        opacity: 0.6,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(children: [Icon(LucideIcons.zap, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('setting_visual_mode'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
              const SizedBox(height: 10),
              DropdownButton<PerformanceMode>(
                value: sp.perfMode,
                isExpanded: true,
                dropdownColor: kColorCream,
                underline: Container(height: 1, color: kColorCoral),
                items: [
                  DropdownMenuItem(value: PerformanceMode.auto, child: Text(context.tr('perf_auto_sub'))),
                  DropdownMenuItem(value: PerformanceMode.bestLooking, child: Text(context.tr('perf_best_looking_sub'))),
                  DropdownMenuItem(value: PerformanceMode.balanced, child: Text(context.tr('perf_balanced_sub'))),
                  DropdownMenuItem(value: PerformanceMode.bestPerformance, child: Text(context.tr('perf_best_performance_sub'))),
                ],
                onChanged: (v) { if (v != null) sp.setPerformanceMode(v); }
              ),
              const SizedBox(height: 5),
              Text(context.tr('current_tier', [sp.tier.name.toUpperCase(), sp.ramDebugInfo]), style: const TextStyle(fontSize: 12, color: Colors.black54))
            ]
          )
        )
      ),
      const SizedBox(height: 10),
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) ...[
        _sw(LucideIcons.playCircle, context.tr('use_internal_player'), context.tr('setting_internal_player_sub'), sp.useInternalPlayer, (v) => sp.toggleInternalPlayer(v)),
        const SizedBox(height: 15),
        LiquidGlassContainer(
          opacity: 0.6,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Row(children: [Icon(LucideIcons.hardDrive, color: kColorCoral), const SizedBox(width: 10), Text(context.tr('setting_video_cache'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                const SizedBox(height: 5),
                Text(context.tr('buffer_duration', [sp.cacheSecs > 300 ? context.tr('unlimited') : '${sp.cacheSecs.toInt()} ${context.tr('seconds')}']), style: const TextStyle(color: Colors.black54, fontSize: 13)),
                Slider(
                  value: sp.cacheSecs, min: 10, max: 310, divisions: 30,
                  activeColor: kColorCoral, inactiveColor: kColorPeach,
                  label: sp.cacheSecs > 300 ? context.tr('unlimited') : "${sp.cacheSecs.toInt()}s",
                  onChanged: (v) => sp.setCacheSecs(v),
                ),
              ]
            )
          )
        ),
        const SizedBox(height: 15)
      ],
      _sec(context.tr('section_development')),
      _cd(LucideIcons.code2, context.tr('setting_github_repo'), context.tr('setting_github_repo_sub'), tr: const Icon(LucideIcons.externalLink, size: 16, color: kColorCoral), onTap: () => _url("https://github.com/minhmc2007/AniCli-Flutter")),
      const SizedBox(height: 10),
      _cd(LucideIcons.rotateCcw, context.tr('setting_reset_welcome'), context.tr('setting_reset_welcome_sub'), onTap: () async {
        await (await SharedPreferences.getInstance()).remove('is_first_launch');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('reset_done')), backgroundColor: kColorCoral));
      }),
      const SizedBox(height: 30),
      _sec(context.tr('section_about')),
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
                    Expanded(child: Text(context.tr('version'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15))),
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
                    Expanded(child: Text(context.tr('build_number'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15))),
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
      physics: t == PerformanceTier.high ? const BouncingScrollPhysics() : const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(left: isMobile ? 20 : 40, right: isMobile ? 20 : 40, top: 10, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:[
            const SizedBox(height: 60),
            Center(
              child:               Text(context.tr('settings_title'), style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral))
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

// Detailed Anime/Manga Display
class AnimeDetailView extends StatefulWidget { final AnimeModel anime; final String heroTag; final String? initialEpisode; const AnimeDetailView({super.key, required this.anime, required this.heroTag, this.initialEpisode}); @override State<AnimeDetailView> createState() => _AnimeDetailViewState(); }
class _AnimeDetailViewState extends State<AnimeDetailView> {
  List<String> _episodes =[]; bool _isLoading = true, _isDownloadMode = false; String? _loadingStatus;
  bool _isTitleExpanded = false;
  @override void initState() { super.initState(); _loadData(); }

  void _loadData() async {
    final src = widget.anime.sourceId;
    final useVi = src == 'vi';
    final isNSFW = src == 'hentaivietsub';
    final isProvider = src.contains('::');

    List<dynamic> items =[];
    if (widget.anime.isManga) {
      if (src == 'zettruyen') items = await ZetTruyenCore.getChapters(widget.anime.id);
      else if (src == 'weebcentral') items = await WeebCentralCore.getChapters(widget.anime.id);
      else if (src == 'truyenqq') items = await TruyenQQCore.getChapters(widget.anime.id);
      else items = await MangaCore.getChapters(widget.anime.id);
    } else if (isProvider) {
      try {
        items = await ProviderCoordinator.episodesList(src, 'sub');
      } catch (e) {
        debugPrint('[$src] episodes error: $e');
      }
    } else {
      items = useVi ? await ViAnimeCore.getEpisodes(widget.anime.id) : (isNSFW ? await HentaiVietsubCore.getEpisodes(widget.anime.id) : await AniCore.getEpisodes(widget.anime.id));
    }
    
    if (mounted) {
      setState(() { _episodes = List<String>.from(items); _isLoading = false; });
      if (widget.initialEpisode != null && _episodes.contains(widget.initialEpisode)) {
        _handleItemTap(widget.initialEpisode!);
      }
    }
  }

  Future<void> _handleItemTap(String idNum) async {
    if (widget.anime.isManga) {
      context.read<UserProvider>().addToHistory(widget.anime, idNum);
      Navigator.push(context, MaterialPageRoute(builder: (ctx) => MangaReaderScreen(anime: widget.anime, chapterNum: idNum, allChapters: _episodes))); return;
    }
    final isProvider = widget.anime.sourceId.contains('::');
    final useVi = !isProvider && widget.anime.sourceId == 'vi';
    final isNSFW = !isProvider && widget.anime.sourceId == 'hentaivietsub';
    final referer = isProvider ? '' : (useVi ? ViAnimeCore.referer : (isNSFW ? HentaiVietsubCore.referer : AniCore.referer));

    String displayEpNum = idNum;

    if (_isDownloadMode) {
      if (Platform.isAndroid || Platform.isIOS) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('detail_download_unavailable')))); return; }
      setState(() => _loadingStatus = context.tr('detail_preparing_download'));

      final url = isProvider
        ? await ProviderCoordinator.getStreamUrl(widget.anime.sourceId, idNum, 'sub')
        : (useVi ? await ViAnimeCore.getStreamUrl(widget.anime.id, idNum) : (isNSFW ? await HentaiVietsubCore.getStreamUrl(widget.anime.id, idNum) : await AniCore.getStreamUrl(widget.anime.id, idNum)));

      setState(() => _loadingStatus = null);
      if (url != null) {
        if (mounted) await showDialog(context: context, barrierDismissible: false, builder: (ctx) => GenericDownloadDialog(url: url, fileName: "${widget.anime.name}-EP$displayEpNum.mp4".replaceAll(RegExp(r'[<>:"/\\|?*]'), ''), referer: referer, title: context.tr('download'), icon: LucideIcons.video));
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('detail_download_not_found')))); }
    } else {
      setState(() => _loadingStatus = context.tr('detail_fetching_stream')); context.read<UserProvider>().addToHistory(widget.anime, displayEpNum);

      String? url;
      String resolvedReferer = referer;
      Map<String, String>? streamExtraHeaders;
      List<StreamEntry> streamEntries = [];
      if (isProvider) {
        try {
          debugPrint('[DEBUG] Fetching streams for sourceId=${widget.anime.sourceId}, ep=$idNum');
          final hints = await ProviderCoordinator.getStreamsWithHints(widget.anime.sourceId, int.tryParse(idNum) ?? 1, 'sub');
          debugPrint('[DEBUG] hints count=${hints.length}');
          final hintKeys = hints.keys.toList();
          url = hintKeys.isNotEmpty ? hintKeys.first : null;
          debugPrint('[DEBUG] streamUrl=$url');
          final firstHint = hints.values.isNotEmpty ? hints.values.first : null;
          if (firstHint?.referrer != null) resolvedReferer = firstHint!.referrer!;
          if (firstHint?.extraHeaders != null) streamExtraHeaders = firstHint!.extraHeaders!;
          for (final k in hintKeys) {
            final h = hints[k]!;
            final ref = h.referrer ?? '';
            final headers = (h.extraHeaders != null && h.extraHeaders!.isNotEmpty) ? Map<String, String>.from(h.extraHeaders!) : const <String, String>{};
            streamEntries.add(StreamEntry(k, referer: ref, extraHeaders: headers));
          }
          debugPrint('[DEBUG] resolvedReferer=$resolvedReferer');
          debugPrint('[DEBUG] streamExtraHeaders=$streamExtraHeaders');
          if (url != null && streamExtraHeaders != null && url.contains('.m3u8')) {
            if (resolvedReferer.isNotEmpty && !streamExtraHeaders.containsKey('Referer')) {
              streamExtraHeaders['Referer'] = resolvedReferer;
            }
            debugPrint('[DEBUG] proxyHeaders=$streamExtraHeaders');
            await HlsProxy.setHeaders(streamExtraHeaders);
            final proxied = HlsProxy.proxyUrl(url);
            debugPrint('[DEBUG] proxiedUrl=$proxied');
            url = proxied;
            streamExtraHeaders = null;
            resolvedReferer = '';
          }
        } catch (e) {
          debugPrint('Provider stream error: $e');
        }
      } else {
        url = useVi ? await ViAnimeCore.getStreamUrl(widget.anime.id, idNum) : (isNSFW ? await HentaiVietsubCore.getStreamUrl(widget.anime.id, idNum) : await AniCore.getStreamUrl(widget.anime.id, idNum));
        if (url != null && useVi && url.contains('.m3u8')) {
          final viaHeaders = <String, String>{
            'Referer': resolvedReferer,
            'User-Agent': _kPlayerUA,
            if (resolvedReferer.isNotEmpty) 'Origin': resolvedReferer.replaceAll(RegExp(r'/+$'), ''),
          };
          debugPrint('[DEBUG] proxyHeaders=$viaHeaders');
          await HlsProxy.setHeaders(viaHeaders);
          final proxied = HlsProxy.proxyUrl(url);
          debugPrint('[DEBUG] proxiedUrl=$proxied');
          url = proxied;
          streamExtraHeaders = null;
          resolvedReferer = '';
        }
      }

      setState(() => _loadingStatus = null);
      if (url is String) {
        final streamUrl = url;
        final streamReferer = resolvedReferer;
        final entries = streamEntries.isNotEmpty ? streamEntries : [StreamEntry(streamUrl, referer: streamReferer, extraHeaders: streamExtraHeaders)];
        void openInternal() => Navigator.of(context).push(PageRouteBuilder(pageBuilder: (_, a, __) => InternalPlayerScreen(urls: entries, title: context.tr('detail_play_title', [widget.anime.name, displayEpNum.toString()]), animeId: widget.anime.id, epNum: displayEpNum), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));
        if ((Platform.isLinux || Platform.isWindows || Platform.isMacOS) && !context.read<SettingsProvider>().useInternalPlayer) {
          final saved = context.read<ProgressProvider>().getProgress(widget.anime.id, displayEpNum); bool resume = false;
          if (saved > 10) resume = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: kColorCream, title: Text(context.tr('resume_title'), style: const TextStyle(color: kColorCoral, fontWeight: FontWeight.bold)), content: Text(context.tr('resume_content', [Duration(seconds: saved).toString().split('.').first])), actions:[TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('resume_start_over'), style: const TextStyle(color: Colors.black54))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kColorCoral, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('resume_resume')))])) ?? false;

          final cacheSecs = context.read<SettingsProvider>().cacheSecs;
          final headerFields = StringBuffer('Referer: $streamReferer');
          if (streamExtraHeaders != null) {
            for (final e in streamExtraHeaders.entries) {
              headerFields.write(', ${e.key}: ${e.value}');
            }
          }
          final List<String> args =[streamUrl, '--http-header-fields=$headerFields', '--user-agent=$_kPlayerUA', '--ytdl=yes', '--force-media-title=${widget.anime.name} - Ep $displayEpNum', '--save-position-on-quit'];
          if (resume) args.add('--start=$saved');
          if (cacheSecs > 300) {
            args.addAll(['--cache=yes', '--demuxer-max-bytes=2000M', '--demuxer-readahead-secs=99999']);
          } else {
            args.add('--demuxer-readahead-secs=${cacheSecs.toInt()}');
          }
          final env = Platform.environment;
          final home = env['USERPROFILE'] ?? env['HOME'] ?? '';
          final scoopMpv = '$home\\scoop\\apps\\mpv\\current\\mpv.exe';
          try {
            await Process.start('mpv', args, mode: ProcessStartMode.detached);
          } catch (_) {
            try {
              await Process.start(scoopMpv, args, mode: ProcessStartMode.detached);
            } catch (_) {
              if (mounted) openInternal();
            }
          }
        } else openInternal();
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('detail_stream_not_found')))); }
    }
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, {Color color = kColorCoral, bool fill = false}) => GestureDetector(onTap: onTap, child: LiquidGlassContainer(borderRadius: BorderRadius.circular(50), child: Container(padding: const EdgeInsets.all(12), child: Icon(icon, color: color, fill: fill ? 1.0 : 0.0))));
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id); final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    return Scaffold(body: LiveGradientBackground(child: Stack(fit: StackFit.expand, children:[
      isMobile ? CustomScrollView(physics: const BouncingScrollPhysics(), slivers:[
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).size.height * 0.55, child: Stack(fit: StackFit.expand, children:[
          CozyHeroImage(heroTag: widget.heroTag, imageUrl: widget.anime.fullImageUrl, radius: 0, boxFit: BoxFit.cover, fallbackTitle: widget.anime.name),
          Container(decoration: BoxDecoration(gradient: LinearGradient(colors:[Colors.transparent, Colors.black.withOpacity(0.7)], begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const[0.6, 1.0]))),
          Positioned(top: 50, left: 20, right: 20, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[_buildCircleBtn(LucideIcons.arrowLeft, () => Navigator.pop(context)), _buildCircleBtn(LucideIcons.heart, () => context.read<UserProvider>().toggleFavorite(widget.anime), color: isFav ? kColorCoral : Colors.black26, fill: isFav)])),
          Positioned(bottom: 20, left: 20, right: 20, child: Hero(tag: "title_${widget.heroTag}", child: Material(color: Colors.transparent, child: GestureDetector(onTap: () => setState(() => _isTitleExpanded = !_isTitleExpanded), child: Text(widget.anime.name, textAlign: TextAlign.center, maxLines: _isTitleExpanded ? null : 2, overflow: _isTitleExpanded ? null : TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, shadows:[Shadow(blurRadius: 10, color: Colors.black.withOpacity(0.5))]))))))
        ]))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text(widget.anime.isManga ? context.tr('chapters') : context.tr('episodes'), style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: kColorCoral)), if (!widget.anime.isManga) MorphingDownloadButton(isDownloading: _isDownloadMode, onToggle: () => setState(() => _isDownloadMode = !_isDownloadMode))]))),
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
            Text(widget.anime.isManga ? context.tr('chapters') : context.tr('episodes'), style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)).animate().fadeIn().slideY(begin: -0.5, end: 0),
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
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: t == PerformanceTier.low ? Duration.zero : const Duration(milliseconds: 200), curve: Curves.easeOut, margin: const EdgeInsets.only(bottom: 12), height: 70, transform: Matrix4.identity()..scale(isH && t != PerformanceTier.low ? 1.01 : 1.0), child: LiquidGlassContainer(opacity: isH ? 0.9 : 0.6, child: Container(decoration: widget.isDownloadMode && isH ? BoxDecoration(border: Border.all(color: kColorCoral, width: 2), borderRadius: BorderRadius.circular(20)) : null, padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children:[Container(width: 40, height: 40, decoration: BoxDecoration(color: kColorCoral.withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text("#", style: GoogleFonts.jetBrainsMono(color: kColorCoral, fontWeight: FontWeight.bold)))), const SizedBox(width: 20), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children:[Text(widget.isManga ? context.tr('chapter_prefix', [widget.epNum]) : context.tr('episode_prefix', [widget.epNum]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: kColorDarkText)), Text(widget.isDownloadMode ? context.tr('tap_to_download') : context.tr('tap_to_play'), style: GoogleFonts.inter(fontSize: 12, color: Colors.black45))])), Icon(widget.isDownloadMode ? LucideIcons.download : (widget.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle), color: kColorCoral, size: 28)]))))));
  }
}

class MorphingDownloadButton extends StatelessWidget {
  final bool isDownloading; final VoidCallback onToggle; const MorphingDownloadButton({super.key, required this.isDownloading, required this.onToggle});
  @override Widget build(BuildContext context) {
    if (context.read<SettingsProvider>().tier == PerformanceTier.low) return IconButton(onPressed: onToggle, icon: Icon(isDownloading ? LucideIcons.check : LucideIcons.download, color: kColorCoral), style: IconButton.styleFrom(backgroundColor: Colors.white));
    return TweenAnimationBuilder<double>(duration: const Duration(milliseconds: 600), curve: Curves.easeOutBack, tween: Tween(begin: 0.0, end: isDownloading ? 1.0 : 0.0), builder: (c, t, child) => GestureDetector(onTap: onToggle, child: Container(width: lerpDouble(50, 240, t)!, height: 50, decoration: BoxDecoration(color: Color.lerp(Colors.white, kColorCoral, t)!, borderRadius: BorderRadius.circular(lerpDouble(25, 15, t)!), boxShadow:[BoxShadow(color: kColorCoral.withOpacity(0.2 + (t * 0.2)), blurRadius: 15, offset: const Offset(0, 5))]), child: ClipRect(child: Stack(alignment: Alignment.center, children:[Opacity(opacity: (1.0 - t).clamp(0.0, 1.0), child: Transform.translate(offset: Offset(-20 * t, 0), child: Icon(LucideIcons.download, color: Color.lerp(kColorCoral, Colors.white, t)!))), Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(20 * (1.0 - t), 0), child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: Container(width: 240, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(LucideIcons.downloadCloud, color: Colors.white, size: 18), const SizedBox(width: 8), Text(context.tr('detail_select_ep_download'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(width: 5), Icon(LucideIcons.x, color: Colors.white70, size: 16)])))))])))));
  }
}

class AnimeGrid extends StatelessWidget {
  final List<AnimeModel> animes; final Function(AnimeModel, String) onTap; final ScrollPhysics? physics; final bool shrinkWrap; final String tagPrefix;
  final Map<String, VoidCallback>? continueCallbacks;
  const AnimeGrid({super.key, required this.animes, required this.onTap, this.physics = const NeverScrollableScrollPhysics(), this.shrinkWrap = true, required this.tagPrefix, this.continueCallbacks});
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    return Padding(padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40), child: GridView.builder(physics: physics, shrinkWrap: shrinkWrap, gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: isMobile ? 150 : 180, childAspectRatio: 0.7, crossAxisSpacing: isMobile ? 15 : 20, mainAxisSpacing: isMobile ? 15 : 20), itemCount: animes.length, itemBuilder: (ctx, i) => AnimeCard(anime: animes[i], heroTag: "${tagPrefix}_${animes[i].id}", onTap: () => onTap(animes[i], "${tagPrefix}_${animes[i].id}"), showPlayBadge: continueCallbacks?.containsKey(animes[i].id) ?? false, onPlay: continueCallbacks?[animes[i].id]).adapt(t, delay: i < 10 ? i * 50 : 0, isScale: true)));
  }
}

class AnimeCard extends StatefulWidget { final AnimeModel anime; final String heroTag; final VoidCallback onTap; final bool showPlayBadge; final VoidCallback? onPlay; const AnimeCard({super.key, required this.anime, required this.heroTag, required this.onTap, this.showPlayBadge=false, this.onPlay}); @override State<AnimeCard> createState() => _AnimeCardState(); }
class _AnimeCardState extends State<AnimeCard> with AutomaticKeepAliveClientMixin {
  bool isH = false; @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: 200.ms, transform: Matrix4.identity()..scale(isH && context.select<SettingsProvider, PerformanceTier>((p) => p.tier) != PerformanceTier.low ? 1.05 : 1.0), child: Stack(fit: StackFit.expand, children:[CozyHeroImage(heroTag: widget.heroTag, imageUrl: widget.anime.fullImageUrl, radius: 20, withShadow: isH, fallbackTitle: widget.anime.name), Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors:[Colors.transparent, kColorDarkText.withOpacity(0.8)], begin: Alignment.center, end: Alignment.bottomCenter))), Positioned(bottom: 12, left: 12, right: 12, child: Hero(tag: "title_${widget.heroTag}", child: Material(color: Colors.transparent, child: Text(widget.anime.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))))), if (widget.anime.isManga) Positioned(top: 10, right: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(4)), child: Text(context.tr('manga_badge'), style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))), if (widget.anime.provider != null && !widget.showPlayBadge) Positioned(top: 10, left: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.85), borderRadius: BorderRadius.circular(4)), child: Text(widget.anime.provider!, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))), if (widget.showPlayBadge && widget.onPlay != null) Positioned(top: 10, left: 10, child: GestureDetector(onTap: widget.onPlay, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: kColorCoral.withOpacity(0.9), borderRadius: BorderRadius.circular(50)), child: const Icon(LucideIcons.play, color: Colors.white, size: 18))))]))));
  }
}

class HistoryCard extends StatefulWidget { final HistoryItem item; final VoidCallback onTap; final VoidCallback? onContinue; const HistoryCard({super.key, required this.item, required this.onTap, this.onContinue}); @override State<HistoryCard> createState() => _HistoryCardState(); }
class _HistoryCardState extends State<HistoryCard> with AutomaticKeepAliveClientMixin {
  bool isH = false; @override bool get wantKeepAlive => true;
  @override Widget build(BuildContext context) {
    super.build(context);
    final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    return MouseRegion(onEnter: (_) => setState(() => isH=true), onExit: (_) => setState(() => isH=false), cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), curve: Curves.easeOut, margin: const EdgeInsets.only(bottom: 15), height: 90, transform: Matrix4.identity()..scale(isH && t != PerformanceTier.low ? 1.02 : 1.0), child: LiquidGlassContainer(opacity: isH ? 0.9 : 0.6, child: Row(children:[SizedBox(width: 90, height: 90, child: CozyHeroImage(heroTag: "history_${widget.item.anime.id}", imageUrl: widget.item.anime.fullImageUrl, radius: 15, fallbackTitle: widget.item.anime.name)), const SizedBox(width: 20), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children:[Text(widget.item.anime.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)), Text(widget.item.anime.isManga ? context.tr('chapter_prefix', [widget.item.displayEpisode]) : context.tr('episode_prefix', [widget.item.displayEpisode]), style: GoogleFonts.inter(color: kColorCoral, fontWeight: FontWeight.w600, fontSize: 14))])), widget.onContinue != null ? IconButton(icon: Icon(widget.item.anime.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle, color: kColorCoral), onPressed: widget.onContinue) : Padding(padding: const EdgeInsets.only(right: 20), child: Icon(widget.item.anime.isManga ? LucideIcons.bookOpen : LucideIcons.playCircle, color: kColorCoral, size: 30))])))));
  }
}

class FeaturedCarousel extends StatelessWidget {
  final List<AnimeModel> animes; final Function(AnimeModel, String) onTap; const FeaturedCarousel({super.key, required this.animes, required this.onTap});
  @override Widget build(BuildContext context) {
    final t = context.select<SettingsProvider, PerformanceTier>((p) => p.tier);
    return SizedBox(height: 220, child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 40), scrollDirection: Axis.horizontal, itemCount: animes.length, itemBuilder: (c, i) => GestureDetector(onTap: () => onTap(animes[i], "carousel_${animes[i].id}"), child: Container(width: 300, margin: const EdgeInsets.only(right: 20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: t != PerformanceTier.low ?[BoxShadow(color: kColorCoral.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))] :[]), child: Stack(fit: StackFit.expand, children:[CozyHeroImage(heroTag: "carousel_${animes[i].id}", imageUrl: animes[i].fullImageUrl, radius: 20, fallbackTitle: animes[i].name), Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors:[Colors.transparent, kColorDarkText.withOpacity(0.9)], begin: Alignment.topCenter, end: Alignment.bottomCenter))), Positioned(bottom: 20, left: 20, child: SizedBox(width: 260, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children:[Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: kColorCoral, borderRadius: BorderRadius.circular(8)), child: Text(context.tr('hot'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))), const SizedBox(height: 5), Text(animes[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])))]))).adapt(t, delay: i * 100)));
  }
}

class GlassDock extends StatelessWidget {
  final int selectedIndex; final Function(int) onItemSelected; const GlassDock({super.key, required this.selectedIndex, required this.onItemSelected});
  @override Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900; final t = Translations.of(context); final items =[(LucideIcons.search, t.tr('tab_browse')), (LucideIcons.history, t.tr('tab_history')), (LucideIcons.heart, t.tr('tab_favorites')), (LucideIcons.settings, t.tr('tab_settings'))];
    return LiquidGlassContainer(borderRadius: BorderRadius.circular(30), opacity: 0.6, useBlur: true, child: Padding(padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: 12), child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(items.length, (i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: IconButton(icon: Icon(items[i].$1, color: selectedIndex == i ? kColorCoral : Colors.black38, size: isMobile ? 20 : 24), onPressed: () => onItemSelected(i), tooltip: items[i].$2))))));
  }
}
