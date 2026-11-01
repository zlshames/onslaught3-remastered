import '../rules_registry.dart';

/// A turret special with no rules of its own: the turret aims and fires its
/// weapon like any other. Its parameters are for the views (the Sniper's
/// brass casings) or name the turret's mechanics in data (the Railgun's
/// piercing beam is its projectile kind, `rail`).
class PlainSpecial extends TurretSpecial {
  const PlainSpecial(this.id, {this.paramKeys = const {}});

  @override
  final String id;

  @override
  final Set<String>? paramKeys;
}
