import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:page_transition/page_transition.dart';
import 'package:toastification/toastification.dart';
import 'package:hivefy/utils/logger.dart';

import 'screens/library.dart';
import 'screens/onboarding.dart';
import 'screens/search.dart';
import 'services/systemconfig.dart';
import 'services/audiohandler.dart';
import 'services/localnotification.dart';
import 'shared/constants.dart';
import 'utils/theme.dart';
import 'utils/font_safe_binding.dart';

void main() async {
  FontSafeWidgetsBinding();
  await ThemeController.init();
  packageInfo = await PackageInfo.fromPlatform();

  await initNotifications();
  await SystemUiConfigurator.configure();

  runApp(ToastificationWrapper(child: ProviderScope(child: const MyApp())));
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
    _init();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    // Deep links
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) {
      Logger.log('Main', 'onAppLink: $uri');
    });
    // Await the audioHandler FutureProvider
    await ref.read(audioHandlerProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(audioHandlerProvider);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeNotifier,
      builder: (context, mode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final ColorScheme lightScheme = lightDynamic ?? ColorScheme.fromSeed(seedColor: spotifyGreen);
            final ColorScheme darkScheme =
                darkDynamic ?? ColorScheme.fromSeed(seedColor: spotifyGreen, brightness: Brightness.dark);

            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                fontFamily: 'SpotifyMix',
                textTheme: ThemeController().spotifyTextTheme,
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
                fontFamily: 'SpotifyMix',
                textTheme: ThemeController().spotifyTextTheme,
              ),
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
                    page = const StartupGate();
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
