import 'dart:io';
import 'dart:ui';
import 'package:animeclient/api/ani_core.dart';
import 'package:animeclient/user_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

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
      ],
      child: const AniCliApp(),
    ),
  );
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

  AnimeModel? _detailAnime;

  void _openDetail(AnimeModel anime) {
    setState(() => _detailAnime = anime);
  }

  void _closeDetail() {
    setState(() => _detailAnime = null);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

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
        activePage = const AboutView(key: ValueKey("AboutTab"));
        activeKey = const ValueKey("AboutTab");
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutQuart,
                switchOutCurve: Curves.easeInQuart,
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.1), end: Offset.zero)
                      .animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _detailAnime != null
                  ? Scaffold(
                    backgroundColor: Colors.transparent,
                    body: AnimeDetailView(
                      key: ValueKey("Detail_${_detailAnime!.id}"),
                      anime: _detailAnime!,
                      onBack: _closeDetail,
                      isMobile: isMobile,
                    ),
                  )
                  : const SizedBox.shrink(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              bottom: _detailAnime == null ? 30 : -100,
              left: 0,
              right: 0,
              child: Center(
                child: GlassDock(
                  selectedIndex: _selectedIndex,
                  onItemSelected: (index) {
                    if (_detailAnime == null) {
                      setState(() => _selectedIndex = index);
                    }
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

// --- INTERNAL PLAYER SCREEN (Android, Windows, macOS) ---
class InternalPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;

  const InternalPlayerScreen(
    {super.key, required this.streamUrl, required this.title});

  @override
  State<InternalPlayerScreen> createState() => _InternalPlayerScreenState();
}

class _InternalPlayerScreenState extends State<InternalPlayerScreen> {
  late final Player player;
  late final VideoController controller;

  @override
  void initState() {
    super.initState();

    // Standard high-performance configuration for Android/Windows/iOS
    player = Player(
      configuration: const PlayerConfiguration(
        vo: 'gpu',
        // 'auto' uses best available hardware decoding (MediaCodec on Android, D3D11 on Windows)
        // This is much smoother than the software decoding we tried on Linux.
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

    player.play();
    player.setVolume(100);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: MaterialVideoControlsTheme(
            normal: MaterialVideoControlsThemeData(
              seekBarThumbColor: kColorCoral,
              seekBarPositionColor: kColorCoral,
              buttonBarButtonColor: Colors.white,
              // Custom top bar with title and close button
              topButtonBar: [
                const SizedBox(width: 20),
                Expanded(
                  child: Text(widget.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close, color: Colors.white))
              ]),
              fullscreen: const MaterialVideoControlsThemeData(
                seekBarThumbColor: kColorCoral,
                seekBarPositionColor: kColorCoral,
                buttonBarButtonColor: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Video(
                  controller: controller,
                  controls: MaterialVideoControls,
                ),
              ),
          ),
        ),
      ),
    );
  }
}

// --- VIEWS ---

class BrowseView extends StatefulWidget {
  final Function(AnimeModel) onAnimeTap;
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
                      child: child));
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
                                style: GoogleFonts.inter(color: Colors.black26)))
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
                                  color: kColorDarkText))
                              .animate()
                              .fadeIn(delay: 200.ms),
                          ),
                          AnimeGrid(
                            animes: _animes, onTap: widget.onAnimeTap),
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
  final Function(AnimeModel) onAnimeTap;
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
            ]))
          : ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 40, vertical: 10),
              physics: const BouncingScrollPhysics(),
              itemCount: history.length,
              itemBuilder: (ctx, i) {
                final item = history[i];
                return HistoryCard(
                  item: item,
                  onTap: () => widget.onAnimeTap(item.anime))
                .animate(delay: (i * 100).ms)
                .slideX(
                  begin: 0.2,
                  end: 0,
                  curve: Curves.easeOutCubic,
                  duration: 500.ms)
                .fadeIn(duration: 400.ms);
              },
          ),
        ),
      ],
    );
  }
}

