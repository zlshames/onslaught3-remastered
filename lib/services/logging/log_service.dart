import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'log_format.dart';
import 'log_level.dart';
import 'log_record.dart';
import 'rotating_log_writer.dart';

/// Where formatted log text goes (the log files, the debug console).
abstract interface class LogSink {
  /// A short name for reports about the sink itself.
  String get name;

  /// Writes [text]: one or more whole lines, already formatted and masked.
  /// May throw or take long; [LogService] contains both.
  Future<void> write(String text);
}

/// Writes to the rotating log files.
class FileLogSink implements LogSink {
  FileLogSink(this.writer);

  final RotatingLogWriter writer;

  @override
  String get name => 'file';

  @override
  Future<void> write(String text) => writer.write(text);
}

/// Prints to the debug console (`flutter run`, logcat, Xcode); debug and
/// profile builds only.
class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  String get name => 'console';

  @override
  Future<void> write(String text) async {
    for (final line in text.split('\n')) {
      if (line.isNotEmpty) debugPrint(line);
    }
  }
}

/// The app's log: takes records from [Logger]s and hands them, formatted
/// and masked, to its sinks.
///
/// Logging never blocks and never fails the caller:
/// - a call ([log]) only checks the level, builds a record and queues it;
///   formatting, masking and writing happen later, in batches of at most
///   [batchSize], on a timer ([flushInterval]) or at once for errors;
/// - nothing a call does throws: a message whose text cannot be produced, a
///   formatter that fails, a sink that throws or hangs ([writeTimeout]) are
///   all contained here and reported to the debug console only;
/// - the queue is bounded ([maxPending]): when the sinks cannot keep up the
///   oldest records are dropped and the next batch says how many;
/// - a sink that fails [maxSinkFailures] times in a row rests for a while
///   (from [sinkRetryDelay], doubling) and the records meant for it meanwhile
///   are counted, not kept;
/// - a record identical to the one before it (level, area, message, error
///   type, fields) is counted instead of queued; the count is written once
///   per batch.
///
/// Before [install] the app has a service without sinks that only keeps the
/// latest records ([maxPending]); installing the real one moves them over,
/// so nothing logged during start-up is lost. A service without sinks sets
/// no timers.
class LogService {
  LogService({
    this.level = LogLevel.info,
    List<LogSink> sinks = const [],
    this.flushInterval = const Duration(milliseconds: 500),
    this.writeTimeout = const Duration(seconds: 10),
    this.maxPending = 5000,
    this.batchSize = 500,
    this.maxSinkFailures = 3,
    this.sinkRetryDelay = const Duration(seconds: 30),
    DateTime Function()? clock,
    String? sessionId,
  }) : _clock = clock ?? DateTime.now,
       sessionId = sessionId ?? _newSessionId() {
    for (final s in sinks) {
      _sinks.add(_SinkState(s));
    }
  }

  /// The service every [Logger] writes to.
  static LogService get instance => _instance;
  static LogService _instance = LogService();

  /// Makes [service] the one every [Logger] writes to, moving over what the
  /// previous one had not written yet. Returns the previous one.
  static LogService install(LogService service) {
    final previous = _instance;
    if (identical(previous, service)) return previous;
    _instance = service;
    previous._handOver(service);
    return previous;
  }

  /// Records below this level are dropped at the call.
  LogLevel level;

  /// How long records wait before they are written (errors do not wait).
  final Duration flushInterval;

  /// A sink write that takes longer counts as a failure.
  final Duration writeTimeout;

  /// The most records waiting to be written; past it the oldest go.
  final int maxPending;

  /// The most records formatted and written in one go.
  final int batchSize;

  /// Failures in a row after which a sink rests.
  final int maxSinkFailures;

  /// How long a failing sink first rests (doubling each time, at most
  /// [_maxRetryDelay]).
  final Duration sinkRetryDelay;
  static const Duration _maxRetryDelay = Duration(minutes: 10);

  /// A random id for this run of the app, written in the session's first
  /// record and in an export; it tells runs apart and identifies nobody.
  final String sessionId;

