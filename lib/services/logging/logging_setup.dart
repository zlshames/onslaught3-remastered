import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_logging.dart';
import 'log_platform.dart';
import 'log_service.dart';
import 'log_store.dart';
import 'rotating_log_writer.dart';

const Logger _log = Logger('app');

AppLifecycleListener? _lifecycle;

/// Starts the app's logging, first thing in `main` (after the binding):
/// opens the log folder (in memory on the web, or when the folder cannot be
/// opened), deletes files past the age limit, installs the service every
/// `Logger` writes to (moving over anything logged before), writes the
/// session's first record, sends uncaught errors to the log and writes the
/// log out whenever the app goes to the background. Never throws: logging
/// that cannot start must not stop the game.
Future<AppLogging> setUpLogging() async {
  Object? storeError;
  LogStore store;
  try {
    store = await openPlatformLogStore();
  } on Object catch (e) {
    storeError = e;
    store = MemoryLogStore();
  }
  final files = RotatingLogWriter(
    store,
    policy: store.persistent ? const LogFilePolicy() : const LogFilePolicy.memory(),
  );
  final service = LogService(
    level: AppLogging.defaultLevel,
    sinks: [FileLogSink(files), if (!kReleaseMode) const ConsoleLogSink()],
  );
  LogService.install(service);
  try {
    await files.prune();
  } on Object catch (e, st) {
    _log.warning('old log files could not be pruned', error: e, stackTrace: st);
  }
  final environment = await LogEnvironment.collect();
  final logging = AppLogging(service: service, files: files, environment: environment);
  _log.info(
    'app started',
    fields: {...environment.toJson(), 'session': service.sessionId, 'level': service.level.id},
  );
  if (storeError != null) {
    _log.warning('the log folder cannot be opened; logging to memory', error: storeError);
  }
  installErrorHandlers();
  _lifecycle?.dispose();
  _lifecycle = AppLifecycleListener(onStateChange: (state) => _onLifecycle(service, state));
  return logging;
}

/// Sends errors nothing else caught to the log: framework errors (build,
/// layout, paint, gestures) and uncaught asynchronous errors. Handlers set
/// before keep running after the log has the error.
void installErrorHandlers() {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      _log.error(
        'framework error${details.library == null ? '' : ' in ${details.library}'}',
        error: details.exception,
        stackTrace: details.stack,
        fields: {'context': details.context?.toDescription()},
      );
    } on Object {
      // The log must not hide the error from the handler below.
    }
    previousFlutter?.call(details);
  };
  final dispatcher = PlatformDispatcher.instance;
  final previous = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    _log.fatal('uncaught error', error: error, stackTrace: stack);
    return previous?.call(error, stack) ?? true;
  };
}

void _onLifecycle(LogService service, AppLifecycleState state) {
  _log.debug('app lifecycle', fields: {'state': state.name});
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached) {
    unawaited(service.flush());
  }
}
