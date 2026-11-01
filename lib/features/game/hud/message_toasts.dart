import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../game_view_model.dart';

/// In-game messages as toasts under the top bar (the original's message
/// window, `TurretInfoMessages`): each new message shows for [duration],
/// one at a time, oldest first.
class MessageToasts extends StatefulWidget {
  const MessageToasts({super.key, required this.viewModel, this.duration = defaultDuration});

  final GameViewModel viewModel;
  final Duration duration;

  static const Duration defaultDuration = Duration(seconds: 4);

  @override
  State<MessageToasts> createState() => _MessageToastsState();
}

class _MessageToastsState extends State<MessageToasts> {
  final List<GameMessage> _queue = [];
  GameMessage? _shown;
  int _seen = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.viewModel.messages.addListener(_onMessages);
    _onMessages();
  }

  @override
  void dispose() {
    widget.viewModel.messages.removeListener(_onMessages);
    _timer?.cancel();
    super.dispose();
  }

  void _onMessages() {
    final all = widget.viewModel.messages.value;
    if (all.length <= _seen) return;
    _queue.addAll(all.skip(_seen));
    _seen = all.length;
    if (_shown == null) _next();
  }

  void _next() {
    _timer?.cancel();
    setState(() => _shown = _queue.isEmpty ? null : _queue.removeAt(0));
    if (_shown != null) _timer = Timer(widget.duration, _next);
  }

  @override
  Widget build(BuildContext context) {
    final m = _shown;
    return IgnorePointer(
      ignoring: m == null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: m == null
            ? const SizedBox.shrink()
            : Semantics(
                key: ValueKey(m.seq),
                liveRegion: true,
                child: GestureDetector(
                  onTap: _next,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420, minHeight: 48),
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: HudColours.panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: m.alert ? Colors.amberAccent : Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m.alert ? Icons.campaign : Icons.info_outline,
                          size: 18,
                          color: m.alert ? Colors.amberAccent : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(m.text, style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
