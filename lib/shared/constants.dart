import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import 'likedsong.dart';

// tab index
final tabIndexProvider = StateProvider<int>((ref) => 0);
final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

final currentSongProvider = StateProvider<SongDetail?>((ref) => null);

// shufflemanage
final shuffleProvider = StateProvider<bool>((ref) => false);

final repeatModeProvider = StateProvider<RepeatMode>((ref) => RepeatMode.none);

// liked songs
final likedSongsProvider =
    StateNotifierProvider<LikedSongsNotifier, List<String>>(
      (ref) => LikedSongsNotifier(),
    );

// common data
List<Playlist> playlists = [];
List<ArtistDetails> artists = [];
List<Album> albums = [];

PackageInfo packageInfo = PackageInfo(
  appName: 'Go Stream',
  packageName: 'com.hivemind.hivefy',
  version: '1.0.0',
  buildNumber: 'h07',
);

// internet value
ValueNotifier<bool> hasInternet = ValueNotifier<bool>(true);

// shared datas
List<Playlist> lovePlaylists = [];
List<Playlist> partyPlaylists = [];
List<Playlist> latestTamilPlayList = [];
List<Album> latestTamilAlbums = [];

// profile update
File? profileFile;
String username = "Oreo";
