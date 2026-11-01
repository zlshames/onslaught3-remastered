# Branding sources

Inputs of `tool/gen_app_icons.dart`, which writes every platform's app icon and
launch image (`fvm dart run tool/gen_app_icons.dart`).

| File | What | Provenance |
|---|---|---|
| `turret_red.png` | the Red turret with its missile launcher, 2098 px, transparent (twice the largest output, so every icon is a downscale) | `.legacy/Onslaught2.swf` symbol 910 `TurretRed`, exported with FFDec 26.3: `java -jar ffdec-cli.jar -zoom 48 -selectid 910 -format sprite:png -export sprite <out> .legacy/Onslaught2.swf` (ffdec-asset-export skill) |

The icon background is the classic ground texture
(`assets/images/classic/ground_classic@3x.jpg`); the launch screens use the
menus' backdrop colour `#1B1F22`. Original art by the original game's author;
the credits on the main menu keep the attribution.
