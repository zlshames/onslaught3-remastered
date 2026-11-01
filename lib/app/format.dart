import 'package:flutter/widgets.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'strings.dart';

/// [number] (as written, an optional minus sign then digits and maybe a
/// fraction) with commas between each group of three integer digits:
/// `3000000` → `3,000,000`, `-1234.5` → `-1,234.5`.
String groupThousands(String number) => number.replaceAllMapped(
  RegExp(r'^(-?)(\d+)'),
  (m) => '${m[1]}${m[2]!.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',')}',
);

/// An amount of cash as the player reads it in [context]'s language: whole
/// dollars, thousands grouped, the currency from `ui.common.cash`
/// (`$3,000`).
String formatCash(BuildContext context, GameData data, num value) =>
    data.tr(context, 'ui.common.cash', {'amount': groupThousands(value.toStringAsFixed(0))});
