import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../../../app/theme.dart';

/// Finds a tutorial pointer target (`tutorial.json` `pointer`, e.g.
/// `WaveClock`, `RoadManager.Waypoint1`) on screen: a rect in global
/// coordinates, or null when it is not showing.
typedef TutorialTargetResolver = Rect? Function(String pointer);

/// The tutorial window (`GameTutorial`): page title and text, Prev / Show me
/// / Next and a close button that leaves for the main menu. "Show me" blinks
/// an arrow at the page's target (`TutorialShow`: visible, then toggled
/// every 400 ms, 7 times) and runs the page's action (the one-off cash);
/// pages marked `showNow` do it as they open. Fills its overlay; only the
/// window itself takes touches. Its own labels come from the unmodded data
/// (`gameDataProvider`).
class TutorialPanel extends ConsumerStatefulWidget {
  const TutorialPanel({
    super.key,
    required this.pages,
    required this.resolve,
    required this.onShow,
    required this.onClose,
    this.top = 0,
    this.window,
  });

  final List<TutorialPage> pages;
  final TutorialTargetResolver resolve;

  /// "Show me" on page [page] (0-based): the game runs its action.
  final ValueChanged<int> onShow;
  final VoidCallback onClose;

  /// Space to leave above the window (the top bar), when [window] is null.
  final double top;

  /// The area the window may fill (the HUD layout's tutorial window): it
  /// sits at the area's top left, the area's width, and grows down to its
  /// height. Null: [widthFor] wide at the top left below [top].
  final Rect? window;

  /// The arrow's blink: toggled every [blinkStep], [blinkToggles] times.
  static const Duration blinkStep = Duration(milliseconds: 400);
  static const int blinkToggles = 7;

  /// The window's width on a screen of [size] (other overlays keep clear
  /// of it).
  static double widthFor(Size size) => math.min(320, size.width * 0.42);

  /// Pointer ids that name the window's own buttons.
  static const String showButton = 'ButtonShow';
  static const String closeButton = 'CloseButton';

  @override
  ConsumerState<TutorialPanel> createState() => _TutorialPanelState();
}

class _TutorialPanelState extends ConsumerState<TutorialPanel> with SingleTickerProviderStateMixin {
  final GlobalKey _window = GlobalKey();
  final GlobalKey _show = GlobalKey();
  final GlobalKey _close = GlobalKey();
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: TutorialPanel.blinkStep * (TutorialPanel.blinkToggles + 1),
  );
  int _page = 0;
  String? _pointer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _opened());
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  TutorialPage get _current => widget.pages[_page];

  void _go(int page) {
    if (page < 0 || page >= widget.pages.length) return;
    setState(() {
      _page = page;
      _pointer = null;
      _blink.reset();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _opened());
  }

  void _opened() {
    if (mounted && _current.showNow) _showMe();
  }

  void _showMe() {
    widget.onShow(_page);
    setState(() => _pointer = _current.pointer);
    _blink.forward(from: 0);
  }

  Rect? _target(String pointer) {
    Rect? own(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    return switch (pointer) {
      TutorialPanel.showButton => own(_show),
      TutorialPanel.closeButton => own(_close),
      _ => widget.resolve(pointer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _current;
    final last = _page == widget.pages.length - 1;
    final size = MediaQuery.sizeOf(context);
    final area =
        widget.window ??
        Rect.fromLTWH(
          8,
          widget.top + 8,
          TutorialPanel.widthFor(size),
          math.max(160, size.height - widget.top - 24),
        );
    return Stack(
      children: [
        Positioned(
          left: area.left,
          top: area.top,
          width: area.width,
          child: Material(
            key: _window,
            color: HudColours.tutorialPanel,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: area.height),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: Colors.black38,
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ref.tr(context, 'ui.tutorial.page', {
                              'page': _page + 1,
                              'pages': widget.pages.length,
                            }),
                            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
                          ),
                        ),
                        IconButton(
                          key: _close,
                          tooltip: ref.tr(context, 'ui.tutorial.close'),
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      page.title,
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        page.body,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: ref.tr(context, 'ui.tutorial.previous'),
                          color: Colors.white,
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _page == 0 ? null : () => _go(_page - 1),
                        ),
                        Expanded(
                          child: Center(
                            child: FilledButton.tonal(
                              key: _show,
                              onPressed: page.pointer == null ? null : _showMe,
                              child: Text(ref.tr(context, 'ui.tutorial.show')),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: ref.tr(context, 'ui.tutorial.next'),
                          color: Colors.white,
                          icon: const Icon(Icons.chevron_right),
                          onPressed: last ? null : () => _go(_page + 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_pointer case final pointer?)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _blink,
                builder: (context, _) {
                  final step = (_blink.value * (TutorialPanel.blinkToggles + 1)).floor();
                  final visible = _blink.isAnimating && step.isEven;
                  final box = context.findRenderObject() as RenderBox?;
                  final target = _target(pointer);
                  final window = _target(TutorialPanel.showButton);
                  if (!visible || box == null || !box.hasSize || target == null) {
                    return const SizedBox.expand();
                  }
                  final local = box.globalToLocal(target.center);
                  final from = window == null ? Offset.zero : box.globalToLocal(window.center);
                  return CustomPaint(
                    painter: _ArrowPainter(tip: local, from: from),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// A fat arrow whose tip is at [tip], pointing along the line from [from].
class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.tip, required this.from});

  final Offset tip;
  final Offset from;

  static const double _length = 46;
  static const double _head = 18;
  static const double _shaft = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final d = tip - from;
    final angle = d.distance < 1 ? -math.pi / 2 : math.atan2(d.dy, d.dx);
    canvas
      ..save()
      ..translate(tip.dx, tip.dy)
      ..rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(-_head, -_head)
      ..lineTo(-_head, -_shaft)
      ..lineTo(-_length, -_shaft)
      ..lineTo(-_length, _shaft)
      ..lineTo(-_head, _shaft)
      ..lineTo(-_head, _head)
      ..close();
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      )
      ..drawPath(path, Paint()..color = HudColours.tutorialArrow)
      ..restore();
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.tip != tip || old.from != from;
}
