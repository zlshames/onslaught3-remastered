import 'package:flutter/widgets.dart';

/// Keys on HUD controls that something outside them must locate on screen
/// (the tutorial's "Show me" arrow). Owned by the game screen.
class HudKeys {
  final GlobalKey exit = GlobalKey(debugLabel: 'hud.exit');
  final GlobalKey cash = GlobalKey(debugLabel: 'hud.cash');
  final GlobalKey waveClock = GlobalKey(debugLabel: 'hud.waveClock');
  final GlobalKey pause = GlobalKey(debugLabel: 'hud.pause');
  final GlobalKey tray = GlobalKey(debugLabel: 'hud.tray');
  final GlobalKey sheet = GlobalKey(debugLabel: 'hud.sheet');
  final GlobalKey messages = GlobalKey(debugLabel: 'hud.messages');
}
