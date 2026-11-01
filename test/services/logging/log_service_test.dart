import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught3_remastered/services/logging/log_service.dart';

/// A sink that keeps what it is given.
class _RecordingSink implements LogSink {
  final List<String> writes = [];

  String get text => writes.join();

  @override
  String get name => 'recording';

  @override
  Future<void> write(String text) async => writes.add(text);
}

/// A sink that throws [failures] times, then records.
class _FailingSink extends _RecordingSink {
  _FailingSink([this.failures = 1 << 30]);

  int failures;
  int calls = 0;

  @override
  String get name => 'failing';

  @override
  Future<void> write(String text) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw StateError('disk full');
    }
    await super.write(text);
  }
}

/// A sink whose writes never finish.
class _HangingSink implements LogSink {
  int calls = 0;

  @override
  String get name => 'hanging';

  @override
  Future<void> write(String text) {
    calls++;
    return Completer<void>().future;
  }
}

class _BadToString {
  @override
  String toString() => throw StateError('no text');
}

LogService _service(
  List<LogSink> sinks, {
  LogLevel level = LogLevel.trace,
  Duration flushInterval = const Duration(hours: 1),
  int maxPending = 5000,
  DateTime Function()? clock,
}) => LogService(
  level: level,
  sinks: sinks,
  flushInterval: flushInterval,
  writeTimeout: const Duration(milliseconds: 50),
  maxPending: maxPending,
  clock: clock,
  sessionId: 'test',
);

