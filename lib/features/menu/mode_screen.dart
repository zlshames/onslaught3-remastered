import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/format.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../services/persistence/profile.dart';

/// One button of the mode page (`GameSelectMode`).
class _ModeTile {
  const _ModeTile({
    required this.labelKey,
    required this.mode,
    required this.route,
    this.tick,
    this.lockedKey,
    this.flagOff = false,
  });

  /// `strings` key of the label.
  final String labelKey;

  /// The `progression.json` mode whose availability gates the button.
  final String mode;

  /// Where it goes (sandbox opens its options first).
  final String route;

  /// The id in [Profile.complete] that ticks it off, if any.
  final String? tick;

  /// `strings` key of the "how to unlock" text (the original's tooltip).
  final String? lockedKey;

  /// Switched off by its feature flag (`FeatureFlags`): shown disabled.
  final bool flagOff;
}

/// The mode page (`GameSelectMode`): Easy / Medium / Hard / Extreme /
/// Sandbox / Quick Tutorial / Challenge Games / Map Tools / Mods. Locked
/// modes show how to unlock them (the original's hover tooltips); finished
/// ones are ticked. Sandbox offers the super sandbox once it is unlocked.
class ModeScreen extends ConsumerWidget {
  const ModeScreen({super.key});

  static String _map(String mode, String difficulty) => '/map?mode=$mode&difficulty=$difficulty';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    return MenuScaffold(
      title: ref.tr(context, 'ui.mode.title'),
      onBack: () => context.go('/'),
      child: MenuData(
        builder: (context, data, profile) {
          final tiles = [
            for (final d in ['easy', 'medium', 'hard'])
              _ModeTile(
                labelKey: 'flow.mode${d[0].toUpperCase()}${d.substring(1)}',
                mode: milestoneMode,
                route: _map(milestoneMode, d),
                tick: d,
              ),
            _ModeTile(
              labelKey: 'flow.modeExtreme',
              mode: 'extreme',
              route: _map(milestoneMode, 'extreme'),
              tick: 'extreme',
              lockedKey: 'flow.lockedExtreme',
            ),
            const _ModeTile(
              labelKey: 'flow.modeSandbox',
              mode: 'sandbox',
              route: 'sandbox',
              lockedKey: 'flow.lockedSandbox',
            ),
            const _ModeTile(
              labelKey: 'flow.modeTutorial',
              mode: GameConfig.tutorialMode,
              route: '/tutorial',
              tick: GameConfig.tutorialMode,
            ),
            const _ModeTile(
              labelKey: 'flow.modeChallenge',
              mode: GameConfig.challengeMode,
              route: '/challenge',
              lockedKey: 'flow.lockedChallenge',
            ),
            _ModeTile(
              labelKey: 'flow.modeMapping',
              mode: 'mapping',
              route: '/maps',
              flagOff: !flags.mapEditor,
            ),
            _ModeTile(
              labelKey: 'flow.modeModding',
              mode: 'modding',
              route: '/mods',
              lockedKey: 'flow.lockedModding',
              flagOff: !flags.mods,
            ),
          ];
          bool available(String mode) => isModeAvailable(
            data.progression,
            profile.progress,
            mode,
            unlockAll: profile.unlockAll,
          );
          return LayoutBuilder(
            builder: (context, box) => GridView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              // Landscape: three across. Narrower: two, or one on a
              // portrait phone, each a fixed height that fits the hint at
              // large text.
              gridDelegate: box.maxWidth > 560
                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 3.2,
                    )
                  : SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: box.maxWidth < 420 ? 1 : 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: MediaQuery.textScalerOf(context).scale(76),
                    ),
              children: [
                for (final t in tiles)
                  _ModeButton(
                    label: data.tr(context, t.labelKey),
                    locked: !available(t.mode),
                    flagOff: t.flagOff,
                    ticked: t.tick != null && profile.complete.contains(t.tick),
                    hint: !available(t.mode)
                        ? (t.lockedKey == null ? null : data.tr(context, t.lockedKey!))
                        : (t.mode == 'sandbox' && !available('sandbox2')
                              ? data.tr(context, 'flow.lockedSandbox2')
                              : null),
                    comingLater: data.tr(context, 'ui.mode.comingLater'),
                    lockedLabel: data.tr(context, 'ui.mode.locked'),
                    completeLabel: data.tr(context, 'ui.mode.complete'),
                    onPressed: () => t.route == 'sandbox'
                        ? _sandbox(context, data, available('sandbox2'))
                        : context.go(t.route),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Sandbox: with the super sandbox unlocked the player picks one (the
  /// original always plays the super sandbox once it is unlocked).
  Future<void> _sandbox(BuildContext context, GameData data, bool super_) async {
    if (!super_) return context.go(_map('sandbox', 'easy'));
    String cash(BuildContext context, String mode) =>
        formatCash(context, data, data.difficulty.modeCash[mode] ?? 0);

    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: Text(data.tr(context, 'ui.mode.superSandbox')),
              subtitle: Text(
                data.tr(context, 'ui.mode.superSandboxInfo', {'cash': cash(context, 'sandbox2')}),
              ),
              onTap: () => Navigator.of(context).pop('sandbox2'),
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: Text(data.tr(context, 'ui.mode.sandbox')),
              subtitle: Text(
                data.tr(context, 'ui.mode.sandboxInfo', {'cash': cash(context, 'sandbox')}),
              ),
              onTap: () => Navigator.of(context).pop('sandbox'),
            ),
          ],
        ),
      ),
    );
    if (mode != null && context.mounted) context.go(_map(mode, 'easy'));
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.locked,
    required this.flagOff,
    required this.ticked,
    required this.hint,
    required this.comingLater,
    required this.lockedLabel,
    required this.completeLabel,
    required this.onPressed,
  });

  final String label;
  final bool locked;
  final bool flagOff;
  final bool ticked;
  final String? hint;

  /// The text of a mode its feature flag switched off.
  final String comingLater;

  /// Spoken after the label of a locked / finished mode.
  final String lockedLabel;
  final String completeLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = !locked && !flagOff;
    final sub = flagOff ? comingLater : hint?.replaceAll('\n', ' ');
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: [label, if (locked) lockedLabel, if (ticked) completeLabel, ?sub].join(', '),
      child: ExcludeSemantics(
        child: Material(
          color: enabled ? AppColours.panelActive : AppColours.panel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled
                ? onPressed
                : () => ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(sub ?? label))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    locked
                        ? Icons.lock
                        : (flagOff
                              ? Icons.schedule
                              : (ticked ? Icons.check_circle : Icons.play_circle_outline)),
                    color: locked ? Colors.white38 : (ticked ? Colors.greenAccent : Colors.white70),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: enabled ? Colors.white : Colors.white54,
                          ),
                        ),
                        if (sub != null)
                          Text(
                            sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
