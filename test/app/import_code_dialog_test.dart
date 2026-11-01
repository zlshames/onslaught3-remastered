import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/dialogs.dart';
import 'package:onslaught3_remastered/app/strings.dart';
import 'package:onslaught3_remastered/services/share/share_codec.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

/// The shared import-code dialog the map and mod imports wrap.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  /// `code:<word>` reads as the word in capitals; anything else is rejected.
  String decode(String code) {
    final t = code.trim();
    if (!t.startsWith('code:')) throw const ShareCodecException('ui.share.notACode');
    return t.substring(5).toUpperCase();
  }

  Future<List<String?>> host(WidgetTester tester) async {
    final answers = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answers.add(
                await showDialog<String>(
                  context: context,
                  builder: (context) => ImportCodeDialog<String>(
                    data: data,
                    title: 'Import',
                    label: 'Code',
                    fieldKey: const Key('code'),
                    decode: decode,
                    errorText: (context, e) => 'Unreadable: ${data.tr(context, e.key, e.args)}',
                    preview: (context, value) => Text('Preview $value'),
                    canAccept: (value) => value != 'BAD',
                    acceptLabel: (context, value) => value == null ? 'Add' : 'Add $value',
                  ),
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

  VoidCallback? accept(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed;

  testWidgets('a readable code shows its preview and is returned', (tester) async {
    final answers = await host(tester);
    expect(find.text('Import'), findsOneWidget);
    expect(accept(tester), isNull, reason: 'nothing read yet');
    await tester.enterText(find.byKey(const Key('code')), 'code:loop');
    await tester.pump();
    expect(find.text('Preview LOOP'), findsOneWidget);
    await tester.tap(find.text('Add LOOP'));
    await tester.pumpAndSettle();
    expect(answers, ['LOOP']);
  });

  testWidgets('an unreadable code shows why; a blank one shows nothing', (tester) async {
    final answers = await host(tester);
    await tester.enterText(find.byKey(const Key('code')), 'junk');
    await tester.pump();
    expect(find.text('Unreadable: not an Onslaught 3 Remastered share code'), findsOneWidget);
    expect(accept(tester), isNull);
    await tester.enterText(find.byKey(const Key('code')), '  ');
    await tester.pump();
    expect(find.textContaining('Unreadable'), findsNothing);
    expect(find.textContaining('Preview'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [null]);
  });

  testWidgets('a code canAccept refuses is previewed but cannot be added', (tester) async {
    await host(tester);
    await tester.enterText(find.byKey(const Key('code')), 'code:bad');
    await tester.pump();
    expect(find.text('Preview BAD'), findsOneWidget);
    expect(accept(tester), isNull);
  });

  testWidgets('Paste reads the clipboard', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.getData') return {'text': 'code:spiral'};
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await host(tester);
    await tester.tap(find.byTooltip('Paste'));
    await tester.pumpAndSettle();
    expect(find.text('code:spiral'), findsOneWidget);
    expect(find.text('Preview SPIRAL'), findsOneWidget);
  });
}
