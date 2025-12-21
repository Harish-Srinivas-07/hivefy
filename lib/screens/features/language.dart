import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivefy/components/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/database.dart';
import '../../services/latestsaavnfetcher.dart';
import '../../shared/constants.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';

final languageNotifierProvider = Provider<ValueNotifier<List<String>>>((ref) {
  final notifier = ValueNotifier<List<String>>(['tamil']); // default language
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

Future<void> initLanguage(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString('app_language') ?? 'tamil';
  final langs = savedLang.split(',').where((e) => e.isNotEmpty).toList();
  ref.read(languageNotifierProvider).value =
      langs.isNotEmpty ? langs : ['tamil'];
}

final List<String> availableLanguages = [
  'hindi',
  'tamil',
  'telugu',
  'english',
  'punjabi',
  'marathi',
  'gujarati',
  'bengali',
  'kannada',
  'bhojpuri',
  'malayalam',
  'sanskrit',
  'haryanvi',
  'rajasthani',
  'odia',
  'assamese',
];

/// --- Language Set Page as ConsumerStatefulWidget ---
class LanguageSetPage extends ConsumerStatefulWidget {
  const LanguageSetPage({super.key});

  @override
  ConsumerState<LanguageSetPage> createState() => _LanguageSetPageState();
}

class _LanguageSetPageState extends ConsumerState<LanguageSetPage> {
  List<String> _selectedLangs = [];
  bool _loading = false;
  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _selectedLangs = List.from(ref.read(languageNotifierProvider).value);
  }

  Future<void> _applyLanguages() async {
    if (!mounted || _selectedLangs.isEmpty) return;

    _loading = true;
    _loadingMessage = "Clearing existing data...";
    if (mounted) setState(() {});

    // Persist languages as comma-separated string
    final prefs = await SharedPreferences.getInstance();
    final langString = _selectedLangs.join(',');
    await prefs.setString('app_language', langString);

    // Clear existing lists
    latestTamilPlayList.clear();
    latestTamilAlbums.clear();
    lovePlaylists.clear();
    partyPlaylists.clear();

    setState(() => _loadingMessage = "Fetching latest playlist & albums...");

    // Fetch all language-specific data in parallel
    final playlistFutures = _selectedLangs.map(
      (l) => LatestSaavnFetcher.getLatestPlaylists(l),
    );
    final albumFutures = _selectedLangs.map(
      (l) => LatestSaavnFetcher.getLatestAlbums(l),
    );

    final playlistResults = await Future.wait(playlistFutures);
    final albumResults = await Future.wait(albumFutures);

    // Flatten results
    latestTamilPlayList = playlistResults.expand((x) => x).toList();
    latestTamilAlbums = albumResults.expand((x) => x).toList();

    setState(() => _loadingMessage = "Fetching your preferences...");

    final loveFutures = _selectedLangs.map(
      (l) => searchPlaylistcache.searchPlaylistCache(query: 'love $l'),
    );
    final partyFutures = _selectedLangs.map(
      (l) => searchPlaylistcache.searchPlaylistCache(query: 'party $l'),
    );

    final loveResults = await Future.wait(loveFutures);
    final partyResults = await Future.wait(partyFutures);

    lovePlaylists = loveResults.expand((x) => x).toList();
    partyPlaylists = partyResults.expand((x) => x).toList();

    _loading = false;
    _loadingMessage = '';
    if (mounted) setState(() {});
    info("Languages updated", Severity.success);

    // Update provider
    ref.read(languageNotifierProvider).value = List.from(_selectedLangs);
  }

  void _toggleLanguage(String lang) {
    if (_loading) return;
    setState(() {
      if (_selectedLangs.contains(lang)) {
        if (_selectedLangs.length > 1) {
          _selectedLangs.remove(lang);
        } else {
          info("At least one language must be selected", Severity.warning);
        }
      } else {
        _selectedLangs.add(lang);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch not strictly needed if we use local state, but good for initial
    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // --- Collapsible AppBar ---
              SliverAppBar(
                pinned: true,
                expandedHeight: 160,
                backgroundColor: spotifyBgColor,
                leading: const BackButton(color: Colors.white),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final minHeight = kToolbarHeight;
                    final maxHeight = 160.0;
                    final collapsePercent = ((constraints.maxHeight -
                                minHeight) /
                            (maxHeight - minHeight))
                        .clamp(0.0, 1.0);

                    return FlexibleSpaceBar(
                      centerTitle: false,
                      titlePadding: EdgeInsets.only(
                        left: collapsePercent < 0.5 ? 16 : 72,
                        bottom: 16,
                        right: 16,
                      ),
                      title: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: collapsePercent < 0.5 ? 1.0 : 0.0,
                        child: const Text(
                          "Language Preferences",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      background: Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 32),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Opacity(
                            opacity: collapsePercent,
                            child: const Text(
                              "Language Preferences",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // --- Section Title ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Select your preferred languages",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "You can select multiple languages for your content.",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              // --- Choice Chips ---
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    children:
                        availableLanguages.map((lang) {
                          final isSelected = _selectedLangs.contains(lang);
                          return ChoiceChip(
                            label: Text(
                              capitalize(lang),
                              style: TextStyle(
                                color: isSelected ? spotifyGreen : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: spotifyGreen.withAlpha(51),
                            backgroundColor: Colors.grey[900],
                            selectedShadowColor: Colors.grey.shade900,
                            color: WidgetStateProperty.resolveWith<Color?>((
                              states,
                            ) {
                              return Colors.grey.shade900;
                            }),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color:
                                    isSelected
                                        ? spotifyGreen
                                        : Colors.grey.shade800,
                                width: isSelected ? 1 : 0,
                              ),
                            ),
                            showCheckmark: false,
                            visualDensity: const VisualDensity(vertical: -2),
                            onSelected: (_) => _toggleLanguage(lang),
                          );
                        }).toList(),
                  ),
                ),
              ),

              // --- Set Language Button ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: spotifyGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _loading ? null : _applyLanguages,
                      child: const Text(
                        "Update Languages",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // --- Loading Overlay with Linear Progress ---
          if (_loading)
            Container(
              color: spotifyBgColor.withAlpha(240),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(spotifyGreen),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadingMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Hang tight!, please keep the app open.",
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
