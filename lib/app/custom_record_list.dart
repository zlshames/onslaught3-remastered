import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/persistence/custom_records.dart';
import 'strings.dart';

/// Custom games' records as list sections: per player map, one section per
/// version of its shape, newest first ([currentVersion] marks the map's
/// shape now); per built-in map played with a mod, one section. Within a
/// section the best waves come first. Shared by the map library (one map)
/// and the records page (all of them).
class CustomRecordList extends StatelessWidget {
  const CustomRecordList({
    super.key,
    required this.data,
    required this.custom,
    this.mapId,
    this.currentVersions = const {},
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final GameData data;
  final CustomRecords custom;

  /// Only this map's records; every record when null.
  final String? mapId;

  /// Player map id → [mapVersionHash] of its shape now (maps still in the
  /// library), to mark the current version.
  final Map<String, String> currentVersions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final records = [
      for (final r in custom.records.values)
        if (mapId == null || r.key.mapId == mapId) r,
    ];
    final sections = <(String, List<CustomRecord>)>[];
    final playerMaps = [
      for (final r in records)
        if (r.key.mapVersion != null) r,
    ];
    final modded = [
      for (final r in records)
        if (r.key.mapVersion == null) r,
    ];
    // Player maps by name, then version (newest first).
    final byMap = <String, List<CustomRecord>>{};
    for (final r in playerMaps) {
      byMap.putIfAbsent(r.key.mapId, () => []).add(r);
    }
    final mapIds = byMap.keys.toList()
      ..sort((a, b) => _latestName(byMap[a]!).compareTo(_latestName(byMap[b]!)));
    for (final id in mapIds) {
      final versions = <int, List<CustomRecord>>{};
      for (final r in byMap[id]!) {
        versions.putIfAbsent(custom.versionOf(id, r.key.mapVersion!) ?? 0, () => []).add(r);
      }
      final current = currentVersions[id];
      for (final n in versions.keys.toList()..sort((a, b) => b.compareTo(a))) {
        final list = versions[n]!;
        final isCurrent = current != null && list.first.key.mapVersion == current;
        final label = data.tr(
          context,
          isCurrent ? 'ui.records.versionCurrent' : 'ui.records.version',
          {'n': n},
        );
        sections.add((mapId == null ? '${_latestName(list)} · $label' : label, list));
      }
    }
    if (mapId == null && playerMaps.isNotEmpty && modded.isNotEmpty) {
      sections.insert(0, (data.tr(context, 'ui.records.playerMaps'), const []));
    }
    if (modded.isNotEmpty) {
      if (mapId == null) sections.add((data.tr(context, 'ui.records.modded'), const []));
      final byBuiltIn = <String, List<CustomRecord>>{};
      for (final r in modded) {
        byBuiltIn.putIfAbsent(r.key.mapId, () => []).add(r);
      }
      for (final e in byBuiltIn.entries) {
        final map = data.maps[e.key];
        sections.add((
          map == null ? e.value.first.mapName : data.mapName(map, locale: uiLocale(context)),
          e.value,
        ));
      }
    }
    if (records.isEmpty) {
      return Padding(
        padding: padding,
        child: Center(
          child: Text(
            data.tr(context, 'ui.records.empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return ListView(
      padding: padding,
      children: [
        for (final (title, list) in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          for (final r in [...list]..sort((a, b) => _best(b).compareTo(_best(a))))
            _RecordRow(data: data, record: r),
        ],
      ],
    );
  }

  /// The map's name as last recorded.
  static String _latestName(List<CustomRecord> list) =>
      (list.reduce((a, b) => a.dateMs >= b.dateMs ? a : b)).mapName;

  static int _best(CustomRecord r) => r.wave;
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.data, required this.record});

  final GameData data;
  final CustomRecord record;

  /// `Hard`, `Sandbox`, `Challenge, Hard`… plus the mod when one was on.
  String _game(BuildContext context) {
    final k = record.key;
    final difficulty = data.tr(context, 'difficulty.${k.difficulty}');
    final game = switch (k.mode) {
      'sandbox' => data.tr(context, 'ui.mode.sandbox'),
      'sandbox2' => data.tr(context, 'ui.mode.superSandbox'),
      'challenge' => data.tr(context, 'ui.records.challenge', {'difficulty': difficulty}),
      _ => difficulty,
    };
    final stored = record.modName;
    final mod = stored == null ? null : data.modName(context, stored);
    return mod == null || k.mod == null
        ? game
        : '$game · ${data.tr(context, 'ui.records.mod', {'name': mod})}';
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final game = _game(context);
    final score = record.score.toStringAsFixed(0);
    final date = _date(record.dateMs);
    return MergeSemantics(
      child: Semantics(
        label: data.tr(context, 'ui.records.row', {
          'game': game,
          'wave': record.wave,
          'kills': record.kills,
          'score': score,
          'date': date,
        }),
        child: ExcludeSemantics(
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(game, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              data.tr(context, 'ui.records.detail', {
                'kills': record.kills,
                'score': score,
                'date': date,
              }),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Text(
              data.tr(context, 'ui.records.wave', {'wave': record.wave}),
              style: const TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
