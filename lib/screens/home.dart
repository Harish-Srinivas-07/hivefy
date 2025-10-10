import 'package:flutter/material.dart';

import 'package:iconly/iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/constants.dart';
import '../shared/player.dart';
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

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  late final List<Widget> _navigators;

  @override
  void initState() {
    super.initState();

    _navigators = [
      _buildNavigator(const Dashboard(), _navigatorKeys[0]),
      _buildNavigator(const Search(), _navigatorKeys[1]),
      _buildNavigator(const LibraryPage(), _navigatorKeys[2]),
    ];
  }

  Widget _buildNavigator(Widget page, GlobalKey<NavigatorState> key) {
    return Navigator(
      key: key,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
    );
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final tabIndex = ref.watch(tabIndexProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final currentNavigatorKey = _navigatorKeys[tabIndex];
        if (currentNavigatorKey.currentState?.canPop() ?? false) {
          currentNavigatorKey.currentState!.pop();
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _buildSideDrawer(),
        body: Stack(
          children: [
            IndexedStack(index: tabIndex, children: _navigators),
            const Align(alignment: Alignment.bottomCenter, child: MiniPlayer()),
          ],
        ),
        bottomNavigationBar: _buildBottomNavBar(tabIndex),
      ),
    );
  }

  Widget _buildBottomNavBar(int tabIndex) {
    return FlashyTabBar(
      height: 60,
      selectedIndex: tabIndex,
      backgroundColor: const Color.fromARGB(255, 21, 21, 21),
      onItemSelected: (index) async {
        ref.read(tabIndexProvider.notifier).state = index;
        final prefs = await SharedPreferences.getInstance();
        prefs.setInt('last_index', index);
      },
      items: [
        FlashyTabBarItem(
          icon: const Icon(IconlyBroken.home, size: 30),
          title: Text('Home', style: TextStyle(fontSize: 16)),
          activeColor: Colors.greenAccent,
          inactiveColor: Colors.grey,
        ),
        FlashyTabBarItem(
          icon: const Icon(IconlyLight.search, size: 30),
          title: Text('Search', style: TextStyle(fontSize: 16)),
          activeColor: Colors.greenAccent,
          inactiveColor: Colors.grey,
        ),
        FlashyTabBarItem(
          icon: const Icon(IconlyBroken.chart, size: 30),
          title: Text('Library', style: TextStyle(fontSize: 16)),
          activeColor: Colors.greenAccent,
          inactiveColor: Colors.grey,
        ),
      ],
    );
  }
}

Widget _buildSideDrawer() {
  return Drawer(
    backgroundColor: const Color(0xFF121212),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      children: [
        Row(
          children: const [
            CircleAvatar(
              radius: 25,
              backgroundImage: AssetImage('assets/icons/logo.png'),
            ),
            SizedBox(width: 12),
            Text('Hivefy', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        const SizedBox(height: 30),
        _drawerItem(Icons.home, "Home"),
        _drawerItem(Icons.library_music, "Your Library"),
        _drawerItem(Icons.favorite, "Liked Songs"),
        _drawerItem(Icons.settings, "Settings"),
      ],
    ),
  );
}

Widget _drawerItem(IconData icon, String title) {
  return ListTile(
    leading: Icon(icon, color: Colors.white70),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    onTap: () {
      // Navigator.pop(context);
      // handle your navigation logic if needed
    },
  );
}
