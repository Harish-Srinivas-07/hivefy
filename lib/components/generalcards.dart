import 'package:flutter/material.dart';
import 'package:hivefy/utils/theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'snackbar.dart';

class GeneralCards extends StatelessWidget {
  final String iconPath;
  final String title;
  final String content;
  final VoidCallback? onClose;
  final String? downloadUrl; // If not null, show "Download Now" button

  const GeneralCards({
    super.key,
    this.iconPath = 'assets/icons/artist.png',
    this.title = 'Fresh Vibes, Every Day',
    this.content =
        'We\'re constantly updating your feed with new artists and trending tracks.',
    this.onClose,
    this.downloadUrl,
  });

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);

    try {
      // Try external application first
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('--> URL launch failed: $e');
      // Fallback to in-app browser if external fails
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.inAppWebView);
      } else {
        info('Cannot open link: $url', Severity.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: spotifyBgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[800]!, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Icon + Title
          Row(
            children: [
              Image.asset(iconPath, width: 28, height: 28, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Content + Button
          Text(
            content,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (downloadUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 6),
              child: GestureDetector(
                onTap: () => _launchUrl(downloadUrl!),
                child: Text(
                  'Download Now',
                  style: const TextStyle(
                    color: spotifyGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget makeItHappenCard() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Make',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                height: .6,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'it Happen ',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Colors.white54,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 5),
                Image.asset(
                  'assets/icons/heart.png',
                  height: 40,
                  alignment: Alignment.center,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'CRAFTED WITH CARE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color.fromARGB(255, 47, 47, 47),
                height: 1,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
