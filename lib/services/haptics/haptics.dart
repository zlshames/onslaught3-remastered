import 'package:flutter/services.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// A kind of vibration, from the lightest to the strongest.
enum HapticCue { selection, light, medium, heavy }

/// Plays a [HapticCue] on the device (or records it in tests).
abstract interface class HapticSink {
  Future<void> play(HapticCue cue);
}

/// The platform's haptic feedback (a no-op where the device has none, such
/// as desktop and the web).
class PlatformHapticSink implements HapticSink {
  const PlatformHapticSink();

  @override
  Future<void> play(HapticCue cue) => switch (cue) {
    HapticCue.selection => HapticFeedback.selectionClick(),
    HapticCue.light => HapticFeedback.lightImpact(),
    HapticCue.medium => HapticFeedback.mediumImpact(),
    HapticCue.heavy => HapticFeedback.heavyImpact(),
  };
}

/// The vibration a game event gives (`docs/REMASTER_PLAN.md` §3.3: haptics
/// on place, sell and unlock), the remaster's touch feedback; the original
/// had none. Building or moving a turret is a firm tap, an upgrade a click,
/// a sale a light tap and a new weapon a strong one. Everything else,
/// including the endless stream of shots and kills, is silent to the hand.
HapticCue? hapticCueFor(GameEvent e) => switch (e) {
  TurretBuilt() || TurretMoved() => HapticCue.medium,
  TurretUpgraded() => HapticCue.selection,
  TurretSold() => HapticCue.light,
  WeaponUnlocked() => HapticCue.heavy,
  _ => null,
};
