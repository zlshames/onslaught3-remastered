import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/services/persistence/document_store.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';

import '../support/log_capture.dart';

/// A store whose writes fail as a full or broken disk would; reads work.
class _WriteFailingStore extends MemoryDocumentStore {
  int writes = 0;

  @override
  Future<void> write(String key, Map<String, Object?> document) async {
    writes++;
    throw StateError('disk full');
  }
}

/// A store whose next write waits on [gate] (once), so a test can order a
/// slow write's outcome after a later one.
class _GatedStore extends MemoryDocumentStore {
  Completer<void>? gate;

  @override
  Future<void> write(String key, Map<String, Object?> document) async {
    final g = gate;
    gate = null;
    if (g != null) await g.future;
    await super.write(key, document);
  }
}

void main() {
  late LogCapture log;
  setUp(() => log = LogCapture.install());

  ProviderContainer container(DocumentStore store) {
    final c = ProviderContainer(overrides: [documentStoreProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    return c;
  }

  test('a change is stored before it is final: a failed write is rolled back and logged', () async {
    final store = _WriteFailingStore();
    final c = container(store);
    final loaded = await c.read(settingsProvider.future);
    expect(loaded.soundOn, isTrue);
    final notifier = c.read(settingsProvider.notifier);

    // Neither `save` nor `change` throws (game_screen fires `change`
    // unawaited), the state is back to what the store holds, and the
    // failure is on record.
    await notifier.save(loaded.copyWith(soundOn: false));
    expect(store.writes, 1);
    expect(c.read(settingsProvider).value?.soundOn, isTrue);
    expect(notifier.lastSaveError, isA<StateError>());
    final records = await log.records();
    expect(records.single, contains('ERROR [persistence] saving a document failed'));
    expect(records.single, contains('notifier=SettingsNotifier'));
    expect(records.single, contains('disk full'));

    await notifier.change((s) => s.copyWith(leftHanded: true));
    expect(store.writes, 2);
    expect(c.read(settingsProvider).value?.leftHanded, isFalse);
    expect(await store.read(Settings.key), isNull, reason: 'nothing was ever written');
  });

  test('a successful write keeps the new state and clears the error', () async {
    final store = MemoryDocumentStore();
    final c = container(store);
    final loaded = await c.read(settingsProvider.future);
    final notifier = c.read(settingsProvider.notifier);
    await notifier.save(loaded.copyWith(soundOn: false));
    expect(c.read(settingsProvider).value?.soundOn, isFalse);
    expect(notifier.lastSaveError, isNull);
    expect((await store.read(Settings.key))!['soundOn'], isFalse);
    expect(await log.records(), isEmpty);
  });

  test('a failed write does not undo a later change, whose own write carried it', () async {
    final store = _GatedStore();
    final c = container(store);
    final loaded = await c.read(settingsProvider.future);
    final notifier = c.read(settingsProvider.notifier);

    final gate = store.gate = Completer<void>();
    final slow = notifier.save(loaded.copyWith(soundOn: false));
    // Applied in call order while the first write is in flight.
    await notifier.change((s) => s.copyWith(leftHanded: true));
    final after = c.read(settingsProvider).value!;
    expect(after.soundOn, isFalse);
    expect(after.leftHanded, isTrue);
    expect((await store.read(Settings.key))!['leftHanded'], isTrue);

    gate.completeError(StateError('disk full'));
    await slow;
    expect(c.read(settingsProvider).value, after, reason: 'the later change stands');
    expect(notifier.lastSaveError, isA<StateError>());
    expect(await log.records(), hasLength(1));
  });
}
