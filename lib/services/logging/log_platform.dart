/// The platform half of logging: the log folder, the system's version and
/// file writes for export. `dart:io` on every platform but the web.
library;

export 'log_store_io.dart' if (dart.library.js_interop) 'log_store_web.dart';
