import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/localnotification.dart';
import '../utils/logger.dart';
import '../utils/theme.dart';

class NotificationPermissionGate extends StatefulWidget {
  const NotificationPermissionGate({
    super.key,
    required this.child,
    this.checkStatus,
    this.checkNotificationsEnabled,
    this.requestPermission,
  });

  final Widget child;
  final Future<PermissionStatus> Function()? checkStatus;
  final Future<bool?> Function()? checkNotificationsEnabled;
  final Future<void> Function()? requestPermission;

  @override
  State<NotificationPermissionGate> createState() => _NotificationPermissionGateState();
}

class _NotificationPermissionGateState extends State<NotificationPermissionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPermissionExplanation());
  }

  Future<void> _showPermissionExplanation() async {
    try {
      final status = await (widget.checkStatus?.call() ?? Permission.notification.status);
      if (!mounted || !status.isDenied) return;
      final enabled = await (widget.checkNotificationsEnabled?.call() ?? areNotificationsEnabled());
      if (!mounted || enabled == true) return;
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: const Color(0xff242424),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.notifications_outlined, color: spotifyGreen, size: 36),
                const SizedBox(height: 16),
                const Text(
                  'Enable notifications',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Allow notifications to see song download progress and app updates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: spotifyGreen, foregroundColor: Colors.black),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('OK'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not now', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      );
      if (accepted == true && mounted) {
        await (widget.requestPermission?.call() ?? requestNotificationPermission());
      }
    } catch (error) {
      Logger.error('Notifications', 'Unable to request notification permission: $error');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