class FavoritesView extends StatefulWidget {
  final Function(AnimeModel) onAnimeTap;
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
                        style: GoogleFonts.inter(color: Colors.black26)))
          : AnimeGrid(animes: favorites, onTap: widget.onAnimeTap),
        ),
      ],
    );
  }
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiquidGlassContainer(
            borderRadius: BorderRadius.circular(50),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Icon(LucideIcons.clapperboard,
                          size: 60, color: kColorCoral)),
          ).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),
          const SizedBox(height: 30),
          Text("AniCli Flutter",
               style: GoogleFonts.inter(
                 fontSize: 32,
                 fontWeight: FontWeight.bold,
                 color: kColorDarkText))
          .animate()
          .fadeIn(delay: 200.ms)
          .slideY(begin: 0.5, end: 0),
          const SizedBox(height: 5),
          Text("v1.5 Stable",
               style: GoogleFonts.inter(
                 fontSize: 14,
                 color: kColorCoral,
                 fontWeight: FontWeight.w600))
          .animate()
          .fadeIn(delay: 400.ms)
          .slideY(begin: 0.5, end: 0),
        ],
      ),
    );
  }
}

// --- RESPONSIVE DETAIL VIEW ---
class AnimeDetailView extends StatefulWidget {
  final AnimeModel anime;
  final VoidCallback onBack;
  final bool isMobile;

  const AnimeDetailView(
    {super.key,
      required this.anime,
      required this.onBack,
      required this.isMobile});
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
        String safeName = "${widget.anime.name} - EP$epNum"
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
      // --- STREAMING LOGIC ---
      setState(() => _loadingStatus = "Fetching Stream...");
      context.read<UserProvider>().addToHistory(widget.anime, epNum);
      final url = await AniCore.getStreamUrl(widget.anime.id, epNum);
      setState(() => _loadingStatus = null);

      if (url != null) {
        // === LINUX FIX: LAUNCH SYSTEM MPV ===
        if (Platform.isLinux) {
          try {
            await Process.start(
              'mpv',
              [
                url,
                '--http-header-fields=Referer: ${AniCore.referer}',
                '--force-media-title=${widget.anime.name} - Ep $epNum',
              ],
              mode: ProcessStartMode.detached,
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Could not launch external MPV: $e")));
            }
          }
        }
        // === ALL OTHER PLATFORMS: USE INTERNAL PLAYER ===
        else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => InternalPlayerScreen(
                streamUrl: url, title: "${widget.anime.name} - Ep $epNum"),
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
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              kColorCream.withOpacity(0.95),
              kColorPeach.withOpacity(0.95)
            ], begin: Alignment.topLeft, end: Alignment.bottomRight))),
            widget.isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
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
                    ])))),
      ],
    );
  }

  // --- DESKTOP LAYOUT ---
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
                _buildCircleBtn(LucideIcons.arrowLeft, widget.onBack),
                _buildCircleBtn(
                  isFav ? LucideIcons.heart : LucideIcons.heart,
                  () => context
                  .read<UserProvider>()
                  .toggleFavorite(widget.anime),
                  color: isFav ? kColorCoral : Colors.black26,
                  fill: isFav),
              ]),
              const SizedBox(height: 30),
              Hero(
                tag: widget.anime.id,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: kColorCoral.withOpacity(0.4),
                        blurRadius: 25,
                        offset: const Offset(0, 10))
                    ]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: CachedNetworkImage(
                        imageUrl: widget.anime.fullImageUrl,
                        fit: BoxFit.cover))))
              .animate()
              .slideX(
                begin: -0.2,
                end: 0,
                duration: 400.ms,
                curve: Curves.easeOut),
                const SizedBox(height: 25),
                Text(widget.anime.name,
                     textAlign: TextAlign.center,
                     style: GoogleFonts.inter(
                       fontSize: 24,
                       fontWeight: FontWeight.bold,
                       color: kColorDarkText))
                .animate()
                .fadeIn(delay: 200.ms),
          ])),
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
                        onToggle: () => setState(() =>
                        _isDownloadMode = !_isDownloadMode)),
                    ]),
                    const SizedBox(height: 20),
                    Expanded(child: _buildEpisodeGrid()),
                ]))),
      ],
    );
  }

  // --- MOBILE LAYOUT ---
  Widget _buildMobileLayout() {
    final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              Hero(
                tag: widget.anime.id,
                child: SizedBox(
                  height: 350,
                  width: double.infinity,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black, Colors.transparent],
                        stops: const [0.6, 1.0],
                      ).createShader(
                        Rect.fromLTRB(0, 0, rect.width, rect.height));
                    },
                    blendMode: BlendMode.dstIn,
                    child: CachedNetworkImage(
                      imageUrl: widget.anime.fullImageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
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
                    _buildCircleBtn(LucideIcons.arrowLeft, widget.onBack),
                    _buildCircleBtn(
                      isFav ? LucideIcons.heart : LucideIcons.heart,
                      () => context
                      .read<UserProvider>()
                      .toggleFavorite(widget.anime),
                      color: isFav ? kColorCoral : Colors.black26,
                      fill: isFav),
                  ],
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Text(widget.anime.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: kColorDarkText,
                              shadows: [
                                Shadow(
                                  blurRadius: 10,
                                  color: Colors.white.withOpacity(0.5))
                              ]))
                .animate()
                .fadeIn()
                .slideY(begin: 0.2, end: 0),
              )
            ],
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
                         onToggle: () => setState(
                           () => _isDownloadMode = !_isDownloadMode)),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
          sliver: _isLoading
          ? const SliverToBoxAdapter(
            child: Center(
              child: CircularProgressIndicator(color: kColorCoral)))
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
                  onTap: () => _handleEpisodeTap(_episodes[i]))
                .animate()
                .scale(delay: (i * 10).ms, duration: 200.ms);
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
            onTap: () => _handleEpisodeTap(_episodes[i]))
          .animate()
          .scale(delay: (i * 20).ms, duration: 200.ms);
        });
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap,
                         {Color color = kColorCoral, bool fill = false}) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlassContainer(
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, fill: fill ? 1.0 : 0.0))));
                         }
}

