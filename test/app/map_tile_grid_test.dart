import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/map_tile_grid.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../support/test_data.dart';

/// The map tiles shared by Choose a Map and Map Tools.
void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  test('two columns on a portrait phone, three on a landscape one, four wider', () {
    expect(MapTileGrid.columnsFor(400), 2);
    expect(MapTileGrid.columnsFor(479), 2);
    expect(MapTileGrid.columnsFor(480), 3);
    expect(MapTileGrid.columnsFor(700), 3);
    expect(MapTileGrid.columnsFor(701), 4);
  });

  Future<List<String>> pumpGrid(WidgetTester tester, {required double width}) async {
    final tapped = <String>[];
    final maps = data.maps.values.take(5).toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 800,
              child: MapTileGrid(
                children: [
                  for (final (i, m) in maps.indexed)
                    MapTile(
                      key: ValueKey(m.id),
                      map: m,
                      data: data,
                      name: 'Map $i',
                      label: 'Play map $i',
                      subtitle: i == 0 ? 'Best: wave 12' : null,
                      onTap: () => tapped.add(m.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('tiles fill the columns for the width', (tester) async {
    await pumpGrid(tester, width: 400);
    final ids = data.maps.keys.take(3).toList();
    final first = tester.getTopLeft(find.byKey(ValueKey(ids[0])));
    final second = tester.getTopLeft(find.byKey(ValueKey(ids[1])));
    final third = tester.getTopLeft(find.byKey(ValueKey(ids[2])));
    expect(second.dy, first.dy, reason: 'two in the first row');
    expect(third.dy, greaterThan(first.dy), reason: 'the third wraps');
    expect(third.dx, first.dx);

    await pumpGrid(tester, width: 800);
    final rowOf4 = [
      for (final id in data.maps.keys.take(5)) tester.getTopLeft(find.byKey(ValueKey(id))).dy,
    ];
    expect(rowOf4.take(4).toSet(), hasLength(1), reason: 'four in the first row');
    expect(rowOf4.last, greaterThan(rowOf4.first));
  });

  testWidgets('a tile shows its name and subtitle, reads as one button, and taps', (tester) async {
    final handle = tester.ensureSemantics();
    final tapped = await pumpGrid(tester, width: 600);
    expect(find.text('Map 0'), findsOneWidget);
    expect(find.text('Best: wave 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Play map 0, Best: wave 12'), findsOneWidget);
    expect(find.bySemanticsLabel('Play map 1'), findsOneWidget);
    await tester.tap(find.text('Map 1'));
    expect(tapped, [data.maps.keys.elementAt(1)]);
    handle.dispose();
  });
}
