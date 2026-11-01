import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/dialogs.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../services/logging/logging.dart';
import '../../services/persistence/mod_library.dart';
import 'mod_dialogs.dart';
import 'mod_value_editors.dart';

const Logger _log = Logger('mods');

/// The mod editor (`/mods`; the original's `GameSelectMod` with
/// `ModInterface`): the moddable items, the values of the chosen item, and
/// the chosen value's editor, side by side as the original's three sliding
/// panels. Every change is stored at once; the switch applies the mod to
/// new games; Export and Import share it as a code.
class ModsScreen extends ConsumerWidget {
  const ModsScreen({super.key, this.initialField});

  /// The value to open first (`TurretBlue.weapon_damage`, from `?field=`);
  /// the first value of the first item when null or unknown.
  final String? initialField;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(modRulesProvider);
    final mods = ref.watch(modsProvider);
    return AsyncGate(
      value: asyncBoth(rules, mods),
      errorFrame: (context, message) => MenuScaffold(
        title: ref.tr(context, 'ui.mods.title'),
        onBack: () => context.go('/mode'),
        child: message,
      ),
      loading: const ColoredBox(
        color: AppColours.backdrop,
        child: Center(child: CircularProgressIndicator()),
      ),
      builder: (context, both) => Theme(
        data: _theme,
        child: _ModEditor(rules: both.$1, mods: both.$2, initialField: initialField),
      ),
    );
  }
}

/// The editor's controls on the dark menu backdrop.
final ThemeData _theme = ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.orange);

/// Changed values are marked in this colour (the original's red
/// "highlighted" glow, lightened for the dark menu).
const Color _modifiedColor = Color(0xFFFF8A65);

class _ModEditor extends ConsumerStatefulWidget {
  const _ModEditor({required this.rules, required this.mods, this.initialField});

  final ModRules rules;
  final ModLibrary mods;
  final String? initialField;

  @override
  ConsumerState<_ModEditor> createState() => _ModEditorState();
}

class _ModEditorState extends ConsumerState<_ModEditor> {
  late String _field =
      widget.rules.field(widget.initialField ?? '')?.id ?? widget.rules.fields.first.id;
  late String _item = widget.rules.field(_field)!.item.id;

  /// Why the last value typed for [_field] was refused.
  String? _error;

  /// Whether the stored mod still validates, worked out once per mod.
  ModDelta? _checked;
  List<ModProblem> _modProblems = const [];

  ModRules get _rules => widget.rules;
  ModLibrary get _mods => widget.mods;
  ModDelta get _mod => _mods.mod;
  GameData get _data => _rules.base;
  ModsNotifier get _store => ref.read(modsProvider.notifier);

  List<ModProblem> get _problems {
    if (!identical(_checked, _mod)) {
      _checked = _mod;
      _modProblems = _rules.validate(_mod);
    }
    return _modProblems;
  }

  void _selectItem(String id) => setState(() {
    _item = id;
    _field = _rules.fieldsOf(id).first.id;
    _error = null;
    _depth = 1;
  });

  void _selectField(String id) => setState(() {
    _field = id;
    _error = null;
    _depth = 2;
  });

  /// On a narrow screen one pane shows at a time: 0 items, 1 the item's
  /// fields, 2 the field's value; back steps out a level.
  int _depth = 0;

  /// Narrower than this, the three panes become one drill-down pane.
  static const double _drillDownBelow = 600;

  Future<void> _save(ModDelta next) => _store.change((m) => m.copyWith(mod: next));

  /// Checks [value] against the descriptor and the modded data as a whole,
  /// then stores it, or shows why not.
  Future<void> _commit(ModField f, Object? value) async {
    final problems = _rules.check(f, value);
    final next = problems.isEmpty ? _rules.withValue(_mod, f, value) : _mod;
    final invalid = problems.isEmpty ? _rules.validate(next) : const <ModProblem>[];
    final refused = [...problems, ...invalid];
    setState(() => _error = refused.isEmpty ? null : modProblemText(context, refused.first, _data));
    if (refused.isEmpty) {
      _log.debug('mod value changed', fields: {'field': f.id});
      await _save(next);
    } else {
      _log.debug('mod value refused', fields: {'field': f.id, 'problem': refused.first.kind.name});
    }
  }

  Future<void> _resetAll() async {
    final ok = await confirm(
      context,
      title: _data.tr(context, 'ui.mods.resetAllTitle'),
      body: _data.tr(context, 'ui.mods.resetAllBody', {'count': _rules.changeCount(_mod)}),
      action: _data.tr(context, 'mods.reset'),
    );
    if (!ok || !mounted) return;
    _log.info('mod reset', fields: {'changes': _rules.changeCount(_mod)});
    setState(() => _error = null);
    await _save(_rules.cleared(_mod));
  }

  Future<void> _export() => showShareCode(
    context,
    data: _data,
    name: _data.modName(context, _mods.name),
    code: ref.read(modSharingProvider).encode(ModDelta(_mod.files, name: _mods.name)),
    hint: _data.tr(context, 'ui.mods.shareHint'),
  );

