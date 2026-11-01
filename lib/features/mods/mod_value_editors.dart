import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/format.dart';
import '../../app/strings.dart';

/// A number as the data writes it: `20`, `1.125`, never `20.0`.
String formatModNumber(num v) =>
    v is double && v.isFinite && v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

/// [formatModNumber] with thousands separated, for reading (`3,000,000`).
String displayModNumber(num v) {
  final s = formatModNumber(v);
  // Four-digit numbers stay ungrouped (`1000`, as the data writes them).
  final digits = RegExp(r'^-?(\d+)').firstMatch(s)?[1];
  return digits == null || digits.length < 5 ? s : groupThousands(s);
}

/// The step the +/− buttons move by (`ModLibraryItem.step`, 1 by default).
double modStep(ValueDescriptor d) => d.step ?? 1;

/// [v] on the [step] grid (`NumericStepper` snapping), without float noise.
num snapToStep(num v, double step) {
  final decimals = formatModNumber(step).split('.').elementAtOrNull(1)?.length ?? 0;
  final snapped = double.parse(((v / step).round() * step).toStringAsFixed(decimals));
  return decimals == 0 ? snapped.toInt() : snapped;
}

/// A short reading of [value] for the value lists.
String summarizeModValue(BuildContext context, GameData data, ModField f, Object? value) =>
    switch (f.type) {
      ModValueType.boolean => data.tr(context, value == true ? 'ui.mods.yes' : 'ui.mods.no'),
      ModValueType.arrayIndexed => switch ((value as List?)?.length ?? 0) {
        1 => data.tr(context, 'ui.mods.entryOne'),
        final n => data.tr(context, 'ui.mods.entryMany', {'count': n}),
      },
      ModValueType.number || ModValueType.integer when value is num => [
        displayModNumber(value),
        ?data.modText(context, f).unit,
      ].join(' '),
      _ => '$value',
    };

/// The player-facing text for [p] (strings `mods.problem.*`), naming the
/// entry and its part for an indexed value, and the value itself when
/// [withField] is set (an import lists problems of many values).
String modProblemText(BuildContext context, ModProblem p, GameData data, {bool withField = false}) {
  final text = data.tr(context, 'mods.problem.${p.kind.name}', {
    'limit': p.limit == null ? '' : displayModNumber(p.limit!),
    'detail': p.detail ?? '',
  });
  final f = p.field;
  final part = f == null ? null : data.modPartText(context, f, p.part == 'key' ? 'key' : 'value');
  return [
    if (withField && f != null)
      '${data.modItemTitle(f.item.id, locale: uiLocale(context))} › ${data.modText(context, f).title}: ',
    if (p.entry != null) '#${p.entry! + 1}${part == null ? '' : ' ${part.title}'}: ',
    text,
  ].join();
}

/// A number field committed on Done or when it loses focus, between −/+
/// buttons that move by the descriptor's step and stop at its bounds.
class ModNumberEditor extends StatefulWidget {
  const ModNumberEditor({
    super.key,
    required this.data,
    required this.field,
    required this.value,
    required this.onCommit,
    this.error,
  });

  /// The game's text.
  final GameData data;
  final ModField field;
  final num value;

  /// A typed value, or the parsed text (null when it is not a number).
  final ValueChanged<Object?> onCommit;
  final String? error;

  @override
  State<ModNumberEditor> createState() => _ModNumberEditorState();
}

/// The text field state a number editor shares: a controller holding
/// [value] as the data writes it, committed with [commit] (the parsed
/// text, null when not a number) on Done ([submit]) and when the field
/// loses focus. The widget's [didUpdateWidget] calls [showValue] when the
/// value it shows changes.
mixin _NumberFieldState<W extends StatefulWidget> on State<W> {
  /// The value the field shows.
  num get value;

  /// Commits [typed], the field's number (null when it is not one).
  void commit(num? typed);

  late final TextEditingController text = TextEditingController(text: formatModNumber(value));
  final FocusNode focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) submit();
    });
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  /// Shows [value] in the field (after the widget's value changed).
  void showValue() => text.text = formatModNumber(value);

  /// Commits the field's text (`3,000` reads as 3000).
  void submit() => commit(num.tryParse(text.text.trim().replaceAll(',', '')));
}

