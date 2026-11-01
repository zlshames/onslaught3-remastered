import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';

/// Golden configuration (golden-tests skill). CI goldens render text as
/// blocks so they are identical on macOS and Linux; platform goldens (real
/// fonts) are only produced locally on macOS for human review and are not
/// committed.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final isCi = Platform.environment['CI'] == 'true';
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: !isCi && Platform.isMacOS),
    ),
    run: testMain,
  );
}
