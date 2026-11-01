// Packs FFDec sprite exports into an asset pack (atlases at every exported
// density, standalone images, sounds) and writes its manifest. Called by
// tool/export_assets.sh once per pack; can be re-run on an existing export:
//
//   fvm dart run tool/pack_atlas.dart --ffdec <export dir> [--map tool/asset_map.json]
//
// Packs: tool/asset_map.json → classic (the original art and sounds);
//        tool/asset_map_enhanced.json → enhanced (vector redraws of the
//        creeps for Enhanced games, layered over classic).
// Inputs:  the pack's asset map (logical id → symbol), the FFDec export
//          (<dir>/png<N>x/DefineSprite_<id>[_Name]/<frame>.png for each
//          density N the export script rendered, and
//          <dir>/svg/… for each frame's size and registration point; shape
//          symbols (`"kind": "shape"`) as <dir>/shape_png<N>x/<id>.png and
//          <dir>/shape_svg/<id>.svg),
//          docs/legacy/legacy_values.json (sound files per event).
// Outputs: assets/images/<pack>/{atlas_<N>x_<page>.png, <image>@<N>x.jpg,
//          manifest.json}, and for a map with "sounds": "legacy"
//          assets/audio/<pack>/<clip>.mp3.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as img;
import 'package:onslaught_core/data_generator.dart';

const _pageSize = 2048; // image px; every GPU we target samples textures this large
const _padding = 2; // image px between cells
const _imageMaxScale = 3; // standalone images are bitmaps (720×480 ground); no detail above this

