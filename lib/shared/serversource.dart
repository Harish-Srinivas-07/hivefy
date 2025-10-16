import 'package:shared_preferences/shared_preferences.dart';

/// Enum for the available servers
enum ServerType { main, mirror, dupe }

extension ServerTypeExtension on ServerType {
  String get displayName {
    switch (this) {
      case ServerType.main:
        return 'Main Server';
      case ServerType.mirror:
        return 'Mirror Server';
      case ServerType.dupe:
        return 'Backup Server';
    }
  }

  String get baseUrl {
    switch (this) {
      case ServerType.main:
        return 'https://jiosaavn-c451wwyru-sumit-kolhes-projects-94a4846a.vercel.app/';
      case ServerType.mirror:
        return 'https://saavn.dev/';
      case ServerType.dupe:
        return 'https://jiosaavnapi-dev.vercel.app/';
    }
  }

  static ServerType fromName(String name) {
    switch (name) {
      case 'Mirror Server':
        return ServerType.mirror;
      case 'Source Dupe':
        return ServerType.dupe;
      default:
        return ServerType.main;
    }
  }
}

class ServerManager {
  static const _key = 'selected_server_enum';

  /// Save selected server
  static Future<void> setServer(ServerType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, type.name);
  }

  /// Get saved server (default to main)
  static Future<ServerType> getSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      return ServerType.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ServerType.main,
      );
    }
    return ServerType.main;
  }

  /// Get only URL
  static Future<String> getSelectedBaseUrl() async {
    final type = await getSelectedServer();
    return type.baseUrl;
  }
}
