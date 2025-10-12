import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/constants.dart';
import '../../utils/theme.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _isTitleCollapsed = false;
  late ScrollController _scrollController;

  bool _isEditingName = false;
  final TextEditingController _nameController = TextEditingController();

  // Load stored data
  Future<void> loadProfileData() async {
    await loadProfiles();
    if (mounted) setState(() {});
  }

  // Pick image and persist it in documents directory
  Future<void> _pickAndStoreImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final dir = await getApplicationDocumentsDirectory();
      final newPath = join(
        dir.path,
        'profile_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final newImage = await File(picked.path).copy(newPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImage', newImage.path);

      setState(() {
        profileFile = newImage;
      });
    }
  }

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
    loadProfileData();
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
                      "Account",
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
                            "Account",
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

          // --- Username Section ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  // --- Avatar with edit overlay ---
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundImage:
                            profileFile != null
                                ? FileImage(profileFile!)
                                : const AssetImage('assets/icons/logo.png')
                                    as ImageProvider,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndStoreImage,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // --- Username display / edit field ---
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Username",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _isEditingName
                            ? Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: TextField(
                                onTapOutside:
                                    (_) => FocusScope.of(context).unfocus(),
                                controller: _nameController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Colors.white24,
                                    ),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: spotifyGreen),
                                  ),
                                ),
                              ),
                            )
                            : Text(
                              username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      ],
                    ),
                  ),

                  // --- Edit / Save Button ---
                  OutlinedButton(
                    onPressed: () async {
                      if (_isEditingName) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'username',
                          _nameController.text.trim(),
                        );
                        username = _nameController.text.trim();
                        _isEditingName = false;
                        setState(() {});
                      } else {
                        _isEditingName = true;
                        _nameController.text = username;
                        setState(() {});
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      _isEditingName ? "Save" : "Edit",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Divider ---
          _buildDivider(),

          // --- Plan Section ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Your Plan",
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- Premium Card ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note, color: spotifyGreen),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Freemium",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // SizedBox(height: 4),
                            Text(
                              "Forever",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 10)),

          // --- Benefits Section ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Snapshot of your benefits",
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildBenefitItem("Ad-free music listening"),
                        _buildBenefitItem("Download to listen offline"),
                        _buildBenefitItem("High audio quality"),
                        _buildBenefitItem("Organise listening queue"),
                      ],
                    ),
                  ),
                  // const SizedBox(height: 12),
                  // OutlinedButton(
                  //   onPressed: () {},
                  //   style: OutlinedButton.styleFrom(
                  //     side: const BorderSide(color: Colors.white30),
                  //     shape: RoundedRectangleBorder(
                  //       borderRadius: BorderRadius.circular(20),
                  //     ),
                  //     padding: const EdgeInsets.symmetric(
                  //       horizontal: 20,
                  //       vertical: 12,
                  //     ),
                  //   ),
                  //   child: const Text(
                  //     "Explore your benefits",
                  //     style: TextStyle(color: Colors.white),
                  //   ),
                  // ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildDivider() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Divider(color: Colors.white12, thickness: 1),
      ),
    );
  }

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check, color: spotifyGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> loadProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  final storedName = prefs.getString('username');
  final imagePath = prefs.getString('profileImage');

  username = storedName ?? "Oreo";
  if (imagePath != null && File(imagePath).existsSync()) {
    profileFile = File(imagePath);
  }
}
