import 'atlas_asset_pack.dart';

export 'atlas_asset_pack.dart';

/// Art that Enhanced games draw differently (docs/ENHANCED_PLAN.md), built by
/// `tool/export_assets.sh` from `tool/asset_map_enhanced.json`: vector
/// redraws of the nine creeps (`tool/art/creeps/`). It holds nothing else, so
/// it is always layered over [ClassicAssetPack] (`enhancedAssetPackProvider`).
class EnhancedAssetPack extends AtlasAssetPack {
  EnhancedAssetPack({super.bundle, super.manifestPath = defaultManifestPath, super.preferredScale})
    : super(id: 'enhanced');

  static const String defaultManifestPath = 'assets/images/enhanced/manifest.json';
}
