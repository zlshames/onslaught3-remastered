import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/share/share_codec.dart';

/// Share strings (`docs/REMASTER_PLAN.md` §4, §8.11): property tests over
/// random documents plus the tolerance and rejection rules.
void main() {
  const codec = ShareCodec();

  late final Map<String, Object?> Function(Random r, [int depth]) randomDoc;

  // A random JSON document: nested maps and lists of numbers, strings
  // (including non-ASCII), booleans and nulls.
  Object? randomJson(Random r, int depth) {
    switch (r.nextInt(depth > 2 ? 4 : 6)) {
      case 0:
        return r.nextInt(1 << 31) - (1 << 30);
      case 1:
        return (r.nextDouble() * 2000 - 1000).roundToDouble() / 4;
      case 2:
        const alphabet = 'abcXYZ 09_-:/+=éß→🙂"\\\n';
        final runes = alphabet.runes.toList();
        return String.fromCharCodes([
          for (var i = 0; i < r.nextInt(20); i++) runes[r.nextInt(runes.length)],
        ]);
      case 3:
        return r.nextBool() ? r.nextBool() : null;
      case 4:
        return [for (var i = 0; i < r.nextInt(6); i++) randomJson(r, depth + 1)];
      default:
        return randomDoc(r, depth + 1);
    }
  }

  randomDoc = (r, [depth = 0]) => {
    for (var i = 0; i < r.nextInt(6); i++) 'k$i${r.nextInt(99)}': randomJson(r, depth),
  };

  test('property: decode(encode(doc)) == doc for 300 random documents', () {
    final r = Random(20261018);
    for (var i = 0; i < 300; i++) {
      final doc = randomDoc(r);
      final text = codec.encode('map', doc);
      expect(text, startsWith('ons3:map:'));
      expect(text, isNot(contains('=')), reason: 'no padding');
      expect(RegExp(r'^ons3:map:[A-Za-z0-9_-]*$').hasMatch(text), isTrue, reason: text);
      expect(jsonEncode(codec.decode('map', text)), jsonEncode(doc), reason: 'doc $i');
    }
  });

  test('property: encoding is deterministic', () {
    final r = Random(7);
    for (var i = 0; i < 50; i++) {
      final doc = randomDoc(r);
      expect(codec.encode('map', doc), codec.encode('map', doc));
    }
  });

  test('pasted text: whitespace, line breaks, padding and the standard alphabet are accepted', () {
    final doc = {'name': 'Loop?>>~~ ', 'n': List.generate(40, (i) => i * 3.5)};
    final text = codec.encode('map', doc);
    final body = text.substring('ons3:map:'.length);
    final wrapped =
        '  ons3:map:\n${[for (var i = 0; i < body.length; i += 20) body.substring(i, min(i + 20, body.length))].join('\n ')}\t';
    expect(codec.decode('map', wrapped), doc);
    final padded = text + '=' * ((4 - body.length % 4) % 4);
    expect(codec.decode('map', padded), doc);
    final standard = text.replaceAll('-', '+').replaceAll('_', '/');
    expect(codec.decode('map', standard), doc);
  });

  test('kindOf names the kind of a share string', () {
    expect(codec.kindOf(codec.encode('mod', const {})), 'mod');
    expect(codec.kindOf(' ons3:map:abc '), 'map');
    expect(codec.kindOf('hello'), isNull);
    expect(codec.kindOf('ons3::abc'), isNull);
  });

  group('rejects', () {
    Matcher fails(String key, [Map<String, Object?> args = const {}]) => throwsA(
      isA<ShareCodecException>()
          .having((e) => e.key, 'key', key)
          .having((e) => e.args, 'args', args),
    );

    test('text that is not a share code', () {
      expect(() => codec.decode('map', 'hello world'), fails('ui.share.notACode'));
    });

    test('a code of another kind', () {
      final mod = codec.encode('mod', const {'a': 1});
      expect(
        () => codec.decode('map', mod),
        fails('ui.share.wrongKind', {'other': 'mod', 'kind': 'map'}),
      );
    });

    test('damaged base64', () {
      expect(() => codec.decode('map', 'ons3:map:@@@@'), fails('ui.share.notBase64'));
    });

    test('a truncated or corrupted payload', () {
      final text = codec.encode('map', {'road': List.generate(50, (i) => i)});
      expect(
        () => codec.decode('map', text.substring(0, text.length - 12)),
        throwsA(isA<ShareCodecException>()),
      );
      expect(
        () => codec.decode('map', 'ons3:map:${base64Url.encode(utf8.encode('plain'))}'),
        throwsA(isA<ShareCodecException>()),
      );
    });

    test('a payload that is not a JSON object', () {
      String raw(String json) =>
          'ons3:map:${base64Url.encode(const GZipEncoder().encodeBytes(utf8.encode(json)))}';
      expect(() => codec.decode('map', raw('[1, 2]')), fails('ui.share.noDocument'));
      expect(() => codec.decode('map', raw('{"a":')), fails('ui.share.notJson'));
    });

    test('a payload that inflates past the size limit', () {
      const small = ShareCodec(maxBytes: 1024);
      final big = codec.encode('map', {'pad': 'x' * 5000});
      expect(big.length, lessThan(200), reason: 'compresses well');
      expect(() => small.decode('map', big), fails('ui.share.damaged'));
    });
  });
}
