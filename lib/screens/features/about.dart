import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/snackbar.dart';
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

  @override
  void initState() {
    super.initState();

    _scrollController =
        ScrollController()..addListener(() {
          final offset = _scrollController.offset;
          if (offset > 120 && !_isTitleCollapsed) {
            setState(() => _isTitleCollapsed = true);
          } else if (offset <= 120 && _isTitleCollapsed) {
            setState(() => _isTitleCollapsed = false);
          }
        });

    _loadPackageInfo();
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
                final collapsePercent = ((constraints.maxHeight - minHeight) /
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
                  '${packageInfo.version} (${packageInfo.buildNumber})',
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.star,
                      color: Colors.orange,
                      size: 16,
                    ),
                    title: Text.rich(
                      TextSpan(
                        text: 'Like this project, star it on ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SpotifyMix',
                        ),
                        children: [
                          TextSpan(
                            text: 'GitHub!',
                            style: const TextStyle(
                              color: spotifyGreen,
                              decoration: TextDecoration.underline,
                              fontFamily: 'SpotifyMix',
                            ),
                          ),
                        ],
                      ),
                    ),
                    onTap: () async {
                      final url = Uri.parse(
                        'https://github.com/Harish-Srinivas-07/hivefy',
                      );

                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      } else {
                        info(
                          'Cant open link, visit github.com/Harish-Srinivas-07',
                          Severity.error,
                        );
                      }
                    },
                  ),
                ),

                Divider(color: Colors.grey.shade800),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
