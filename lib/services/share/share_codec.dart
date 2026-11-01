import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A share string that cannot be read: wrong prefix or kind, damaged
/// text, or a payload that is not a JSON object. It carries why as a string
/// key ([key], `ui.share.*`) and its arguments ([args]), which the import
/// dialogs look up in the interface language.
class ShareCodecException implements Exception {
  const ShareCodecException(this.key, [this.args = const {}]);

  /// The reason's key in the string table.
  final String key;

  /// The reason's `{placeholder}` values.
  final Map<String, Object?> args;

  @override
  String toString() => 'ShareCodecException: $key${args.isEmpty ? '' : ' $args'}';
}

/// Encodes documents (maps, mods) as text that fits in a message or a
/// QR code (`docs/REMASTER_PLAN.md` §4): `ons3:<kind>:<base64url(gzip(json))>`,
/// without base64 padding. Decoding is forgiving about what a chat app does
/// to pasted text (whitespace and line breaks anywhere, padding added back,
/// the standard base64 alphabet) and strict about the rest. The payload's
/// own `schemaVersion` is the caller's to check and migrate.
class ShareCodec {
  const ShareCodec({this.maxBytes = 256 * 1024});

  static const String scheme = 'ons3';

  /// Kind of a shared map (`ons3:map:…`).
  static const String mapKind = 'map';

  /// Kind of a shared mod (`ons3:mod:…`).
  static const String modKind = 'mod';

  /// Largest decompressed payload accepted, in bytes (guards against a
  /// small string that inflates without limit).
  final int maxBytes;

  // gzip header fields that depend on the platform and the clock (MTIME,
  // bytes 4–7; OS, byte 9), fixed so one platform always writes the same
  // string for the same document.
  static const int _mtimeStart = 4;
  static const int _mtimeEnd = 8;
  static const int _osByte = 9;
  static const int _osUnknown = 255;

  String encode(String kind, Map<String, Object?> document) {
    final bytes = Uint8List.fromList(
      const GZipEncoder().encodeBytes(utf8.encode(jsonEncode(document))),
    );
    bytes.fillRange(_mtimeStart, _mtimeEnd, 0);
    bytes[_osByte] = _osUnknown;
    return '$scheme:$kind:${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  /// The kind of share string [text] claims to be (`map`, `mod`), or null
  /// when it is not one.
  String? kindOf(String text) {
    final parts = _compact(text).split(':');
    return parts.length == 3 && parts[0] == scheme && parts[1].isNotEmpty ? parts[1] : null;
  }

  /// The document in [text], which must be a share string of [kind].
  Map<String, Object?> decode(String kind, String text) {
    final compact = _compact(text);
    final head = '$scheme:$kind:';
    if (!compact.startsWith(head)) {
      final other = kindOf(compact);
      throw other == null
          ? const ShareCodecException('ui.share.notACode')
          : ShareCodecException('ui.share.wrongKind', {'other': other, 'kind': kind});
    }
    var body = compact.substring(head.length).replaceAll('+', '-').replaceAll('/', '_');
    body = body.replaceAll('=', '');
    body = body.padRight(body.length + (4 - body.length % 4) % 4, '=');
    final Uint8List zipped;
    try {
      zipped = base64Url.decode(body);
    } on FormatException {
      throw const ShareCodecException('ui.share.notBase64');
    }
    final out = OutputMemoryStream();
    final bool complete;
    try {
      complete = const GZipDecoder().decodeStream(
        InputMemoryStream(zipped),
        out,
        maxOutputSize: maxBytes,
      );
    } on Object {
      throw const ShareCodecException('ui.share.damaged');
    }
    if (!complete) throw const ShareCodecException('ui.share.incomplete');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(out.getBytes()));
    } on FormatException {
      throw const ShareCodecException('ui.share.notJson');
    }
    if (json is! Map) throw const ShareCodecException('ui.share.noDocument');
    return json.cast<String, Object?>();
  }

  static String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');
}
