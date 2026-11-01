import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// A snapshot of the camera for the debug overlay and tests.
@immutable
class CameraReadout {
  const CameraReadout({
    required this.zoom,
    required this.relativeZoom,
    required this.center,
    required this.viewport,
  });

  static const CameraReadout initial = CameraReadout(
    zoom: 1,
    relativeZoom: 1,
    center: Offset.zero,
    viewport: Size.zero,
  );

  /// Screen logical px per world px.
  final double zoom;

  /// Zoom relative to fit-whole-map.
  final double relativeZoom;

  /// World point at the centre of the screen.
  final Offset center;
  final Size viewport;

  @override
  bool operator ==(Object other) =>
      other is CameraReadout &&
      other.zoom == zoom &&
      other.relativeZoom == relativeZoom &&
      other.center == center &&
      other.viewport == viewport;

  @override
  int get hashCode => Object.hash(zoom, relativeZoom, center, viewport);
}

/// Camera commands widgets may issue without importing Flame (rule R2).
abstract interface class CameraControls {
  ValueListenable<CameraReadout> get cameraReadout;
  void zoomIn();
  void zoomOut();
  void fitMap();
}
