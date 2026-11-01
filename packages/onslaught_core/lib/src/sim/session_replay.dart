import 'game_command.dart';
import 'game_event.dart';
import 'game_session.dart';

/// Rebuilds a game from its command log: steps a fresh [session] (made from
/// the same config and data) to [toTick], sending each command at the step
/// it was logged against. The simulation is deterministic, so the result is
/// the logged game exactly; the session re-logs the commands as it goes, so
/// it can carry on and be saved again. Silent: events go only to [onEvent].
///
/// Runs in slices ([advance]) so an app can keep drawing while a long game
/// is rebuilt.
class SessionReplay {
  SessionReplay(this.session, this.commands, this.toTick, {this.onEvent})
    : assert(session.tick == 0, 'replay into a fresh session');

  final GameSession session;
  final List<ScheduledCommand> commands;

  /// The step the log was saved at; commands logged against it are sent
  /// but left pending, as they were.
  final int toTick;

  /// Sees every event the rebuilt steps produce.
  final void Function(GameEvent event)? onEvent;

  int _next = 0;

  /// Steps done so far.
  int get done => session.tick;

  bool get finished => session.tick >= toTick;

  /// Runs up to [maxSteps] steps; returns [finished].
  bool advance(int maxSteps) {
    var steps = 0;
    while (session.tick < toTick && steps < maxSteps) {
      _sendDue();
      final events = session.step();
      final listener = onEvent;
      if (listener != null) events.forEach(listener);
      steps++;
    }
    if (finished) _sendDue();
    return finished;
  }

  /// Runs to the end in one go.
  void runToEnd() => advance(toTick);

  void _sendDue() {
    while (_next < commands.length && commands[_next].tick <= session.tick) {
      session.enqueue(commands[_next++].command);
    }
  }
}
