import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../game_view_model.dart';
import '../layout/hud_layout.dart';
import 'format.dart';
import 'hud_keys.dart';

/// The game's stats and controls (`docs/REMASTER_PLAN.md` §3.3): back,
/// lives, cash, kills, wave, the next-wave clock (tap to send the wave now),
/// the speed button (when the rules profile offers it), settings and pause.
/// Reads only the view model.
///
/// Along [Axis.horizontal] it is the thin translucent bar over the top of
/// the screen: the full row when at least [HudMetrics.compactBelow] wide
/// (landscape, exactly as v1), a compact row on portrait phones (no map
/// name or kills, short cash, the wave as an icon and number). Along
/// [Axis.vertical] it is a rail down the left side (Enhanced `rails`).
/// Tap targets are the same size in every form.
class StatsBar extends StatelessWidget {
  const StatsBar({
    super.key,
    required this.viewModel,
    required this.onExit,
    this.onSettings,
    this.keys,
    this.axis = Axis.horizontal,
    this.inset = EdgeInsets.zero,
  });

  final GameViewModel viewModel;
  final VoidCallback onExit;

  /// Opens the game settings; no button when null.
  final VoidCallback? onSettings;

  /// Keys on the controls the tutorial points at.
  final HudKeys? keys;

  /// Along the top (a bar) or down a side (a rail).
  final Axis axis;

  /// What the controls keep clear of (a notch); the background covers it.
  final EdgeInsets inset;

  /// Height of the bar in logical px.
  static const double height = HudMetrics.statsBarHeight;

  /// Width of the rail in logical px.
  static const double railWidth = HudMetrics.trayRailWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tabular (fixed-width) digits so the readouts don't jitter or nudge
    // their neighbours as the numbers tick.
    final text = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final small = theme.textTheme.labelLarge?.copyWith(
      color: Colors.white70,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder<HudState>(
      valueListenable: viewModel.hud,
      builder: (context, hud, _) {
        if (axis == Axis.vertical) return _rail(context, hud, text, small);
        return LayoutBuilder(
          builder: (context, box) => box.maxWidth < HudMetrics.compactBelow
              ? _compact(context, hud, text)
              : _wide(context, hud, text, small),
        );
      },
    );
  }

  GameData get _data => viewModel.data;

  Widget _exit(BuildContext context) => IconButton(
    key: keys?.exit,
    tooltip: _data.tr(context, 'ui.hud.exit'),
    icon: const Icon(Icons.arrow_back, color: Colors.white),
    onPressed: onExit,
  );

