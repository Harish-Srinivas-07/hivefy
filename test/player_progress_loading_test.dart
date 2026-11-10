import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/shimmers.dart';
import 'package:hivefy/shared/player.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  testWidgets('seek bar previews a drag and seeks only on release', (tester) async {
    final states = StreamController<PlayerState>.broadcast();
    addTearDown(states.close);
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerSeekBar(
            position: const Duration(seconds: 10),
            duration: const Duration(seconds: 100),
            playerStateStream: states.stream,
            onSeek: (position) async => seeks.add(position),
          ),
        ),
      ),
    );
    final slider = find.byKey(const ValueKey('player-seek-track'));
    final bounds = tester.getRect(slider);
    final gesture = await tester.startGesture(Offset(bounds.left + bounds.width * 0.1, bounds.center.dy));
    await gesture.moveTo(Offset(bounds.left + bounds.width * 0.7, bounds.center.dy));
    await tester.pump();
    expect(seeks, isEmpty);
    expect(
      tester.widget<FractionallySizedBox>(find.byKey(const ValueKey('player-seek-fill'))).widthFactor,
      greaterThan(0.5),
    );
    expect(find.text('0:10'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, inInclusiveRange(60, 80));
  });

  testWidgets('loading and ready states keep the same progress control height', (tester) async {
    final states = StreamController<PlayerState>.broadcast();
    addTearDown(states.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerProgressTrack(
                playerStateStream: states.stream,
                child: Slider(value: 0.5, onChanged: (_) {}),
              ),
              const Text('Controls below'),
            ],
          ),
        ),
      ),
    );
    final initialY = tester.getTopLeft(find.text('Controls below')).dy;
    states.add(PlayerState(true, ProcessingState.buffering));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Controls below')).dy, initialY);
    states.add(PlayerState(true, ProcessingState.ready));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Controls below')).dy, initialY);
  });

  testWidgets('progress track shimmers while loading or buffering and restores seeking', (tester) async {
    final states = StreamController<PlayerState>.broadcast();
    addTearDown(states.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerProgressTrack(
            playerStateStream: states.stream,
            child: Slider(value: 0.5, onChanged: (_) {}),
          ),
        ),
      ),
    );

    states.add(PlayerState(true, ProcessingState.loading));
    await tester.pump();
    expect(find.byType(PlayerProgressLoading), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    states.add(PlayerState(true, ProcessingState.buffering));
    await tester.pump();
    expect(find.byType(PlayerProgressLoading), findsOneWidget);

    states.add(PlayerState(true, ProcessingState.ready));
    await tester.pump();
    expect(find.byType(PlayerProgressLoading), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);

    states.add(PlayerState(false, ProcessingState.ready));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
  });
}
