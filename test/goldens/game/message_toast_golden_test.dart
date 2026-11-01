import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:onslaught3_remastered/features/game/game_view_model.dart';
import 'package:onslaught3_remastered/features/game/hud/message_toasts.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fake_game_view_model.dart';
import '../../support/pump.dart';
import '../../support/test_data.dart';

/// Goldens for a message toast, info and alert.
void main() {
  final GameData data = loadTestGameData();

  goldenTest(
    'message toast',
    fileName: 'message_toast',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final alert in [false, true])
          GoldenTestScenario(
            name: alert ? 'alert' : 'info',
            constraints: BoxConstraints.tight(const Size(460, 70)),
            child: goldenHost(
              MessageToasts(
                viewModel: FakeGameViewModel(data: data)
                  ..messagesValue = [
                    GameMessage(
                      seq: 0,
                      text: alert
                          ? 'New weapon available: Range Enhancer'
                          : 'Welcome to Onslaught 3 Remastered!',
                      alert: alert,
                    ),
                  ],
              ),
            ),
          ),
      ],
    ),
  );
}
