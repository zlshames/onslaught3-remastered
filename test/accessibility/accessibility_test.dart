import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/pump.dart';
import '../support/test_data.dart';

/// Phase 8 accessibility checks (`docs/REMASTER_PLAN.md` §8.1 item 13), on
/// every screen of the app at the Pixel 10's size in both orientations and
/// the smallest portrait phone (iPhone SE): every control
/// is labelled and at least 48 dp (Android) / 44 pt (iOS) to tap, text
/// contrasts with its background, and nothing overflows with the system
/// text size at 100 % or 130 %.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Every screen, with everything unlocked so all controls show.
  const screens = {
    'home': '/',
    'mode': '/mode',
    'map': '/map?mode=normal&difficulty=easy',
    'challenge': '/challenge',
    'settings': '/settings',
    'mods': '/mods',
    'map library': '/maps',
    'map editor': '/editor',
    'game': '/game/map1',
    'tutorial': '/tutorial',
    'records': '/records',
  };

  /// Screen sizes: the Pixel 10 AVD in landscape (the original matrix) and
  /// portrait, and the iPhone SE in portrait.
  const sizes = {
    '': Size(923, 411),
    ' portrait': Size(411, 923),
    ' small portrait': Size(375, 667),
  };

  Future<void> open(WidgetTester tester, String location, double textScale, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = MemoryDocumentStore();
    await store.write(Profile.key, const Profile(unlockAll: true).toJson());
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(data: data, store: store, noHaptics: true),
        child: OnslaughtApp(initialLocation: location),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final size in sizes.entries) {
    for (final textScale in [1.0, 1.3]) {
      for (final s in screens.entries) {
        testWidgets('${s.key}${size.key} at ${(textScale * 100).round()} % text', (tester) async {
          final handle = tester.ensureSemantics();
          await open(tester, s.value, textScale, size.value);
          expect(tester.takeException(), isNull, reason: 'no overflow or build error');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
          // Leave the screen so its game (if any) is disposed inside the test.
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
