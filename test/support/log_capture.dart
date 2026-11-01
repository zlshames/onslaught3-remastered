import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught3_remastered/services/logging/log_service.dart';

/// Captures what the app logs during one test: installs a [LogService]
/// writing to memory (every level) and puts the previous one back after
/// the test. Plain `test`s only: in a `testWidgets` close the service at
/// the end (`docs/LOGGING.md`, Tests).
class LogCapture implements LogSink {
  LogCapture._();

  /// Starts capturing for the current test.
  factory LogCapture.install() {
    final capture = LogCapture._();
    final service = LogService(level: LogLevel.trace, sinks: [capture], sessionId: 'test');
    final previous = LogService.install(service);
    addTearDown(() async {
      await service.close();
      LogService.install(previous);
    });
    capture._service = service;
    return capture;
  }

  late final LogService _service;

  /// Keeps only records at [level] and above from now on.
  set level(LogLevel level) => _service.level = level;
  final StringBuffer _text = StringBuffer();

  @override
  String get name => 'capture';

  @override
  Future<void> write(String text) async => _text.write(text);

  /// Every record logged so far, each with its continuation lines (error,
  /// stack), once the queue is written.
  Future<List<String>> records() async {
    await _service.flush();
    final out = <String>[];
    for (final line in _text.toString().split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') && out.isNotEmpty) {
        out.last = '${out.last}\n$line';
      } else {
        out.add(line);
      }
    }
    return out;
  }
}
