import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/services/logging/app_logging.dart';
import 'package:onslaught3_remastered/services/logging/log_level.dart';
import 'package:onslaught3_remastered/services/logging/log_service.dart';
import 'package:onslaught3_remastered/services/logging/log_store.dart';
import 'package:onslaught3_remastered/services/logging/log_store_io.dart';
import 'package:onslaught3_remastered/services/logging/rotating_log_writer.dart';

void main() {
  group('rotation', () {
    Future<void> rotatesBySize(LogStore store) async {
      final w = RotatingLogWriter(
        store,
        policy: const LogFilePolicy(maxFileBytes: 100, maxFiles: 3),
      );
      for (var i = 0; i < 10; i++) {
        await w.write('${'$i' * 39}\n'); // 40 bytes: two lines per file
      }
      expect(await w.files(), ['app.2.log', 'app.1.log', 'app.log'], reason: 'oldest first');
      expect(await store.size('app.log'), 80);
      final newest = utf8.decode((await store.read('app.log'))!);
      expect(newest, startsWith('8'), reason: 'lines 8 and 9');
      final oldest = utf8.decode((await store.read('app.2.log'))!);
      expect(oldest, startsWith('4'), reason: 'lines 0–3 rotated out');
      expect(await store.list(), hasLength(3));
    }

    test('rotates by size and keeps a fixed number of files (memory)', () async {
      await rotatesBySize(MemoryLogStore());
    });

    test('rotates by size and keeps a fixed number of files (disk)', () async {
      final dir = await Directory.systemTemp.createTemp('logs');
      addTearDown(() => dir.delete(recursive: true));
      await rotatesBySize(IoLogStore(Directory('${dir.path}/logs')));
    });

    test('a batch larger than the limit is still written whole', () async {
      final store = MemoryLogStore();
      final w = RotatingLogWriter(store, policy: const LogFilePolicy(maxFileBytes: 10));
      await w.write('x' * 50);
      expect(await store.size('app.log'), 50);
    });

    test('a writer that reopens the files continues the current one', () async {
      final store = MemoryLogStore();
      const policy = LogFilePolicy(maxFileBytes: 100, maxFiles: 2);
      await RotatingLogWriter(store, policy: policy).write('a' * 90);
      await RotatingLogWriter(store, policy: policy).write('b' * 20);
      expect(store.text('app.1.log'), 'a' * 90);
      expect(store.text('app.log'), 'b' * 20);
    });

    test('prune deletes files past the age limit and past the file limit', () async {
      final now = DateTime.utc(2026, 10, 21);
      final store = MemoryLogStore(clock: () => now);
      for (final n in ['app.log', 'app.1.log', 'app.2.log', 'app.7.log', 'other.txt']) {
        await store.append(n, 'x');
      }
      store.touch('app.2.log', now.subtract(const Duration(days: 30)));
      final w = RotatingLogWriter(
        store,
        // The default policy: 5 files, 14 days.
        clock: () => now,
      );
      await w.prune();
      expect((await store.list())..sort(), ['app.1.log', 'app.log', 'other.txt']);
    });

    test('clear deletes only the log files', () async {
      final store = MemoryLogStore();
      final w = RotatingLogWriter(store, policy: const LogFilePolicy(maxFileBytes: 5));
      await w.write('aaaa');
      await w.write('bbbb');
      await store.append('keep.txt', 'k');
      await w.clear();
      expect(await store.list(), ['keep.txt']);
      await w.write('c');
      expect(store.text('app.log'), 'c');
    });
  });

  group('AppLogging', () {
    late LogService previous;
    setUp(() => previous = LogService.instance);
    tearDown(() => LogService.install(previous));

    test('export zips every log file with info.json, and no personal data', () async {
      final now = DateTime.utc(2026, 10, 21, 14, 3, 5);
      final logging = AppLogging.memory(clock: () => now);
      LogService.install(logging.service);
      const log = Logger('test');
      log.info('player jane.doe@example.com', fields: {'mapName': 'Fortress'});
      log.error('save failed', error: const FileSystemException('x', '/Users/janedoe/a'));
      final archive = await logging.export();
      expect(archive.fileName, 'onslaught3-remastered-logs-20261021T140305Z.zip');

      final zip = ZipDecoder().decodeBytes(archive.bytes);
      final names = zip.files.map((f) => f.name).toList();
      expect(names, containsAll(['logs/app.log', 'info.json']));
      final logText = utf8.decode(zip.findFile('logs/app.log')!.content);
      expect(logText, contains('INFO  [test] player'));
      expect(logText, contains('ERROR [test] save failed'));
      for (final secret in ['jane.doe', 'example', 'Fortress', 'janedoe']) {
        expect(logText, isNot(contains(secret)), reason: secret);
      }
      final info = jsonDecode(utf8.decode(zip.findFile('info.json')!.content)) as Map;
      expect(info['session'], logging.service.sessionId);
      expect(info['logLevel'], 'trace');
      expect(info['keptAcrossRestarts'], isFalse);
      expect(info['files'], [
        {'name': 'logs/app.log', 'bytes': zip.findFile('logs/app.log')!.size},
      ]);
    });

    test('clear empties the files and the log carries on', () async {
      final logging = AppLogging.memory();
      LogService.install(logging.service);
      const Logger('test').info('old line');
      await logging.service.flush();
      await logging.clear();
      await logging.service.flush();
      final text = utf8.decode((await logging.files.store.read('app.log'))!);
      expect(text, isNot(contains('old line')));
      expect(text, contains('logs cleared'));
    });

    test('setLevel changes what is kept; null is the build default', () {
      final logging = AppLogging.memory();
      logging.setLevel(LogLevel.error);
      expect(logging.service.level, LogLevel.error);
      logging.setLevel(null);
      expect(logging.service.level, AppLogging.defaultLevel);
    });
  });
}
