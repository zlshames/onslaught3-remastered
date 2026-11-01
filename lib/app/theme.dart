import 'package:flutter/material.dart';

/// The app's colour seed: the original road's sandy core (`#B2885B`).
const Color appSeedColour = Color(0xFFB2885B);

/// The app theme in [brightness] (menus on the dark backdrop use the dark
/// one whatever the system setting, so their text keeps its contrast).
ThemeData appTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: appSeedColour, brightness: brightness),
);

/// The colours the menus, the editors and the mod editor share (the HUD
/// keeps its own, [HudColours]). Skin-independent: both skins draw the
/// menus alike.
abstract final class AppColours {
  /// The dark backdrop behind every menu page and the mod editor.
  static const Color backdrop = Color(0xFF1B1F22);

  /// [backdrop] over the map editor's canvas (its tool bars), mostly opaque.
  static const Color backdropOverlay = Color(0xE61B1F22);

  /// [backdrop] behind the map editor's bottom bar, nearly opaque.
  static const Color backdropBar = Color(0xF21B1F22);

  /// A card, tile or dropdown on the [backdrop]; a locked or idle button.
  static const Color panel = Color(0xFF2A2E31);

  /// A card or tool that is available or armed (a green [panel]).
  static const Color panelActive = Color(0xFF3A4A2A);

  /// The original ground's green, under map thumbnails and in the editor.
  static const Color ground = Color(0xFF5B7F3A);
}

/// The in-game HUD's own colours: its dark panels over the play area and
/// the colour badges. Both skins draw them alike today; a skin that changes
/// one moves it onto `UiSkin`.
abstract final class HudColours {
  /// A panel over the play area (the turret sheet, the message toasts).
  static const Color panel = Color(0xE6202428);

  /// The game-over panel, a little more opaque than [panel].
  static const Color gameOverPanel = Color(0xF0202428);

  /// The tutorial window, nearly opaque.
  static const Color tutorialPanel = Color(0xF2202428);

  /// The tutorial's pointing arrow.
  static const Color tutorialArrow = Color(0xFFFFD54F);

  /// A turret sheet toggle that is on (the targeting mode in use).
  static const Color toggleOn = Color(0xFF2E7D32);

  /// A colour badge's shape.
  static const Color badgeFill = Color(0xFFFFFFFF);

  /// A colour badge's outline and letter.
  static const Color badgeInk = Color(0xFF000000);
}
