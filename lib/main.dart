import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'services/logging/logging_setup.dart';
import 'services/persistence/document_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logging = await setUpLogging();
  // The app follows the device (docs/history/SCREEN_FIT_PLAN.md §5.3): portrait and
  // both landscapes; upside-down portrait only on tablets.
  final view = PlatformDispatcher.instance.implicitView;
  final tablet = view != null && view.physicalSize.shortestSide / view.devicePixelRatio >= 600;
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    if (tablet) DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Hive.initFlutter();
  final store = await HiveDocumentStore.open();
  runApp(
    ProviderScope(
      overrides: [
        documentStoreProvider.overrideWithValue(store),
        appLoggingProvider.overrideWithValue(logging),
      ],
      child: const OnslaughtApp(),
    ),
  );
}
