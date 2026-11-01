import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../../app/strings.dart';
import '../colour_badges.dart';

/// The colour badge of turret [turretId] ([colourBadgeFor]), [size] across;
/// nothing for a turret that is not a colour. Decorative: the controls it
/// sits on already name the turret to assistive technology.
class ColourBadgeIcon extends StatelessWidget {
  const ColourBadgeIcon({super.key, required this.data, required this.turretId, this.size = 20});

  final GameData data;
  final String turretId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final locale = uiLocale(context);
    final badge = colourBadgeFor(data, turretId, locale: locale);
    if (badge == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _BadgePainter(badge, DefaultTextStyle.of(context).style.fontFamily),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.badge, this.fontFamily);

  final ColourBadge badge;
  final String? fontFamily;
  final TextPainter _text = TextPainter();

  @override
  void paint(Canvas canvas, Size size) => paintColourBadge(
    canvas,
    size.center(Offset.zero),
    size.shortestSide,
    badge,
    _text,
    fontFamily: fontFamily,
  );

  @override
  bool shouldRepaint(_BadgePainter old) => old.badge != badge || old.fontFamily != fontFamily;
}
