import 'package:animeclient/api/ani_core.dart';
import 'package:animeclient/user_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Added for GitHub link

// --- THEME COLORS ---
const kColorCream = Color(0xFFFEEAC9); // Main Background
const kColorPeach = Color(0xFFFFCDC9); // Secondary Gradient
const kColorSoftPink = Color(0xFFFDACAC); // Borders/Accents
const kColorCoral = Color(0xFFFD7979); // Primary/Buttons
const kColorDarkText = Color(0xFF4A2B2B); // Text Color

void main() {
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
      title: 'Ani-Cli Flutter',
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

// --- LIVE BACKGROUND WIDGET ---
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
  AnimeModel? _openedAnime;

  void _openDetail(AnimeModel anime) {
    setState(() => _openedAnime = anime);
  }

  void _closeDetail() {
    setState(() => _openedAnime = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LiveGradientBackground(
        child: Stack(
          children: [
            // Main Content Area
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.05),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _openedAnime != null
                  ? AnimeDetailView(
                    key: ValueKey(_openedAnime!.id),
                    anime: _openedAnime!,
                    onBack: _closeDetail,
                  )
                  : IndexedStack(
                    key: const ValueKey('tabs'),
                    index: _selectedIndex,
                    children: [
                      BrowseView(onAnimeTap: _openDetail),
                      HistoryView(onAnimeTap: _openDetail),
                      FavoritesView(onAnimeTap: _openDetail),
                      const AboutView(),
                    ],
                  ),
            ),

            // Bottom Dock
            if (_openedAnime == null)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: GlassDock(
                    selectedIndex: _selectedIndex,
                    onItemSelected: (index) => setState(() => _selectedIndex = index),
                  ),
                ),
              ).animate().slideY(begin: 1, end: 0, delay: 300.ms, curve: Curves.easeOutBack),
          ],
        ),
      ),
    );
  }
}

// --- VIEW: BROWSE ---
class BrowseView extends StatefulWidget {
  final Function(AnimeModel) onAnimeTap;
  const BrowseView({super.key, required this.onAnimeTap});

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AnimeModel> _animes = [];
  bool _isLoading = false;

  void _doSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    final results = await AniCore.search(query);
    if (mounted) setState(() { _animes = results; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 60),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: kColorCoral.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kColorDarkText, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: "Search Anime...",
                hintStyle: TextStyle(color: Colors.black38),
                border: InputBorder.none,
                icon: Icon(LucideIcons.search, color: kColorCoral),
              ),
              onSubmitted: _doSearch,
            ),
          ),
        ).animate().fadeIn().slideY(begin: -0.5, end: 0),

        const SizedBox(height: 20),
        Expanded(
          child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kColorCoral))
          : _animes.isEmpty
          ? Center(child: Text("Search for something...", style: GoogleFonts.inter(color: Colors.black26)))
          : AnimeGrid(animes: _animes, onTap: widget.onAnimeTap),
        ),
      ],
    );
  }
}

// --- VIEW: HISTORY ---
class HistoryView extends StatelessWidget {
  final Function(AnimeModel) onAnimeTap;
  const HistoryView({super.key, required this.onAnimeTap});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<UserProvider>().history;

    return Column(
      children: [
        const SizedBox(height: 60),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Watch History", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)),
            if (history.isNotEmpty)
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 20, color: kColorDarkText),
                onPressed: () => context.read<UserProvider>().clearHistory(),
                tooltip: "Clear History",
              )
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: history.isEmpty
          ? Center(child: Text("Go watch some anime!", style: GoogleFonts.inter(color: Colors.black26)))
          : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            itemCount: history.length,
            itemBuilder: (ctx, i) {
              final item = history[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: GestureDetector(
                  onTap: () => onAnimeTap(item.anime),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white),
                      boxShadow: [
                        BoxShadow(color: kColorCoral.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                          child: CachedNetworkImage(
                            imageUrl: item.anime.fullImageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.anime.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                   Text("Last watched: Episode ${item.episode}",
                                        style: const TextStyle(color: kColorCoral, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.playCircle, color: kColorCoral, size: 30),
                        const SizedBox(width: 20),
                      ],
                    ),
                  ),
                ),
              ).animate().slideX(begin: 0.2, end: 0, delay: (i * 50).ms);
            },
          ),
        ),
      ],
    );
  }
}

// --- VIEW: FAVORITES ---
class FavoritesView extends StatelessWidget {
  final Function(AnimeModel) onAnimeTap;
  const FavoritesView({super.key, required this.onAnimeTap});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<UserProvider>().favorites;

    return Column(
      children: [
        const SizedBox(height: 60),
        Text("Favorites", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorCoral)),
        const SizedBox(height: 20),
        Expanded(
          child: favorites.isEmpty
          ? Center(child: Text("No favorites yet!", style: GoogleFonts.inter(color: Colors.black26)))
          : AnimeGrid(animes: favorites, onTap: onAnimeTap),
        ),
      ],
    );
  }
}

