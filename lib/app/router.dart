import 'package:go_router/go_router.dart';

import '../features/editor/map_editor_screen.dart';
import '../features/editor/map_library_screen.dart';
import '../features/game/attract_view.dart';
import '../features/game/game_screen.dart';
import '../features/menu/challenge_screen.dart';
import '../features/menu/home_screen.dart';
import '../features/menu/map_screen.dart';
import '../features/menu/mode_screen.dart';
import '../features/menu/settings_screen.dart';
import '../features/mods/mods_screen.dart';
import '../features/records/records_screen.dart';

/// Screen routes (`docs/REMASTER_PLAN.md` §3.4): `/` main menu (the attract
/// demo behind it) → `/mode` → `/map` → `/game/<map>`; `/challenge` → `/map`;
/// `/tutorial`; `/settings`; `/records` (custom games' records); `/mods` (the
/// mod editor, `?field=<item>.<asset>` opens a value); `/maps` (the player's
/// maps) → `/editor` (`?map=<id>` edits one). Query parameters carry what is being played:
/// `mode`, `difficulty` and `challenge` (a challenge key). A player map plays
/// at `/game/<its id>`.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(background: AttractView()),
    ),
    GoRoute(path: '/mode', builder: (context, state) => const ModeScreen()),
    GoRoute(
      path: '/map',
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return MapScreen(
          mode: q['mode'] ?? GameScreen.defaultMode,
          difficulty: q['difficulty'] ?? GameScreen.defaultDifficulty,
          challengeKey: q['challenge'],
        );
      },
    ),
    GoRoute(
      path: '/challenge',
      builder: (context, state) =>
          ChallengeScreen(initialKey: state.uri.queryParameters['challenge']),
    ),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/records', builder: (context, state) => const RecordsScreen()),
    GoRoute(
      path: '/mods',
      builder: (context, state) => ModsScreen(initialField: state.uri.queryParameters['field']),
    ),
    GoRoute(path: '/maps', builder: (context, state) => const MapLibraryScreen()),
    GoRoute(
      path: '/editor',
      builder: (context, state) => MapEditorScreen(mapId: state.uri.queryParameters['map']),
    ),
    GoRoute(path: '/tutorial', builder: (context, state) => const GameScreen.tutorial()),
    GoRoute(path: '/resume', builder: (context, state) => const GameScreen.resume()),
    GoRoute(
      path: '/game/:mapId',
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return GameScreen(
          mapId: state.pathParameters['mapId']!,
          mode: q['mode'] ?? GameScreen.defaultMode,
          difficulty: q['difficulty'] ?? GameScreen.defaultDifficulty,
          challengeKey: q['challenge'],
        );
      },
    ),
  ],
);
