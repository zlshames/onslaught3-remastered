import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/dialogs.dart';
import '../../app/strings.dart';
import '../../services/persistence/mod_library.dart';
import 'mod_value_editors.dart';

/// Asks for a mod code (`ons3:mod:…`) or a mod saved by the original game
/// ("Load a Saved Mod" in `ModImportExport`), shows what it changes and
/// what was left out, and returns it to replace the current mod, or null.
Future<ModImport?> showModImport(
  BuildContext context, {
  required ModSharing sharing,
  required ModRules rules,
  required ModDelta current,
}) {
  final data = rules.base;
  return showDialog<ModImport>(
    context: context,
    builder: (context) => ImportCodeDialog<ModImport>(
      data: data,
      title: data.tr(context, 'ui.mods.importTitle'),
      label: data.tr(context, 'ui.mods.importField'),
      fieldKey: const Key('modImportCode'),
      width: 480,
      decode: (code) => sharing.decode(code, rules),
      errorText: (context, e) =>
          data.tr(context, 'ui.mods.importError', {'detail': data.tr(context, e.key, e.args)}),
      preview: (context, mod) => _ImportPreview(mod: mod, rules: rules, current: current),
      canAccept: (mod) => mod.usable,
      acceptLabel: (context, _) => data.tr(context, 'ui.mods.load'),
    ),
  );
}

/// An imported mod's name, change count and signature, how many current
/// changes it replaces, and what was left out of it.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.mod, required this.rules, required this.current});

  final ModImport mod;
  final ModRules rules;
  final ModDelta current;

  /// Problems listed before "and N more".
  static const int _shown = 4;

  @override
  Widget build(BuildContext context) {
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    final replacing = rules.changeCount(current);
    final data = rules.base;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            if (mod.delta.name case final name?)
              data.modName(context, name)
            else
              data.tr(context, 'ui.mods.unnamed'),
            data.tr(context, 'ui.mods.changedValues', {'count': rules.changeCount(mod.delta)}),
            if (!mod.delta.isEmpty)
              data.tr(context, 'ui.mods.signature', {'signature': modSignature(mod.delta)}),
          ].join(' · '),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (replacing > 0)
          Text(data.tr(context, 'ui.mods.replaces', {'count': replacing}), style: error),
        if (mod.problems.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            data.tr(context, mod.usable ? 'ui.mods.leftOut' : 'ui.mods.unusable'),
            style: mod.usable ? null : error,
          ),
          for (final p in mod.problems.take(_shown))
            Text(
              data.tr(context, 'ui.mods.problem', {
                'problem': modProblemText(context, p, data, withField: true),
              }),
              style: error,
            ),
          if (mod.problems.length > _shown)
            Text(
              data.tr(context, 'ui.mods.moreProblems', {'count': mod.problems.length - _shown}),
              style: error,
            ),
        ],
      ],
    );
  }
}

/// Asks for the mod's name; returns it trimmed, or null.
Future<String?> askModName(
  BuildContext context, {
  required String initial,
  required GameData data,
}) => askName(
  context,
  data: data,
  title: data.tr(context, 'ui.mods.nameTitle'),
  label: data.tr(context, 'ui.mods.nameField'),
  emptyError: data.tr(context, 'ui.mods.noName'),
  initial: initial,
  // The same limit as a map's name.
  maxLength: data.world.editor.maxNameLength,
  fieldKey: const Key('modNameField'),
);
