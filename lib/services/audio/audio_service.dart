import 'dart:async';
import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../assets/asset_pack.dart';
import '../logging/logging.dart';

const Logger _log = Logger('audio');

/// Plays one clip. Abstracted so tests and headless runs need no audio plugin.
abstract interface class AudioSink {
  Future<void> play(String bundlePath, {required double volume, required double pan});
}

/// Plays through flame_audio (audioplayers) with one small pool of players
/// per clip, so a game that fires constantly reuses players instead of
/// creating one per sound (a new `AudioPlayer` per play exhausted the
/// Android Java heap within minutes). A sound is dropped when its clip
/// already has [voicesPerClip] playing or [maxVoices] are playing in all;
/// the original counts 16 channels (`SoundPlayer.chan_max`).
class FlameAudioSink implements AudioSink {
  FlameAudioSink() {
    // Clip paths in the asset packs are full bundle paths.
    FlameAudio.audioCache.prefix = '';
  }

  static const int voicesPerClip = 3;
  static const int maxVoices = 16;

  /// Assumed clip length when the player cannot report one.
  static const Duration _fallbackLength = Duration(seconds: 1);

  final Map<String, Future<AudioPool>> _pools = {};
  final Map<String, int> _voices = {};
  int _playing = 0;

  @override
  Future<void> play(String bundlePath, {required double volume, required double pan}) async {
    // audioplayers has no per-play pan in its pool; pan is kept in the API
    // for the original pan rule.
    if (_playing >= maxVoices || (_voices[bundlePath] ?? 0) >= voicesPerClip) return;
    _playing++;
    _voices[bundlePath] = (_voices[bundlePath] ?? 0) + 1;
    try {
      final pool = await _pools.putIfAbsent(bundlePath, () => _createPool(bundlePath));
      final length = await pool.getDuration() ?? _fallbackLength;
      await pool.start(volume: volume);
      Timer(length, () => _release(bundlePath));
    } catch (_) {
      _release(bundlePath);
      rethrow;
    }
  }

  Future<AudioPool> _createPool(String bundlePath) async {
    try {
      final pool = await FlameAudio.createPool(bundlePath, maxPlayers: voicesPerClip);
      _log.trace('sound loaded', fields: {'path': bundlePath});
      return pool;
    } on Object catch (e, st) {
      _log.warning(
        'sound cannot be loaded',
        error: e,
        stackTrace: st,
        fields: {'path': bundlePath},
      );
      rethrow;
    }
  }

  void _release(String bundlePath) {
    _playing--;
    _voices[bundlePath] = (_voices[bundlePath] ?? 1) - 1;
  }
}

/// Maps audio event ids (`fire.cannon`, `ui.build`) to clips through the
/// game data and the asset pack chain, picking a random variant and applying
/// the original volume and pan rule (`SoundPlayer.play`). Game events will be
/// routed here by the session facade.
class AudioService {
  AudioService({required this.data, required this.pack, required this.sink, math.Random? random})
    : _random = random ?? math.Random();

  final GameData data;
  final AssetPack pack;
  final AudioSink sink;
  final math.Random _random;

  bool muted = false;

  /// Volume 0–100; defaults to the data's volume.
  double? volumeOverride;

  /// Pan for a sound at world x: `(spread · x / width − spread / 2)`,
  /// clamped to −1…1 (`SoundPlayer`).
  double panFor(double x) {
    final spread = data.audio.panSpread;
    final p = spread * x / data.world.playWidth - spread / 2;
    return p.clamp(-1.0, 1.0);
  }

  /// Plays [eventId]; returns the bundle path played, or null if muted or
  /// nothing resolves.
  Future<String?> play(String eventId, {double? x}) async {
    if (muted) return null;
    final clips = data.audio.events[eventId];
    if (clips == null || clips.isEmpty) return null;
    final clip = clips[_random.nextInt(clips.length)];
    final paths = pack.sound(clip);
    if (paths == null || paths.isEmpty) return null;
    final path = paths[_random.nextInt(paths.length)];
    final volume = (volumeOverride ?? data.audio.volume) / 100;
    await sink.play(path, volume: volume, pan: x == null ? 0 : panFor(x));
    return path;
  }
}
