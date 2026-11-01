import 'game_data.dart';
import 'map_definition.dart';
import 'tutorial_defs.dart';

/// The string-table keys of the player-facing text that lives in the data
/// documents (names, challenge pickers, the tutorial, the mod editor). The
/// generator writes each one's English into `strings/en.json`, copied from
/// the document, so translations can override it; [DataText] reads them.
abstract final class DataTextKeys {
  /// `turret.blue.name`.
  static String turret(String id) => 'turret.$id.name';

  /// `combo.nuke.name`.
  static String combo(String id) => 'combo.$id.name';

  /// `map.map1.name` (built-in maps only; a player's map keeps its name).
  static String map(String id) => 'map.$id.name';

  /// `challenge.warmup.name`.
  static String challenge(String id) => 'challenge.$id.name';

  /// `challenge.picker.cash.one-meelion-dollars`: keyed by the English
  /// label, so the original's mislabelled options (`classicPickers`) share
  /// the keys of the labels they show.
  static String picker(String picker, String label) => 'challenge.picker.$picker.${slug(label)}';

  /// `tutorial.page.0.title` (pages counted from 0).
  static String tutorialTitle(int page) => 'tutorial.page.$page.title';

  /// `tutorial.page.0.body`.
  static String tutorialBody(int page) => 'tutorial.page.$page.body';

  /// `mods.item.TurretBlue`.
  static String modItem(String id) => 'mods.item.$id';

  /// `descriptor.weapon_damage.title`; an indexed value's entry parts are
  /// `descriptor.upgrade_damage.key.title` and `….value.unit`.
  static String descriptor(String asset, String attribute, {String? part}) =>
      'descriptor.$asset.${part == null ? '' : '$part.'}$attribute';

  /// `One Meelion Dollars!` → `one-meelion-dollars`; `$30` → `30`.
  static String slug(String label) =>
      label.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}

/// The data's own text in a locale: the [DataTextKeys] string in [locale],
/// else English, else the document's text (a key the tables lack, such as a
/// test's data or a future document field).
extension DataText on GameData {
  /// [key] in [locale], falling back to English, then to [fallback].
  String textOr(String key, String fallback, {String locale = 'en'}) =>
      strings[locale]?.strings[key] ?? strings['en']?.strings[key] ?? fallback;

  /// The turret [id]'s name.
  String turretName(String id, {String locale = 'en'}) =>
      textOr(DataTextKeys.turret(id), turrets[id]?.name ?? id, locale: locale);

  /// The combo recipe [id]'s name.
  String comboName(String id, {String locale = 'en'}) =>
      textOr(DataTextKeys.combo(id), combos[id]?.name ?? id, locale: locale);

  /// [map]'s name: a built-in map's from the tables, a player's as given.
  String mapName(MapDefinition map, {String locale = 'en'}) =>
      map.builtIn ? textOr(DataTextKeys.map(map.id), map.name, locale: locale) : map.name;

  /// The challenge preset [id]'s name ([fallback] when it is not a preset).
  String challengeName(String id, String fallback, {String locale = 'en'}) =>
      textOr(DataTextKeys.challenge(id), fallback, locale: locale);

  /// A challenge [picker]'s option [label].
  String pickerLabel(String picker, String label, {String locale = 'en'}) =>
      textOr(DataTextKeys.picker(picker, label), label, locale: locale);

  /// Tutorial page [page]'s title.
  String tutorialTitle(int page, {String locale = 'en'}) =>
      textOr(DataTextKeys.tutorialTitle(page), tutorial.pages[page].title, locale: locale);

  /// Tutorial page [page]'s text.
  String tutorialBody(int page, {String locale = 'en'}) =>
      textOr(DataTextKeys.tutorialBody(page), tutorial.pages[page].body, locale: locale);

  /// The tutorial's pages with their titles and text in [locale].
  List<TutorialPage> tutorialPages({String locale = 'en'}) => [
    for (final (i, p) in tutorial.pages.indexed)
      TutorialPage(
        title: tutorialTitle(i, locale: locale),
        body: tutorialBody(i, locale: locale),
        pointer: p.pointer,
        setCash: p.setCash,
        showNow: p.showNow,
      ),
  ];

  /// The mod editor item [id]'s title (`Turret: Blue Cannon`).
  String modItemTitle(String id, {String locale = 'en'}) =>
      textOr(DataTextKeys.modItem(id), modEditor.item(id)?.title ?? id, locale: locale);

  /// The mod value [asset]'s descriptor [attribute] (`title`,
  /// `description`, `unit`), or that of its entries' [part] (`key`,
  /// `value`); [fallback] is the descriptor's own text.
  String descriptorText(
    String asset,
    String attribute,
    String fallback, {
    String? part,
    String locale = 'en',
  }) => textOr(DataTextKeys.descriptor(asset, attribute, part: part), fallback, locale: locale);
}
