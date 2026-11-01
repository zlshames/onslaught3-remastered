import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/dialogs.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

/// The shared name dialog (the map editor's Save, the mod editor's name).
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// Hosts a button that asks for a name; the answers collect in the list.
  Future<List<String?>> host(
    WidgetTester tester, {
    String initial = 'Loop',
    NameWarning? Function(BuildContext context, String name)? warningBuilder,
  }) async {
    final answers = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answers.add(
                await askName(
                  context,
                  data: data,
                  title: 'Name it',
                  label: 'Name',
                  emptyError: 'Needs a name',
                  initial: initial,
                  maxLength: 12,
                  warningBuilder: warningBuilder,
                  fieldKey: const Key('nameField'),
                ),
              ),
              child: const Text('ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    return answers;
  }

  FilledButton accept(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('Save returns the trimmed name; Cancel returns null', (tester) async {
    final answers = await host(tester);
    expect(find.text('Name it'), findsOneWidget);
    expect(find.text('Loop'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('nameField'))).maxLength, 12);
    await tester.enterText(find.byKey(const Key('nameField')), '  Spiral  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, ['Spiral', null]);
  });

  testWidgets('a blank name says so and cannot be saved', (tester) async {
    final answers = await host(tester);
    await tester.enterText(find.byKey(const Key('nameField')), '   ');
    await tester.pump();
    expect(find.text('Needs a name'), findsOneWidget);
    expect(accept(tester).onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Name it'), findsOneWidget, reason: 'Done does nothing while blank');
    expect(answers, isEmpty);
  });

  testWidgets('Done saves like the button', (tester) async {
    final answers = await host(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(answers, ['Loop']);
  });

  testWidgets('a warning shows under the field and renames Save', (tester) async {
    final answers = await host(
      tester,
      warningBuilder: (context, name) =>
          name == 'Taken' ? (warning: 'Replaces Taken', action: 'Replace') : null,
    );
    expect(find.text('Replaces Taken'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('nameField')), 'Taken ');
    await tester.pump();
    expect(find.text('Replaces Taken'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(answers, ['Taken']);
  });
}
