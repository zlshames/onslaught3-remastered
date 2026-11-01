import 'package:flutter/material.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'map_thumbnail.dart';
import 'theme.dart';

/// Map tiles in a grid that fits the width: two columns on a portrait
/// phone, three on a landscape one, four on a tablet or desktop.
class MapTileGrid extends StatelessWidget {
  const MapTileGrid({super.key, required this.children});

  /// The tiles ([MapTile]s), in order.
  final List<Widget> children;

  /// The columns for a grid [width] logical px wide.
  static int columnsFor(double width) => width > 700 ? 4 : (width < 480 ? 2 : 3);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      crossAxisCount: columnsFor(box.maxWidth),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.2,
      children: children,
    ),
  );
}

/// A map as a tile: the thumbnail of its road, its [name] and, when given,
/// a [subtitle] (a map's best record). One button for screen readers, read
/// as [label] then the [subtitle].
class MapTile extends StatelessWidget {
  const MapTile({
    super.key,
    required this.map,
    required this.data,
    required this.name,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final MapDefinition map;
  final GameData data;

  /// The map's name as shown.
  final String name;

  /// What a screen reader says for the tile (the [subtitle] follows).
  final String label;
  final VoidCallback onTap;

  /// A line under the name, in amber (a best record).
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: [label, ?subtitle].join(', '),
    child: ExcludeSemantics(
      child: Material(
        color: AppColours.panel,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: data.world.playWidth / data.world.playHeight,
                  child: CustomPaint(
                    painter: MapThumbnailPainter(map: map, data: data),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (subtitle case final s?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    s,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
