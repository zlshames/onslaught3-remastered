import 'dart:typed_data';

import 'log_store.dart';

/// The web has no file system: the page's logs are kept in memory.
Future<LogStore> openPlatformLogStore() async => MemoryLogStore();

/// The browser does not say which operating system it runs on in a form
/// worth logging.
String platformOsVersion() => 'web';

/// Not reported on the web.
String platformDartVersion() => 'web';

/// The web shares bytes directly; no file is written.
Future<String?> writeTemporaryFile(String name, Uint8List bytes) async => null;

/// Not used on the web (the share sheet or a download takes the file).
Future<String> saveToDownloads(String name, Uint8List bytes) =>
    throw UnsupportedError('no downloads folder on the web');
