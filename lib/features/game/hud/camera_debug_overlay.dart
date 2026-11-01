import 'package:flutter/material.dart';

import '../camera/camera_controls.dart';

/// `--dart-define=DEBUG_OVERLAY=true`: camera readout (zoom, centre) and
/// zoom/fit buttons, so the camera can be checked where pinch cannot be
/// scripted (adb has no multi-touch).
class CameraDebugOverlay extends StatelessWidget {
  const CameraDebugOverlay({super.key, required this.controls});

  final CameraControls controls;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ValueListenableBuilder<CameraReadout>(
              valueListenable: controls.cameraReadout,
              builder: (context, r, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _button(Icons.zoom_out, 'Zoom out', controls.zoomOut),
                  _button(Icons.fit_screen, 'Fit map', controls.fitMap),
                  _button(Icons.zoom_in, 'Zoom in', controls.zoomIn),
                  const SizedBox(width: 8),
                  // Wraps on a narrow portrait phone rather than overflowing.
                  Flexible(
                    child: Text(
                      'zoom ${r.zoom.toStringAsFixed(3)} '
                      '(${r.relativeZoom.toStringAsFixed(2)}× fit)  '
                      'centre ${r.center.dx.toStringAsFixed(1)},'
                      '${r.center.dy.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback onPressed) => IconButton(
    tooltip: label,
    icon: Icon(icon, color: Colors.white),
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    onPressed: onPressed,
  );
}
