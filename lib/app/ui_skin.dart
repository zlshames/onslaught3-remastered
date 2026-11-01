import 'package:onslaught_core/onslaught_core.dart';

/// The presentation a game is drawn with (`docs/REMASTER_PLAN.md` §5.3):
/// Classic keeps the landscape screen exactly as v1 shipped it and adds only
/// what a new screen shape needs (portrait, live switching, safe areas);
/// Enhanced also gets the extras of `docs/history/SCREEN_FIT_PLAN.md` (side rails,
/// the far-side turret panel, ground beyond the play area, sharp ground,
/// the lifted ghost and the bigger turret hit zone). Chosen per game from
/// its [RulesProfile] (`RulesProfile.enhancedSkin`; an Enhanced profile,
/// `docs/ENHANCED_PLAN.md` E0, sets it and selects the skin with no further
/// change) or forced by `--dart-define=ENHANCED_SKIN=true`.
enum UiSkin {
  classic,
  enhanced;

  /// The skin of a game played with [profile] ([RulesProfile.enhancedSkin]).
  static UiSkin forProfile(RulesProfile profile) => profile.enhancedSkin ? enhanced : classic;

  /// Whether the HUD may move into side rails on wide landscape screens
  /// (otherwise landscape always uses the top bar and right tray).
  bool get offersRails => this == enhanced;

  /// Whether the selected-turret panel opens on the side away from the
  /// turret in landscape (Classic keeps the bottom sheet there).
  bool get farSidePanelInLandscape => this == enhanced;

  /// Whether the Ground setting (Classic / Sharp) is offered.
  bool get sharpGroundOffered => this == enhanced;

  /// How far above a touching finger a tray drag puts the ghost, in logical
  /// px (0 = under the finger, as v1).
  double get ghostLiftPt => this == enhanced ? 40 : 0;

  /// The smallest on-screen radius a tap picks a turret within, in logical
  /// px (0 = only the turret's own footprint in world px, as v1).
  double get turretHitPt => this == enhanced ? 22 : 0;
}
