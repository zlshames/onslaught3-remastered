import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/assets/atlas_asset_pack.dart';
import 'package:onslaught3_remastered/services/persistence/map_library.dart';
import 'package:onslaught3_remastered/services/persistence/mod_library.dart';
import 'package:onslaught3_remastered/services/share/share_codec.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/log_capture.dart';
import '../support/test_data.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.text);

  final String? text;

  @override
  Future<ByteData> load(String key) async {
    final t = text;
    if (t == null) throw StateError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(t)));
  }
}

/// The services' log lines: share codes and asset packs.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  const map = MapDefinition(
    id: 'custom-1',
    name: 'Jane Fortress',
    base: Vec2(560, 200),
    road: [Vec2(0, 100), Vec2(400, 100), Vec2(565, 227)],
    builtIn: false,
  );

  test('making a map or mod code is logged without the code or the name', () async {
    final log = LogCapture.install();
    final code = const MapSharing().encode(map);
    const ModSharing().encode(const ModDelta({}, name: 'Mine'));
    final records = await log.records();
    expect(records[0], endsWith('DEBUG [maps] map code made map=custom-1 length=${code.length}'));
    expect(records[1], contains('DEBUG [mods] mod code made files=0 length='));
    expect(records.join(), isNot(contains(code)));
    expect(records.join(), isNot(contains('Jane')));
  });

  test('a map code that cannot be read is logged at trace with its reason', () async {
    final log = LogCapture.install();
    expect(
      () => const MapSharing().decode('ons3:map:nope', const MapLibrary(), data.world),
      throwsA(isA<ShareCodecException>()),
    );
    final records = await log.records();
    expect(records.single, contains('TRACE [maps] map code not readable reason=ui.share.'));
  });

  test('an asset pack that loads says what it holds; one that fails is an error', () async {
    final log = LogCapture.install();
    final manifest = jsonEncode({
      'schemaVersion': 2,
      'pack': 'test',
      'atlases': <String, Object?>{},
      'sprites': <String, Object?>{},
      'sounds': <String, Object?>{},
    });
    await AtlasAssetPack(id: 'test', manifestPath: 'm.json', bundle: _Bundle(manifest)).load();
    await expectLater(
      AtlasAssetPack(id: 'broken', manifestPath: 'm.json', bundle: _Bundle(null)).load(),
      throwsStateError,
    );
    final records = await log.records();
    expect(records[0], contains('DEBUG [assets] asset pack loaded pack=test sprites=0 sounds=0'));
    expect(records[1], contains('ERROR [assets] asset pack cannot be loaded pack=broken'));
    expect(records[1], contains('no asset m.json'));
  });
}
