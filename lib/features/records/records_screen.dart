import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/custom_record_list.dart';
import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';

/// The custom games' records (`/records`; owner decision, 2026-10-19): the
/// best game on each version of each player map and on each built-in map
/// played with a mod. Custom games never count towards the standard
/// progress (`RulesProfile.customGamesSeparate`), so their results live
/// here instead.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(mapLibraryProvider).value;
    return MenuScaffold(
      title: ref.tr(context, 'ui.records.title'),
      onBack: () => context.go('/'),
      child: MenuData(
        builder: (context, data, profile) => CustomRecordList(
          data: data,
          custom: profile.custom,
          currentVersions: {
            for (final m in library?.maps ?? const <MapDefinition>[]) m.id: mapVersionHash(m),
          },
        ),
      ),
    );
  }
}
