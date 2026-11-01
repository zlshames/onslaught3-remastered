import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/audio/audio_service.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

class _Sink implements AudioSink {
  final played = <(String, double, double)>[];
  @override
  Future<void> play(String bundlePath, {required double volume, required double pan}) async =>
      played.add((bundlePath, volume, pan));
}

class _Pack implements AssetPack {
  @override
  String get id => 'p';
  @override
  Future<void> load() async {}
  @override
  Set<String> get spriteIds => const {};
  @override
  Set<String> get soundIds => const {};
  @override
  SpriteAsset? sprite(String id) => null;
  @override
  List<String>? sound(String id) => ['audio/$id.mp3'];
  @override
  PackTheme? get theme => null;
  @override
  GroundSource? ground(String id) => null;
}

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  AudioService service(_Sink sink) =>
      AudioService(data: data, pack: _Pack(), sink: sink, random: math.Random(1));

  test('original pan rule: (1.7·x/720 − 0.85), clamped', () {
    // 2350-gaby's GameStatus.sound_pan_max (2221-nyehi: 1.6).
    final s = service(_Sink());
    expect(s.panFor(0), closeTo(-0.85, 1e-9));
    expect(s.panFor(360), closeTo(0, 1e-9));
    expect(s.panFor(720), closeTo(0.85, 1e-9));
  });

  test('plays a clip of the event at the data volume', () async {
    final sink = _Sink();
    final path = await service(sink).play('cannon', x: 720);
    expect(path, startsWith('audio/sfx.ons2-cannon'));
    expect(sink.played.single.$2, closeTo(0.8, 1e-9));
    expect(sink.played.single.$3, closeTo(0.85, 1e-9));
  });

  test('silent events, unknown events and mute play nothing', () async {
    final sink = _Sink();
    final s = service(sink);
    expect(await s.play('attacker-hit'), isNull);
    expect(await s.play('no-such-event'), isNull);
    s.muted = true;
    expect(await s.play('cannon'), isNull);
    expect(sink.played, isEmpty);
  });
}