// --- SHARED WIDGETS ---
class MorphingDownloadButton extends StatelessWidget {
  final bool isDownloading;
  final VoidCallback onToggle;
  const MorphingDownloadButton(
    {super.key, required this.isDownloading, required this.onToggle});
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
              borderRadius:
              BorderRadius.circular(lerpDouble(25, 15, t)!),
              boxShadow: [
                BoxShadow(
                  color: kColorCoral.withOpacity(0.2 + (t * 0.2)),
                  blurRadius: 15,
                  offset: const Offset(0, 5))
              ]),
              child: ClipRect(
                child: Stack(alignment: Alignment.center, children: [
                  Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(-20 * t, 0),
                      child: Icon(LucideIcons.download,
                                  color: Color.lerp(
                                    kColorCoral, Colors.white, t)!))),
                             Opacity(
                               opacity: t.clamp(0.0, 1.0),
                               child: Transform.translate(
                                 offset: Offset(20 * (1.0 - t), 0),
                                 child: SingleChildScrollView(
                                   scrollDirection: Axis.horizontal,
                                   physics: const NeverScrollableScrollPhysics(),
                                   child: Container(
                                     width: 240,
                                     padding: const EdgeInsets.symmetric(
                                       horizontal: 16),
                                       child: Row(
                                         mainAxisAlignment:
                                         MainAxisAlignment.center,
                                         children: const [
                                           Icon(LucideIcons.downloadCloud,
                                                color: Colors.white, size: 18),
                                                SizedBox(width: 8),
                                                Text("Select Ep to Download",
                                                     style: TextStyle(
                                                       color: Colors.white,
                                                       fontWeight: FontWeight.bold,
                                                       fontSize: 13)),
                                                  SizedBox(width: 5),
                                                  Icon(LucideIcons.x,
                                                       color: Colors.white70, size: 16)
                                         ]))))),
                ]))));
      });
  }
}

