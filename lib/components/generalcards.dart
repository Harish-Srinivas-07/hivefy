import 'package:flutter/material.dart';

class GeneralCards extends StatelessWidget {
  final String iconPath;
  final String title;
  final String content;
  final VoidCallback? onClose;

  const GeneralCards({
    super.key,
    this.iconPath = 'assets/icons/artist.png',
    this.title = 'Fresh Vibes, Every Day',
    this.content =
        'We\'re constantly updating your feed with new artists and trending tracks.',
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 27, 27, 27),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(iconPath, width: 24, height: 24, color: Colors.white),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
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
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    content,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
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