class _ModNumberEditorState extends State<ModNumberEditor> with _NumberFieldState<ModNumberEditor> {
  @override
  num get value => widget.value;

  @override
  void commit(num? typed) {
    if (typed == widget.value && widget.error == null) return;
    widget.onCommit(typed);
  }

  @override
  void didUpdateWidget(ModNumberEditor old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.field.id != widget.field.id) showValue();
  }

  void _nudge(int direction) {
    final d = widget.field.descriptor;
    final step = modStep(d);
    var next = snapToStep(widget.value + direction * step, step);
    if (d.min != null && next < d.min!) next = snapToStep(d.min!, step);
    if (d.max != null && next > d.max!) next = snapToStep(d.max!, step);
    widget.onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.field.descriptor;
    final canDown = d.min == null || widget.value > d.min!;
    final canUp = d.max == null || widget.value < d.max!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton.filledTonal(
          tooltip: widget.data.tr(context, 'ui.mods.decrease'),
          onPressed: canDown ? () => _nudge(-1) : null,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        // 160 wide, narrower in a tight pane (a portrait tablet).
        Flexible(
          child: SizedBox(
            width: 160,
            child: TextField(
              key: const Key('modNumber'),
              controller: text,
              focusNode: focus,
              keyboardType: TextInputType.numberWithOptions(
                decimal: true,
                signed: d.min == null || d.min! < 0,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                suffixText: widget.data.modText(context, widget.field).unit,
                errorText: widget.error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => submit(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: widget.data.tr(context, 'ui.mods.increase'),
          onPressed: canUp ? () => _nudge(1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// A yes/no value (`ModValueBoolean`'s checkbox).
class ModBooleanEditor extends StatelessWidget {
  const ModBooleanEditor({
    super.key,
    required this.data,
    required this.value,
    required this.onCommit,
  });

  /// The game's text.
  final GameData data;
  final bool value;
  final ValueChanged<Object?> onCommit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Switch(key: const Key('modBoolean'), value: value, onChanged: onCommit),
      const SizedBox(width: 8),
      Text(data.tr(context, value ? 'ui.mods.yes' : 'ui.mods.no')),
    ],
  );
}

/// A text value (`ModValueString`), committed on Done or focus loss.
class ModStringEditor extends StatefulWidget {
  const ModStringEditor({
    super.key,
    required this.field,
    required this.value,
    required this.onCommit,
    this.error,
  });

  final ModField field;
  final String value;
  final ValueChanged<Object?> onCommit;
  final String? error;

  @override
  State<ModStringEditor> createState() => _ModStringEditorState();
}

class _ModStringEditorState extends State<ModStringEditor> {
  late final TextEditingController _text = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.value) widget.onCommit(_text.text);
    });
  }

  @override
  void didUpdateWidget(ModStringEditor old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('modString'),
    controller: _text,
    focusNode: _focus,
    decoration: InputDecoration(isDense: true, errorText: widget.error),
    onSubmitted: widget.onCommit,
  );
}

/// Indexed entries (`ModValueArrayIndexed`): one row per entry with its key
/// and value, and a menu to insert above or below (the midpoint of the
/// neighbours, as the original did), move up or down, or remove. The
/// whole list is committed on every change.
class ModIndexedEditor extends StatelessWidget {
  const ModIndexedEditor({
    super.key,
    required this.data,
    required this.field,
    required this.entries,
    required this.onCommit,
    this.error,
  });

  /// The game's text.
  final GameData data;
  final ModField field;
  final List<Map<String, Object?>> entries;
  final ValueChanged<Object?> onCommit;
  final String? error;

  String get _keyField => field.def.keyField!;
  String get _valueField => field.def.valueField!;

  num _at(int i, String part) => entries[i][part]! as num;

  void _set(int i, String part, num? v) {
    final next = [
      for (final e in entries) {...e},
    ];
    next[i][part] = v;
    onCommit(next);
  }

  /// A new entry between [a] and [b] (either may be null at an end).
  Map<String, Object?> _between(int? a, int? b) {
    num mid(String part, ValueDescriptor? d) {
      final lo = a == null ? null : _at(a, part);
      final hi = b == null ? null : _at(b, part);
      final v = lo != null && hi != null ? (lo + hi) / 2 : (lo ?? hi)!;
      return snapToStep(v, d == null ? 1 : modStep(d));
    }

    return {
      _keyField: mid(_keyField, field.descriptor.key),
      _valueField: mid(_valueField, field.descriptor.value),
    };
  }

  void _act(int i, String action) {
    final next = [
      for (final e in entries) {...e},
    ];
    switch (action) {
      case 'above':
        next.insert(i, _between(i == 0 ? null : i - 1, i));
      case 'below':
        next.insert(i + 1, _between(i, i + 1 < entries.length ? i + 1 : null));
      case 'up':
        next.insert(i - 1, next.removeAt(i));
      case 'down':
        next.insert(i + 1, next.removeAt(i));
      case 'remove':
        next.removeAt(i);
    }
    onCommit(next);
  }

  @override
  Widget build(BuildContext context) {
    final d = field.descriptor;
    final canAdd = d.max == null || entries.length < d.max!;
    final canRemove = d.min == null || entries.length > d.min!;
    final keyText = data.modPartText(context, field, 'key');
    final valueText = data.modPartText(context, field, 'value');
    String head(ModDescriptorText? p, String fallback) =>
        [p?.title ?? fallback, if (p?.unit != null) '(${p!.unit})'].join(' ');
    final style = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 36),
            Expanded(child: Text(head(keyText, _keyField), style: style)),
            const SizedBox(width: 8),
            Expanded(child: Text(head(valueText, _valueField), style: style)),
            const SizedBox(width: 48),
          ],
        ),
        for (var i = 0; i < entries.length; i++)
          Row(
            key: ValueKey('modEntry$i'),
            children: [
              SizedBox(width: 36, child: Text('#${i + 1}')),
              Expanded(
                child: _NumberCell(
                  key: ValueKey('modEntry$i:key'),
                  label: '#${i + 1} ${keyText?.title ?? _keyField}',
                  value: _at(i, _keyField),
                  onCommit: (v) => _set(i, _keyField, v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberCell(
                  key: ValueKey('modEntry$i:value'),
                  label: '#${i + 1} ${valueText?.title ?? _valueField}',
                  value: _at(i, _valueField),
                  onCommit: (v) => _set(i, _valueField, v),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: data.tr(context, 'ui.mods.entry', {'number': i + 1}),
                onSelected: (a) => _act(i, a),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'above',
                    enabled: canAdd,
                    child: Text(data.tr(context, 'ui.mods.insertAbove')),
                  ),
                  PopupMenuItem(
                    value: 'below',
                    enabled: canAdd,
                    child: Text(data.tr(context, 'ui.mods.insertBelow')),
                  ),
                  PopupMenuItem(
                    value: 'up',
                    enabled: i > 0,
                    child: Text(data.tr(context, 'ui.mods.moveUp')),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: i < entries.length - 1,
                    child: Text(data.tr(context, 'ui.mods.moveDown')),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    enabled: canRemove,
                    child: Text(data.tr(context, 'ui.mods.remove')),
                  ),
                ],
              ),
            ],
          ),
        if (entries.isEmpty)
          TextButton.icon(
            onPressed: canAdd
                ? () => onCommit([
                    {_keyField: d.key?.min ?? 1, _valueField: d.value?.min ?? 1},
                  ])
                : null,
            icon: const Icon(Icons.add),
            label: Text(data.tr(context, 'ui.mods.addEntry')),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// One number of an indexed entry, committed on Done or focus loss.
class _NumberCell extends StatefulWidget {
  const _NumberCell({super.key, required this.label, required this.value, required this.onCommit});

  final String label;
  final num value;
  final ValueChanged<num?> onCommit;

  @override
  State<_NumberCell> createState() => _NumberCellState();
}

class _NumberCellState extends State<_NumberCell> with _NumberFieldState<_NumberCell> {
  @override
  num get value => widget.value;

  @override
  void commit(num? typed) {
    if (typed != widget.value) widget.onCommit(typed);
  }

  @override
  void didUpdateWidget(_NumberCell old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) showValue();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: TextField(
      controller: text,
      focusNode: focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(isDense: true),
      onSubmitted: (_) => submit(),
    ),
  );
}