void main() {
  late LogService previous;
  setUp(() => previous = LogService.instance);
  tearDown(() => LogService.install(previous));

  group('levels', () {
    test('records below the level are dropped before any work', () async {
      final sink = _RecordingSink();
      final s = _service([sink], level: LogLevel.warning);
      var built = false;
      s.log(LogLevel.info, 't', () {
        built = true;
        return 'expensive';
      });
      s.log(LogLevel.warning, 't', 'kept');
      await s.flush();
      expect(built, isFalse, reason: 'a lazy message below the level is never built');
      expect(sink.text, contains('WARN  [t] kept'));
      expect(sink.text, isNot(contains('expensive')));
    });

    test('a lazy message at the level is built', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      s.log(LogLevel.debug, 't', () => 'built ${1 + 1}');
      await s.flush();
      expect(sink.text, contains('DEBUG [t] built 2'));
    });

    test('a logger writes to the installed service', () async {
      final sink = _RecordingSink();
      LogService.install(_service([sink], level: LogLevel.info));
      const log = Logger('area');
      log.debug('hidden');
      log.info('shown', fields: {'wave': 3});
      expect(log.isEnabled(LogLevel.debug), isFalse);
      await LogService.instance.flush();
      expect(sink.text, contains('INFO  [area] shown wave=3'));
      expect(sink.text, isNot(contains('hidden')));
    });
  });

  group('never blocks', () {
    test('a call returns before anything is written', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      s.log(LogLevel.info, 't', 'queued');
      expect(sink.writes, isEmpty);
      expect(s.pendingCount, 1);
      await s.flush();
      expect(sink.writes, hasLength(1));
    });

    test('records wait for the flush interval and go out in one batch', () async {
      final sink = _RecordingSink();
      final s = _service([sink], flushInterval: const Duration(milliseconds: 10));
      for (var i = 0; i < 20; i++) {
        s.log(LogLevel.info, 't', 'line $i');
      }
      expect(sink.writes, isEmpty);
      final until = DateTime.now().add(const Duration(seconds: 5));
      while (sink.writes.isEmpty && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(sink.writes, hasLength(1), reason: 'one write for the whole batch');
      expect('line '.allMatches(sink.text), hasLength(20));
    });

    test('errors are written without waiting for the interval', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      s.log(LogLevel.error, 't', 'boom');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(sink.text, contains('ERROR [t] boom'));
    });

    test('a sink that never finishes times out and the log moves on', () async {
      final hanging = _HangingSink();
      final good = _RecordingSink();
      final s = _service([hanging, good]);
      s.log(LogLevel.info, 't', 'one');
      await s.flush().timeout(const Duration(seconds: 2));
      expect(hanging.calls, 1);
      expect(good.text, contains('one'));
      expect(s.internalErrors, 1);
    });

    test('a full queue drops the oldest records and says how many', () async {
      final sink = _RecordingSink();
      final s = _service([sink], maxPending: 3);
      for (var i = 0; i < 5; i++) {
        s.log(LogLevel.info, 't', 'r$i');
      }
      expect(s.pendingCount, 3);
      await s.flush();
      expect(sink.text, contains('2 records were dropped'));
      expect(sink.text, isNot(contains('r0')));
      expect(sink.text, contains('r4'));
    });
  });

  group('never fails the caller', () {
    test('a throwing sink does not reach the caller or the other sinks', () async {
      final bad = _FailingSink();
      final good = _RecordingSink();
      LogService.install(_service([bad, good]));
      const log = Logger('t');
      expect(() => log.error('saved failed', error: StateError('x')), returnsNormally);
      await expectLater(LogService.instance.flush(), completes);
      expect(good.text, contains('ERROR [t] saved failed'));
      expect(LogService.instance.internalErrors, greaterThan(0));
    });

    test('a message or error that cannot be turned into text is written as such', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      expect(() => s.log(LogLevel.info, 't', () => throw StateError('x')), returnsNormally);
      expect(() => s.log(LogLevel.info, 't', _BadToString()), returnsNormally);
      expect(
        () => s.log(LogLevel.warning, 't', 'with error', error: _BadToString()),
        returnsNormally,
      );
      await s.flush();
      expect(sink.text, contains('<message could not be produced: StateError>'));
      expect(sink.text, contains('_BadToString (its description failed)'));
    });

    test('a field whose value cannot be turned into text does not lose the record', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      s.log(LogLevel.info, 't', 'fields', fields: {'bad': _BadToString()});
      await s.flush();
      expect(sink.text, contains('a record could not be written'));
    });

    test('a sink that keeps failing rests, then hears what it missed', () async {
      var now = DateTime.utc(2026, 10, 21);
      final bad = _FailingSink(3);
      final s = LogService(
        level: LogLevel.trace,
        sinks: [bad],
        flushInterval: const Duration(hours: 1),
        // sinkRetryDelay: the default 30 s.
        clock: () => now,
      );
      for (var i = 0; i < 3; i++) {
        s.log(LogLevel.info, 't', 'try $i');
        await s.flush();
      }
      expect(bad.calls, 3);
      s.log(LogLevel.info, 't', 'while resting');
      await s.flush();
      expect(bad.calls, 3, reason: 'resting: not called');
      now = now.add(const Duration(seconds: 31));
      s.log(LogLevel.info, 't', 'back');
      await s.flush();
      expect(bad.calls, 4);
      expect(bad.text, contains('records were not written here while it was failing'));
      expect(bad.text, contains('back'));
    });
  });

  group('stack traces', () {
    test('an error without a stack gets the caller\'s; info gets none', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      s.log(LogLevel.info, 't', 'plain');
      s.log(LogLevel.error, 't', 'failed');
      await s.flush();
      final parts = sink.text.split('ERROR');
      expect(parts.first, isNot(contains('stack:')));
      expect(parts.last, contains('stack:'));
      expect(parts.last, contains('log_service_test.dart'));
      expect(parts.last, isNot(contains('log_service.dart')), reason: 'own frames dropped');
    });

    test('a given stack trace is written', () async {
      final sink = _RecordingSink();
      final s = _service([sink]);
      try {
        throw StateError('inner');
      } on StateError catch (e, st) {
        s.log(LogLevel.warning, 't', 'caught', error: e, stackTrace: st);
      }
      await s.flush();
      expect(sink.text, contains('error: StateError: Bad state: inner'));
      expect(sink.text, contains('stack:'));
    });
  });

  test('records that differ only in their fields are all written', () async {
    final sink = _RecordingSink();
    final s = _service([sink]);
    s.log(LogLevel.debug, 't', 'turret built', fields: {'uid': 1});
    s.log(LogLevel.debug, 't', 'turret built', fields: {'uid': 2});
    await s.flush();
    expect(sink.text, contains('uid=1'));
    expect(sink.text, contains('uid=2'));
    expect(sink.text, isNot(contains('repeated')));
  });

  test('repeats of one record are counted instead of written', () async {
    final sink = _RecordingSink();
    final s = _service([sink]);
    for (var i = 0; i < 5; i++) {
      s.log(LogLevel.warning, 't', 'same');
    }
    s.log(LogLevel.info, 't', 'other');
    await s.flush();
    expect('] same'.allMatches(sink.text), hasLength(1));
    expect(sink.text, contains('the previous message repeated 4 more times'));
    expect(sink.text.indexOf('repeated'), lessThan(sink.text.indexOf('other')));
  });

  test('personal data is masked before a sink sees it', () async {
    final sink = _RecordingSink();
    final s = _service([sink]);
    s.log(
      LogLevel.error,
      't',
      'mail jane.doe@example.com from 10.0.0.12',
      error: StateError('/Users/janedoe/x password=abc'),
      fields: {'playerName': 'Jane', 'wave': 4},
    );
    await s.flush();
    final text = sink.text;
    for (final secret in ['jane.doe', 'example', '0.0.12', 'janedoe', 'abc', 'Jane']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(text, contains('wave=4'));
  });

  test('installing moves over what was logged before, without sinks no timers', () async {
    final early = _service([]);
    LogService.install(early);
    const Logger('boot').info('before setup');
    expect(early.pendingCount, 1);
    await early.flush();
    expect(early.pendingCount, 1, reason: 'without sinks the record waits');
    final sink = _RecordingSink();
    final real = _service([sink]);
    LogService.install(real);
    expect(early.pendingCount, 0);
    await real.flush();
    expect(sink.text, contains('[boot] before setup'));
  });

  test('a closed service takes no more records', () async {
    final sink = _RecordingSink();
    final s = _service([sink]);
    s.log(LogLevel.info, 't', 'last');
    await s.close();
    s.log(LogLevel.info, 't', 'after');
    await s.flush();
    expect(sink.text, contains('last'));
    expect(sink.text, isNot(contains('after')));
  });
}
