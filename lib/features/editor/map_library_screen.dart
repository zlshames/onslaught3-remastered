import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/custom_record_list.dart';
import '../../app/dialogs.dart';
import '../../app/map_tile_grid.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../services/logging/logging.dart';
import '../../services/persistence/custom_records.dart';
import '../../services/persistence/map_library.dart';
import 'editor_dialogs.dart';

const Logger _log = Logger('editor');

/// Map Tools (`/maps`; the original's `GameSelectMapping` library): the
/// player's maps as thumbnails. A map can be played, edited, shared or
/// deleted; New opens the editor; Import adds a map from a share code. A map
/// played as a custom game shows its best wave, and its records (every
/// version of its road) open from its menu.
class MapLibraryScreen extends ConsumerWidget {
  const MapLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(mapLibraryProvider);
    return MenuData(
      builder: (context, data, profile) => AsyncGate(
        value: library,
        errorFrame: (context, message) => MenuScaffold(
          title: data.tr(context, 'flow.modeMapping'),
          onBack: () => context.go('/mode'),
          child: message,
        ),
        builder: (context, l) => _Library(data: data, library: l, custom: profile.custom),
      ),
    );
  }
}

class _Library extends ConsumerWidget {
  const _Library({required this.data, required this.library, required this.custom});

  final GameData data;
  final MapLibrary library;
  final CustomRecords custom;

  /// The best custom record on [map]'s shape now, any mode or mod.
  CustomRecord? _best(MapDefinition map) {
    final version = mapVersionHash(map);
    CustomRecord? best;
    for (final r in custom.forMap(map.id)) {
      if (r.key.mapVersion != version) continue;
      if (best == null || improvesCustomBest(best.result, r.result)) best = r;
    }
    return best;
  }

  Future<void> _records(BuildContext context, MapDefinition map) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColours.backdrop,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      data.tr(context, 'ui.records.mapTitle', {'name': map.name}),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: data.tr(context, 'ui.common.close'),
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: CustomRecordList(
                data: data,
                custom: custom,
                mapId: map.id,
                currentVersions: {map.id: mapVersionHash(map)},
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final imported = await showImport(
      context,
      sharing: ref.read(mapSharingProvider),
      library: library,
      data: data,
    );
    if (imported == null || !context.mounted) return;
    _log.info(
      'map imported',
      fields: {
        'map': imported.map.id,
        'mapName': Pii(imported.map.name),
        'problems': imported.problems.map((p) => p.name).join(','),
        'replaces': imported.replaces != null,
      },
    );
    await ref.read(mapLibraryProvider.notifier).save(imported.map);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(data.tr(context, 'editor.imported', {'name': imported.map.name}))),
      );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, MapDefinition map) async {
    final action = await showChoiceSheet<String>(
      context,
      title: map.name,
      choices: [
        ('play', Icons.play_arrow, data.tr(context, 'ui.menu.play')),
        ('edit', Icons.edit, data.tr(context, 'ui.editor.edit')),
        ('share', Icons.share, data.tr(context, 'ui.editor.share')),
        if (custom.forMap(map.id).isNotEmpty)
          ('records', Icons.emoji_events_outlined, data.tr(context, 'ui.records.menu')),
        ('delete', Icons.delete_outline, data.tr(context, 'ui.editor.delete')),
      ],
    );
    if (!context.mounted) return;
    if (action != null) _log.debug('map action', fields: {'map': map.id, 'action': action});
    switch (action) {
      case 'play':
        final profile = await ref.read(profileProvider.future);
        if (!context.mounted) return;
        final choice = await pickGame(context, data, profile);
        if (choice != null && context.mounted) context.go(gameRoute(map.id, choice));
      case 'records':
        await _records(context, map);
      case 'edit':
        context.go(Uri(path: '/editor', queryParameters: {'map': map.id}).toString());
      case 'share':
        await showShareCode(
          context,
          data: data,
          name: map.name,
          code: ref.read(mapSharingProvider).encode(map),
        );
      case 'delete':
        final ok = await confirm(
          context,
          title: data.tr(context, 'ui.editor.deleteTitle', {'name': map.name}),
          body: data.tr(context, 'ui.editor.deleteBody'),
          action: data.tr(context, 'ui.editor.delete'),
        );
        if (ok && context.mounted) await ref.read(mapLibraryProvider.notifier).delete(map.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LayoutBuilder(builder: (context, box) => _build(context, ref, narrow: box.maxWidth < 600));

  Widget _build(BuildContext context, WidgetRef ref, {required bool narrow}) {
    final maps = [...library.maps]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return MenuScaffold(
      title: data.tr(context, 'flow.modeMapping'),
      onBack: () => context.go('/mode'),
      // On a narrow phone the actions are icon buttons, so the title keeps
      // its room.
      actions: narrow
          ? [
              IconButton(
                tooltip: data.tr(context, 'ui.editor.import'),
                color: Colors.white,
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.download),
              ),
              IconButton(
                tooltip: data.tr(context, 'ui.editor.newMap'),
                color: Colors.amber,
                onPressed: () => context.go('/editor'),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 4),
            ]
          : [
              TextButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.download),
                label: Text(data.tr(context, 'ui.editor.import')),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.icon(
                  onPressed: () => context.go('/editor'),
                  icon: const Icon(Icons.add),
                  label: Text(data.tr(context, 'ui.editor.newMap')),
                ),
              ),
            ],
      child: maps.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  data.tr(context, 'ui.editor.noMaps'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : MapTileGrid(
              children: [
                for (final m in maps)
                  MapTile(
                    map: m,
                    data: data,
                    name: m.name,
                    label: data.tr(context, 'ui.editor.tile', {'name': m.name}),
                    subtitle: switch (_best(m)) {
                      final b? => data.tr(context, 'ui.records.best', {'wave': b.wave}),
                      null => null,
                    },
                    onTap: () => _open(context, ref, m),
                  ),
              ],
            ),
    );
  }
}
