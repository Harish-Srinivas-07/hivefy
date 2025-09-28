import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconly/iconly.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/constants.dart';
import '../shared/miniplayer.dart';
import 'dashboard.dart';
import 'library.dart';
import 'search.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final List<Widget> _pages = const [Dashboard(), Search(), LibraryPage()];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _loadLastIndex();
  }

  Future<void> _loadLastIndex() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final lastIndex = prefs.getInt('last_index') ?? 0;
    ref.read(tabIndexProvider.notifier).state = lastIndex;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final tabIndex = ref.watch(tabIndexProvider);
    final albumPage = ref.watch(albumPageProvider);

    // Show album page if set, else default tab
    final currentPage = albumPage ?? _pages[tabIndex];

    return PopScope(
      canPop: albumPage == null,
      onPopInvokedWithResult: (canPop, _) {
        final albumPage = ref.read(albumPageProvider);
        if (albumPage != null) {
          ref.read(albumPageProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Active page
            currentPage,

            // MiniPlayer positioned above bottom nav bar
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [MiniPlayer()],
              ),
            ),
          ],
        ),
        bottomNavigationBar: FlashyTabBar(
          selectedIndex: tabIndex,
          showElevation: true,
          height: 55,
          backgroundColor: const Color.fromARGB(255, 21, 21, 21),
          iconSize: 28,
          animationCurve: Curves.easeOutExpo,
          onItemSelected: (index) async {
            // Reset album page when switching tabs
            ref.read(albumPageProvider.notifier).state = null;

            ref.read(tabIndexProvider.notifier).state = index;
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setInt('last_index', index);
          },
          items: [
            FlashyTabBarItem(
              icon: const Icon(IconlyBroken.home),
              title: Text('Home', style: GoogleFonts.poppins()),
              activeColor: Colors.greenAccent,
              inactiveColor: Colors.grey,
            ),
            FlashyTabBarItem(
              icon: const Icon(IconlyLight.search),
              title: Text('Search', style: GoogleFonts.poppins()),
              activeColor: Colors.greenAccent,
              inactiveColor: Colors.grey,
            ),
            FlashyTabBarItem(
              icon: const Icon(IconlyBroken.chart),
              title: Text('Library', style: GoogleFonts.poppins()),
              activeColor: Colors.greenAccent,
              inactiveColor: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
