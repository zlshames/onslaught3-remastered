import 'log_record.dart';
import 'pii.dart';

/// Writes a [LogRecord] as text, masked ([PiiRedactor]):
///
/// ```text
/// 2026-10-21T14:03:05.123Z INFO  [game] Game started mode=classic map=m01
///   error: StateError: Bad state: disk gone
///   stack:
///     #0      PersistenceService.load (package:…/settings.dart:221:7)
/// ```
///
/// Continuation lines are indented so a reader (or `grep`) can tell where
/// each record starts.
abstract final class LogFormat {
  /// Longer messages and errors are cut to this many characters.
  static const int maxTextLength = 4000;

  /// At most this many stack frames are written per record.
  static const int maxStackFrames = 40;

  /// [record] as one or more lines, each ending in a newline. Never throws:
  /// a record that cannot be written comes out as one line saying so.
  static String format(LogRecord record) {
    try {
      final out = StringBuffer()
        ..write(record.time.toUtc().toIso8601String())
        ..write(' ')
        ..write(record.level.label.padRight(5))
        ..write(' [')
        ..write(record.tag)
        ..write('] ')
        ..write(_clip(PiiRedactor.redact(record.message)));
      record.fields.forEach((k, v) => out.write(' $k=${PiiRedactor.field(k, v)}'));
      out.write('\n');
      final error = record.error;
      if (error != null) out.write('  error: ${_clip(PiiRedactor.redact(describeError(error)))}\n');
      final stack = record.stackTrace;
      if (stack != null) {
        final frames = stackFrames(stack);
        if (frames.isNotEmpty) {
          out.write('  stack:\n');
          for (final f in frames) {
            out.write('    ${PiiRedactor.redact(f)}\n');
          }
        }
      }
      return out.toString();
    } on Object catch (e) {
      return '${DateTime.now().toUtc().toIso8601String()} ERROR [log] a record could not be '
          'written (${e.runtimeType})\n';
    }
  }

  /// [error] as text, without what could hold personal data that the masks
  /// do not recognise: a [FormatException]'s source (the whole document it
  /// was reading) is left out.
  /// An error whose own text cannot be produced comes out as its type.
  static String describeError(Object error) {
    try {
      if (error is FormatException) {
        final at = error.offset == null ? '' : ' (at offset ${error.offset})';
        return 'FormatException: ${error.message}$at';
      }
      return error is String ? error : '${error.runtimeType}: $error';
    } on Object {
      return '${error.runtimeType} (its description failed)';
    }
  }

  /// The frames of [stack] worth reading: the logger's own frames and blank
  /// lines dropped, at most [maxStackFrames] (the rest counted).
  static List<String> stackFrames(StackTrace stack) {
    final lines = stack
        .toString()
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty && !_ownFrame.hasMatch(l))
        .toList();
    if (lines.length <= maxStackFrames) return lines;
    return [...lines.take(maxStackFrames), '… ${lines.length - maxStackFrames} more frames'];
  }

  static final RegExp _ownFrame = RegExp(
    r'(package:onslaught3_remastered/|[/\\]lib[/\\])services[/\\]logging[/\\]',
  );

  static String _clip(String text) => text.length <= maxTextLength
      ? text
      : '${text.substring(0, maxTextLength)}… (${text.length - maxTextLength} more characters)';
}
