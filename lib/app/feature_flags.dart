import 'package:flutter/foundation.dart';

/// Gates unfinished features so trunk stays shippable. Compile-time defaults
/// come from `--dart-define`s.
@immutable
class FeatureFlags {
  const FeatureFlags({
    this.debugOverlay = false,
    this.debugMenu = false,
    this.mapEditor = true,
    this.mods = true,
    this.enhancedSkin = false,
  });

  /// Defaults from `--dart-define=DEBUG_OVERLAY=true` etc. The debug menu is
  /// on in debug builds unless `DEBUG_MENU=false`.
  factory FeatureFlags.fromEnvironment() =>
      const FeatureFlags(debugMenu: bool.fromEnvironment('DEBUG_MENU', defaultValue: kDebugMode));

  /// Camera readout and zoom buttons over the game (QA on devices where
  /// pinch cannot be scripted, e.g. adb).
  final bool debugOverlay;

  /// The settings screen's debug section (unlock every mode).
  final bool debugMenu;

  /// Map Tools: the map library and editor. On by default;
  /// `--dart-define=MAP_EDITOR=false` shows its menu button disabled, so a
  /// build can ship without player maps while trunk stays shippable.
  final bool mapEditor;

  /// The mod editor. On by default; `--dart-define=MODS=false` shows its
  /// menu button disabled, so a build can ship without mods.
  final bool mods;

  /// Draws every game and menu with the Enhanced skin (`UiSkin.enhanced`)
  /// before Enhanced mode exists, so QA and goldens can exercise it
  /// (`--dart-define=ENHANCED_SKIN=true`). Off by default.
  final bool enhancedSkin;

  FeatureFlags copyWith({
    bool? debugOverlay,
    bool? debugMenu,
    bool? mapEditor,
    bool? mods,
    bool? enhancedSkin,
  }) => FeatureFlags(
    debugOverlay: debugOverlay ?? this.debugOverlay,
    debugMenu: debugMenu ?? this.debugMenu,
    mapEditor: mapEditor ?? this.mapEditor,
    mods: mods ?? this.mods,
    enhancedSkin: enhancedSkin ?? this.enhancedSkin,
  );
}
