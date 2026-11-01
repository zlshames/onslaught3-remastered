import 'dart:math' as math;

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

/// "Challenge Games" (`GameSelectChallenge`): step through the presets or
/// set the seven pickers for a custom challenge; a custom set that matches a
/// preset is that preset. The box shows the challenge's best game and a tick
/// once passed (`challengeChanged`). Play goes on to the map.
class ChallengeScreen extends ConsumerStatefulWidget {
  const ChallengeScreen({super.key, this.initialKey});

  /// The challenge to show first ([challengeKey]); the first preset if null.
  final String? initialKey;

  @override
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

/// Picker ids in the original's order, with their label keys.
const List<(String, String)> _pickers = [
  ('difficulty', 'ui.challenge.difficulty'),
  ('objective', 'ui.challenge.objective'),
  ('cash', 'ui.challenge.cash'),
  ('timeLimit', 'ui.challenge.timeLimit'),
  ('turretLimit', 'ui.challenge.turretLimit'),
  ('waveSize', 'ui.challenge.waveSize'),
  ('waveSpeed', 'ui.challenge.waveSpeed'),
];

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
  Map<String, Object?>? _values;
  int _preset = 0;

  static String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// The picker values that make up challenge [c].
  static Map<String, Object?> _valuesOf(ChallengeDef c) {
    final o = c.objective;
    return {
      'difficulty': c.difficulty,
      'objective': o == null
          ? null
          : '${o.type == ChallengeObjective.waves ? 'w' : 'k'},${o.target}',
      'cash': c.cash,
      'timeLimit': c.timeLimitS,
      'turretLimit': c.turretLimit,
      'waveSize': c.waveSizes.join(','),
      'waveSpeed': [for (final s in c.waveSpeeds) _n(s)].join(','),
    };
  }

  /// `challengeEncode` of picker values.
  static String _keyOf(Map<String, Object?> v) {
    String opt(Object? x) => x == null ? 'undefined' : (x is num ? _n(x) : '$x');
    return [
      'challenge',
      v['difficulty'],
      opt(v['objective']),
      opt(v['cash']),
      opt(v['timeLimit']),
      opt(v['turretLimit']),
      opt(v['waveSize']),
      opt(v['waveSpeed']),
    ].join(';');
  }

