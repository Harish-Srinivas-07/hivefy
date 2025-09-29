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
  Widget build(BuildContext context) {
    super.build(context);

    final tabIndex = ref.watch(tabIndexProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Each tab gets its own navigator to preserve state
          IndexedStack(
            index: tabIndex,
            children: List.generate(_pages.length, (i) {
              return Navigator(
                key: GlobalKey<NavigatorState>(), // keep separate stack per tab
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(builder: (_) => _pages[i]);
                },
              );
            }),
          ),

          // MiniPlayer above nav bar
          const Align(alignment: Alignment.bottomCenter, child: MiniPlayer()),
        ],
      ),
      bottomNavigationBar: FlashyTabBar(
        selectedIndex: tabIndex,
        onItemSelected: (index) async {
          ref.read(tabIndexProvider.notifier).state = index;
          final prefs = await SharedPreferences.getInstance();
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
    );
  }
}
