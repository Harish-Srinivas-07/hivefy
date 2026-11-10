import 'package:flutter/material.dart';

import '../utils/theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 52 : 72,
                height: compact ? 52 : 72,
                decoration: BoxDecoration(color: spotifyGreen.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Icon(icon, color: spotifyGreen.withValues(alpha: 0.9), size: compact ? 25 : 34),
              ),
              SizedBox(height: compact ? 12 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: compact ? 16 : 20),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyStatePage extends StatelessWidget {
  const EmptyStatePage({super.key, required this.state});
  final EmptyState state;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: BackButton(color: Colors.white),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: state,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
