import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/logging/app_logging.dart';
import '../services/logging/log_level.dart';
import '../services/logging/log_service.dart';
import '../services/logging/log_share.dart';
import '../services/persistence/settings.dart';
import 'dialogs.dart';
import 'providers.dart';
import 'settings_form.dart';
import 'strings.dart';

/// Settings → Diagnostics: how much the log keeps, and the log files
/// exported as a zip (to attach to a bug report) or deleted.
class DiagnosticsSettings extends ConsumerStatefulWidget {
  const DiagnosticsSettings({super.key, required this.settings, required this.data});

  final Settings settings;
  final GameData data;

  /// Finds the export row in tests.
  static const Key exportKey = Key('diagnostics.export');

  /// Finds the clear row in tests.
  static const Key clearKey = Key('diagnostics.clear');

  @override
  ConsumerState<DiagnosticsSettings> createState() => _DiagnosticsSettingsState();
}

class _DiagnosticsSettingsState extends ConsumerState<DiagnosticsSettings> {
  static const Logger _log = Logger('settings');

  bool _busy = false;

  String _tr(String key, [Map<String, Object?> args = const {}]) =>
      widget.data.tr(context, key, args);

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Where the share sheet points from (iPad, Mac): the row at [row].
  static Rect? _origin(BuildContext row) {
    final box = row.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export(BuildContext row) async {
    final subject = _tr('ui.settings.exportLogsSubject');
    final origin = _origin(row);
    setState(() => _busy = true);
    try {
      final archive = await ref.read(appLoggingProvider).export();
      final result = await ref
          .read(logSharerProvider)
          .share(archive, subject: subject, origin: origin);
      if (!mounted) return;
      if (result is LogSaved) _say(_tr('ui.settings.exportLogsSaved', {'path': result.path}));
    } on Object catch (e, st) {
      _log.error('exporting the logs failed', error: e, stackTrace: st);
      if (mounted) _say(_tr('ui.settings.exportLogsFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final yes = await confirm(
      context,
      title: _tr('ui.settings.clearLogsTitle'),
      body: _tr('ui.settings.clearLogsBody'),
      action: _tr('ui.settings.clearLogs'),
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(appLoggingProvider).clear();
      if (mounted) _say(_tr('ui.settings.clearLogsDone'));
    } on Object catch (e, st) {
      _log.error('clearing the logs failed', error: e, stackTrace: st);
      if (mounted) _say(_tr('ui.settings.clearLogsFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.settings.logLevelChoice ?? AppLogging.defaultLevel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            _tr('ui.settings.diagnostics'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SettingChoiceTile(
          title: _tr('ui.settings.logLevel'),
          info: _tr('ui.settings.logLevelInfo'),
          choice: (expanded) => DropdownButton<LogLevel>(
            isExpanded: expanded,
            value: level,
            onChanged: (v) {
              if (v == null) return;
              ref.read(settingsProvider.notifier).save(widget.settings.copyWith(logLevel: v));
            },
            items: [
              for (final l in LogLevel.choices)
                DropdownMenuItem(value: l, child: Text(_tr(_levelKey(l)))),
            ],
          ),
        ),
        Builder(
          builder: (row) => ListTile(
            key: DiagnosticsSettings.exportKey,
            title: Text(_tr('ui.settings.exportLogs')),
            subtitle: Text(_tr('ui.settings.exportLogsInfo')),
            trailing: _busy
                ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator())
                : const Icon(Icons.ios_share),
            enabled: !_busy,
            onTap: () => _export(row),
          ),
        ),
        ListTile(
          key: DiagnosticsSettings.clearKey,
          title: Text(_tr('ui.settings.clearLogs')),
          subtitle: Text(_tr('ui.settings.clearLogsInfo')),
          trailing: const Icon(Icons.delete_outline),
          enabled: !_busy,
          onTap: _clear,
        ),
      ],
    );
  }

  static String _levelKey(LogLevel l) => switch (l) {
    LogLevel.trace => 'ui.settings.logLevelTrace',
    LogLevel.debug => 'ui.settings.logLevelDebug',
    LogLevel.info => 'ui.settings.logLevelNormal',
    LogLevel.warning => 'ui.settings.logLevelWarning',
    LogLevel.error || LogLevel.fatal => 'ui.settings.logLevelError',
  };
}
