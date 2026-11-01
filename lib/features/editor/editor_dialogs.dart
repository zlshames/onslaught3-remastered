import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/dialogs.dart';
import '../../app/map_thumbnail.dart';
import '../../app/strings.dart';
import '../../services/persistence/map_library.dart';
import '../../services/persistence/profile.dart';

/// The player-facing text for a [MapProblem] (`mapSave` warnings and the
/// remaster's checks).
String problemText(BuildContext context, MapProblem p, GameData data) => switch (p) {
  MapProblem.noStart => data.tr(context, 'editor.noStart'),
  MapProblem.noBase => data.tr(context, 'editor.noBase'),
  MapProblem.tooShort => data.tr(context, 'editor.tooShort', {
    'length': data.world.editor.minRoadLength.toStringAsFixed(0),
  }),
  MapProblem.outside => data.tr(context, 'editor.outside'),
};

/// Asks for the name to save a map under (`MappingSave`: any name; an
/// existing name is overwritten). Returns the trimmed name, or null.
Future<String?> askMapName(
  BuildContext context, {
  required String initial,
  required MapLibrary library,
  required GameData data,
  String? currentId,
}) => askName(
  context,
  data: data,
  title: data.tr(context, 'ui.editor.saveTitle'),
  label: data.tr(context, 'ui.editor.nameField'),
  emptyError: data.tr(context, 'editor.noName'),
  initial: initial,
  maxLength: data.world.editor.maxNameLength,
  warningBuilder: (context, name) {
    final other = library.byName(name);
    if (other == null || other.id == currentId) return null;
    return (
      warning: data.tr(context, 'ui.editor.replaces', {'name': name}),
      action: data.tr(context, 'ui.editor.replace'),
    );
  },
);

/// Asks for a share code and returns the map it holds (with its library
/// id), or null if cancelled. Shows why a code cannot be read.
Future<ImportedMap?> showImport(
  BuildContext context, {
  required MapSharing sharing,
  required MapLibrary library,
  required GameData data,
}) => showDialog<ImportedMap>(
  context: context,
  builder: (context) => ImportCodeDialog<ImportedMap>(
    data: data,
    title: data.tr(context, 'ui.editor.importTitle'),
    label: data.tr(context, 'ui.editor.importField'),
    fieldKey: const Key('importCode'),
    decode: (code) => sharing.decode(code, library, data.world),
    errorText: (context, e) =>
        data.tr(context, 'ui.editor.importError', {'detail': data.tr(context, e.key, e.args)}),
    preview: (context, map) => _ImportPreview(map: map, data: data),
    canAccept: (map) => map.problems.isEmpty,
    acceptLabel: (context, map) =>
        data.tr(context, map?.replaces == null ? 'ui.editor.add' : 'ui.editor.replace'),
  ),
);

/// An imported map's thumbnail, name, the map it replaces and its problems.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.map, required this.data});

  final ImportedMap map;
  final GameData data;

  @override
  Widget build(BuildContext context) {
    final world = data.world;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: AspectRatio(
            aspectRatio: world.playWidth / world.playHeight,
            child: CustomPaint(
              painter: MapThumbnailPainter(map: map.map, data: data),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(map.map.name, style: Theme.of(context).textTheme.titleMedium),
              if (map.replaces case final replaces?)
                Text(data.tr(context, 'ui.editor.replaces', {'name': replaces.name}), style: error),
              for (final p in map.problems) Text(problemText(context, p, data), style: error),
            ],
          ),
        ),
      ],
    );
  }
}

/// How to play a map: a difficulty in the normal mode, or a sandbox.
typedef GameChoice = ({String mode, String difficulty});

/// Asks which game to play a player map in: the difficulties and sandboxes
/// the player has unlocked (the original played custom maps at the last
/// chosen difficulty).
Future<GameChoice?> pickGame(BuildContext context, GameData data, Profile profile) {
  bool available(String mode) =>
      isModeAvailable(data.progression, profile.progress, mode, unlockAll: profile.unlockAll);
  final choices = <(String, GameChoice)>[
    for (final d in ['easy', 'medium', 'hard'])
      (data.tr(context, 'difficulty.$d'), (mode: milestoneMode, difficulty: d)),
    if (available('extreme'))
      (data.tr(context, 'difficulty.extreme'), (mode: milestoneMode, difficulty: 'extreme')),
    if (available('sandbox'))
      (data.tr(context, 'ui.mode.sandbox'), (mode: 'sandbox', difficulty: 'easy')),
    if (available('sandbox2'))
      (data.tr(context, 'ui.mode.superSandbox'), (mode: 'sandbox2', difficulty: 'easy')),
  ];
  return showChoiceSheet<GameChoice>(
    context,
    title: data.tr(context, 'ui.editor.playTitle'),
    choices: [for (final (label, choice) in choices) (choice, Icons.play_arrow, label)],
  );
}

/// The route that plays [mapId] as [choice].
String gameRoute(String mapId, GameChoice choice) => Uri(
  path: '/game/$mapId',
  queryParameters: {'mode': choice.mode, 'difficulty': choice.difficulty},
).toString();
