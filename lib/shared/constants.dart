import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/datamodel.dart';

// tab index 
final tabIndexProvider = StateProvider<int>((ref) => 0);

// current song
final playerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  return player;
});

final currentSongProvider = StateProvider<SongDetail?>((ref) => null);

// pages
final albumPageProvider = StateProvider<Widget?>((ref) => null);


// common data
List<Playlist> playlists = [];
List<ArtistDetails> artists = [];

PackageInfo packageInfo = PackageInfo(
  appName: 'Go Stream',
  packageName: 'com.hivemind.hivefy',
  version: '1.0.0',
  buildNumber: 'h07',
);
