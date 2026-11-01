import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/assets/asset_pack.dart';
import 'package:onslaught3_remastered/services/assets/classic_asset_pack.dart';
import 'package:onslaught3_remastered/services/assets/procedural_ground_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the procedural pack draws only the ground, with the shader', () {
    const pack = ProceduralGroundPack();
    final ground = pack.ground(ProceduralGroundPack.groundId);
    expect(ground, isA<ShaderGround>());
    expect((ground! as ShaderGround).shader, ProceduralGroundPack.shader);
    expect((ground as ShaderGround).palette, hasLength(3));
    expect(pack.ground('ground.other'), isNull);
    expect(pack.sprite(ProceduralGroundPack.groundId), isNull);
    expect(pack.spriteIds, isEmpty);
  });

  test('the classic pack draws the ground as its image; the chain takes the first', () async {
    final classic = ClassicAssetPack();
    await classic.load();
    expect(classic.ground(ProceduralGroundPack.groundId), isA<ImageGround>());
    final plain = AssetPackChain([classic]);
    expect(plain.ground(ProceduralGroundPack.groundId), isA<ImageGround>());
    final sharp = AssetPackChain([const ProceduralGroundPack(), classic]);
    expect(sharp.ground(ProceduralGroundPack.groundId), isA<ShaderGround>());
    // Every other id still comes from the classic pack.
    expect(sharp.sprite(ProceduralGroundPack.groundId), isNotNull);
  });
}
