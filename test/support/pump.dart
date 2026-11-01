import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:onslaught3_remastered/app/feature_flags.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'fakes.dart';

/// The provider overrides an app under test runs with: [data] as the game
/// data, and when given, [store] as the document store and [flags] as the
/// feature flags.
///
/// [fakes] puts an [EmptyAssetPack] and a [SilentAudioSink] in place of the
/// real art and sound; [noHaptics] adds [NoHaptics]. [extra] holds any other
/// overrides a test needs (fixed notifiers, a failing asset pack).
List<Override> appOverrides({
  required GameData data,
  DocumentStore? store,
  FeatureFlags? flags,
  bool fakes = true,
  bool noHaptics = false,
  List<Override> extra = const [],
}) => [
  gameDataProvider.overrideWith((ref) => data),
  if (fakes) assetPackProvider.overrideWith((ref) => EmptyAssetPack()),
  if (fakes) audioSinkProvider.overrideWithValue(SilentAudioSink()),
  if (noHaptics) hapticSinkProvider.overrideWithValue(NoHaptics()),
  if (store != null) documentStoreProvider.overrideWithValue(store),
  if (flags != null) featureFlagsProvider.overrideWithValue(flags),
  ...extra,
];

/// The sand background the HUD goldens are drawn on.
const goldenBackground = Color(0xFFE8C9A0);

/// The app the HUD goldens draw [child] in: a [brightness] theme on the sand
/// background.
///
/// With [textScale], the screen's media query is replaced by a bare one at
/// that text scale (the large-text scenarios); without it the app's own media
/// query stays. At scale 1 the two draw the same pixels.
Widget goldenHost(Widget child, {Brightness brightness = Brightness.light, double? textScale}) {
  final scaffold = Scaffold(backgroundColor: goldenBackground, body: child);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: brightness),
    home: textScale == null
        ? scaffold
        : MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: scaffold,
          ),
  );
}
