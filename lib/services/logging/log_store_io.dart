import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'log_store.dart';

/// Log files in a folder on disk (every platform but the web).
class IoLogStore implements LogStore {
  IoLogStore(this.directory);

  final Directory directory;

  File _file(String name) => File('${directory.path}${Platform.pathSeparator}$name');

  @override
  bool get persistent => true;

  @override
  Future<void> append(String name, String text) async {
    await directory.create(recursive: true);
    await _file(name).writeAsString(text, mode: FileMode.append, flush: true);
  }

  @override
  Future<int> size(String name) async {
    final f = _file(name);
    return await f.exists() ? f.length() : 0;
  }

  @override
  Future<DateTime?> modified(String name) async {
    final f = _file(name);
    return await f.exists() ? f.lastModified() : null;
  }

  @override
  Future<void> rename(String from, String to) async {
    final f = _file(from);
    if (!await f.exists()) return;
    final target = _file(to);
    if (await target.exists()) await target.delete();
    await f.rename(target.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> list() async {
    if (!await directory.exists()) return [];
    return [
      await for (final e in directory.list())
        if (e is File) e.uri.pathSegments.last,
    ];
  }

  @override
  Future<Uint8List?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsBytes() : null;
  }
}

/// The app's log folder: `logs` in its support directory (private to the
/// app, not shown to the player, backed up with it on no platform that
/// matters for logs).
Future<LogStore> openPlatformLogStore() async {
  final base = await getApplicationSupportDirectory();
  return IoLogStore(Directory('${base.path}${Platform.pathSeparator}logs'));
}

/// The operating system and its version, as the platform reports it.
String platformOsVersion() => '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

/// The Dart runtime's version.
String platformDartVersion() => Platform.version.split(' ').first;

/// Where an exported archive is written before it is shared: the
/// temporary directory (the share sheet copies it).
Future<String?> writeTemporaryFile(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

/// Saves [bytes] as [name] in the Downloads folder (or the documents folder
/// when the platform has none) and returns its path: Linux, where the share
/// sheet cannot take files.
Future<String> saveToDownloads(String name, Uint8List bytes) async {
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