void main(List<String> argv) {
  final args =
      (ArgParser()
            ..addOption('ffdec', mandatory: true)
            ..addOption('map', defaultsTo: 'tool/asset_map.json'))
          .parse(argv);
  final ffdec = args['ffdec'] as String;
  final mapPath = args['map'] as String;
  final map = (jsonDecode(File(mapPath).readAsStringSync()) as Map).cast<String, Object?>();
  final pack = map['pack'] as String? ?? 'classic';
  final outImages = 'assets/images/$pack';
  final sprites = (map['sprites']! as Map).cast<String, Object?>();
  final images = (map['images'] as Map?)?.cast<String, Object?>() ?? const {};
  final scales = [
    for (final d in Directory(ffdec).listSync().whereType<Directory>())
      ?RegExp(r'^png(\d+)x$').firstMatch(d.uri.pathSegments.where((s) => s.isNotEmpty).last)?[1],
  ].map(int.parse).toList()..sort();
  if (scales.isEmpty) throw StateError('no png<N>x exports under $ffdec');

  // 1. Load every frame at every scale plus its SVG metadata.
  final frames = <_Frame>[];
  for (final e in sprites.entries) {
    final spec = (e.value! as Map).cast<String, Object?>();
    final symbol = spec['symbol']! as int;
    if (spec['kind'] == 'shape') {
      // A single-frame shape (e.g. a turret body without its weapon).
      final meta = _svgMeta(File('$ffdec/shape_svg/$symbol.svg').readAsStringSync());
      frames.add(
        _Frame(e.key, 0, meta, {
          for (final s in scales)
            s: img.decodePng(File('$ffdec/shape_png${s}x/$symbol.png').readAsBytesSync())!,
        }),
      );
      continue;
    }
    var svgs = _frameFiles(_symbolDir('$ffdec/svg', symbol), '.svg');
    if (spec['frames'] == 'first') svgs = svgs.take(1).toList();
    // A vector redraw replaces symbols that are only a small bitmap in
    // the SWF (the creeps); FFDec's export still gives each frame's size
    // and registration point, so the redraw drops into the same frame.
    final redraw = spec['svg'] as String?;
    for (var i = 0; i < svgs.length; i++) {
      final meta = _svgMeta(svgs[i].readAsStringSync());
      final name = svgs[i].uri.pathSegments.last.replaceAll('.svg', '');
      frames.add(
        _Frame(e.key, i, meta, {
          for (final s in scales)
            s: () {
              final png = img.decodePng(
                File('${_symbolDir('$ffdec/png${s}x', symbol).path}/$name.png').readAsBytesSync(),
              )!;
              return redraw == null ? png : _rasterizeSvg(redraw, png.width, png.height);
            }(),
        }),
      );
    }
  }

  // 2–3. Lay out and render pages per scale. Each density has its own
  // layout so dense atlases split into more pages while small ones stay few;
  // a sprite's frames stay together so a renderer can load only the pages of
  // the sprites it draws.
  Directory(outImages).createSync(recursive: true);
  for (final f in Directory(outImages).listSync().whereType<File>()) {
    f.deleteSync();
  }
  final atlases = <String, List<String>>{};
  final pageCounts = <int, int>{};
  for (final s in scales) {
    final cells = _layout(frames, s);
    final pageCount = cells.values.map((c) => c.page).fold(0, math.max) + 1;
    pageCounts[s] = pageCount;
    final paths = <String>[];
    for (var p = 0; p < pageCount; p++) {
      final used = frames.where((f) => cells[f]!.page == p).toList();
      final w = used.map((f) => cells[f]!.x + f.images[s]!.width).fold(1, math.max);
      final h = used.map((f) => cells[f]!.y + f.images[s]!.height).fold(1, math.max);
      final canvas = img.Image(width: _align4(w), height: _align4(h), numChannels: 4);
      for (final f in used) {
        img.compositeImage(
          canvas,
          f.images[s]!,
          dstX: cells[f]!.x,
          dstY: cells[f]!.y,
          blend: img.BlendMode.direct,
        );
      }
      final path = '$outImages/atlas_${s}x_$p.png';
      File(path).writeAsBytesSync(img.encodePng(canvas, level: 9));
      paths.add(path);
    }
    atlases['$s'] = paths;
    for (final f in frames) {
      f.rects[s] = [
        cells[f]!.page,
        cells[f]!.x,
        cells[f]!.y,
        f.images[s]!.width,
        f.images[s]!.height,
      ];
    }
  }

  final manifestSprites = <String, Map<String, Object?>>{};
  for (final f in frames) {
    final list = (manifestSprites[f.id] ??= {'frames': <Object?>[]})['frames']! as List<Object?>;
    list.add({
      'w': f.meta.width,
      'h': f.meta.height,
      'ax': f.meta.originX,
      'ay': f.meta.originY,
      'rects': {for (final s in scales) '$s': f.rects[s]},
    });
  }

  // 4. Standalone images (the ground) after the atlas pages.
  for (final e in images.entries) {
    final spec = (e.value! as Map).cast<String, Object?>();
    final src = img.decodeImage(File(spec['file']! as String).readAsBytesSync())!;
    final w = spec['width']! as int;
    final h = spec['height']! as int;
    final rects = <String, Object?>{};
    for (final s in scales.where((s) => s <= _imageMaxScale)) {
      final resized = img.copyResize(
        src,
        width: w * s,
        height: h * s,
        interpolation: img.Interpolation.cubic,
      );
      final path = '$outImages/${e.key.replaceAll('.', '_')}@${s}x.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(resized, quality: 88));
      atlases['$s']!.add(path);
      rects['$s'] = [atlases['$s']!.length - 1, 0, 0, w * s, h * s];
    }
    manifestSprites[e.key] = {
      'frames': [
        {'w': w, 'h': h, 'ax': 0, 'ay': 0, 'rects': rects},
      ],
    };
  }

  // 5. Sounds referenced by the legacy sound events (copied unchanged:
  // no loudness normaliser is installed on this machine). Only a pack whose
  // map says "sounds": "legacy" (classic) carries them.
  final sounds = <String, String>{};
  if (map['sounds'] == 'legacy') {
    final outAudio = 'assets/audio/$pack';
    final legacy = (jsonDecode(File('docs/legacy/legacy_values.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
    final events = ((legacy['engine']! as Map)['soundEvents']! as Map).cast<String, Object?>();
    final audioDir = Directory(outAudio)..createSync(recursive: true);
    for (final f in audioDir.listSync().whereType<File>()) {
      f.deleteSync();
    }
    for (final files in events.values) {
      for (final f in (files! as List<Object?>).cast<String>()) {
        final clip = legacyClipId(f);
        final dest = '$outAudio/${clip.substring('sfx.'.length)}.mp3';
        File('.legacy/dissassembled/sounds/$f').copySync(dest);
        sounds[clip] = dest;
      }
    }
  }

  final manifest = {
    'schemaVersion': 2,
    'pack': pack,
    'source':
        'tool/export_assets.sh (JPEXS FFDec 26.3) from .legacy/Onslaught2.swf; symbols in $mapPath',
    'scales': scales,
    'atlases': atlases,
    if (map['theme'] case final Map<String, Object?> theme) 'theme': theme,
    'sprites': Map.fromEntries(
      manifestSprites.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'sounds': Map.fromEntries(sounds.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
  };
  File('$outImages/manifest.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  print(
    'Packed $pack: ${frames.length} frames of ${manifestSprites.length} sprites; pages per scale '
    '${pageCounts.entries.map((e) => '${e.key}x: ${e.value}').join(', ')}; ${sounds.length} sounds.',
  );
}

class _Meta {
  const _Meta(this.width, this.height, this.originX, this.originY);
  final double width;
  final double height;
  final double originX;
  final double originY;
}

class _Frame {
  _Frame(this.id, this.index, this.meta, this.images);
  final String id;
  final int index;
  final _Meta meta;
  final Map<int, img.Image> images;

  /// Per scale: `[page, x, y, w, h]` in that scale's atlas.
  final Map<int, List<int>> rects = {};
}

class _Cell {
  _Cell(this.page, this.x, this.y);
  final int page;
  final int x;
  final int y;
}

/// Shelf packing of scale [s] in image px. Sprites are placed whole (their
/// frames in order), tallest sprite first (ties by id, so the output is
/// deterministic). A frame larger than a page gets a page of its own sized
/// to fit.
Map<_Frame, _Cell> _layout(List<_Frame> frames, int s) {
  int cellW(_Frame f) => f.images[s]!.width + _padding;
  int cellH(_Frame f) => f.images[s]!.height + _padding;
  final bySprite = <String, List<_Frame>>{};
  for (final f in frames) {
    (bySprite[f.id] ??= []).add(f);
  }
  int tallest(List<_Frame> fs) => fs.map(cellH).fold(0, math.max);
  final order = bySprite.entries.toList()
    ..sort((a, b) {
      final h = tallest(b.value).compareTo(tallest(a.value));
      return h != 0 ? h : a.key.compareTo(b.key);
    });
  final cells = <_Frame, _Cell>{};
  var page = 0;
  var x = 0;
  var y = 0;
  var rowH = 0;
  var pageUsed = false;
  for (final sprite in order) {
    for (final f in sprite.value..sort((a, b) => a.index.compareTo(b.index))) {
      if (cellW(f) > _pageSize || cellH(f) > _pageSize) {
        if (pageUsed) page++;
        cells[f] = _Cell(page, 0, 0);
        page++;
        x = y = rowH = 0;
        pageUsed = false;
        continue;
      }
      if (x + cellW(f) > _pageSize) {
        x = 0;
        y += rowH;
        rowH = 0;
      }
      if (y + cellH(f) > _pageSize) {
        page++;
        x = y = rowH = 0;
      }
      cells[f] = _Cell(page, x, y);
      pageUsed = true;
      x += cellW(f);
      rowH = math.max(rowH, cellH(f));
    }
  }
  return cells;
}

int _align4(int v) => (v + 3) & ~3;

Directory _symbolDir(String root, int symbol) {
  final pattern = RegExp('^DefineSprite_$symbol(_.*)?\$');
  final dirs = Directory(root)
      .listSync()
      .whereType<Directory>()
      .where((d) => pattern.hasMatch(d.uri.pathSegments.where((s) => s.isNotEmpty).last))
      .toList();
  if (dirs.isEmpty) throw StateError('symbol $symbol not exported under $root');
  return dirs.first;
}

List<File> _frameFiles(Directory dir, String ext) =>
    dir.listSync().whereType<File>().where((f) => f.path.endsWith(ext)).toList()
      ..sort((a, b) => _frameNo(a).compareTo(_frameNo(b)));

int _frameNo(File f) => int.parse(f.uri.pathSegments.last.split('.').first);

/// Renders the SVG at [path] to exactly [width] × [height] pixels with
/// `rsvg-convert` (librsvg; developer machine only, like FFDec:
/// `brew install librsvg`).
img.Image _rasterizeSvg(String path, int width, int height) {
  final result = Process.runSync('rsvg-convert', [
    '--width=$width',
    '--height=$height',
    '--format=png',
    path,
  ], stdoutEncoding: null);
  if (result.exitCode != 0) {
    throw StateError('rsvg-convert failed for $path: ${result.stderr}');
  }
  return img.decodePng(Uint8List.fromList(result.stdout as List<int>))!.convert(numChannels: 4);
}

/// Frame size and symbol origin from FFDec's SVG: the root `<svg>`
/// width/height and the translation of the root `<g>` (world px).
_Meta _svgMeta(String svg) {
  double attr(String name) =>
      double.parse(RegExp('$name="([-\\d.E]+)px"').firstMatch(svg)!.group(1)!);
  final m = RegExp(r'<g transform="matrix\(1\.0, 0\.0, 0\.0, 1\.0, ([-\d.E]+), ([-\d.E]+)\)"')
      .firstMatch(svg);
  return _Meta(
    attr('width'),
    attr('height'),
    m == null ? 0 : double.parse(m[1]!),
    m == null ? 0 : double.parse(m[2]!),
  );
}