class AnimeGrid extends StatelessWidget {
  final List<AnimeModel> animes;
  final Function(AnimeModel) onTap;
  const AnimeGrid({super.key, required this.animes, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isMobile ? 150 : 180,
          childAspectRatio: 0.7,
          crossAxisSpacing: isMobile ? 15 : 20,
          mainAxisSpacing: isMobile ? 15 : 20),
          itemCount: animes.length,
          itemBuilder: (ctx, i) {
            return AnimeCard(anime: animes[i], onTap: () => onTap(animes[i]))
            .animate(delay: (i * 50).ms)
            .scale(
              begin: const Offset(0.8, 0.8),
              curve: Curves.easeOutBack,
              duration: 400.ms)
            .fadeIn(duration: 300.ms);
          }),
    );
  }
}

class AnimeCard extends StatefulWidget {
  final AnimeModel anime;
  final VoidCallback onTap;
  const AnimeCard({super.key, required this.anime, required this.onTap});
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: isHovered
            ? [
              BoxShadow(
                color: kColorCoral.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8))
            ]
            : [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
            ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                  imageUrl: widget.anime.fullImageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                  Container(color: kColorPeach)),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          kColorDarkText.withOpacity(0.8)
                        ],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter))),
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Text(widget.anime.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)))
              ])))));
  }
}

class EpisodeChip extends StatefulWidget {
  final String epNum;
  final bool isDownloadMode;
  final VoidCallback onTap;
  const EpisodeChip(
    {super.key,
      required this.epNum,
      required this.isDownloadMode,
      required this.onTap});
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
              : (widget.isDownloadMode
              ? kColorCoral
              : kColorSoftPink),
              width: widget.isDownloadMode ? 2 : 1),
              boxShadow: isHovered
              ? [
                BoxShadow(
                  color: kColorCoral.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4))
              ]
              : []),
              child: Stack(alignment: Alignment.center, children: [
                Text(widget.epNum,
                     style: TextStyle(
                       fontWeight: FontWeight.bold,
                       color: isHovered ? Colors.white : kColorCoral)),
                       if (widget.isDownloadMode && isHovered)
                         const Positioned(
                           right: 8,
                           child: Icon(LucideIcons.download,
                                       size: 12, color: Colors.white))
              ]))));
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
            child: Row(children: [
              CachedNetworkImage(
                imageUrl: widget.item.anime.fullImageUrl,
                width: 90,
                height: 90,
                fit: BoxFit.cover),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.item.anime.name,
                           maxLines: 1,
                           overflow: TextOverflow.ellipsis,
                           style: GoogleFonts.inter(
                             fontWeight: FontWeight.bold, fontSize: 16)),
                             Text("Episode ${widget.item.episode}",
                                  style: GoogleFonts.inter(
                                    color: kColorCoral,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14))
                    ])),
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(LucideIcons.playCircle,
                                  color: kColorCoral, size: 30))
            ])))));
  }
}

class FeaturedCarousel extends StatelessWidget {
  final List<AnimeModel> animes;
  final Function(AnimeModel) onTap;
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
          return GestureDetector(
            onTap: () => onTap(anime),
            child: Container(
              width: 300,
              margin: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: kColorCoral.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8))
                ]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: anime.fullImageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                kColorDarkText.withOpacity(0.9)
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter))),
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
                                             borderRadius:
                                             BorderRadius.circular(8)),
                                             child: const Text("HOT",
                                                               style: TextStyle(
                                                                 color: Colors.white,
                                                                 fontSize: 10,
                                                                 fontWeight: FontWeight.bold))),
                                                 const SizedBox(height: 5),
                                                 Text(anime.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.inter(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold)),
                                     ]))),
                    ],
                  ),
                ),
            ),
          )
          .animate()
          .slideX(
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
  const GlassDock(
    {super.key, required this.selectedIndex, required this.onItemSelected});
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    final items = [
      (LucideIcons.search, "Browse"),
      (LucideIcons.history, "History"),
      (LucideIcons.heart, "Favorites"),
      (LucideIcons.info, "About")
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
                  icon: Icon(items[index].$1,
                             color: isSelected ? kColorCoral : Colors.black38,
                             size: isMobile ? 20 : 24),
                             onPressed: () => onItemSelected(index),
                             tooltip: items[index].$2));
            }))));
  }
}
