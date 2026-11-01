import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/diagnostics_settings.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/settings_form.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../services/persistence/settings.dart';

/// The settings page: the player settings ([SettingsForm]), saved as they
/// change, the log's level, export and clear ([DiagnosticsSettings]), and in
/// debug builds a switch that unlocks every mode (the
/// original's debug mode, `GameManager.modeIsAvailable`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final settings = ref.watch(settingsProvider).value ?? const Settings();
    return MenuScaffold(
      title: ref.tr(context, 'ui.settings.title'),
      onBack: () => context.go('/'),
      child: MenuData(
        builder: (context, data, profile) => Theme(
          data: appTheme(Brightness.dark),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              SettingsForm(
                settings: settings,
                data: data,
                showGround: ref.watch(uiSkinProvider).sharpGroundOffered,
                onChanged: (s) => ref.read(settingsProvider.notifier).save(s),
              ),
              const Divider(),
              DiagnosticsSettings(settings: settings, data: data),
              if (flags.debugMenu) ...[
                const Divider(),
                SwitchListTile(
                  title: const Text('Debug: unlock every mode'),
                  subtitle: const Text('Progress is kept; this only opens the locked modes.'),
                  value: profile.unlockAll,
                  onChanged: (v) =>
                      ref.read(profileProvider.notifier).change((p) => p.copyWith(unlockAll: v)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
