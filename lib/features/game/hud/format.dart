/// Number formats shared by the HUD widgets.
library;

/// `12`, `2.5`: whole numbers without a decimal, others with one.
String plainNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// `3.5M`, `12k`, `950`: big amounts in a few characters.
String shortNumber(double v) {
  String trim(double x) => x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (v.abs() >= 1e6) return '${trim(v / 1e6)}M';
  if (v.abs() >= 1e3) return '${trim(v / 1e3)}k';
  return plainNumber(v.roundToDouble());
}
