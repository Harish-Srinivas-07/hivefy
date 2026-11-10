/// Requests a phone-sized YouTube Music thumbnail for the full player.
String fullPlayerArtworkUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  // i.ytimg thumbnails use named sizes rather than resize parameters. The image
  // widget falls back to the original URL when a video has no max-resolution art.
  if (uri.host == 'i.ytimg.com') {
    final path = uri.path.replaceFirst(RegExp(r'/(?:hqdefault|mqdefault|sddefault)\.jpg$'), '/maxresdefault.jpg');
    return path == uri.path ? url : uri.replace(path: path).toString();
  }

  if (!(uri.host == 'googleusercontent.com' ||
      uri.host.endsWith('.googleusercontent.com') ||
      uri.host == 'ggpht.com' ||
      uri.host.endsWith('.ggpht.com'))) {
    return url;
  }

  final resizeStart = uri.path.lastIndexOf('=w');
  if (resizeStart < 0) return url;
  final path = '${uri.path.substring(0, resizeStart)}=w1080-h1080-l90-rj';
  return uri.replace(path: path).toString();
}

/// Requests a medium thumbnail for the compact queue and lyrics artwork.
String compactPlayerArtworkUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  if (uri.host == 'i.ytimg.com') {
    final path = uri.path.replaceFirst(RegExp(r'/(?:hqdefault|mqdefault|maxresdefault)\.jpg$'), '/sddefault.jpg');
    return path == uri.path ? url : uri.replace(path: path).toString();
  }

  if (!(uri.host == 'googleusercontent.com' ||
      uri.host.endsWith('.googleusercontent.com') ||
      uri.host == 'ggpht.com' ||
      uri.host.endsWith('.ggpht.com'))) {
    return url;
  }

  final resizeStart = uri.path.lastIndexOf('=w');
  if (resizeStart < 0) return url;
  final path = '${uri.path.substring(0, resizeStart)}=w720-h720-l90-rj';
  return uri.replace(path: path).toString();
}

/// Requests a small thumbnail for the mini player.
String miniPlayerArtworkUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  if (uri.host == 'i.ytimg.com') {
    final path = uri.path.replaceFirst(
      RegExp(r'/(?:hqdefault|mqdefault|sddefault|maxresdefault)\.jpg$'),
      '/mqdefault.jpg',
    );
    return path == uri.path ? url : uri.replace(path: path).toString();
  }

  if (!(uri.host == 'googleusercontent.com' ||
      uri.host.endsWith('.googleusercontent.com') ||
      uri.host == 'ggpht.com' ||
      uri.host.endsWith('.ggpht.com'))) {
    return url;
  }

  final resizeStart = uri.path.lastIndexOf('=w');
  if (resizeStart < 0) return url;
  final path = '${uri.path.substring(0, resizeStart)}=w180-h180-l90-rj';
  return uri.replace(path: path).toString();
}
