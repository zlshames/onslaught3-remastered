import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/logging/log_service.dart';
import 'providers.dart';
import 'router.dart';
import 'strings.dart';
import 'theme.dart';

/// The application shell: theme, routes and the interface language. The
/// languages offered are the data's string tables (`strings/<locale>.json`);
/// the player's choice (`Settings.locale`) wins, else the device's language
/// when the data has it, else English.
class OnslaughtApp extends ConsumerStatefulWidget {
  const OnslaughtApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  ConsumerState<OnslaughtApp> createState() => _OnslaughtAppState();
}

class _OnslaughtAppState extends ConsumerState<OnslaughtApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  static const Logger _log = Logger('navigation');
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    // The log keeps the level the player chose (Settings → Diagnostics).
    ref.listenManual(
      settingsProvider.select((s) => s.value?.logLevelChoice),
      (_, level) => ref.read(appLoggingProvider).setLevel(level),
      fireImmediately: true,
    );
    _router.routerDelegate.addListener(_logRoute);
  }

  /// Logs each screen opened, by its path only: the query (what is being
  /// played) stays out.
  void _logRoute() {
    try {
      final path = _router.routerDelegate.currentConfiguration.uri.path;
      if (path == _lastPath) return;
      _lastPath = path;
      _log.debug('screen', fields: {'path': path});
    } on Object {
      // A route that cannot be read is not worth a log line.
    }
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_logRoute);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gameDataProvider).value;
    final chosen = ref.watch(settingsProvider.select((s) => s.value?.locale));
    final supported = supportedLocalesOf(data);
    return MaterialApp.router(
      onGenerateTitle: (context) => data?.tr(context, 'app.title') ?? 'Onslaught 3 Remastered',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      locale: chosen != null && supported.contains(Locale(chosen)) ? Locale(chosen) : null,
      supportedLocales: supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
    );
  }
}
