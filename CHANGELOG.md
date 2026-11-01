# Changelog

Player-visible changes per version (release-build skill). Deliberate departures from the
original game are listed in `docs/DEVIATIONS.md`.

## Unreleased

- On a screen with a notch or punch hole, the game's bars, tray and turret panel and the map
  editor's bars now reach the edge of the screen; only their buttons keep clear of the cut-out.

## 1.0.0-beta.1

The first public beta of Onslaught 3 Remastered: the original Onslaught 2 rebuilt for phones,
tablets, desktop and the web, playing as the original did, with its challenges, sandbox, tutorial,
map editor and mod editor, plus:

- Past the edge of the map, the sand carries on under a tint in both portrait and landscape.
- Tower placement: Settings → Tower placement chooses drag and drop, or drop and lock (release
  drops the ghost, a drag anywhere nudges it, Place builds). Drop and lock is the default in
  the Android and iOS apps.
- Leaving a game stores it, and Play offers to resume or discard it.
- Art stays sharp at every zoom, and the turret panel is shorter in portrait.
- Play in portrait or landscape: turn the device (or resize the window) at any time, even
  mid-wave, and the HUD moves to where the screen has room (a selected turret stays
  selected and the view pans to keep it in sight). In portrait the map stays
  upright between the stats bar and a tray along the bottom, and a game starts showing as much
  of it as it can; pinch or double-tap to zoom in, and pan around. Menus, Map Tools and Mods reflow too, and
  a window too small to play pauses the game until it is bigger.
- A Red's rockets that lose their target circle until the next creep comes, as in the
  original, instead of disappearing after 20 seconds.
- Rockets leave smoke trails again, as in the original; Settings → Rocket smoke and Smoke
  puffs kept (1–500, the original's range).
- Vibration on building, upgrading, selling and new weapons (Settings → Vibration).
- Follows the last original build, 2350-gaby (Slipcor's "Onslaught 2.2"): Challenge games
  unlock as soon as you start the tutorial ("Play the tutorial to unlock the challenges"),
  rocket smoke keeps up to 200 puffs by default (was 100), and sounds pan a little wider
  across the map. The game-speed setting and mod import keep working, although 2350-gaby
  disabled them (`speedSettingSaved`, `modImportPaste` in `docs/DEVIATIONS.md`).
- Colour badges: Settings → Colour badges marks Blue, Green, Red and Yellow turrets with a
  shape and a letter on the map, in the tray and in the turret sheet, so they can be told
  apart without colour vision.
- Every screen is checked for tap-target size, labels for screen readers, text contrast and
  system text at 130 %; the Settings page text is readable again on its dark background.
- Settings → Language (the game follows the device's language when a translation exists).
- Settings → Diagnostics: the game keeps a local log for bug reports (personal details such as
  e-mail addresses, user names in file paths and IP addresses are masked). Choose how much it
  records, export it as a zip to share, or clear it. Nothing is sent anywhere unless you share
  it.
- Language: German (Deutsch), machine-translated, including the tutorial, turret, combo, map
  and challenge names, the challenge pickers, the mod editor and in-game announcements.
- The difficulty is named ("Difficulty: Easy", "in Medium mode") where the original printed
  its id ("easy"); `difficultyNames` in `docs/DEVIATIONS.md`.
- Custom games: a game with a mod switched on or on one of your own maps is labelled
  "Custom game" and does not count towards unlocks, completed modes or challenge records
  (`customGamesSeparate` in `docs/DEVIATIONS.md`). Instead they keep their own records:
  the best wave, kills and score per map, mod, mode and difficulty, on the new Records page
  (main menu) and on each map in Map Tools. Editing a map's road starts a new version of its
  records; the old version's records stay.
- App icons and launch screens on every platform, made from the original Red turret.

Download sizes: Android about 37 MB (arm64), 35 MB (armv7), 38 MB (x86_64) and 75 MB (universal);
macOS about 37 MB; web about 30 MB.
