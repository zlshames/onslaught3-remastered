import 'package:meta/meta.dart';

import 'json_reader.dart';

/// An editor descriptor for one value (`mods.ModLibraryItem`): title,
/// description and the bounds the original mod editor enforced.
@immutable
class ValueDescriptor {
  const ValueDescriptor({
    required this.title,
    required this.description,
    this.type,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.keyField,
    this.valueField,
    this.key,
    this.value,
  });

  factory ValueDescriptor.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'title',
      'description',
      'type',
      'min',
      'max',
      'step',
      'unit',
      'keyField',
      'valueField',
      'key',
      'value',
    });
    return ValueDescriptor(
      title: r.string('title'),
      description: r.string('description'),
      type: r.optString('type'),
      min: r.optNumber('min'),
      max: r.optNumber('max'),
      step: r.optNumber('step'),
      unit: r.optString('unit'),
      keyField: r.optString('keyField'),
      valueField: r.optString('valueField'),
      key: r.optChild('key', ValueDescriptor.fromJson),
      value: r.optChild('value', ValueDescriptor.fromJson),
    );
  }

  final String title;
  final String description;

  /// number, integer, boolean, string or arrayIndexed.
  final String? type;
  final double? min;
  final double? max;
  final double? step;
  final String? unit;

  /// For indexed arrays: the parallel key/value field names and descriptors.
  final String? keyField;
  final String? valueField;
  final ValueDescriptor? key;
  final ValueDescriptor? value;

  /// Whether [v] lies inside [min]/[max].
  bool accepts(num v) => (min == null || v >= min!) && (max == null || v <= max!);

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'type': ?type,
    'min': ?optJsonNumber(min),
    'max': ?optJsonNumber(max),
    'step': ?optJsonNumber(step),
    'unit': ?unit,
    'keyField': ?keyField,
    'valueField': ?valueField,
    'key': ?key?.toJson(),
    'value': ?value?.toJson(),
  };
}

/// `descriptors.json`: original mod-editor descriptors by legacy asset name.
@immutable
class DescriptorDefs {
  const DescriptorDefs(this.byAsset);

  factory DescriptorDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'descriptors'});
    return DescriptorDefs(r.mapOf('descriptors', ValueDescriptor.fromJson));
  }

  static const int schemaVersion = 1;
  final Map<String, ValueDescriptor> byAsset;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'descriptors': {for (final e in byAsset.entries) e.key: e.value.toJson()},
  };
}
