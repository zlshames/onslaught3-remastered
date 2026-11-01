import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught3_remastered/features/game/layout/hud_layout.dart';

import '../../../goldens/devices.dart';

/// Classic landscape must not change (owner, 2026-10-19): on every
/// landscape golden size it is still the v1 layout, top bar 48 and tray 76.
void main() {
  for (final d in {...GoldenDevices.all, ...GoldenDevices.landscapeExtra}.entries) {
    test('${d.key} ${d.value}: Classic landscape is the v1 layout', () {
      final l = HudLayout.resolve(d.value, EdgeInsets.zero, skin: UiSkin.classic);
      expect(l.kind, HudLayoutKind.bars);
      expect(l.fillsMap, isFalse);
      expect(l.mapInsets, const EdgeInsets.only(top: 48, right: 76));
      expect(l.stats, Rect.fromLTWH(0, 0, d.value.width, 48));
      expect(l.tray, Rect.fromLTRB(d.value.width - 76, 48, d.value.width, d.value.height));
      expect(l.sheetEdgeFor(Offset(10, d.value.height - 10)), SheetEdge.bottom);
      // The map area is never narrow enough for the compact HUD forms.
      expect(l.map.width, greaterThanOrEqualTo(HudMetrics.compactBelow));
    });
  }
}
