// lib/screens/home.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flashy_tab_bar2/flashy_tab_bar2.dart';
import 'package:iconly/iconly.dart';
import 'package:page_transition/page_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/theme.dart';
import 'features/drawer.dart';
import 'dashboard.dart';
import 'features/profile.dart';
import 'library.dart';
import 'search.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => HomeState();
}

class HomeState extends ConsumerState<Home> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // per-tab navigators
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
    loadProfiles();
  }

  Widget _buildNavigator(Widget page, GlobalKey<NavigatorState> key) {
    return Navigator(
      key: key,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
    );
  }

  // Helper to push into the currently active tab navigator
  Future<void> pushToActiveTab(Widget page) async {
    final tabIndex = ref.read(tabIndexProvider);
    final currentKey = _navigatorKeys[tabIndex];
    final state = currentKey.currentState;

    if (state != null) {
      state.push(
        PageTransition(
          type: PageTransitionType.rightToLeft,
          duration: const Duration(milliseconds: 100),
          reverseDuration: const Duration(milliseconds: 100),
          child: page,
        ),
      );
    } else {
      Navigator.of(context).push(
        PageTransition(
          type: PageTransitionType.rightToLeft,
          duration: const Duration(milliseconds: 100),
          reverseDuration: const Duration(milliseconds: 100),
          child: page,
        ),
      );
    }
  }

  Future<bool> onWillPop() async {
    final tabIndex = ref.read(tabIndexProvider);
    final currentKey = _navigatorKeys[tabIndex];
    final currentState = currentKey.currentState;
    if (currentState != null && currentState.canPop()) {
      currentState.pop();
      return false;
    }
    if (tabIndex != 0) {
      ref.read(tabIndexProvider.notifier).state = 0;
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final tabIndex = ref.watch(tabIndexProvider);
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final currentKey = _navigatorKeys[tabIndex];
        final currentState = currentKey.currentState;
        if (currentState != null && currentState.canPop()) {
          currentState.pop();
          return;
        }
        if (tabIndex != 0) {
          ref.read(tabIndexProvider.notifier).state = 0;
          return;
        }
      },
      child: Scaffold(
        key: scaffoldKey,
        drawer: SideDrawer(
          onNavigate: (page) async {
            Navigator.of(context).pop();
            await Future.delayed(const Duration(microseconds: 300));
            await pushToActiveTab(page);
          },
        ),
        body: Stack(
          children: [
            IndexedStack(index: tabIndex, children: _navigators),
            if (!isKeyboardVisible)
              const Align(
                alignment: Alignment.bottomCenter,
                child: MiniPlayer(),
              ),
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
          title: const Text('Home', style: TextStyle(fontSize: 16)),
          activeColor: spotifyGreen,
          inactiveColor: Colors.grey,
        ),
        FlashyTabBarItem(
          icon: const Icon(IconlyLight.search, size: 30),
          title: const Text('Search', style: TextStyle(fontSize: 16)),
          activeColor: spotifyGreen,
          inactiveColor: Colors.grey,
        ),
        FlashyTabBarItem(
          icon: const Icon(IconlyBroken.chart, size: 30),
          title: const Text('Library', style: TextStyle(fontSize: 16)),
          activeColor: spotifyGreen,
          inactiveColor: Colors.grey,
        ),
      ],
    );
  }
}
