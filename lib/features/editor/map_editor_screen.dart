import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/dialogs.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../services/assets/asset_pack.dart';
import '../../services/logging/logging.dart';
import '../../services/persistence/map_library.dart';
import 'editor_canvas.dart';
import 'editor_controller.dart';
import 'editor_dialogs.dart';

const Logger _log = Logger('editor');

/// The map editor (`/editor`, `/editor?map=<id>`; the original's Mapping
/// page): a new map, or a map from the player's library.
class MapEditorScreen extends ConsumerWidget {
  const MapEditorScreen({super.key, this.mapId});

  /// The library map to edit; null for a new map.
  final String? mapId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final library = ref.watch(mapLibraryProvider);
    final pack = ref.watch(assetPackProvider);
    return AsyncGate(
      value: asyncBoth(data, library),
      errorFrame: (context, message) => Scaffold(body: message),
      // The theme's text colour on the plain Scaffold.
      errorStyle: const TextStyle(),
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, both) => _Editor(
        key: ValueKey(mapId),
        data: both.$1,
        map: mapId == null ? null : both.$2.byId(mapId!),
        pack: pack.value,
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.data, this.map, this.pack});

  final GameData data;
  final MapDefinition? map;
  final AssetPack? pack;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final MapEditorController _c = MapEditorController(
    world: widget.data.world,
    map: widget.map,
  );
  final GlobalKey<EditorCanvasState> _canvas = GlobalKey();
  final FocusNode _focus = FocusNode(debugLabel: 'editor');
  PaletteItem? _armed;
  Vec2? _hover;
  int _helpPage = 0;
  bool _helpOpen = true;

  static const double _barHeight = 48;
  static const double _railWidth = 76;

  /// Height of the palette as a strip along the bottom (portrait).
  static const double _stripHeight = 76;

  /// Narrower than this, the top bar folds Fit, Help and Share into a menu.
  static const double _compactBarBelow = 600;

  GameData get _data => widget.data;

  static const List<String> _helpKeys = [
    'editor.help.welcome',
    'editor.help.edit',
    'editor.help.save',
    'editor.help.share',
    'editor.help.tips',
  ];

  @override
  void initState() {
    super.initState();
    // A map being edited needs no welcome.
    _helpOpen = widget.map == null;
    _log.info('editor opened', fields: {'map': widget.map?.id ?? 'new'});
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

  /// Saves the map (`mapSave`): it must validate, then gets a name. Returns
  /// the saved map, or null.
  Future<MapDefinition?> _save() async {
    final problems = _c.problems;
    if (problems.isNotEmpty) {
      _log.debug('save refused', fields: {'problems': problems.map((p) => p.name).join(',')});
      _toast(problemText(context, problems.first, _data));
      return null;
    }
    final library = ref.read(mapLibraryProvider).value ?? const MapLibrary();
    final name = await askMapName(
      context,
      initial: _c.name,
      library: library,
      data: _data,
      currentId: _c.savedId,
    );
    if (name == null || !mounted) return null;
    FocusManager.instance.primaryFocus?.unfocus();
    _focus.requestFocus();
    // A name in use keeps that map's id, so saving over it replaces it.
    final map = _c.buildMap(id: library.idFor(name), name: name)!;
    _log.debug(
      'editor saved',
      fields: {'map': map.id, 'waypoints': map.road.length, 'replaced': _c.savedId != map.id},
    );
    await ref.read(mapLibraryProvider.notifier).save(map);
    _c.markSaved(map);
    if (mounted) _toast(_data.tr(context, 'editor.saved', {'name': name}));
    return map;
  }

  /// The saved map, saving first if it changed (`mapPlay` opens the save
  /// window when the map has unsaved changes).
  Future<MapDefinition?> _saved() async {
    final id = _c.savedId;
    if (!_c.dirty && id != null) {
      return ref.read(mapLibraryProvider).value?.byId(id);
    }
    if (_c.savedId != null || !_c.draft.isEmpty) _toast(_data.tr(context, 'editor.unsaved'));
    return _save();
  }

  Future<void> _share() async {
    final map = await _saved();
    if (map == null || !mounted) return;
    await showShareCode(
      context,
      data: _data,
      name: map.name,
      code: ref.read(mapSharingProvider).encode(map),
    );
  }

  Future<void> _play() async {
    final map = await _saved();
    if (map == null || !mounted) return;
    final profile = await ref.read(profileProvider.future);
    if (!mounted) return;
    final choice = await pickGame(context, _data, profile);
    if (choice != null && mounted) {
      _log.debug('editor plays the map', fields: {'map': map.id});
      context.go(gameRoute(map.id, choice));
    }
  }

  Future<void> _clear() async {
    final ok = await confirm(
      context,
      title: _data.tr(context, 'ui.editor.clearTitle'),
      body: _data.tr(context, 'ui.editor.clearBody'),
      action: _data.tr(context, 'ui.editor.clear'),
    );
    if (ok && mounted) {
      _log.debug('editor cleared');
      _c.clear();
    }
  }

  Future<void> _leave() async {
    if (_c.dirty) {
      final leave = await confirm(
        context,
        title: _data.tr(context, 'ui.editor.leaveTitle'),
        body: _data.tr(context, 'editor.unsaved'),
        action: _data.tr(context, 'ui.editor.leave'),
        cancel: _data.tr(context, 'ui.editor.keepEditing'),
      );
      if (!leave || !mounted) return;
    }
    _log.debug('editor left', fields: {'unsaved': _c.dirty});
    context.go('/maps');
  }

  // ------------------------------------------------------------ keys

  /// Desktop shortcuts (`KeyboardManagerMapping`): 1 / 2 / 3 put the start,
  /// a waypoint (Shift+2: at the road's start) or the base at the cursor; arrows nudge the selected
  /// waypoint (Shift: faster); Backspace/Delete removes it; Ctrl/Cmd+Z undo,
  /// with Shift redo.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final rules = _data.world.editor;
    final step = keys.isShiftPressed ? rules.nudgeFast : rules.nudge;
    final k = e.logicalKey;
    final hover = _hover;
    if (keys.isControlPressed || keys.isMetaPressed) {
      if (k == LogicalKeyboardKey.keyZ) {
        keys.isShiftPressed ? _c.redo() : _c.undo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        _c.redo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (k) {
      case LogicalKeyboardKey.digit1 when hover != null:
        _c.placeStart(hover);
      case LogicalKeyboardKey.digit2 when hover != null:
        keys.isShiftPressed ? _c.insertWaypointAtStart(hover) : _c.addWaypoint(hover);
      case LogicalKeyboardKey.digit3 when hover != null:
        _c.placeBase(hover);
      case LogicalKeyboardKey.backspace || LogicalKeyboardKey.delete:
        _c.deleteSelected();
      case LogicalKeyboardKey.arrowLeft:
        _c.nudgeSelected(Vec2(-step, 0));
      case LogicalKeyboardKey.arrowRight:
        _c.nudgeSelected(Vec2(step, 0));
      case LogicalKeyboardKey.arrowUp:
        _c.nudgeSelected(Vec2(0, -step));
      case LogicalKeyboardKey.arrowDown:
        _c.nudgeSelected(Vec2(0, step));
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _build(context, box.biggest));

  Widget _build(BuildContext context, Size size) {
    final padding = MediaQuery.paddingOf(context);
    // Tall screens: the palette is a strip along the bottom and the map
    // fills the space upright, like a portrait game.
    final portrait = size.height > size.width;
    final bottomBar = portrait ? _stripHeight + padding.bottom : 0.0;
    final rightBar = portrait ? 0.0 : _railWidth + padding.right;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // The keyboard (map name) must not refit the map.
        resizeToAvoidBottomInset: false,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: EditorCanvas(
                  key: _canvas,
                  controller: _c,
                  pack: widget.pack,
                  armed: _armed,
                  insets: EdgeInsets.only(
                    top: _barHeight + padding.top,
                    right: rightBar,
                    bottom: bottomBar,
                  ),
                  fill: portrait,
                  onPlaced: () => setState(() => _armed = null),
                  onHover: (p) => _hover = p,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _topBar(compact: size.width < _compactBarBelow),
              ),
              if (portrait)
                Positioned(left: 0, right: 0, bottom: 0, child: _palette(Axis.horizontal))
              else
                Positioned(
                  top: _barHeight + padding.top,
                  right: 0,
                  bottom: 0,
                  child: _palette(Axis.vertical),
                ),
              Positioned(
                left: padding.left + 8,
                right: rightBar + (portrait ? padding.right : 0) + 8,
                bottom: (portrait ? bottomBar : padding.bottom) + 8,
                child: Center(child: _status()),
              ),
              if (_helpOpen)
                portrait
                    ? Positioned(
                        left: padding.left + 8,
                        right: padding.right + 8,
                        // Above the status pill.
                        bottom: bottomBar + 64,
                        child: _help(width: null),
                      )
                    : Positioned(
                        top: _barHeight + padding.top + 8,
                        left: padding.left + 8,
                        child: _help(),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  // The background runs to the screen's edges; only the controls keep clear
  // of a notch.
  Widget _bar({required List<Widget> children}) => Material(
    color: AppColours.backdropOverlay,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: _barHeight,
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Row(children: children),
        ),
      ),
    ),
  );

  Widget _topBar({bool compact = false}) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => _bar(
      children: [
        IconButton(
          tooltip: _data.tr(context, 'ui.common.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _leave,
        ),
        Expanded(
          child: Text(
            // The name, with a dot while there are unsaved changes.
            [
              if (_c.name.isEmpty) _data.tr(context, 'ui.editor.newMap') else _c.name,
              if (_c.dirty) '•',
            ].join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        IconButton(
          tooltip: _data.tr(context, 'ui.editor.undo'),
          icon: const Icon(Icons.undo),
          onPressed: _c.canUndo ? _c.undo : null,
          color: Colors.white,
          disabledColor: Colors.white24,
        ),
        IconButton(
          tooltip: _data.tr(context, 'ui.editor.redo'),
          icon: const Icon(Icons.redo),
          onPressed: _c.canRedo ? _c.redo : null,
          color: Colors.white,
          disabledColor: Colors.white24,
        ),
        if (compact)
          PopupMenuButton<VoidCallback>(
            tooltip: _data.tr(context, 'ui.editor.more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              for (final (icon, key, action) in [
                (Icons.fit_screen, 'ui.editor.fit', () => _canvas.currentState?.fit()),
                (
                  Icons.help_outline,
                  'ui.editor.help',
                  () => setState(() => _helpOpen = !_helpOpen),
                ),
                (Icons.share, 'ui.editor.share', _share),
              ])
                PopupMenuItem<VoidCallback>(
                  value: action,
                  child: ListTile(
                    leading: Icon(icon),
                    title: Text(_data.tr(context, key)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          )
        else ...[
          IconButton(
            tooltip: _data.tr(context, 'ui.editor.fit'),
            icon: const Icon(Icons.fit_screen),
            onPressed: () => _canvas.currentState?.fit(),
          ),
          IconButton(
            tooltip: _data.tr(context, 'ui.editor.help'),
            icon: const Icon(Icons.help_outline),
            onPressed: () => setState(() => _helpOpen = !_helpOpen),
          ),
        ],
        IconButton(
          tooltip: _data.tr(context, 'ui.common.save'),
          icon: const Icon(Icons.save),
          onPressed: _save,
        ),
        if (!compact)
          IconButton(
            tooltip: _data.tr(context, 'ui.editor.share'),
            icon: const Icon(Icons.share),
            onPressed: _share,
          ),
        if (compact)
          IconButton(
            tooltip: _data.tr(context, 'ui.menu.play'),
            icon: const Icon(Icons.play_arrow),
            color: Colors.amber,
            onPressed: _play,
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _play,
              icon: const Icon(Icons.play_arrow),
              label: Text(_data.tr(context, 'ui.menu.play')),
            ),
          ),
      ],
    ),
  );

  /// The palette and tools: a rail down the right in landscape, a
  /// scrolling strip along the bottom in portrait ([Axis.horizontal]).
  Widget _palette(Axis axis) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => Material(
      color: AppColours.backdropOverlay,
      child: SafeArea(
        left: axis == Axis.horizontal,
        top: false,
        child: SizedBox(
          width: axis == Axis.vertical ? _railWidth : null,
          height: axis == Axis.horizontal ? _stripHeight : null,
          child: SingleChildScrollView(
            scrollDirection: axis,
            padding: axis == Axis.vertical
                ? const EdgeInsets.symmetric(vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 6),
            child: Flex(
              direction: axis,
              children: [
                _paletteItem(
                  PaletteItem.start,
                  _data.tr(context, 'ui.editor.start'),
                  placed: _c.draft.start != null,
                ),
                _paletteItem(
                  PaletteItem.base,
                  _data.tr(context, 'ui.editor.base'),
                  placed: _c.draft.base != null,
                ),
                if (axis == Axis.vertical)
                  const Divider(color: Colors.white24, height: 12)
                else
                  const VerticalDivider(color: Colors.white24, width: 12),
                _railButton(
                  icon: _c.snap ? Icons.grid_on : Icons.grid_off,
                  label: _data.tr(context, 'ui.editor.grid'),
                  selected: _c.snap,
                  onPressed: _c.toggleSnap,
                ),
                _railButton(
                  icon: Icons.grid_goldenratio,
                  label: _data.tr(context, 'ui.editor.align'),
                  onPressed: _c.alignAll,
                ),
                _railButton(
                  icon: Icons.delete_outline,
                  label: _data.tr(context, 'ui.editor.delete'),
                  onPressed: _c.selected == null ? null : _c.deleteSelected,
                ),
                _railButton(
                  icon: Icons.layers_clear,
                  label: _data.tr(context, 'ui.editor.clear'),
                  onPressed: _clear,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _railButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    bool selected = false,
  }) {
    final color = onPressed == null ? Colors.white24 : (selected ? Colors.amber : Colors.white);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: _railWidth,
            height: 44,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                children: [
                  Icon(icon, color: color, size: 20),
                  Text(label, style: TextStyle(color: color, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A palette marker: drag it onto the map, or tap it and then the map.
  Widget _paletteItem(PaletteItem item, String label, {required bool placed}) {
    final armed = _armed == item;
    final icon = Icon(
      item == PaletteItem.start ? Icons.flag : Icons.home_work,
      color: item == PaletteItem.start ? const Color(0xFF66BB6A) : const Color(0xFFB0BEC5),
      size: 26,
    );
    final tile = Container(
      width: _railWidth - 12,
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: armed ? AppColours.panelActive : AppColours.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: armed ? Colors.amber : Colors.white24),
      ),
      padding: const EdgeInsets.all(3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            icon,
            Text(
              placed ? '$label ✓' : label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: armed,
      label: _data.tr(context, placed ? 'ui.editor.paletteOnMap' : 'ui.editor.palette', {
        'label': label,
      }),
      child: ExcludeSemantics(
        child: Draggable<PaletteItem>(
          data: item,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: Material(color: Colors.transparent, child: icon),
          ),
          onDragStarted: () => setState(() => _armed = null),
          child: GestureDetector(
            onTap: () => setState(() => _armed = armed ? null : item),
            child: tile,
          ),
        ),
      ),
    );
  }

  /// What to do next: the armed palette item, or why the map cannot be
  /// saved yet.
  Widget _status() => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final armed = _armed;
      final String? text;
      if (armed != null) {
        text = _data.tr(
          context,
          armed == PaletteItem.start ? 'ui.editor.placeStart' : 'ui.editor.placeBase',
        );
      } else if (_c.drag != null) {
        text = _c.drag!.valid ? null : _data.tr(context, 'ui.editor.dropToRemove');
      } else {
        final problems = _c.problems;
        text = problems.isEmpty ? null : problemText(context, problems.first, _data);
      }
      if (text == null) return const SizedBox.shrink();
      return Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: armed == null ? 16 : 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(text, style: const TextStyle(color: Colors.white)),
              ),
              if (armed != null)
                TextButton(
                  onPressed: () => setState(() => _armed = null),
                  child: Text(_data.tr(context, 'ui.common.cancel')),
                )
              else
                const SizedBox(height: 40),
            ],
          ),
        ),
      );
    },
  );

  /// The help pages (`MappingHelp`), one at a time.
  Widget _help({double? width = 300}) => Material(
    color: AppColours.backdropBar,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _data.tr(context, _helpKeys[_helpPage]),
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          Row(
            children: [
              Text(
                '${_helpPage + 1} / ${_helpKeys.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                tooltip: _data.tr(context, 'ui.editor.previousTip'),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: _helpPage == 0 ? null : () => setState(() => _helpPage--),
              ),
              IconButton(
                tooltip: _data.tr(context, 'ui.editor.nextTip'),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: _helpPage == _helpKeys.length - 1
                    ? null
                    : () => setState(() => _helpPage++),
              ),
              IconButton(
                tooltip: _data.tr(context, 'ui.editor.closeTips'),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _helpOpen = false),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
