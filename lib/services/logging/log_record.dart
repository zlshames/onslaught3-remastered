import 'package:flutter/foundation.dart';

import 'log_level.dart';

/// One thing that was logged, as the caller gave it. Nothing in it has been
/// formatted or masked yet: that happens later, off the caller's path
/// (`LogService`).
@immutable
class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.fields = const {},
  });

  /// When it was logged (UTC).
  final DateTime time;
  final LogLevel level;

  /// The area it came from (`persistence`, `game`, `audio`, …).
  final String tag;
  final String message;

  /// The error being reported, if any.
  final Object? error;

  /// Where it happened: the error's stack, or for an error-level record
  /// logged without one, the caller's.
  final StackTrace? stackTrace;

  /// Extra values, written as `key=value` after the message.
  final Map<String, Object?> fields;
}
