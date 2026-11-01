/// How serious a log record is, least to most. A [LogService] keeps the
/// records at or above its level and drops the rest before any work is done
/// on them.
enum LogLevel {
  /// Step-by-step detail (every route change, every document read).
  trace('trace', 'TRACE'),

  /// Detail that helps find a bug (what was loaded, what was chosen).
  debug('debug', 'DEBUG'),

  /// Things the player did or the app decided (a game started, a mod applied).
  info('info', 'INFO'),

  /// Something went wrong and the app carried on (a sound could not play).
  warning('warning', 'WARN'),

  /// Something failed that the player may notice (a save failed).
  error('error', 'ERROR'),

  /// The app cannot carry on as it was (an uncaught error).
  fatal('fatal', 'FATAL');

  const LogLevel(this.id, this.label);

  /// The stored value (`Settings.logLevelChoice`).
  final String id;

  /// The fixed-width tag written in a log line.
  final String label;

  /// The level a player can choose in Settings, least detail first.
  static const List<LogLevel> choices = [error, warning, info, debug, trace];

  /// The level stored as [id], or null when none (or an unknown one) is stored.
  static LogLevel? tryFromId(String? id) => values.where((l) => l.id == id).firstOrNull;

  /// Whether a record at [other] is kept by a service at this level.
  bool allows(LogLevel other) => other.index >= index;
}
