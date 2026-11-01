import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/dialogs.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

/// The shared confirm dialog: true only for its action button.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  Future<List<bool>> host(WidgetTester tester, {String? cancel}) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameDataProvider.overrideWith((ref) => data)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => answers.add(
                  await confirm(
                    context,
                    title: 'Clear the map?',
                    body: 'Everything goes.',
                    action: 'Clear',
                    cancel: cancel,
                  ),
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return answers;
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('the action answers true, Cancel and a tap outside false', (tester) async {
    final answers = await host(tester);
    await ask(tester);
    expect(find.byType(CompactDialog), findsOneWidget);
    expect(find.text('Clear the map?'), findsOneWidget);
    expect(find.text('Everything goes.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    await ask(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await ask(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(CompactDialog), findsNothing);
    expect(answers, [true, false, false]);
  });

  testWidgets('a custom cancel label replaces Cancel', (tester) async {
    final answers = await host(tester, cancel: 'Keep editing');
    await ask(tester);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });
}