  Future<void> _import() async {
    final imported = await showModImport(
      context,
      sharing: ref.read(modSharingProvider),
      rules: _rules,
      current: _mod,
    );
    if (imported == null || !mounted) return;
    _log.info(
      'mod imported',
      fields: {
        'modName': Pii(imported.delta.name ?? _mods.name),
        'files': imported.delta.files.length,
        'problems': imported.problems.length,
      },
    );
    setState(() => _error = null);
    await _save(ModDelta(imported.delta.files, name: imported.delta.name ?? _mods.name));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_data.tr(context, 'mods.loaded'))));
  }

  Future<void> _rename() async {
    final name = await askModName(
      context,
      initial: _data.modName(context, _mods.name),
      data: _data,
    );
    if (name == null || !mounted) return;
    _log.debug('mod renamed', fields: {'modName': Pii(name)});
    await _save(ModDelta(_mod.files, name: name));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _build(context, narrow: box.maxWidth < _drillDownBelow),
  );

  Widget _build(BuildContext context, {required bool narrow}) {
    final empty = _mod.isEmpty;
    const white = TextStyle(color: Colors.white);
    Widget action(String key, IconData icon, VoidCallback? onPressed) => narrow
        ? IconButton(
            tooltip: _data.tr(context, key),
            color: Colors.white,
            onPressed: onPressed,
            icon: Icon(icon),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(_data.tr(context, key)),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          );
    return MenuScaffold(
      title: _data.tr(context, 'flow.modeModding'),
      onBack: narrow && _depth > 0 ? () => setState(() => _depth--) : () => context.go('/mode'),
      actions: [
        action('ui.mods.import', Icons.download, _import),
        action('ui.mods.export', Icons.share, empty ? null : _export),
        IconButton(
          tooltip: _data.tr(context, 'ui.mods.resetAll'),
          color: Colors.white,
          onPressed: empty ? null : _resetAll,
          icon: const Icon(Icons.restart_alt),
        ),
        const SizedBox(width: 8),
      ],
      child: DefaultTextStyle.merge(
        style: white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBar(
              mods: _mods,
              changes: _rules.changeCount(_mod),
              problems: _problems,
              data: _data,
              onActive: (v) {
                _log.info('mod switched', fields: {'on': v});
                _store.change((m) => m.copyWith(active: v));
              },
              onRename: _rename,
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Portrait phones: one pane at a time (items → fields →
                  // value).
                  if (box.maxWidth < _drillDownBelow) {
                    return switch (_depth) {
                      0 => _itemList(),
                      1 => _fieldList(),
                      _ => _valuePane(),
                    };
                  }
                  final narrow = box.maxWidth < 760;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: narrow ? 190 : 240, child: _itemList()),
                      const VerticalDivider(width: 1),
                      SizedBox(width: narrow ? 230 : 300, child: _fieldList()),
                      const VerticalDivider(width: 1),
                      Expanded(child: _valuePane()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemList() {
    final children = <Widget>[];
    String? group;
    final locale = uiLocale(context);
    for (final item in _rules.items) {
      final title = _data.modItemTitle(item.id, locale: locale);
      if (item.group != group) {
        group = item.group;
        children.add(_Header(_data.tr(context, 'mods.group.$group')));
      }
      final changed = _rules.itemIsSet(item.id, _mod);
      children.add(
        _Row(
          key: Key('modItem:${item.id}'),
          changedLabel: _data.tr(context, 'ui.mods.changed'),
          title: title.contains(': ') ? title.split(': ').last : title,
          selected: item.id == _item,
          changed: changed,
          onTap: () => _selectItem(item.id),
        ),
      );
    }
    return ListView(
      key: const Key('modItems'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [_Header(_data.tr(context, 'mods.items'), big: true), ...children],
    );
  }

  Widget _fieldList() {
    final item = _rules.items.firstWhere((i) => i.id == _item);
    final changed = _rules.itemIsSet(_item, _mod);
    return ListView(
      key: const Key('modFields'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _Header(_data.modItemTitle(item.id, locale: uiLocale(context)), big: true),
        if (changed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('modResetItem'),
                onPressed: () {
                  setState(() => _error = null);
                  _save(_rules.withoutItem(_mod, _item));
                },
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(_data.tr(context, 'mods.reset')),
              ),
            ),
          ),
        for (final f in _rules.fieldsOf(_item))
          _Row(
            key: Key('modField:${f.id}'),
            changedLabel: _data.tr(context, 'ui.mods.changed'),
            title: _data.modText(context, f).title,
            subtitle: summarizeModValue(context, _data, f, _rules.valueOf(f, _mod)),
            selected: f.id == _field,
            changed: _rules.isSet(f, _mod),
            onTap: () => _selectField(f.id),
          ),
      ],
    );
  }

  Widget _valuePane() {
    final f = _rules.field(_field)!;
    final value = _rules.valueOf(f, _mod);
    final d = f.descriptor;
    final words = _data.modText(context, f);
    final changed = _rules.isSet(f, _mod);
    final dim = TextStyle(color: Colors.white.withValues(alpha: 0.7));
    void commit(Object? v) => _commit(f, v);
    return SingleChildScrollView(
      key: Key('modValue:${f.id}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(words.title, style: Theme.of(context).textTheme.titleMedium)),
              if (changed)
                TextButton.icon(
                  key: const Key('modResetValue'),
                  onPressed: () {
                    setState(() => _error = null);
                    _save(_rules.withoutValue(_mod, f));
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(_data.tr(context, 'mods.reset')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          switch (f.type) {
            ModValueType.number || ModValueType.integer => ModNumberEditor(
              key: ValueKey(f.id),
              data: _data,
              field: f,
              value: value! as num,
              onCommit: commit,
              error: _error,
            ),
            ModValueType.boolean => ModBooleanEditor(
              data: _data,
              value: value == true,
              onCommit: commit,
            ),
            ModValueType.string => ModStringEditor(
              key: ValueKey(f.id),
              field: f,
              value: '$value',
              onCommit: commit,
              error: _error,
            ),
            ModValueType.arrayIndexed => ModIndexedEditor(
              key: ValueKey(f.id),
              data: _data,
              field: f,
              entries: [for (final e in value! as List) (e as Map).cast<String, Object?>()],
              onCommit: commit,
              error: _error,
            ),
          },
          if (_error != null && f.type == ModValueType.boolean)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          // `ModAssetDesc`: the description, then Min, Max and Units.
          Text(
            [
              words.description,
              if (d.min != null) _data.tr(context, 'mods.min', {'value': displayModNumber(d.min!)}),
              if (d.max != null) _data.tr(context, 'mods.max', {'value': displayModNumber(d.max!)}),
              if (words.unit != null) _data.tr(context, 'mods.units', {'value': words.unit}),
            ].join('\n'),
            style: dim,
          ),
          if (changed && f.type != ModValueType.arrayIndexed) ...[
            const SizedBox(height: 8),
            Text(
              _data.tr(context, 'ui.mods.default', {
                'value': summarizeModValue(context, _data, f, f.defaultValue),
              }),
              style: dim,
            ),
          ],
        ],
      ),
    );
  }
}

/// The switch that applies the mod to new games, its name, how much it
/// changes and its signature, and any reason it cannot be used.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.mods,
    required this.changes,
    required this.problems,
    required this.data,
    required this.onActive,
    required this.onRename,
  });

  final ModLibrary mods;
  final int changes;
  final List<ModProblem> problems;
  final GameData data;
  final ValueChanged<bool> onActive;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: Colors.white.withValues(alpha: 0.7));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              // The label toggles too, and names the switch for screen readers.
              MergeSemantics(
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => onActive(!mods.active),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          key: const Key('modActive'),
                          value: mods.active,
                          onChanged: onActive,
                        ),
                        const SizedBox(width: 4),
                        // Wraps on a narrow phone at large text.
                        Flexible(child: Text(data.tr(context, 'ui.mods.useInNewGames'))),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('modName'),
                onPressed: onRename,
                icon: const Icon(Icons.edit, size: 16),
                label: Text(data.modName(context, mods.name)),
              ),
              Text(
                changes == 0
                    ? data.tr(context, 'ui.mods.noChanges')
                    : data.tr(context, changes == 1 ? 'ui.mods.changeOne' : 'ui.mods.changeMany', {
                        'count': changes,
                        'signature': modSignature(mods.mod),
                      }),
                key: const Key('modSummary'),
                style: dim,
              ),
            ],
          ),
          if (problems.isNotEmpty)
            Text(
              modProblemText(context, problems.first, data, withField: true),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (changes == 0)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(data.tr(context, 'mods.help'), style: dim),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.big = false});

  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, big ? 10 : 12, 16, 4),
    child: Text(
      big ? text : text.toUpperCase(),
      style: big
          ? Theme.of(context).textTheme.titleSmall
          : Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Colors.white54, letterSpacing: 1),
    ),
  );
}

/// A list row (`ModListItem`): selected rows are lit, changed ones marked.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    required this.selected,
    required this.changed,
    required this.onTap,
    required this.changedLabel,
    this.subtitle,
  });

  final String title;

  /// Spoken for the changed marker.
  final String changedLabel;
  final String? subtitle;
  final bool selected;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 44,
    selected: selected,
    selectedTileColor: Colors.white.withValues(alpha: 0.12),
    selectedColor: Colors.white,
    textColor: Colors.white,
    title: Text(title, style: TextStyle(fontWeight: changed ? FontWeight.bold : null)),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: changed ? _modifiedColor : Colors.white60),
          ),
    trailing: changed
        ? Icon(Icons.circle, size: 10, color: _modifiedColor, semanticLabel: changedLabel)
        : null,
    onTap: onTap,
  );
}