// --- VIEW: ABOUT (UPDATED) ---
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo / Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: kColorCoral.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))
                ],
              ),
              child: const Icon(LucideIcons.clapperboard, size: 60, color: kColorCoral),
            ).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),

            const SizedBox(height: 30),

            Text("Ani-Cli Flutter", style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: kColorDarkText)),
            const SizedBox(height: 5),
            Text("v1.0.0", style: GoogleFonts.inter(fontSize: 14, color: kColorCoral, fontWeight: FontWeight.w600)),

            const SizedBox(height: 30),

            // Info Card
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white),
              ),
              child: Column(
                children: [
                  const Text(
                    "This is an Anime Client based on the modified ani-cli script.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),

                  // GitHub Link Button
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () async {
                        final Uri url = Uri.parse('https://github.com/minhmc2007/ani-cli');
                        if (!await launchUrl(url)) {
                          debugPrint("Could not launch $url");
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: kColorDarkText,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.github, color: kColorCream, size: 20),
                            const SizedBox(width: 10),
                            Text("minhmc2007/ani-cli", style: GoogleFonts.inter(color: kColorCream, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: kColorDarkText.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text("License: GPLv3", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ).animate().slideY(begin: 0.2, end: 0, delay: 200.ms, curve: Curves.easeOutQuart),
          ],
        ),
      ),
    );
  }
}

// --- VIEW: DETAILS & PLAYER ---
class AnimeDetailView extends StatefulWidget {
  final AnimeModel anime;
  final VoidCallback onBack;

  const AnimeDetailView({super.key, required this.anime, required this.onBack});

  @override
  State<AnimeDetailView> createState() => _AnimeDetailViewState();
}

class _AnimeDetailViewState extends State<AnimeDetailView> {
  List<String> _episodes = [];
  bool _isLoading = true;
  String? _loadingStatus;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  void _loadEpisodes() async {
    final eps = await AniCore.getEpisodes(widget.anime.id);
    if (mounted) setState(() { _episodes = eps; _isLoading = false; });
  }

  void _playEpisode(String epNum) async {
    setState(() => _loadingStatus = "Opening Player...");
    context.read<UserProvider>().addToHistory(widget.anime, epNum);
    final url = await AniCore.getStreamUrl(widget.anime.id, epNum);
    setState(() => _loadingStatus = null);

    if (url != null) {
      AniCore.playInMpv(url);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stream not found")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFav = context.watch<UserProvider>().isFavorite(widget.anime.id);

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 350,
              height: double.infinity,
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildCircleBtn(LucideIcons.arrowLeft, widget.onBack),
                      _buildCircleBtn(
                        isFav ? LucideIcons.heart : LucideIcons.heart,
                        () => context.read<UserProvider>().toggleFavorite(widget.anime),
                        color: isFav ? kColorCoral : Colors.black26,
                        fill: isFav,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Hero(
                    tag: widget.anime.id,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CachedNetworkImage(
                          imageUrl: widget.anime.fullImageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.anime.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: kColorDarkText),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 100),
                  Text("Episodes", style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: kColorCoral)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: kColorCoral))
                    : GridView.builder(
                      padding: const EdgeInsets.only(right: 40, bottom: 40),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 100,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _episodes.length,
                      itemBuilder: (ctx, i) {
                        return EpisodeChip(
                          epNum: _episodes[i],
                          onTap: () => _playEpisode(_episodes[i]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_loadingStatus != null)
          Container(
            color: kColorCream.withOpacity(0.8),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: kColorCoral),
                  const SizedBox(height: 20),
                  Text(_loadingStatus!, style: const TextStyle(fontSize: 18, color: kColorCoral, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onTap, {Color color = kColorCoral, bool fill = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: kColorCoral.withOpacity(0.2), blurRadius: 10)],
        ),
        child: Icon(icon, color: color, fill: fill ? 1.0 : 0.0),
      ),
    );
  }
}

// --- SHARED WIDGETS ---
class AnimeGrid extends StatelessWidget {
  final List<AnimeModel> animes;
  final Function(AnimeModel) onTap;

  const AnimeGrid({super.key, required this.animes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 120),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.7,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: animes.length,
      itemBuilder: (ctx, i) {
        return AnimeCard(anime: animes[i], onTap: () => onTap(animes[i]));
      },
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
            ? [BoxShadow(color: kColorCoral.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]
            : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: widget.anime.id,
                  child: CachedNetworkImage(
                    imageUrl: widget.anime.fullImageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: kColorPeach),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
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
                  child: Text(
                    widget.anime.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EpisodeChip extends StatefulWidget {
  final String epNum;
  final VoidCallback onTap;
  const EpisodeChip({super.key, required this.epNum, required this.onTap});
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
            color: isHovered ? kColorCoral : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isHovered ? kColorCoral : kColorSoftPink),
            boxShadow: isHovered
            ? [BoxShadow(color: kColorCoral.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
            : [],
          ),
          child: Center(
            child: Text(
              widget.epNum,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isHovered ? Colors.white : kColorCoral,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassDock extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  const GlassDock({super.key, required this.selectedIndex, required this.onItemSelected});
  @override
  Widget build(BuildContext context) {
    final items = [
      (LucideIcons.search, "Browse"),
      (LucideIcons.history, "History"),
      (LucideIcons.heart, "Favorites"),
      (LucideIcons.info, "About"),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(color: kColorCoral.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (index) {
          final isSelected = selectedIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              icon: Icon(items[index].$1, color: isSelected ? kColorCoral : Colors.black38),
              onPressed: () => onItemSelected(index),
              tooltip: items[index].$2,
            ),
          );
        }),
      ),
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
  }
}
