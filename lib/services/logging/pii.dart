/// Personal data in logs: a value the caller knows is personal ([Pii]) and
/// the masking every log line goes through before it is written
/// ([PiiRedactor]). Logs must never hold personal data in the clear; what
/// is masked keeps its first and last characters and its length, so two
/// lines can still be told to be about the same thing.
library;

/// A value that is personal (a name the player typed, an address): its
/// [toString] is the masked text, so it can be put in a message or a field
/// as it is (`log.info('Saved ${Pii(map.name)}')`).
class Pii {
  const Pii(this.value);

  final Object? value;

  @override
  String toString() => PiiRedactor.mask('$value');
}

/// Masks personal data in text. Used by the log formatter on every message,
/// field, error and stack line; never throws.
abstract final class PiiRedactor {
  /// What a secret (a password, a token) is replaced with, whatever its
  /// length: nothing of it is kept.
  static const String secretMask = '********';

  /// [text] with its middle replaced by asterisks: the first and last
  /// characters stay when it is longer than 4, only the first when it is 3
  /// or 4, none when shorter.
  static String mask(String text) {
    final chars = text.runes.toList();
    final n = chars.length;
    if (n == 0) return '';
    if (n <= 2) return '*' * n;
    final first = String.fromCharCode(chars.first);
    if (n <= 4) return '$first${'*' * (n - 1)}';
    return '$first${'*' * (n - 2)}${String.fromCharCode(chars.last)}';
  }

  /// Words that make a field personal wherever they appear in its name
  /// (`email`, `userName`, `player_name`, `ip`, …).
  static const Set<String> _personalWords = {
    'email', 'mail', 'user', 'username', 'login', 'account', 'phone', 'mobile', 'address', //
    'ip', 'ssn', 'card', 'iban', 'name', 'device',
  };

  /// Words that make a field secret: nothing of its value is kept.
  static const Set<String> _secretWords = {
    'password', 'passwd', 'pwd', 'secret', 'token', 'auth', 'authorization', 'cookie', //
  };

  /// The lower-case words of a field name (`playerName` → `player`, `name`).
  static List<String> _words(String key) => key
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  static bool _isSecretKey(String key) {
    final words = _words(key);
    return words.any(_secretWords.contains) || words.join().contains('apikey');
  }

  /// Whether a field called [key] holds personal or secret data.
  static bool isSensitiveKey(String key) =>
      _isSecretKey(key) || _words(key).any(_personalWords.contains);

  /// A field's value as written: all of it hidden when [key] is secret,
  /// masked when it is personal, else redacted like a message.
  static String field(String key, Object? value) {
    final text = '$value';
    if (value is Pii) return text;
    if (_isSecretKey(key)) return secretMask;
    if (isSensitiveKey(key)) return mask(text);
    return redact(text);
  }

  static final List<(RegExp, String Function(Match))> _rules = [
    // `password=…`, `token: …`, `Bearer …`: the secret goes entirely.
    (
      RegExp(
        r'\b(bearer|token|access_token|refresh_token|api[_-]?key|apikey|secret|password|passwd|'
        r'pwd|authorization)\b(\s*[:=]\s*|\s+)((?:bearer|basic|token)\s+)?("?)([^\s"&,;]+)',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}${m[3] ?? ''}${m[4]}$secretMask',
    ),
    // e-mail addresses: the local part and the domain name, not the TLD.
    (
      RegExp(r'([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)\.([A-Za-z]{2,})'),
      (m) => '${mask(m[1]!)}@${mask(m[2]!)}.${m[3]}',
    ),
    // URL query values (`?q=…&name=…`).
    (RegExp(r'([?&][^=\s&#?]+=)([^&\s#]+)'), (m) => '${m[1]}${mask(m[2]!)}'),
    // A user's home folder in a path (macOS, Linux; Windows, where the
    // name may hold spaces and runs to the next separator).
    (RegExp(r'(/Users/|/home/)([^/\\\s:]+)'), (m) => '${m[1]}${mask(m[2]!)}'),
    (
      RegExp(r'([A-Za-z]:[\\/]Users[\\/])([^\\/:\r\n]+)', caseSensitive: false),
      (m) => '${m[1]}${mask(m[2]!)}',
    ),
    // Install and device identifiers in paths (iOS app containers,
    // simulators).
    (
      RegExp(
        r'(?<=[/\\])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}',
      ),
      (m) => mask(m[0]!),
    ),
    // IPv6 addresses and MAC addresses (five or more hex groups, or `::`).
    (
      RegExp(
        r'(?<![\w:])(?:[0-9A-Fa-f]{1,4}[:-]){5,7}[0-9A-Fa-f]{1,4}(?![\w:])|'
        r'(?<![\w:])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){0,6}::(?:[0-9A-Fa-f]{1,4}:?){1,7}(?![\w:])',
      ),
      (m) => _keepFirstGroup(m[0]!),
    ),
    // IPv4 addresses: the first number stays.
    (
      RegExp(r'(?<![\w.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\w.])'),
      (m) => '${m[1]}.${'*' * m[2]!.length}.${'*' * m[3]!.length}.${'*' * m[4]!.length}',
    ),
    // Card numbers (13–19 digits passing the Luhn check): the last four stay.
    (RegExp(r'(?<![\w.])\d(?:[ -]?\d){12,18}(?![\w.])'), (m) => _card(m[0]!)),
    // Phone numbers: international (`+49 170 1234567`, `+491701234567`) or
    // grouped (`(555) 123-4567`, `555-123-4567`): the last two digits stay.
    (
      RegExp(
        r'(?<![\w+])(?:\+\d{1,3}[\s.-]?(?:\(?\d{1,4}\)?[\s.-]?){1,4}\d{2,6}|'
        r'(?:\(\d{2,4}\)\s?|\d{3}[.-])\d{3}[.-]\d{4})(?![\w])',
      ),
      (m) => _keepLastDigits(m[0]!, 2),
    ),
  ];

  /// [text] with every piece of personal data the rules recognise masked:
  /// secrets after `password=`/`token:`/`Bearer`, e-mail addresses, URL
  /// query values, the user name in home-folder paths, install ids in paths,
  /// IP and MAC addresses, card numbers and phone numbers. Text it cannot
  /// process comes back as a placeholder, never in the clear.
  static String redact(String text) {
    try {
      var out = text;
      for (final (pattern, replace) in _rules) {
        out = out.replaceAllMapped(pattern, replace);
      }
      return out;
    } on Object {
      return '<redaction failed: ${text.length} characters withheld>';
    }
  }

  static String _keepFirstGroup(String address) {
    final i = address.indexOf(RegExp('[:-]'));
    final head = i < 0 ? '' : address.substring(0, i + 1);
    return head + address.substring(head.length).replaceAll(RegExp('[0-9A-Fa-f]'), '*');
  }

  static String _card(String digits) {
    final only = digits.replaceAll(RegExp(r'\D'), '');
    if (!_luhn(only)) return digits;
    return _keepLastDigits(digits, 4);
  }

  static String _keepLastDigits(String text, int keep) {
    final total = RegExp(r'\d').allMatches(text).length;
    var seen = 0;
    return text.replaceAllMapped(RegExp(r'\d'), (m) => ++seen > total - keep ? m[0]! : '*');
  }

  static bool _luhn(String digits) {
    var sum = 0;
    var double = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (double) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      double = !double;
    }
    return sum % 10 == 0;
  }
}
