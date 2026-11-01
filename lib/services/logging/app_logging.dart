import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'log_level.dart';
import 'log_platform.dart';
import 'log_service.dart';
import 'log_store.dart';
import 'pii.dart';
import 'rotating_log_writer.dart';

/// What a log reader needs to know about the app and the device, and
/// nothing that identifies the player: written as the session's first
/// record and as `info.json` in an export.
@immutable
class LogEnvironment {
  const LogEnvironment({
    this.appName = 'unknown',
    this.version = 'unknown',
    this.buildNumber = 'unknown',
    this.platform = 'unknown',
    this.os = 'unknown',
    this.dart = 'unknown',
    this.buildMode = 'unknown',
  });

  /// Reads the app's version and the platform. Never throws: what cannot be
  /// read stays `unknown`.
  static Future<LogEnvironment> collect() async {
    String appName = 'unknown', version = 'unknown', build = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appName = info.appName;
      version = info.version;
      build = info.buildNumber;
    } on Object {
      // Unknown in tests and on platforms without the plugin.
    }
    String safe(String Function() read) {
      try {
        return PiiRedactor.redact(read());
      } on Object {
        return 'unknown';
      }
    }

    return LogEnvironment(
      appName: appName,
      version: version,
      buildNumber: build,
      platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      os: safe(platformOsVersion),
      dart: safe(platformDartVersion),
      buildMode: kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    );
  }

  final String appName;
  final String version;
  final String buildNumber;
  final String platform;
  final String os;
  final String dart;
  final String buildMode;

  Map<String, Object?> toJson() => {
    'app': appName,
    'version': version,
    'build': buildNumber,
    'platform': platform,
    'os': os,
    'dart': dart,
    'buildMode': buildMode,
  };
}

/// An exported zip of the log files.
@immutable
class LogArchive {
  const LogArchive({required this.fileName, required this.bytes});

  /// `onslaught3-remastered-logs-<UTC time>.zip`.
  final String fileName;
  final Uint8List bytes;
}

/// The app's logging as the rest of the app sees it: the [service] every
/// `Logger` writes to, the rotating [files] it writes, and the actions
/// Settings offers (level, export, clear).
class AppLogging {
  AppLogging({
    required this.service,
    required this.files,
    this.environment = const LogEnvironment(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Logging that keeps its files in memory, for tests and previews.
  factory AppLogging.memory({LogLevel level = LogLevel.trace, DateTime Function()? clock}) {
    final files = RotatingLogWriter(
      MemoryLogStore(clock: clock),
      policy: const LogFilePolicy.memory(),
      clock: clock,
    );
    return AppLogging(
      service: LogService(level: level, sinks: [FileLogSink(files)], clock: clock),
      files: files,
      clock: clock,
    );
  }

  final LogService service;
  final RotatingLogWriter files;
  final LogEnvironment environment;
  final DateTime Function() _clock;

  /// The level when the player has not chosen one: everything useful for
  /// a bug report in a release build, more while developing.
  static LogLevel get defaultLevel => kDebugMode ? LogLevel.debug : LogLevel.info;

  static const Logger _log = Logger('log');

  /// Keeps records at [level] and above from now on (null = [defaultLevel]).
  void setLevel(LogLevel? level) {
    final next = level ?? defaultLevel;
    if (service.level == next) return;
    service.level = next;
    _log.info('log level set', fields: {'level': next.id});
  }

  /// Zips the log files (written up to now) with an `info.json` describing
  /// the app, the platform and the export. The zip is built off the UI
  /// thread where the platform allows.
  Future<LogArchive> export() async {
    await service.flush();
    final now = _clock().toUtc();
    final contents = <String, Uint8List>{};
    for (final name in await files.files()) {
      final bytes = await files.store.read(name);
      if (bytes != null) contents['logs/$name'] = bytes;
    }
    final info = {
      ...environment.toJson(),
      'session': service.sessionId,
      'logLevel': service.level.id,
      'exportedAt': now.toIso8601String(),
      'keptAcrossRestarts': files.store.persistent,
      'files': [
        for (final e in contents.entries) {'name': e.key, 'bytes': e.value.length},
      ],
    };
    contents['info.json'] = utf8.encode(const JsonEncoder.withIndent('  ').convert(info));
    final bytes = await compute(_zip, contents);
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '');
    _log.info('logs exported', fields: {'files': contents.length - 1, 'bytes': bytes.length});
    return LogArchive(fileName: 'onslaught3-remastered-logs-$stamp.zip', bytes: bytes);
  }

  /// Deletes every log file; the log carries on in a new one.
  Future<void> clear() async {
    await service.flush();
    await files.clear();
    _log.info('logs cleared');
  }
}

Uint8List _zip(Map<String, Uint8List> contents) {
  final archive = Archive();
  contents.forEach((name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encodeBytes(archive);
}
