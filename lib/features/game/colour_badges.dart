import 'package:flutter/widgets.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/theme.dart';

/// The shape of a colour badge (`TurretArt.badgeShapes`, by name).
enum BadgeShape { circle, triangle, square, diamond }

final Map<String, BadgeShape> _shapes = BadgeShape.values.asNameMap();

/// A colour-blind-safe mark for a colour turret: a shape and a letter, drawn
/// in black on white so it reads without colour vision (a remaster
/// accessibility addition, `docs/REMASTER_PLAN.md` §7). Combos are recipes
/// of colours, so telling the four apart matters on the map, in the tray
/// and in the sheet.
@immutable
class ColourBadge {
  const ColourBadge({required this.shape, required this.letter});

  final BadgeShape shape;
  final String letter;

  @override
  bool operator ==(Object other) =>
      other is ColourBadge && other.shape == shape && other.letter == letter;

  @override
  int get hashCode => Object.hash(shape, letter);
}

/// The badge of turret [turretId], or null for turrets that are not a colour
/// (modifiers, supers, utilities). The shape is the turret's
/// `art.badgeShape` (a circle when it names none, e.g. a colour a content
/// pack adds); the letter is the `badge.<id>` string in [locale], else the
/// first letter of the turret's name.
ColourBadge? colourBadgeFor(GameData data, String turretId, {String locale = 'en'}) {
  final def = data.turrets[turretId];
  if (def == null || def.category != TurretCategory.basic) return null;
  return ColourBadge(
    shape: _shapes[def.art.badgeShape] ?? BadgeShape.circle,
    letter: colourLetter(data, turretId, locale: locale),
  );
}

/// The one-letter name of colour [turretId] (`badge.<id>`, else its name's
/// first letter), as on its badge and in combo partner lists.
String colourLetter(GameData data, String turretId, {String locale = 'en'}) {
  final key = 'badge.$turretId';
  final text = data.text(key, locale: locale);
  if (text != key) return text;
  final name = data.turretName(turretId, locale: locale);
  return name.isEmpty ? '?' : name.characters.first.toUpperCase();
}

final Paint _fill = Paint()..color = HudColours.badgeFill;
final Paint _edge = Paint()
  ..color = HudColours.badgeInk
  ..style = PaintingStyle.stroke;

/// Paints [badge] centred on [centre], [size] across, onto [canvas]. [text]
/// is a painter the caller keeps between frames (laid out here); the letter
/// is set in [fontFamily] (the platform's default when null).
void paintColourBadge(
  Canvas canvas,
  Offset centre,
  double size,
  ColourBadge badge,
  TextPainter text, {
  String? fontFamily,
}) {
  final r = size / 2;
  _edge.strokeWidth = size / 12;
  final path = switch (badge.shape) {
    BadgeShape.circle => Path()..addOval(Rect.fromCircle(center: centre, radius: r * 0.9)),
    BadgeShape.square => Path()..addRect(Rect.fromCircle(center: centre, radius: r * 0.8)),
    BadgeShape.triangle =>
      Path()
        ..moveTo(centre.dx, centre.dy - r)
        ..lineTo(centre.dx + r, centre.dy + r * 0.8)
        ..lineTo(centre.dx - r, centre.dy + r * 0.8)
        ..close(),
    BadgeShape.diamond =>
      Path()
        ..moveTo(centre.dx, centre.dy - r)
        ..lineTo(centre.dx + r, centre.dy)
        ..lineTo(centre.dx, centre.dy + r)
        ..lineTo(centre.dx - r, centre.dy)
        ..close(),
  };
  canvas
    ..drawPath(path, _fill)
    ..drawPath(path, _edge);
  // The triangle's middle sits low, so its letter does too.
  final letterSize = badge.shape == BadgeShape.circle || badge.shape == BadgeShape.square
      ? size * 0.62
      : size * 0.5;
  text
    ..text = TextSpan(
      text: badge.letter,
      style: TextStyle(
        fontFamily: fontFamily,
        color: HudColours.badgeInk,
        fontSize: letterSize,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    )
    ..textDirection = TextDirection.ltr
    ..layout();
  final dy = badge.shape == BadgeShape.triangle ? r * 0.2 : 0;
  text.paint(canvas, centre - Offset(text.width / 2, text.height / 2 - dy));
}
