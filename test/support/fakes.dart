import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/audio/audio_service.dart';
import 'package:onslaught3_remastered/services/haptics/haptics.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// An asset pack with no sprites, sounds, theme or ground: the game draws
/// placeholder shapes and plays nothing.
class EmptyAssetPack implements AssetPack {
  @override
  String get id => 'empty';
  @override
  Future<void> load() async {}
  @override
  Set<String> get spriteIds => const {};
  @override
  Set<String> get soundIds => const {};
  @override
  SpriteAsset? sprite(String id) => null;
  @override
  List<String>? sound(String id) => null;
  @override
  PackTheme? get theme => null;
  @override
  GroundSource? ground(String id) => null;
}

/// An audio sink that plays nothing.
class SilentAudioSink implements AudioSink {
  @override
  Future<void> play(String bundlePath, {required double volume, required double pan}) async {}
}

/// A haptic sink that never vibrates.
class NoHaptics implements HapticSink {
  @override
  Future<void> play(HapticCue cue) async {}
}

/// The world of a live [GameSession], for Flame layers under test.
class SessionWorldView implements WorldView {
  SessionWorldView(this.s);
  final GameSession s;
  @override
  List<Creep> get creeps => s.creeps;
  @override
  List<Turret> get turrets => s.turrets;
  @override
  List<Projectile> get projectiles => s.projectiles;
  @override
  List<Blast> get blasts => s.blasts;
  @override
  List<ShockwaveWalker> get walkers => s.walkers;
  @override
  double get nowMs => s.clock.nowMs;
}
