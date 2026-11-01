import 'package:onslaught3_remastered/services/audio/audio_service.dart';
import 'package:onslaught3_remastered/services/haptics/haptics.dart';

// These live here, not with the fakes in `test/support/`, because a web build
// cannot import from outside this folder.

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
