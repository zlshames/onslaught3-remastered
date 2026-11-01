import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/format.dart';

import '../support/test_data.dart';

void main() {
  test('groupThousands groups the integer digits only', () {
    expect(groupThousands('0'), '0');
    expect(groupThousands('999'), '999');
    expect(groupThousands('1000'), '1,000');
    expect(groupThousands('3000000'), '3,000,000');
    expect(groupThousands('-1234'), '-1,234');
    expect(groupThousands('12345.678'), '12,345.678');
    expect(groupThousands('1e+21'), '1e+21');
  });

  testWidgets('formatCash: whole dollars, grouped, through ui.common.cash', (tester) async {
    final data = loadTestGameData();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(data.text('ui.common.cash'), r'${amount}');
    expect(formatCash(context, data, 30), r'$30');
    expect(formatCash(context, data, 3000), r'$3,000');
    expect(formatCash(context, data, 3000000), r'$3,000,000');
    expect(formatCash(context, data, 1234.6), r'$1,235');
  });
}
