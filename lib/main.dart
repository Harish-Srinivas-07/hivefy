import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:page_transition/page_transition.dart';

import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/search.dart';
import 'shared/constants.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  packageInfo = await PackageInfo.fromPlatform();
  runApp(ProviderScope(child: const MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> initDeepLinks() async {
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) {
      debugPrint('onAppLink: $uri');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeNotifier,
      builder: (context, mode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final ColorScheme lightScheme =
                lightDynamic ??
                ColorScheme.fromSeed(seedColor: Colors.greenAccent);
            final ColorScheme darkScheme =
                darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: Colors.greenAccent,
                  brightness: Brightness.dark,
                );

            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
              darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
              themeMode: mode,
              onGenerateRoute: (settings) {
                Widget page;
                switch (settings.name) {
                  case '/search':
                    page = const Search();
                    break;
                  case '/library':
                    page = const LibraryPage();
                    break;
                  default:
                    page = const Home();
                }
                return PageTransition(
                  type: PageTransitionType.rightToLeft,
                  child: page,
                  settings: settings,
                  duration: const Duration(milliseconds: 300),
                  reverseDuration: const Duration(milliseconds: 300),
                );
              },
            );
          },
        );
      },
    );
  }
}