  final DateTime Function() _clock;
  final List<_SinkState> _sinks = [];
  final ListQueue<LogRecord> _pending = ListQueue();
  Timer? _timer;
  Future<void> _chain = Future.value();
  bool _flushQueued = false;
  bool _closed = false;
  int _dropped = 0;

  String? _lastKey;
  LogRecord? _lastRecord;
  int _repeats = 0;

  /// How many problems the service itself has had (a failed write, a
  /// message that could not be produced); for tests and diagnostics.
  int get internalErrors => _internalErrors;
  int _internalErrors = 0;

  /// Records waiting to be written.
  int get pendingCount => _pending.length;

  /// Whether a record at [level] would be kept.
  bool isEnabled(LogLevel level) => !_closed && this.level.allows(level);

  /// Adds a sink; records already queued go to it too.
  void addSink(LogSink sink) => _sinks.add(_SinkState(sink));

  /// Queues a record. [message] may be a function, called only
  /// when [level] is kept. An error-level record logged without a stack
  /// trace gets the caller's. Never throws, never waits.
  void log(
    LogLevel level,
    String tag,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    try {
      if (!isEnabled(level)) return;
      final record = LogRecord(
        time: _clock().toUtc(),
        level: level,
        tag: tag,
        message: _text(message),
        error: error,
        stackTrace: stackTrace ?? (level.index >= LogLevel.error.index ? StackTrace.current : null),
        fields: fields == null || fields.isEmpty ? const {} : Map.unmodifiable(fields),
      );
      _enqueue(record);
    } on Object catch (e) {
      _internal('a log call failed', e);
    }
  }

  /// Writes everything queued so far; completes when the sinks have it.
  /// Never throws.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _chain = _chain.then((_) => _drainAll());
  }

  /// Writes what is queued and stops taking records.
  Future<void> close() async {
    await flush();
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }

  String _text(Object? message) {
    try {
      final value = message is Object? Function() ? message() : message;
      return '$value';
    } on Object catch (e) {
      _internalErrors++;
      return '<message could not be produced: ${e.runtimeType}>';
    }
  }

  void _enqueue(LogRecord record) {
    final key =
        '${record.level.index}|${record.tag}|${record.message}|${record.error?.runtimeType}|'
        '${_fieldsKey(record.fields)}';
    if (key == _lastKey) {
      _repeats++;
      _schedule(record.level);
      return;
    }
    _closeRepeats();
    _lastKey = key;
    _lastRecord = record;
    _push(record);
    _schedule(record.level);
  }

  /// The fields as text for telling records apart; a field that cannot be
  /// turned into text makes the record unique rather than lose it.
  static String _fieldsKey(Map<String, Object?> fields) {
    if (fields.isEmpty) return '';
    try {
      return fields.toString();
    } on Object {
      return 'unique:${identityHashCode(fields)}';
    }
  }

  /// Queues the "repeated" note for the record before, if it repeated.
  void _closeRepeats() {
    final last = _lastRecord;
    if (_repeats == 0 || last == null) return;
    _push(
      LogRecord(
        time: _clock().toUtc(),
        level: last.level,
        tag: last.tag,
        message: 'the previous message repeated $_repeats more times',
      ),
    );
    _repeats = 0;
  }

  void _push(LogRecord record) {
    _pending.addLast(record);
    while (_pending.length > maxPending) {
      _pending.removeFirst();
      _dropped++;
    }
  }

  void _schedule(LogLevel level) {
    if (_sinks.isEmpty || _closed) return;
    if (level.index >= LogLevel.error.index) {
      if (_flushQueued) return;
      _flushQueued = true;
      scheduleMicrotask(() {
        _flushQueued = false;
        unawaited(flush());
      });
      return;
    }
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> _drainAll() async {
    // Without sinks the records wait for [install] to move them on.
    if (_sinks.isEmpty) return;
    try {
      _closeRepeats();
      // Repeats after this batch are counted afresh, still against the
      // same record.
      while (_pending.isNotEmpty || _dropped > 0) {
        await _drainBatch();
      }
    } on Object catch (e) {
      _internal('writing the log failed', e);
    }
  }

  Future<void> _drainBatch() async {
    final out = StringBuffer();
    if (_dropped > 0) {
      out.write(
        LogFormat.format(
          LogRecord(
            time: _clock().toUtc(),
            level: LogLevel.warning,
            tag: 'log',
            message: '$_dropped records were dropped: the log could not keep up',
          ),
        ),
      );
      _dropped = 0;
    }
    var n = 0;
    while (_pending.isNotEmpty && n < batchSize) {
      out.write(LogFormat.format(_pending.removeFirst()));
      n++;
    }
    final text = out.toString();
    final now = _clock();
    for (final sink in _sinks) {
      await _writeTo(sink, text, n, now);
    }
  }

  Future<void> _writeTo(_SinkState sink, String text, int records, DateTime now) async {
    if (!sink.ready(now)) {
      sink.missed += records;
      return;
    }
    try {
      final gap = sink.missed == 0
          ? ''
          : LogFormat.format(
              LogRecord(
                time: now.toUtc(),
                level: LogLevel.warning,
                tag: 'log',
                message: '${sink.missed} records were not written here while it was failing',
              ),
            );
      await sink.sink.write('$gap$text').timeout(writeTimeout);
      sink.succeeded();
    } on Object catch (e) {
      sink.failed(now, maxSinkFailures, sinkRetryDelay, _maxRetryDelay);
      sink.missed += records;
      _internal('the ${sink.sink.name} log sink failed', e);
    }
  }

  void _handOver(LogService next) {
    _timer?.cancel();
    _timer = null;
    _closeRepeats();
    for (final r in _pending) {
      next._push(r);
    }
    next._dropped += _dropped;
    _pending.clear();
    _dropped = 0;
    _lastKey = null;
    _lastRecord = null;
    if (next._pending.isNotEmpty) next._schedule(LogLevel.info);
  }

  /// Reports a problem of the log itself where it cannot loop back into the
  /// log: the debug console, in debug builds only.
  void _internal(String what, Object error) {
    _internalErrors++;
    if (!kDebugMode) return;
    try {
      debugPrint('LogService: $what (${error.runtimeType}: $error)');
    } on Object {
      // Nothing else can be done.
    }
  }

  static String _newSessionId() {
    Random random;
    try {
      random = Random.secure();
    } on UnsupportedError {
      random = Random();
    }
    return [for (var i = 0; i < 8; i++) random.nextInt(16).toRadixString(16)].join();
  }
}

