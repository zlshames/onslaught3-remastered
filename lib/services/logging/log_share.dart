import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'app_logging.dart';
import 'log_platform.dart';

/// What happened to an exported archive.
sealed class LogShareResult {
  const LogShareResult();
}

/// The share sheet took it (or the browser downloaded it).
class LogShared extends LogShareResult {
  const LogShared();
}

/// The player closed the share sheet.
class LogShareDismissed extends LogShareResult {
  const LogShareDismissed();
}

/// Saved as a file at [path] (Linux, where the share sheet cannot take
/// files).
class LogSaved extends LogShareResult {
  const LogSaved(this.path);

  final String path;
}

/// Hands an exported archive to the player: the system share sheet, a
/// download on the web, a file in Downloads on Linux.
abstract interface class LogSharer {
  /// Shares [archive]; [subject] is the e-mail subject a mail app uses and
  /// [origin] where the share sheet points from on an iPad or a Mac. Throws
  /// when the platform fails.
  Future<LogShareResult> share(LogArchive archive, {required String subject, Rect? origin});
}

/// [LogSharer] through `share_plus`.
class PlatformLogSharer implements LogSharer {
  const PlatformLogSharer();

  static const String _mime = 'application/zip';

  @override
  Future<LogShareResult> share(LogArchive archive, {required String subject, Rect? origin}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return LogSaved(await saveToDownloads(archive.fileName, archive.bytes));
    }
    final path = await writeTemporaryFile(archive.fileName, archive.bytes);
    final file = path == null
        ? XFile.fromData(archive.bytes, name: archive.fileName, mimeType: _mime)
        : XFile(path, name: archive.fileName, mimeType: _mime);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: path == null ? [archive.fileName] : null,
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? const LogShareDismissed()
        : const LogShared();
  }
}
