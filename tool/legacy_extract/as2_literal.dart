/// A tiny reader for the literal subset of ActionScript 2 that the original
/// game uses to declare its data: numbers, strings, booleans, `undefined`,
/// `{k: v}` / `new Object({k: v})`, `[a, b]` / `new Array(a, b)`, and dotted
/// identifiers (returned as [As2Ref]).
///
/// It reads values out of the legacy source; no legacy code is copied or run.
library;

/// A reference to a named value (e.g. `mods.ModDefaults.MOD_NUMBER`,
/// `this.ButtonShow`, `_root.Cash`), kept as its dotted name.
class As2Ref {
  const As2Ref(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is As2Ref && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'As2Ref($name)';
}

/// The AS2 `undefined` value.
class As2Undefined {
  const As2Undefined._();
  static const As2Undefined instance = As2Undefined._();

  @override
  String toString() => 'undefined';
}

/// Thrown when the source does not contain the expected literal.
class As2ParseException implements Exception {
  As2ParseException(this.message, this.source, this.offset);
  final String message;
  final String source;
  final int offset;

  @override
  String toString() {
    final start = (offset - 30).clamp(0, source.length);
    final end = (offset + 30).clamp(0, source.length);
    return 'As2ParseException: $message at $offset near '
        '"${source.substring(start, end)}"';
  }
}

/// Parses a single literal from [source] (surrounding whitespace allowed).
Object? parseAs2Literal(String source) {
  final p = _Parser(source);
  final v = p.value();
  p.skipWs();
  if (!p.atEnd) p.fail('unexpected trailing input');
  return v;
}

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;

  Never fail(String msg) => throw As2ParseException(msg, s, i);

  void skipWs() {
    while (!atEnd && ' \t\r\n'.contains(s[i])) {
      i++;
    }
  }

  bool _peekWord(String w) =>
      s.startsWith(w, i) && (i + w.length >= s.length || !_isIdent(s[i + w.length]));

  void expect(String c) {
    skipWs();
    if (!s.startsWith(c, i)) fail('expected "$c"');
    i += c.length;
  }

  Object? value() {
    skipWs();
    if (atEnd) fail('unexpected end');
    final c = s[i];
    if (c == '"' || c == "'") return string();
    if (c == '{') return object();
    if (c == '[') return array(']');
    if (c == '-' || c == '.' || _isDigit(c)) return number();
    if (_peekWord('new')) {
      i += 3;
      skipWs();
      final ctor = identPath();
      expect('(');
      skipWs();
      if (ctor == 'Object') {
        if (s[i] == ')') {
          i++;
          return <String, Object?>{};
        }
        final o = value();
        expect(')');
        return o;
      }
      if (ctor == 'Array') return array(')');
      // Any other constructor (e.g. `new ComboData()`): an empty record.
      expect(')');
      return <String, Object?>{};
    }
    if (_peekWord('true')) {
      i += 4;
      return true;
    }
    if (_peekWord('false')) {
      i += 5;
      return false;
    }
    if (_peekWord('undefined') || _peekWord('null')) {
      i += s.startsWith('undefined', i) ? 9 : 4;
      return As2Undefined.instance;
    }
    if (_isIdentStart(c)) return As2Ref(identPath());
    fail('unexpected character "$c"');
  }

  String identPath() {
    skipWs();
    final start = i;
    while (!atEnd && (_isIdent(s[i]) || s[i] == '.')) {
      i++;
    }
    if (start == i) fail('expected an identifier');
    return s.substring(start, i);
  }

  String string() {
    final q = s[i++];
    final b = StringBuffer();
    while (true) {
      if (atEnd) fail('unterminated string');
      final c = s[i++];
      if (c == q) break;
      if (c == r'\') {
        if (atEnd) fail('unterminated escape');
        final e = s[i++];
        b.write(switch (e) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => e,
        });
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  num number() {
    final start = i;
    if (s[i] == '-') i++;
    while (!atEnd && (_isDigit(s[i]) || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) {
      i++;
    }
    final text = s.substring(start, i);
    final n = num.tryParse(text);
    if (n == null) fail('bad number "$text"');
    return n;
  }

  Map<String, Object?> object() {
    expect('{');
    final out = <String, Object?>{};
    skipWs();
    if (s[i] == '}') {
      i++;
      return out;
    }
    while (true) {
      skipWs();
      final key = (s[i] == '"' || s[i] == "'") ? string() : identPath();
      expect(':');
      out[key] = value();
      skipWs();
      if (s[i] == ',') {
        i++;
        continue;
      }
      expect('}');
      return out;
    }
  }

  List<Object?> array(String close) {
    if (close == ']') expect('[');
    final out = <Object?>[];
    skipWs();
    if (s.startsWith(close, i)) {
      i++;
      return out;
    }
    while (true) {
      out.add(value());
      skipWs();
      if (s[i] == ',') {
        i++;
        continue;
      }
      expect(close);
      return out;
    }
  }
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isIdentStart(String c) => RegExp(r'[A-Za-z_$]').hasMatch(c);
bool _isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

/// One `target = value;` statement found in a block of AS2 source.
class As2Assignment {
  const As2Assignment(this.target, this.valueSource, this.line);

  /// Left-hand side, e.g. `this.TurretBlue.turret_cost` or `_loc2_.title`.
  final String target;

  /// Right-hand side source text (not yet parsed).
  final String valueSource;

  /// 1-based line number in the scanned text.
  final int line;

  Object? get value => parseAs2Literal(valueSource);
}

final _assign = RegExp(r'^\s*([A-Za-z_$][\w$]*(?:\.[\w$]+|\[[^\]]+\])*)\s*=\s*(.+);\s*$');

/// Scans [source] line by line for simple assignments. Statements in the
/// legacy export are one per line, which keeps this reliable.
Iterable<As2Assignment> scanAssignments(String source) sync* {
  final lines = source.split('\n');
  for (var n = 0; n < lines.length; n++) {
    final m = _assign.firstMatch(lines[n]);
    if (m == null) continue;
    final target = m.group(1)!;
    if (target.startsWith('var ')) continue;
    yield As2Assignment(target, m.group(2)!, n + 1);
  }
}

/// The body of `function name(...) { ... }` in [source], by brace matching.
String functionBody(String source, String name) {
  final m = RegExp('function\\s+$name\\s*\\(').firstMatch(source);
  if (m == null) throw StateError('function $name not found');
  final open = source.indexOf('{', m.end);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  throw StateError('unbalanced braces in function $name');
}
