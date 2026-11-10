import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/player_sheet.dart';

void main() {
  testWidgets('closing from compact artwork starts the flight at its actual position', (tester) async {
    final artworkKey = GlobalKey();
    const compactRect = Rect.fromLTWH(20, 60, 56, 56);
    playerSheet.fullArtworkKey = artworkKey;
    playerSheet.miniArtworkRect = const Rect.fromLTWH(30, 700, 44, 44);
    addTearDown(() {
      playerSheet.fullArtworkKey = null;
      playerSheet.miniArtworkRect = null;
      playerSheet.engaged.value = false;
      playerSheet.progress.value = 0;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerSheetLayer(
          player: Stack(
            children: [
              Positioned.fromRect(
                rect: compactRect,
                child: ColoredBox(key: artworkKey, color: Colors.red),
              ),
            ],
          ),
          artwork: const ColoredBox(key: ValueKey('flight-artwork'), color: Colors.blue),
        ),
      ),
    );
    playerSheet.dragTo(1);
    await tester.pump();
    playerSheet.dragTo(.99);
    await tester.pump();
    final flight = tester.getRect(find.byKey(const ValueKey('flight-artwork')));
    expect(flight.left, closeTo(compactRect.left, 1));
    expect(flight.top, closeTo(compactRect.top, 8));
    expect(flight.width, closeTo(compactRect.width, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('player sheet opens promptly and settles fully', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerSheetLayer(player: SizedBox(), artwork: SizedBox()),
      ),
    );

    playerSheet.open();
    await tester.pump(); // Mount the player before starting the spring.
    await tester.pump(); // Start the spring ticker.
    await tester.pump(const Duration(milliseconds: 300));
    expect(playerSheet.progress.value, greaterThan(.98));

    await tester.pump(const Duration(milliseconds: 400));
    expect(playerSheet.progress.value, 1);
    expect(playerSheet.engaged.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    playerSheet.engaged.value = false;
    playerSheet.progress.value = 0;
  });
}
