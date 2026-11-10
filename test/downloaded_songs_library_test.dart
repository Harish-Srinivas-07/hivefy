import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/database.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/screens/library.dart';
import 'package:hivefy/services/audiohandler.dart';
import 'package:hivefy/services/offlinemanager.dart';
import 'package:hivefy/shared/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('downloaded playlist shows only downloads and updates after removal', (tester) async {
    final directory = Directory.systemTemp.createTempSync('hivefy_download_test');
    final downloaded = File('${directory.path}/downloaded.m4a');
    final cached = File('${directory.path}/cached.m4a');
    downloaded.writeAsBytesSync([1]);
    cached.writeAsBytesSync([1]);
    SharedPreferences.setMockInitialValues({
      'offlineSongs': jsonEncode({'downloaded': downloaded.path}),
      'cachedSongs': jsonEncode({'cached': cached.path}),
    });
    addTearDown(() {
      hasInternet.value = true;
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await AppDatabase.saveSongDetail(
      SongDetail(
        id: 'downloaded',
        title: 'Downloaded track',
        type: 'song',
        url: '',
        images: [],
        ytVideoId: 'downloaded',
      ),
    );
    await AppDatabase.saveSongDetail(
      SongDetail(id: 'cached', title: 'Cached track', type: 'song', url: '', images: [], ytVideoId: 'cached'),
    );
    await offlineManager.init();
    hasInternet.value = false;
    final pendingAudio = Completer<MyAudioHandler>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWith((ref) => pendingAudio.future)],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Downloaded Songs'), findsOneWidget);
    expect(find.text('Playlist • 1 song'), findsOneWidget);
    await tester.tap(find.text('Downloaded Songs'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Downloaded track'), findsOneWidget);
    expect(find.text('Cached track'), findsNothing);

    await tester.runAsync(() => offlineManager.deleteSong('downloaded'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('No downloaded songs yet'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Playlist • 0 songs'), findsWidgets);
  });
}
