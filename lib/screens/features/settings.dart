import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/database.dart';
import '../../components/snackbar.dart';
import '../../services/offlinemanager.dart';
import '../../utils/theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool notificationsEnabled = false;
  bool _isTitleCollapsed = false;
  late ScrollController _scrollController;
  final DiskSpacePlus diskSpacePlus = DiskSpacePlus();

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
    _checkNotificationStatus();
  }

  Future<void> _checkNotificationStatus() async {
    final status = await Permission.notification.status;
    setState(() => notificationsEnabled = status.isGranted);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() => notificationsEnabled = status.isGranted);
    if (!status.isGranted) openAppSettings();
  }

  Future<double> getDeviceStorageInBytes() async {
    final totalGB = await diskSpacePlus.getTotalDiskSpace ?? 0;

    // Sanity check: if totalGB is unrealistic, fallback to 32 GB
    final safeGB = (totalGB > 0 && totalGB < 1024) ? totalGB : 32.0;

    return safeGB * 1024 * 1024 * 1024;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // --- Collapsible AppBar ---
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
                      "Settings",
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
                            "Settings",
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

          // --- Notifications ---
          _buildSectionTitle(
            "Notifications",
            subtitle: "Manage app notification settings",
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    notificationsEnabled
                        ? 'assets/icons/bell.png'
                        : 'assets/icons/alert.png',
                    width: 28,
                    height: 28,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "App Notifications",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notificationsEnabled
                              ? "You will receive notifications for updates"
                              : "Notifications are off, tap to enable",
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!notificationsEnabled)
                    TextButton(
                      onPressed: _requestNotificationPermission,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(
                          color: Colors.greenAccent,
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        "Enable",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildDivider(),

          // --- User Preferences ---
          _buildSectionTitle(
            "Preferences",
            subtitle: "Manage your recent activity and search history",
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                iconAsset: 'assets/icons/last_played.png',
                title: "Last Played Songs",
                content: "Clear your recent song history",
                onDelete: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('last_songs');
                  info('Last Played Songs cleared', Severity.success);
                },
              ),
              SettingsRow(
                iconAsset: 'assets/icons/last_album.png',
                title: "Last Played Albums",
                content: "Clear your recent albums history",
                onDelete: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('last_albums');
                  info('Last Played Albums cleared', Severity.success);
                },
              ),
              SettingsRow(
                iconAsset: 'assets/icons/search.png',
                title: "Search History",
                content: "Clear all previous searches",
                onDelete: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('search_history');
                  info('Search History cleared', Severity.success);
                },
              ),
            ]),
          ),
          _buildDivider(),

          // --- Offline Manager Section ---
          _buildSectionTitle(
            "Offline Manager",
            subtitle: "Manage all downloaded songs and albums",
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                iconAsset: 'assets/icons/data.png',
                title: "Delete All Offline Songs",
                content: "Remove all downloaded songs.",
                onDelete: () async {
                  await offlineManager.deleteAllSongs();
                  info('All offline songs deleted', Severity.success);
                },
              ),
            ]),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  offlineManager.getOfflineStorageUsed(),
                  offlineManager.getOfflineStorageUsedFormatted(),
                  getDeviceStorageInBytes(),
                ]),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  final offlineBytes = snapshot.data![0] as double;
                  final usedFormatted = snapshot.data![1] as String;
                  final totalBytes = snapshot.data![2] as double;
                  final fraction =
                      totalBytes > 0
                          ? (offlineBytes / totalBytes).clamp(0.0, 1.0) + .01
                          : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Offline Songs: $usedFormatted",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Stack(
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: fraction,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: spotifyGreen,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${_formatBytes(offlineBytes)} used",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            "${_formatBytes(totalBytes)} total",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          _buildDivider(),

          // --- Main Database Caches ---
          _buildSectionTitle(
            "Caches",
            subtitle: "Remove caches, only when you face some caches issue!",
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                iconAsset: 'assets/icons/song.png',
                title: "Songs Cache",
                content: "Remove saved songs.",
                onDelete: () async {
                  await AppDatabase.clearSongs();
                  info('Songs cleared', Severity.success);
                },
              ),
              SettingsRow(
                iconAsset: 'assets/icons/artist.png',
                title: "Artist Cache",
                content: "Remove saved artists information",
                onDelete: () async {
                  await ArtistCache().clear();
                  info('Artist cleared', Severity.success);
                },
              ),
              SettingsRow(
                iconAsset: 'assets/icons/disc.png',
                title: "Album Cache",
                content: "Remove saved albums data",
                onDelete: () async {
                  await AlbumCache().clear();
                  info('Album cleared', Severity.success);
                },
              ),
              SettingsRow(
                iconAsset: 'assets/icons/playlist.png',
                title: "Playlist Cache",
                content: "Remove saved playlists",
                onDelete: () async {
                  await PlaylistCache().clear();
                  info('Playlists cleared', Severity.success);
                },
              ),
            ]),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(String title, {String? subtitle}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildDivider() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Divider(color: Colors.white12, thickness: 1),
      ),
    );
  }
}

// --- SettingsRow with improved spacing ---
class SettingsRow extends StatelessWidget {
  final String title;
  final String content;
  final String iconAsset;
  final VoidCallback onDelete;
  final bool showDelete;

  const SettingsRow({
    super.key,
    required this.title,
    required this.content,
    required this.iconAsset,
    required this.onDelete,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(iconAsset, width: 28, height: 28, color: Colors.white),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          if (showDelete)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Colors.white30, width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                "Clear",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatBytes(double bytes) {
  if (bytes <= 0) return "0 B";

  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;

  if (bytes >= gb) return "${(bytes / gb).toStringAsFixed(2)} GB";
  if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(2)} MB";
  if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(2)} KB";
  return "${bytes.toStringAsFixed(0)} B";
}
