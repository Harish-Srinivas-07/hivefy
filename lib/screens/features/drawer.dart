// lib/screens/features/drawer.dart

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../../shared/constants.dart';
import '../../utils/theme.dart';
import 'about.dart';
import 'language.dart';
import 'profile.dart';
import 'settings.dart';
import 'soundcapsule.dart';

typedef DrawerNavigateCallback = void Function(Widget page);

class SideDrawer extends StatelessWidget {
  final DrawerNavigateCallback? onNavigate;

  const SideDrawer({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: spotifyBgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FutureBuilder(
                future: loadProfiles(),
                builder: (context, snapshot) {
                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            (profileFile != null && profileFile!.existsSync())
                                ? FileImage(profileFile!)
                                : const AssetImage('assets/icons/logo.png')
                                    as ImageProvider,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username.isNotEmpty ? username : "Oreo",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () {
                              if (onNavigate != null) {
                                onNavigate!(ProfilePage());
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProfilePage(),
                                  ),
                                );
                              }
                            },
                            behavior: HitTestBehavior.opaque,
                            child: const Text(
                              'View Profile',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            Divider(color: Colors.grey.shade800, height: .7),
            const SizedBox(height: 8),

            // --- Drawer Items ---
            _DrawerItem(
              icon: Icons.bubble_chart_outlined,
              title: "Sound Capsule",
              onTap: () {
                if (onNavigate != null) {
                  onNavigate!(SoundCapsule());
                } else {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => SoundCapsule()));
                }
              },
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              title: "Settings & Storage",
              onTap: () {
                if (onNavigate != null) {
                  onNavigate!(SettingsPage());
                } else {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => SettingsPage()));
                }
              },
            ),
            _DrawerItem(
              icon: Icons.language,
              title: "Language",
              onTap: () {
                if (onNavigate != null) {
                  onNavigate!(LanguageSetPage());
                } else {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => LanguageSetPage()));
                }
              },
            ),
            _DrawerItem(
              icon: Icons.info_outline,
              title: "About",
              onTap: () {
                if (onNavigate != null) {
                  onNavigate!(AboutPage());
                } else {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => AboutPage()));
                }
              },
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 16),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "v${packageInfo.version}\n",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (packageInfo.installTime != null)
                      TextSpan(
                        text:
                            'Installed on : ${DateFormat('d MMM, yyyy hh:mm a').format(packageInfo.installTime!)}',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _DrawerItem({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () {},
      splashColor: Colors.white10,
      highlightColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Icon(icon, color: Colors.white70, size: 26),
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
