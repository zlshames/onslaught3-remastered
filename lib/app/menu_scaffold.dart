import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/persistence/profile.dart';
import 'providers.dart';
import 'strings.dart';
import 'theme.dart';

/// Sends the system back (Android's Back button or gesture) to
/// [onBack] instead of letting it close the app: screens navigate with
/// `context.go`, so each route is the only page on the stack and a plain
/// pop would leave the app. With [onBack] null the pop goes through (the
/// main menu still exits). Dialogs above the page close first, as usual.
class SystemBack extends StatelessWidget {
  const SystemBack({super.key, required this.onBack, required this.child});

  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: onBack == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack?.call();
    },
    child: child,
  );
}

/// A menu page: a dark backdrop, a back button, a title and the page body,
/// laid out for phones in either orientation. The system back does what the back
/// button does ([SystemBack]).
class MenuScaffold extends ConsumerWidget {
  const MenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final Widget child;

  /// Back navigation, for the back button and the system back; no back
  /// button (and the system back leaves the app) when null.
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SystemBack(
    onBack: onBack,
    child: Scaffold(
      backgroundColor: AppColours.backdrop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        toolbarHeight: 48,
        leading: onBack == null
            ? null
            : IconButton(
                tooltip: ref.tr(context, 'ui.common.back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
        automaticallyImplyLeading: false,
        title: Text(title),
        actions: actions,
      ),
      body: SafeArea(top: false, child: child),
    ),
  );
}

/// The game data and the player's profile, once both are loaded; a spinner
/// (or the error) until then.
class MenuData extends ConsumerWidget {
  const MenuData({super.key, required this.builder});

  final Widget Function(BuildContext context, GameData data, Profile profile) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncGate(
    value: asyncBoth(ref.watch(gameDataProvider), ref.watch(profileProvider)),
    errorPadding: const EdgeInsets.all(16),
    builder: (context, both) => builder(context, both.$1, both.$2),
  );
}

/// [a] and [b] together: data once both have it, the first error while
/// either has failed, loading otherwise (as a switch over the pair would
/// read them).
AsyncValue<(A, B)> asyncBoth<A, B>(AsyncValue<A> a, AsyncValue<B> b) => switch ((a, b)) {
  (AsyncData(value: final x), AsyncData(value: final y)) => AsyncData((x, y)),
  (AsyncError(:final error, :final stackTrace), _) ||
  (_, AsyncError(:final error, :final stackTrace)) => AsyncError(error, stackTrace),
  _ => const AsyncLoading(),
};

/// What a page shows for an [AsyncValue] it needs: [builder] once it has
/// data, the error (`ui.menu.loadError`, or the error alone when the game
/// data itself failed to load) while it has failed, [loading] until then.
/// [errorFrame] puts the error message in the page's frame (a
/// [MenuScaffold], a plain [Scaffold]); by default it stands alone.
class AsyncGate<T> extends ConsumerWidget {
  const AsyncGate({
    super.key,
    required this.value,
    required this.builder,
    this.errorFrame,
    this.errorStyle = const TextStyle(color: Colors.white),
    this.errorPadding = EdgeInsets.zero,
    this.loading = const Center(child: CircularProgressIndicator()),
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T value) builder;

  /// The page around the error message (the message alone when null).
  final Widget Function(BuildContext context, Widget message)? errorFrame;

  /// The error text's style: white, for the dark menu backdrop.
  final TextStyle errorStyle;

  /// Space around the error text.
  final EdgeInsetsGeometry errorPadding;

  /// What shows while loading.
  final Widget loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (value) {
    AsyncData(value: final v) => builder(context, v),
    AsyncError(:final error) => _error(context, ref, error),
    _ => loading,
  };

  Widget _error(BuildContext context, WidgetRef ref, Object error) {
    final message = Center(
      child: Padding(
        padding: errorPadding,
        child: Text(
          // The error text alone when the data itself failed to load.
          ref.watch(gameDataProvider).value?.tr(context, 'ui.menu.loadError', {'error': error}) ??
              '$error',
          style: errorStyle,
        ),
      ),
    );
    return errorFrame?.call(context, message) ?? message;
  }
}
