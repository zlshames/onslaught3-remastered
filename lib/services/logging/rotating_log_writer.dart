import 'log_store.dart';

/// How big and how old the log files may get.
class LogFilePolicy {
  const LogFilePolicy({
    this.maxFileBytes = 1024 * 1024,
    this.maxFiles = 5,
    this.maxAge = const Duration(days: 14),
  }) : assert(maxFiles >= 1);

  /// The policy for the web, where the files are kept in memory.
  const LogFilePolicy.memory() : this(maxFileBytes: 256 * 1024, maxFiles: 3);

  /// A file is rotated before a write would take it past this size.
  final int maxFileBytes;

  /// How many files are kept, the current one included.
  final int maxFiles;

  /// Older files (by last write) are deleted when the log opens.
  final Duration maxAge;
}

/// Writes log text to `app.log` in a [LogStore], rotating it by size:
/// when a write would take `app.log` past [LogFilePolicy.maxFileBytes] it
/// becomes `app.1.log`, `app.1.log` becomes `app.2.log`, and so on; the file
/// past [LogFilePolicy.maxFiles] is deleted. Not safe for concurrent calls:
/// its one caller (`FileLogSink` through `LogService`) writes one batch at a
/// time.
class RotatingLogWriter {
  RotatingLogWriter(this.store, {this.policy = const LogFilePolicy(), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LogStore store;
  final LogFilePolicy policy;
  final DateTime Function() _clock;

  /// The file being written.
  static const String currentName = 'app.log';

  /// The name of the [index]th older file (0 = the current one).
  static String nameAt(int index) => index == 0 ? currentName : 'app.$index.log';

  static final RegExp _ours = RegExp(r'^app(\.\d+)?\.log$');

  int? _size;

  /// Adds [text] to the current file, rotating first when it would grow
  /// past the size limit (a file is never left empty by a rotation, so one
  /// batch larger than the limit still gets written).
  Future<void> write(String text) async {
    final bytes = _utf8Length(text);
    final size = _size ??= await store.size(currentName);
    if (size > 0 && size + bytes > policy.maxFileBytes) await rotate();
    await store.append(currentName, text);
    _size = (_size ?? 0) + bytes;
  }

  /// Starts a new current file, shifting the older ones along.
  Future<void> rotate() async {
    await store.delete(nameAt(policy.maxFiles - 1));
    for (var i = policy.maxFiles - 2; i >= 0; i--) {
      await store.rename(nameAt(i), nameAt(i + 1));
    }
    _size = 0;
  }

  /// Deletes files older than [LogFilePolicy.maxAge] and any beyond
  /// [LogFilePolicy.maxFiles] (left by a policy that kept more).
  Future<void> prune() async {
    final now = _clock();
    for (final name in await store.list()) {
      final index = _indexOf(name);
      if (index == null) continue;
      final modified = await store.modified(name);
      final tooOld = modified != null && now.difference(modified) > policy.maxAge;
      if (index >= policy.maxFiles || tooOld) {
        await store.delete(name);
        if (index == 0) _size = 0;
      }
    }
  }

  /// The log files that exist, oldest first.
  Future<List<String>> files() async {
    final names = [
      for (final n in await store.list())
        if (_indexOf(n) != null) n,
    ];
    names.sort((a, b) => _indexOf(b)!.compareTo(_indexOf(a)!));
    return names;
  }

  /// Deletes every log file.
  Future<void> clear() async {
    for (final name in await files()) {
      await store.delete(name);
    }
    _size = 0;
  }

  static int? _indexOf(String name) {
    if (!_ours.hasMatch(name)) return null;
    if (name == currentName) return 0;
    return int.parse(name.substring(4, name.length - 4));
  }

  static int _utf8Length(String text) {
    var n = 0;
    for (final r in text.runes) {
      n += r < 0x80 ? 1 : (r < 0x800 ? 2 : (r < 0x10000 ? 3 : 4));
    }
    return n;
  }
}
