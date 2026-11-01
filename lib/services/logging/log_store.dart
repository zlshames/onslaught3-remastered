import 'dart:convert';
import 'dart:typed_data';

/// Where log files live: a flat folder of named text files. The rotation
/// policy sits on top of it (`RotatingLogWriter`), so every platform's store
/// rotates the same way.
abstract interface class LogStore {
  /// Adds [text] to the end of file [name], creating it when missing.
  Future<void> append(String name, String text);

  /// The size of file [name] in bytes; 0 when it does not exist.
  Future<int> size(String name);

  /// When file [name] was last written; null when it does not exist.
  Future<DateTime?> modified(String name);

  /// Renames [from] to [to], replacing [to]. Nothing happens when [from]
  /// does not exist.
  Future<void> rename(String from, String to);

  /// Deletes file [name]; nothing happens when it does not exist.
  Future<void> delete(String name);

  /// The files' names.
  Future<List<String>> list();

  /// File [name]'s bytes; null when it does not exist.
  Future<Uint8List?> read(String name);

  /// Whether the files outlive the app (false for the in-memory store).
  bool get persistent;
}

/// Log files kept in memory: the web build (no file system) and tests. They
/// last as long as the page or the app.
class MemoryLogStore implements LogStore {
  MemoryLogStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, StringBuffer> _files = {};
  final Map<String, DateTime> _modified = {};

  @override
  bool get persistent => false;

  @override
  Future<void> append(String name, String text) async {
    (_files[name] ??= StringBuffer()).write(text);
    _modified[name] = _clock();
  }

  @override
  Future<int> size(String name) async {
    final f = _files[name];
    return f == null ? 0 : utf8.encode(f.toString()).length;
  }

  @override
  Future<DateTime?> modified(String name) async => _modified[name];

  @override
  Future<void> rename(String from, String to) async {
    final f = _files.remove(from);
    final m = _modified.remove(from);
    if (f == null) return;
    _files[to] = f;
    if (m != null) _modified[to] = m;
  }

  @override
  Future<void> delete(String name) async {
    _files.remove(name);
    _modified.remove(name);
  }

  @override
  Future<List<String>> list() async => _files.keys.toList();

  @override
  Future<Uint8List?> read(String name) async {
    final f = _files[name];
    return f == null ? null : utf8.encode(f.toString());
  }

  /// File [name] as text (tests).
  String text(String name) => _files[name]?.toString() ?? '';

  /// Sets when file [name] was last written (tests of the age limit).
  void touch(String name, DateTime when) => _modified[name] = when;
}
