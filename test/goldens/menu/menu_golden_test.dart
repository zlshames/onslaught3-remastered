import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/features/menu/challenge_screen.dart';
import 'package:onslaught3_remastered/features/menu/map_screen.dart';
import 'package:onslaught3_remastered/features/menu/mode_screen.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/pump.dart';
import '../../support/test_data.dart';
import '../devices.dart';

/// Goldens for the Phase 5 menus at phone size: the mode page for a new and
/// a seasoned player, the maps, and the challenge page with a best game.
void main() {
  final GameData data = loadTestGameData();

  Widget screen(Widget child, Profile profile) => ProviderScope(
    overrides: appOverrides(
      data: data,
      flags: const FeatureFlags(),
      fakes: false,
      extra: [profileProvider.overrideWith(() => _FixedProfile(profile))],
    ),
    child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
  );

  final warmup = data.challenges.presets.firstWhere((p) => p.id == 'warmup');
  final seasoned = Profile(
    available: const {'extreme', 'sandbox', 'challenge'},
    complete: {'easy', 'medium', 'tutorial', challengeKey(warmup)},
    challengeBest: {
      challengeKey(warmup): ChallengeBest(
        kills: 20,
        spent: 30,
        score: 600,
        dateMs: DateTime(2026, 10, 18, 9, 5).millisecondsSinceEpoch,
      ),
    },
  );

  goldenTest(
    'mode page',
    fileName: 'mode_screen',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'new player',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const ModeScreen(), const Profile()),
        ),
        GoldenTestScenario(
          name: 'seasoned player',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const ModeScreen(), seasoned),
        ),
      ],
    ),
  );

  goldenTest(
    'map page',
    fileName: 'map_screen',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'medium',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const MapScreen(difficulty: 'medium'), const Profile()),
        ),
      ],
    ),
  );

  goldenTest(
    'challenge page',
    fileName: 'challenge_screen',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'warmup, passed',
          constraints: BoxConstraints.tight(GoldenDevices.phone),
          child: screen(const ChallengeScreen(), seasoned),
        ),
      ],
    ),
  );

  goldenTest(
    'menus in portrait',
    fileName: 'menus_portrait',
    pumpBeforeTest: (tester) async => tester.pump(const Duration(milliseconds: 50)),
    builder: () => GoldenTestGroup(
      columns: 4,
      children: [
        for (final d in GoldenDevices.portrait.entries.where((d) => d.value.width < 600)) ...[
          GoldenTestScenario(
            name: '${d.key} modes',
            constraints: BoxConstraints.tight(d.value),
            child: screen(const ModeScreen(), seasoned),
          ),
          GoldenTestScenario(
            name: '${d.key} maps',
            constraints: BoxConstraints.tight(d.value),
            child: screen(const MapScreen(difficulty: 'medium'), const Profile()),
          ),
        ],
        GoldenTestScenario(
          name: 'phonePortrait challenge',
          constraints: BoxConstraints.tight(GoldenDevices.phonePortrait),
          child: screen(const ChallengeScreen(), seasoned),
        ),
        GoldenTestScenario(
          name: 'tabletPortrait challenge',
          constraints: BoxConstraints.tight(GoldenDevices.tabletPortrait),
          child: screen(const ChallengeScreen(), seasoned),
        ),
      ],
    ),
  );
}

class _FixedProfile extends ProfileNotifier {
  _FixedProfile(this.profile);

  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}