  static bool _same(Object? a, Object? b) => a is num && b is num ? a == b : a == b;

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(featureFlagsProvider);
    final corrected = ref.watch(rulesProfileProvider).challengePickerData;
    return MenuData(
      builder: (context, data, profile) {
        final presets = [
          for (final p in data.challenges.presets)
            if (!p.debugOnly || flags.debugMenu) p,
        ];
        _values ??= () {
          final from = widget.initialKey == null
              ? null
              : challengeFromKey(widget.initialKey!, data.challenges);
          if (from != null) {
            final i = presets.indexOf(from);
            if (i >= 0) _preset = i;
            return _valuesOf(from);
          }
          return _valuesOf(presets[_preset]);
        }();
        final values = _values!;
        final key = _keyOf(values);
        final challenge = challengeFromKey(key, data.challenges);
        final isPreset = challenge != null && challenge.id != customChallengeId;
        bool available(String? mode) =>
            mode == null ||
            isModeAvailable(data.progression, profile.progress, mode, unlockAll: profile.unlockAll);
        final pickers = data.challenges.pickersFor(corrected: corrected);

        void setPreset(int i) => setState(() {
          _preset = (i + presets.length) % presets.length;
          _values = _valuesOf(presets[_preset]);
        });

        final pickerTiles = [
          for (final (id, label) in _pickers)
            _Picker(
              label: data.tr(context, label),
              options: [
                for (final o in pickers[id] ?? const <PickerOption>[])
                  if (available(o.requiresMode)) o,
              ],
              value: values[id],
              labelOf: (o) => data.pickerLabel(id, o.label, locale: uiLocale(context)),
              same: _same,
              onChanged: (v) => setState(() => _values = {...values, id: v}),
            ),
        ];
        final sideTiles = <Widget>[
          Row(
            children: [
              IconButton(
                tooltip: data.tr(context, 'ui.challenge.previous'),
                color: Colors.white,
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setPreset(isPreset ? _preset - 1 : _preset),
              ),
              Expanded(
                child: Text(
                  isPreset
                      ? data.challengeName(challenge.id, challenge.name, locale: uiLocale(context))
                      : data.tr(context, 'flow.customChallenge'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
              IconButton(
                tooltip: data.tr(context, 'ui.challenge.next'),
                color: Colors.white,
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setPreset(isPreset ? _preset + 1 : _preset),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _BestBox(
            data: data,
            best: profile.challengeBest[key],
            passed: profile.complete.contains(key),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(data.tr(context, 'ui.menu.play')),
            onPressed: challenge == null
                ? null
                : () => context.go(
                    Uri(
                      path: '/map',
                      queryParameters: {'mode': GameConfig.challengeMode, 'challenge': key},
                    ).toString(),
                  ),
          ),
        ];
        return MenuScaffold(
          title: data.tr(context, 'flow.modeChallenge'),
          onBack: () => context.go('/mode'),
          child: LayoutBuilder(
            // Narrow (portrait phones): the preset, best and Play above the
            // pickers in one list; otherwise the pickers beside a side panel.
            builder: (context, box) => box.maxWidth < 640
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [...sideTiles, const SizedBox(height: 12), ...pickerTiles],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
                          children: pickerTiles,
                        ),
                      ),
                      SizedBox(
                        width: 270,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                          children: sideTiles,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.same,
    required this.onChanged,
  });

  final String label;
  final List<PickerOption> options;
  final Object? value;

  /// An option's label in the interface language.
  final String Function(PickerOption) labelOf;
  final bool Function(Object?, Object?) same;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    var index = options.indexWhere((o) => same(o.value, value));
    final shown = [
      ...options,
      // A value no option offers (a picker option still locked).
      if (index < 0) PickerOption('$value', value),
    ];
    if (index < 0) index = shown.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // At most a third of a narrow screen for the label.
          SizedBox(
            width: math.min(120, MediaQuery.sizeOf(context).width * 0.35),
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              value: index,
              dropdownColor: AppColours.panel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              items: [
                for (var i = 0; i < shown.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      labelOf(shown[i]).replaceAll('\n', ' '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (i) => i == null ? null : onChanged(shown[i].value),
            ),
          ),
        ],
      ),
    );
  }
}

/// The best game of the challenge shown (`GameChallengeStats`), or
/// "unplayed" (`GameChallengeUnplayed`).
class _BestBox extends StatelessWidget {
  const _BestBox({required this.data, required this.best, required this.passed});

  final GameData data;
  final ChallengeBest? best;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = best;
    String two(int v) => v.toString().padLeft(2, '0');
    final body = b == null
        ? [
            Text(
              data.tr(context, 'ui.challenge.unplayed'),
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ]
        : () {
            final d = DateTime.fromMillisecondsSinceEpoch(b.dateMs);
            return [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.tr(context, 'ui.challenge.best'),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  if (passed) ...[
                    const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      data.tr(context, 'ui.challenge.passed'),
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                data.tr(context, 'ui.challenge.bestKills', {
                  'kills': b.kills,
                  'spent': formatCash(context, data, b.spent),
                }),
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                data.tr(context, 'ui.challenge.bestScore', {'score': b.score.toStringAsFixed(0)}),
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                '${two(d.day)}/${two(d.month)}/${d.year}, ${two(d.hour)}:${two(d.minute)}',
                style: const TextStyle(color: Colors.white54),
              ),
            ];
          }();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: passed ? Colors.greenAccent : Colors.white24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
    );
  }
}
