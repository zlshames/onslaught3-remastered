import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/persistence/settings.dart';
import 'strings.dart';

/// The player settings the game uses (the original's settings window, PC
/// and online fields dropped): sound on and volume, wave spacing, send the
/// next wave as soon as the field is clear, remember the wave settings, the
/// base game speed and rocket smoke (`PrefSmoke`, `PrefSmokeMax`), plus the
/// remaster's vibration, tower placement (drag and drop / drop and lock),
/// colour badges and (Enhanced skin) ground. Bounds
/// and defaults come from the
/// data. Shared by the settings screen and the in-game settings sheet.
class SettingsForm extends StatelessWidget {
  const SettingsForm({
    super.key,
    required this.settings,
    required this.data,
    required this.onChanged,
    this.showSpeed = true,
    this.showGround = false,
  });

  final Settings settings;
  final GameData data;
  final ValueChanged<Settings> onChanged;

  /// The base speed applies when a game starts; in a game the top bar's
  /// speed button changes it.
  final bool showSpeed;

  /// Offer Ground: Classic / Sharp (the Enhanced skin's
  /// `UiSkin.sharpGroundOffered`).
  final bool showGround;

  /// The original's game-speed slider snaps to 5 % steps (`PrefData`).
  static const double speedStepPercent = 5;

  @override
  Widget build(BuildContext context) {
    final waves = data.waves;
    final spacing = (settings.waveSpacingS ?? waves.waveSpacingMs / 1000).clamp(
      waves.spacingPrefMinS,
      waves.spacingPrefMaxS,
    );
    final volume = (settings.volume ?? data.audio.volume).clamp(0.0, 100.0);
    final minSpeed = data.rules.speedFactorMin * 100;
    final maxSpeed = data.rules.speedFactorMax * 100;
    final speed = (settings.timeScale * 100).clamp(minSpeed, maxSpeed);
    final smoke = data.world.effects.rocketSmoke;
    final smokeOn = settings.smokeOn(data);
    final smokeMax = settings.smokeLimit(data);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.sound')),
          value: settings.soundOn,
          onChanged: (v) => onChanged(settings.copyWith(soundOn: v)),
        ),
        _SliderTile(
          label: data.tr(context, 'ui.settings.volume'),
          value: volume.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          display: '${volume.round()}',
          onChanged: settings.soundOn ? (v) => onChanged(settings.copyWith(volume: v)) : null,
        ),
        _SliderTile(
          label: data.tr(context, 'ui.settings.waveSpacing'),
          value: spacing.toDouble(),
          min: waves.spacingPrefMinS,
          max: waves.spacingPrefMaxS,
          divisions: (waves.spacingPrefMaxS - waves.spacingPrefMinS).round(),
          display: data.tr(context, 'ui.settings.seconds', {'value': spacing.round()}),
          onChanged: (v) => onChanged(settings.copyWith(waveSpacingS: v.roundToDouble())),
        ),
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.waveFollow')),
          value: settings.waveFollow,
          onChanged: (v) => onChanged(settings.copyWith(waveFollow: v)),
        ),
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.waveRemember')),
          value: settings.waveRemember,
          onChanged: (v) => onChanged(settings.copyWith(waveRemember: v)),
        ),
        if (showSpeed)
          _SliderTile(
            label: data.tr(context, 'ui.settings.speed'),
            value: speed.toDouble(),
            min: minSpeed,
            max: maxSpeed,
            divisions: ((maxSpeed - minSpeed) / speedStepPercent).round(),
            display: '${speed.round()} %',
            onChanged: (v) => onChanged(settings.copyWith(timeScale: v.roundToDouble() / 100)),
          ),
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.smoke')),
          value: smokeOn,
          onChanged: (v) => onChanged(settings.copyWith(rocketSmoke: v)),
        ),
        _SliderTile(
          label: data.tr(context, 'ui.settings.smokeMax'),
          value: smokeMax.toDouble(),
          min: smoke.maxPrefMin.toDouble(),
          max: smoke.maxPrefMax.toDouble(),
          divisions: smoke.maxPrefMax - smoke.maxPrefMin,
          display: '$smokeMax',
          onChanged: smokeOn ? (v) => onChanged(settings.copyWith(smokeMax: v.round())) : null,
        ),
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.haptics')),
          subtitle: Text(data.tr(context, 'ui.settings.hapticsInfo')),
          value: settings.haptics,
          onChanged: (v) => onChanged(settings.copyWith(haptics: v)),
        ),
        SettingChoiceTile(
          title: data.tr(context, 'ui.settings.language'),
          choice: (expanded) => DropdownButton<String?>(
            isExpanded: expanded,
            value: data.strings.containsKey(settings.locale) ? settings.locale : null,
            onChanged: (v) => onChanged(settings.withLocale(v)),
            items: [
              DropdownMenuItem(child: Text(data.tr(context, 'ui.settings.deviceLanguage'))),
              for (final t in data.strings.values)
                DropdownMenuItem(value: t.locale, child: Text(t['language.name'])),
            ],
          ),
        ),
        SettingChoiceTile(
          title: data.tr(context, 'ui.settings.placement'),
          info: data.tr(context, 'ui.settings.placementInfo'),
          choice: (expanded) => DropdownButton<PlacementMode>(
            isExpanded: expanded,
            value: settings.placement,
            onChanged: (v) => onChanged(settings.copyWith(placement: v)),
            items: [
              DropdownMenuItem(
                value: PlacementMode.dragAndDrop,
                child: Text(data.tr(context, 'ui.settings.placementDrag')),
              ),
              DropdownMenuItem(
                value: PlacementMode.dropAndLock,
                child: Text(data.tr(context, 'ui.settings.placementLock')),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: Text(data.tr(context, 'ui.settings.colourBadges')),
          subtitle: Text(data.tr(context, 'ui.settings.colourBadgesInfo')),
          value: settings.colourBadges,
          onChanged: (v) => onChanged(settings.copyWith(colourBadges: v)),
        ),
        if (showGround)
          SettingChoiceTile(
            title: data.tr(context, 'ui.settings.ground'),
            info: data.tr(context, 'ui.settings.groundInfo'),
            choice: (expanded) => DropdownButton<bool>(
              isExpanded: expanded,
              value: settings.sharpGround,
              onChanged: (v) => onChanged(settings.copyWith(sharpGround: v)),
              items: [
                DropdownMenuItem(
                  value: false,
                  child: Text(data.tr(context, 'ui.settings.groundClassic')),
                ),
                DropdownMenuItem(
                  value: true,
                  child: Text(data.tr(context, 'ui.settings.groundSharp')),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A setting picked from a dropdown: beside its title when there is room,
/// under it on a narrow phone (where a trailing dropdown would crowd the
/// title out).
class SettingChoiceTile extends StatelessWidget {
  const SettingChoiceTile({super.key, required this.title, required this.choice, this.info});

  final String title;
  final String? info;

  /// The dropdown; [expanded] when it spans the row under the title.
  final Widget Function(bool expanded) choice;

  /// Narrower than this, the dropdown goes under the title.
  static const double stackBelow = 420;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final info = this.info;
      if (box.maxWidth >= stackBelow) {
        return ListTile(
          title: Text(title),
          subtitle: info == null ? null : Text(info),
          trailing: choice(false),
        );
      }
      return ListTile(
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [?(info == null ? null : Text(info)), choice(true)],
        ),
      );
    },
  );
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: SizedBox(width: 56, child: Text(display, textAlign: TextAlign.end)),
    subtitle: Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: display,
      semanticFormatterCallback: (_) => display,
      onChanged: onChanged,
    ),
  );
}
