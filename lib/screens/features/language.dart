import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivefy/components/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/database.dart';
import '../../services/latestsaavnfetcher.dart';
import '../../shared/constants.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';

final languageNotifierProvider = Provider<ValueNotifier<String>>((ref) {
  final notifier = ValueNotifier<String>('tamil'); // default language
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

Future<void> initLanguage(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final savedLang = prefs.getString('app_language') ?? 'tamil';
  ref.read(languageNotifierProvider).value = savedLang;
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
  String? _selectedLang;
  bool _loading = false;
  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _selectedLang = ref.read(languageNotifierProvider).value;
  }

  Future<void> _applyLanguage(String lang) async {
    _loading = true;
    _loadingMessage = "Clearing existing data...";
    if (mounted) setState(() {});

    // Persist language
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', lang);

    // Clear existing lists
    latestTamilPlayList.clear();
    latestTamilAlbums.clear();
    lovePlaylists.clear();
    partyPlaylists.clear();

    if (mounted) setState(() => _loadingMessage = "Fetching playlists...");
    latestTamilPlayList = await LatestSaavnFetcher.getLatestPlaylists(lang);

    if (mounted) setState(() => _loadingMessage = "Fetching albums...");
    latestTamilAlbums = await LatestSaavnFetcher.getLatestAlbums(lang);

    if (mounted) {
      setState(() => _loadingMessage = "Fetching famous playlists...");
    }
    lovePlaylists = await searchPlaylistcache.searchPlaylistCache(
      query: 'love $lang',
    );

    if (mounted) {
      setState(() => _loadingMessage = "Fetching famous playlists...");
    }
    partyPlaylists = await searchPlaylistcache.searchPlaylistCache(
      query: 'party $lang',
    );

    // Update provider
    ref.read(languageNotifierProvider).value = lang;

    _loading = false;
    _loadingMessage = '';
    if (mounted) setState(() {});

    info("Language set to ${capitalize(lang)}", Severity.success);
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageNotifierProvider).value;

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
                        "Select your preferred language",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "This language will be used for app content after confirmation.",
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
                          final isSelected = _selectedLang == lang;
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
                            onSelected: (_) {
                              if (!_loading) {
                                setState(() => _selectedLang = lang);
                              }
                            },
                          );
                        }).toList(),
                  ),
                ),
              ),

              // --- Set Language Button ---
              if (_selectedLang != null && _selectedLang != currentLang)
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
                        onPressed:
                            _loading
                                ? null
                                : () => _applyLanguage(_selectedLang!),
                        child: const Text(
                          "Set Language",
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
                      "Please wait...",
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
