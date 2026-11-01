import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/app.dart';
import 'package:onslaught3_remastered/app/diagnostics_settings.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/services/logging/app_logging.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught3_remastered/services/logging/log_service.dart';
import 'package:onslaught3_remastered/services/logging/log_share.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/pump.dart';
import '../support/test_data.dart';

/// Records what it is asked to share; [result] is what the share sheet
/// "did", [fail] makes it throw.
class _FakeSharer implements LogSharer {
  _FakeSharer({this.result = const LogShared(), this.fail = false});

  final LogShareResult result;
  final bool fail;
  final List<LogArchive> shared = [];
  final List<String> subjects = [];

  @override
  Future<LogShareResult> share(LogArchive archive, {required String subject, Rect? origin}) async {
    if (fail) throw StateError('no share sheet');
    shared.add(archive);
    subjects.add(subject);
    return result;
  }
}

/// Settings → Diagnostics: the level is stored and applied, the logs are
/// exported as a zip to the share sheet, and cleared after a confirmation.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  late LogService previous;
  setUp(() => previous = LogService.instance);
  tearDown(() => LogService.install(previous));

  Future<(MemoryDocumentStore, AppLogging, _FakeSharer)> open(
    WidgetTester tester, {
    _FakeSharer? sharer,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryDocumentStore();
    final logging = AppLogging.memory();
    LogService.install(logging.service);
    final share = sharer ?? _FakeSharer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: appOverrides(
          data: data,
          store: store,
          extra: [
            appLoggingProvider.overrideWithValue(logging),
            logSharerProvider.overrideWithValue(share),
          ],
        ),
        child: const OnslaughtApp(initialLocation: '/settings'),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (store, logging, share);
  }

  /// Writes what is queued and stops the service, so no flush timer is
  /// left when the test ends.
  Future<void> finish(WidgetTester tester, AppLogging logging) async {
    await tester.runAsync(logging.service.close);
  }

  /// Lets real-async work (the zip is built in another isolate) finish.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  testWidgets('the log level is stored and applied at once', (tester) async {
    final (store, logging, _) = await open(tester);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(logging.service.level, AppLogging.defaultLevel);

    await tester.tap(find.byType(DropdownButton<LogLevel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Errors only').last);
    await tester.pumpAndSettle();

    final saved = Settings.fromJson((await store.read(Settings.key))!);
    expect(saved.logLevelChoice, LogLevel.error);
    expect(logging.service.level, LogLevel.error);
    await finish(tester, logging);
  });

  testWidgets('export shares a zip of the logs', (tester) async {
    final (_, logging, sharer) = await open(tester);
    const Logger('test').info('a line to export');

    await tester.tap(find.byKey(DiagnosticsSettings.exportKey));
    await waitFor(tester, () => sharer.shared.isNotEmpty);

    final archive = sharer.shared.single;
    expect(archive.fileName, startsWith('onslaught3-remastered-logs-'));
    expect(sharer.subjects.single, 'Onslaught 3 Remastered logs');
    final zip = ZipDecoder().decodeBytes(archive.bytes);
    final log = utf8.decode(zip.findFile('logs/app.log')!.content);
    expect(log, contains('a line to export'));
    expect(zip.findFile('info.json'), isNotNull);
    expect(logging.service.internalErrors, 0);
    await finish(tester, logging);
  });

  testWidgets('a failed export says so and is logged', (tester) async {
    final (_, logging, _) = await open(tester, sharer: _FakeSharer(fail: true));
    await tester.tap(find.byKey(DiagnosticsSettings.exportKey));
    await waitFor(tester, () => find.text('The logs could not be exported').evaluate().isNotEmpty);
    await logging.service.flush();
    final text = utf8.decode((await logging.files.store.read('app.log'))!);
    expect(text, contains('ERROR [settings] exporting the logs failed'));
    await finish(tester, logging);
  });

  testWidgets('a file saved instead of shared (Linux) shows where', (tester) async {
    final (_, logging, _) = await open(
      tester,
      sharer: _FakeSharer(result: const LogSaved('/tmp/x.zip')),
    );
    await tester.tap(find.byKey(DiagnosticsSettings.exportKey));
    await waitFor(tester, () => find.text('Logs saved to /tmp/x.zip').evaluate().isNotEmpty);
    await finish(tester, logging);
  });

  testWidgets('clear asks first, then deletes the log files', (tester) async {
    final (_, logging, _) = await open(tester);
    const Logger('test').info('old line');
    await logging.service.flush();

    await tester.tap(find.byKey(DiagnosticsSettings.clearKey));
    await tester.pumpAndSettle();
    expect(find.text('Clear the logs?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await logging.files.files(), isNotEmpty, reason: 'Cancel keeps them');

    await tester.tap(find.byKey(DiagnosticsSettings.clearKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear logs'));
    await tester.pumpAndSettle();
    expect(find.text('Logs cleared'), findsOneWidget);
    await logging.service.flush();
    final text = utf8.decode((await logging.files.store.read('app.log'))!);
    expect(text, isNot(contains('old line')));
    await finish(tester, logging);
  });
}
