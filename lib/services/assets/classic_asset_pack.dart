import 'atlas_asset_pack.dart';

export 'atlas_asset_pack.dart';

/// The original game's art and sound, exported from the SWF by
/// `tool/export_assets.sh` (`tool/asset_map.json`). Classic games, the menus
/// and the editors draw from it; every other pack layers over it.
class ClassicAssetPack extends AtlasAssetPack {
  ClassicAssetPack({super.bundle, super.manifestPath = defaultManifestPath, super.preferredScale})
    : super(id: 'classic');

  static const String defaultManifestPath = 'assets/images/classic/manifest.json';
}
