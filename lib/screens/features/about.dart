import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/generalcards.dart';
import '../../components/snackbar.dart';
import '../../services/systemconfig.dart';
import '../../shared/constants.dart';
import '../../utils/theme.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  late ScrollController _scrollController;
  bool _isTitleCollapsed = false;
  bool _showUpdateAvailable = true;

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController()
      ..addListener(() {
        final offset = _scrollController.offset;
        if (offset > 120 && !_isTitleCollapsed) {
          setState(() => _isTitleCollapsed = true);
        } else if (offset <= 120 && _isTitleCollapsed) {
          setState(() => _isTitleCollapsed = false);
        }
      });

    _loadPackageInfo();
    checkForUpdate();
    if (mounted) setState(() {});
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => packageInfo = info);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: getDominantDarker(spotifyGreen),
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildCreditsSection() {
    final credits = [
      {
        'icon': 'assets/icons/case.png',
        'title': 'HiveMinds',
        'username': 'thehiveminds.in',
        'url': 'https://thehiveminds.in',
      },
      {
        'icon': 'assets/icons/atsign.png',
        'title': 'Contact Us',
        'username': 'info@thehiveminds.in',
        'url': 'mailto:info@thehiveminds.in',
      },
      {
        'icon': 'assets/icons/github.png',
        'title': 'GitHub',
        'username': 'Harish-Srinivas-07',
        'url': 'https://github.com/Harish-Srinivas-07',
      },
      {
        'icon': 'assets/icons/linkedin.png',
        'title': 'LinkedIn',
        'username': 'harishsrinivas-sr',
        'url': 'https://www.linkedin.com/in/harishsrinivas-sr/',
      },
      {
        'icon': 'assets/icons/case.png',
        'title': 'Portfolio',
        'username': 'harishsrinivas.netlify.app',
        'url': 'https://harishsrinivas.netlify.app',
      },
      {
        'icon': 'assets/icons/atsign.png',
        'title': 'Instagram',
        'username': '@being_exception',
        'url': 'https://www.instagram.com/being_exception',
      },
      {
        'icon': 'assets/icons/medium.png',
        'title': 'Medium',
        'username': '@sr.harishsrinivas',
        'url': 'https://medium.com/@sr.harishsrinivas',
      },
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Credits",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Connect with me',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...credits.map(
              (c) => GestureDetector(
                onTap: () async {
                  final urlStr = c['url']!;
                  final uri = Uri.parse(urlStr);
                  try {
                    if (urlStr.startsWith('mailto:')) {
                      await launchUrl(uri);
                      return;
                    }
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint('--> URL launch failed: $e');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.inAppWebView);
                    } else {
                      info('Cannot open link: ${c['url']}', Severity.error);
                    }
                  }
                },

                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Image.asset(
                        c['icon']!,
                        height: 28,
                        width: 28,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['title']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c['username']!,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // --- Collapsible Sliver AppBar ---
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: getDominantDarker(spotifyGreen),
            leading: const BackButton(color: Colors.white),
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = kToolbarHeight;
                final maxHeight = 160.0;
                final collapsePercent =
                    ((constraints.maxHeight - minHeight) /
                            (maxHeight - minHeight))
                        .clamp(0.0, 1.0);

                return FlexibleSpaceBar(
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(
                    left: _isTitleCollapsed ? 72 : 16,
                    bottom: 16,
                    right: 16,
                  ),
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isTitleCollapsed ? 1.0 : 0.0,
                    child: const Text(
                      "About",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  background: Container(
                    color: spotifyBgColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 32),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Opacity(
                          opacity: collapsePercent,
                          child: const Text(
                            "About",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // --- App Name & Label ---
                Center(
                  child: Column(
                    children: [
                      Text(
                        packageInfo.appName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'APP INFO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: getDominantDarker(spotifyGreen),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _infoRow(
                  'VERSION',
                  '${packageInfo.version} ::${packageInfo.buildNumber}',
                ),
                _infoRow('PACKAGE', packageInfo.packageName),
                _infoRow(
                  'SIGNATURE',
                  packageInfo.buildSignature.isNotEmpty
                      ? packageInfo.buildSignature
                      : 'N/A',
                ),
                _infoRow('INSTALLER', packageInfo.installerStore ?? 'Unknown'),
                const SizedBox(height: 20),
                if (isAppUpdateAvailable && _showUpdateAvailable) ...[
                  const SizedBox(height: 20),
                  GeneralCards(
                    iconPath: 'assets/icons/alert.png',
                    title: 'Update Available!',
                    content:
                        'Please update the app to enjoy the best experience and latest features.',
                    downloadUrl:
                        'https://github.com/Harish-Srinivas-07/hivefy/releases/latest',
                    onClose: () {
                      _showUpdateAvailable = false;
                      setState(() {});
                    },
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse('https://hivefyweb.vercel.app');
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        debugPrint('--> URL launch failed: $e');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.inAppWebView);
                        } else {
                          info(
                            'Cannot open link: https://hivefyweb.vercel.app',
                            Severity.error,
                          );
                        }
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withAlpha(25),
                          width: 1.0,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'assets/icons/logo.png',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Hivefy Web',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: spotifyGreen,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'WEB',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Stream your favorite music anywhere via browser',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'hivefyweb.vercel.app',
                                  style: TextStyle(
                                    color: spotifyGreen.withAlpha(204),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white54,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(
                        'https://github.com/Harish-Srinivas-07/hivefy',
                      );
                      try {
                        // Try external application first
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        debugPrint('--> URL launch failed: $e');
                        // Fallback to in-app browser if external fails
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.inAppWebView);
                        } else {
                          info(
                            'Cannot open link: https://github.com/Harish-Srinivas-07/hivefy',
                            Severity.error,
                          );
                        }
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(51),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.star,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: 'Like this project ?\nStar it on ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'SpotifyMix',
                                  fontSize: 14,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'GitHub!',
                                    style: TextStyle(
                                      color: spotifyGreen,
                                      // decoration: TextDecoration.underline,
                                      fontFamily: 'SpotifyMix',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: const Icon(
                              Icons.open_in_new,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse('https://thehiveminds.in');
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        debugPrint('--> URL launch failed: $e');
                      }
                    },
                    child: Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          text: 'Need Custom Software?\n',
                          style: TextStyle(
                            color: spotifyGreen,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SpotifyMix',
                            fontSize: 15,
                            height: 1.5,
                          ),
                          children: const [
                            TextSpan(
                              text:
                                  'If any software needed to build just contact us.\nWe build any application, web app, and more.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade800),
                const SizedBox(height: 20),
              ],
            ),
          ),
          _buildCreditsSection(),
        ],
      ),
    );
  }
}