class _SinkState {
  _SinkState(this.sink);

  final LogSink sink;
  int failures = 0;
  int missed = 0;
  DateTime? restUntil;
  Duration? lastRest;

  bool ready(DateTime now) => restUntil == null || !now.isBefore(restUntil!);

  void succeeded() {
    failures = 0;
    missed = 0;
    restUntil = null;
    lastRest = null;
  }

  void failed(DateTime now, int maxFailures, Duration first, Duration longest) {
    failures++;
    if (failures < maxFailures) return;
    final rest = lastRest == null ? first : lastRest! * 2;
    lastRest = rest > longest ? longest : rest;
    restUntil = now.add(lastRest!);
    failures = 0;
  }
}

/// Writes records for one area of the app ([tag]) to [LogService.instance]:
///
/// ```dart
/// const _log = Logger('persistence');
/// _log.warning('settings could not be read', error: e, stackTrace: st);
/// _log.debug(() => 'expensive ${detail()}'); // built only when kept
/// ```
///
/// Every method returns at once and never throws.
class Logger {
  const Logger(this.tag);

  final String tag;

  /// Whether a record at [level] would be kept (to skip work that only
  /// feeds the log).
  bool isEnabled(LogLevel level) => LogService.instance.isEnabled(level);

  void trace(Object? message, {Map<String, Object?>? fields}) =>
      LogService.instance.log(LogLevel.trace, tag, message, fields: fields);

  void debug(Object? message, {Map<String, Object?>? fields}) =>
      LogService.instance.log(LogLevel.debug, tag, message, fields: fields);

  void info(Object? message, {Map<String, Object?>? fields}) =>
      LogService.instance.log(LogLevel.info, tag, message, fields: fields);

  void warning(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => LogService.instance.log(
    LogLevel.warning,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void error(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => LogService.instance.log(
    LogLevel.error,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  void fatal(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => LogService.instance.log(
    LogLevel.fatal,
    tag,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );
}
