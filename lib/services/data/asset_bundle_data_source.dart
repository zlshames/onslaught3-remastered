import 'package:flutter/services.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// Reads data documents from the Flutter asset bundle under [root].
class AssetBundleDataSource implements DataSource {
  AssetBundleDataSource({AssetBundle? bundle, this.root = 'assets/data'})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;

  @override
  Future<String> read(String path) => _bundle.loadString('$root/$path');
}
