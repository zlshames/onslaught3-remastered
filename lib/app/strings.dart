import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/persistence/mod_library.dart';
import 'providers.dart';

/// The interface language at [context]: the locale the app resolved (the
/// player's choice, else the device's language when the data has it, else
/// English), as a `strings/<locale>.json` code.
String uiLocale(BuildContext context) => Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

/// The game's text in the interface language (localisation hook): every
/// string the player reads comes from `strings/<locale>.json` through
/// here, falling back to English and then to the key itself.
extension GameText on GameData {
  /// The string [key] in [context]'s language with each `{name}` in [args]
  /// filled in.
  String tr(BuildContext context, String key, [Map<String, Object?> args = const {}]) =>
      fill(text(key, locale: uiLocale(context)), args);

  /// A mod's [name] as shown: the name a new mod is saved with
  /// ([ModLibrary.defaultName]) in [context]'s language, any other as given.
  String modName(BuildContext context, String name) =>
      name == ModLibrary.defaultName ? tr(context, 'ui.mods.defaultName') : name;

  /// The mod value [field]'s descriptor text in [context]'s language.
  ModDescriptorText modText(BuildContext context, ModField field) =>
      _modText(uiLocale(context), field, field.descriptor, null);

  /// The same for its entries' `key` or `value` [part], or null when the
  /// descriptor has none.
  ModDescriptorText? modPartText(BuildContext context, ModField field, String part) {
    final d = part == 'key' ? field.descriptor.key : field.descriptor.value;
    return d == null ? null : _modText(uiLocale(context), field, d, part);
  }

  ModDescriptorText _modText(String locale, ModField field, ValueDescriptor d, String? part) {
    String text(String attribute, String own) =>
        descriptorText(field.def.asset, attribute, own, part: part, locale: locale);
    final unit = d.unit;
    return (
      title: text('title', d.title),
      description: text('description', d.description),
      unit: unit == null ? null : text('unit', unit),
    );
  }
}

/// A mod value descriptor's words ([ValueDescriptor]) in one language.
typedef ModDescriptorText = ({String title, String description, String? unit});

/// The same lookup for widgets that sit above the loaded data (a menu's
/// frame, the home screen): reads the unmodded data from [gameDataProvider]
/// while building, and is empty until it has loaded.
extension RefText on WidgetRef {
  /// [GameText.tr] over the loaded data, or `''` while it loads.
  String tr(BuildContext context, String key, [Map<String, Object?> args = const {}]) =>
      watch(gameDataProvider).value?.tr(context, key, args) ?? '';
}

/// [template] with each `{name}` replaced by `args[name]`.
String fill(String template, Map<String, Object?> args) {
  var out = template;
  args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

/// The locales the data has text for, English first.
List<Locale> supportedLocalesOf(GameData? data) {
  final codes = {'en', ...?data?.strings.keys};
  return [for (final c in codes) Locale(c)];
}