  Widget _lives(BuildContext context, HudState hud, TextStyle? text) => _Readout(
    label: _data.tr(context, 'ui.hud.lives', {'lives': hud.lives}),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
        const SizedBox(width: 4),
        Text('${hud.lives}', style: text),
      ],
    ),
  );

  Widget _cash(BuildContext context, HudState hud, TextStyle? text, {bool short = false}) =>
      _Readout(
        key: keys?.cash,
        label: _data.tr(context, 'ui.hud.cash', {'cash': hud.cash.toStringAsFixed(0)}),
        child: Text(
          '\$${short ? shortNumber(hud.cash) : hud.cash.toStringAsFixed(0)}',
          style: text,
        ),
      );

  Widget _waveIcon(BuildContext context, HudState hud, TextStyle? text) => _Readout(
    label: _data.tr(context, 'ui.hud.wave', {'wave': hud.wave}),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.waves, color: Colors.white70, size: 20),
        const SizedBox(width: 4),
        Text('${hud.wave}', style: text),
      ],
    ),
  );

  Widget _clock(HudState hud) => _NextWaveButton(
    key: keys?.waveClock,
    data: _data,
    hud: hud,
    onSend: () => viewModel.dispatch(const SendNextWave()),
  );

  List<Widget> _buttons(BuildContext context, HudState hud) => [
    if (viewModel.profile.inGameSpeedButton)
      _SpeedButton(
        data: _data,
        speed: hud.speed,
        max: _data.rules.speedFactorMax,
        onSet: (s) => viewModel.dispatch(SetSpeed(s)),
      ),
    if (onSettings != null)
      IconButton(
        tooltip: _data.tr(context, 'ui.hud.settings'),
        icon: const Icon(Icons.settings, color: Colors.white),
        onPressed: onSettings,
      ),
    IconButton(
      key: keys?.pause,
      tooltip: _data.tr(context, hud.paused ? 'ui.hud.resume' : 'ui.hud.pause'),
      icon: Icon(hud.paused ? Icons.play_arrow : Icons.pause, color: Colors.white),
      onPressed: hud.gameOver ? null : () => viewModel.dispatch(SetPaused(!hud.paused)),
    ),
  ];

  Widget _wide(BuildContext context, HudState hud, TextStyle? text, TextStyle? small) => Container(
    height: height + inset.vertical,
    padding: inset + const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.black.withValues(alpha: 0.45),
    child: Row(
      children: [
        _exit(context),
        const SizedBox(width: 4),
        _lives(context, hud, text),
        const SizedBox(width: 16),
        _cash(context, hud, text),
        const SizedBox(width: 16),
        _Readout(
          label: _data.tr(context, 'ui.hud.wave', {'wave': hud.wave}),
          child: Text(_data.tr(context, 'ui.hud.wave', {'wave': hud.wave}), style: text),
        ),
        const SizedBox(width: 16),
        _Readout(
          label: _data.tr(context, 'ui.hud.killsLabel', {'kills': hud.kills}),
          child: Text(_data.tr(context, 'ui.hud.kills', {'kills': hud.kills}), style: small),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            _data.mapName(viewModel.map, locale: uiLocale(context)),
            style: small,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _clock(hud),
        ..._buttons(context, hud),
      ],
    ),
  );

  /// Portrait phones: the readouts share what the buttons leave, shrinking
  /// together rather than overflowing.
  Widget _compact(BuildContext context, HudState hud, TextStyle? text) => Container(
    height: height + inset.vertical,
    padding: inset + const EdgeInsets.symmetric(horizontal: 2),
    color: Colors.black.withValues(alpha: 0.45),
    child: Row(
      children: [
        _exit(context),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                _lives(context, hud, text),
                const SizedBox(width: 10),
                _cash(context, hud, text, short: true),
                const SizedBox(width: 10),
                _waveIcon(context, hud, text),
              ],
            ),
          ),
        ),
        _clock(hud),
        ..._buttons(context, hud),
      ],
    ),
  );

  /// A rail down the left side (Enhanced `rails`); scrolls if the screen is
  /// too short for every control.
  Widget _rail(BuildContext context, HudState hud, TextStyle? text, TextStyle? small) => Container(
    width: railWidth + inset.horizontal,
    padding: inset,
    color: Colors.black.withValues(alpha: 0.45),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        Center(child: _exit(context)),
        const SizedBox(height: 4),
        Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: _lives(context, hud, text)),
        ),
        const SizedBox(height: 8),
        Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: _cash(context, hud, text, short: true)),
        ),
        const SizedBox(height: 8),
        Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: _waveIcon(context, hud, text)),
        ),
        const SizedBox(height: 4),
        _clock(hud),
        for (final b in _buttons(context, hud)) Center(child: b),
      ],
    ),
  );
}

class _Readout extends StatelessWidget {
  const _Readout({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(child: child),
  );
}

/// The wave clock: a ring that empties as the next wave approaches, with the
/// seconds left; tapping sends the wave now (`WaveClock`, Space).
class _NextWaveButton extends StatelessWidget {
  const _NextWaveButton({super.key, required this.data, required this.hud, required this.onSend});

  final GameData data;
  final HudState hud;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final fraction = hud.waveSpacingSeconds <= 0
        ? 0.0
        : (hud.nextWaveSeconds / hud.waveSpacingSeconds).clamp(0.0, 1.0);
    final enabled = !hud.paused && !hud.gameOver;
    return Tooltip(
      message: data.tr(context, 'ui.hud.sendWave'),
      child: Semantics(
        button: true,
        label: data.tr(context, 'ui.hud.nextWave', {
          'seconds': hud.nextWaveSeconds.toStringAsFixed(1),
        }),
        child: InkResponse(
          onTap: enabled ? onSend : null,
          radius: 24,
          child: SizedBox(
            width: 76,
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 3,
                    color: Colors.amberAccent,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(width: 4),
                // A fixed-width, left-aligned slot with tabular digits, so
                // the ring stays put as the seconds tick (and as "10" turns
                // into "9.9").
                SizedBox(
                  width: 32,
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hud.nextWaveSeconds.toStringAsFixed(hud.nextWaveSeconds < 10 ? 1 : 0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The in-game speed button (`RulesProfile.inGameSpeedButton`): cycles
/// 1×, 2×, … up to the data's maximum speed factor.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.data,
    required this.speed,
    required this.max,
    required this.onSet,
  });

  final GameData data;
  final double speed;
  final double max;
  final ValueChanged<double> onSet;

  @override
  Widget build(BuildContext context) {
    final next = speed + 1 > max + 1e-9 ? 1.0 : (speed.floorToDouble() + 1);
    final label = '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';
    return Tooltip(
      message: data.tr(context, 'ui.settings.speed'),
      child: Semantics(
        button: true,
        label: data.tr(context, 'ui.hud.speed', {'speed': label}),
        child: InkResponse(
          onTap: () => onSet(next),
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
