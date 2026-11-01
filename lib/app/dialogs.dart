import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../services/share/share_codec.dart';
import 'strings.dart';

// Dialogs shared by the map editor and the mod editor (features may not
// import each other, rule R3).

/// Shows a share code (a map's, a mod's) with a Copy button; [hint] says
/// what to do with it (a map's hint when null).
Future<void> showShareCode(
  BuildContext context, {
  required GameData data,
  required String name,
  required String code,
  String? hint,
}) => showDialog<void>(
  context: context,
  builder: (context) => CompactDialog(
    title: data.tr(context, 'ui.dialog.shareTitle', {'name': name}),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hint ?? data.tr(context, 'ui.dialog.shareHint')),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(child: SelectableText(code, key: const Key('shareCode'))),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(data.tr(context, 'ui.common.close')),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.copy),
        label: Text(data.tr(context, 'ui.dialog.copy')),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(data.tr(context, 'ui.dialog.copied'))));
          Navigator.of(context).pop();
        },
      ),
    ],
  ),
);

/// Asks a yes/no question: [title], [body], a Cancel button ([cancel], or
/// `ui.common.cancel`) and the [action] button. True only when [action] was
/// pressed; Cancel, the system back and a tap outside answer false. The
/// caller checks `mounted` before using its state after the await.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  String? cancel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) => CompactDialog(
          title: title,
          content: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancel ?? ref.tr(context, 'ui.common.cancel')),
            ),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
          ],
        ),
      ),
    ) ??
    false;

/// What [askName] shows under the field for a name that clashes with
/// something (a map that would be replaced): the [warning] in the error
/// colour, and [action] in place of Save on the accept button.
typedef NameWarning = ({String warning, String action});

/// Asks for a name: a [label]led field holding [initial], at most
/// [maxLength] characters, that says [emptyError] while it is blank. Save
/// (or Done) returns the trimmed name; Cancel, the system back and a tap
/// outside return null. [warningBuilder], given the trimmed name, can warn
/// about it and rename the Save button. [data] gives Cancel's and Save's
/// text; [fieldKey] finds the field in tests.
Future<String?> askName(
  BuildContext context, {
  required GameData data,
  required String title,
  required String label,
  required String emptyError,
  required String initial,
  required int maxLength,
  NameWarning? Function(BuildContext context, String name)? warningBuilder,
  Key? fieldKey,
}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(
    data: data,
    title: title,
    label: label,
    emptyError: emptyError,
    initial: initial,
    maxLength: maxLength,
    warningBuilder: warningBuilder,
    fieldKey: fieldKey,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.data,
    required this.title,
    required this.label,
    required this.emptyError,
    required this.initial,
    required this.maxLength,
    this.warningBuilder,
    this.fieldKey,
  });

  final GameData data;
  final String title;
  final String label;
  final String emptyError;
  final String initial;
  final int maxLength;
  final NameWarning? Function(BuildContext context, String name)? warningBuilder;
  final Key? fieldKey;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _name => _text.text.trim();

  void _submit() {
    if (_name.isNotEmpty) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final warning = widget.warningBuilder?.call(context, _name);
    return CompactDialog(
      title: widget.title,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: widget.fieldKey,
              controller: _text,
              autofocus: true,
              maxLength: widget.maxLength,
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _name.isEmpty ? widget.emptyError : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (warning != null)
              Text(warning.warning, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(data.tr(context, 'ui.common.cancel')),
        ),
        FilledButton(
          onPressed: _name.isEmpty ? null : _submit,
          child: Text(warning?.action ?? data.tr(context, 'ui.common.save')),
        ),
      ],
    );
  }
}

/// A dialog that reads a share code (a map's, a mod's): a [label]led field
/// with a Paste button, read on every change with [decode]. A code that
/// cannot be read ([ShareCodecException]) shows [errorText]; one that can
/// shows [preview] under the field, and the [acceptLabel] button returns it
/// when [canAccept] allows. Cancel returns null. [data] gives Cancel's and
/// Paste's text; [fieldKey] finds the field in tests.
class ImportCodeDialog<T extends Object> extends StatefulWidget {
  const ImportCodeDialog({
    super.key,
    required this.data,
    required this.title,
    required this.label,
    required this.decode,
    required this.errorText,
    required this.preview,
    required this.acceptLabel,
    this.canAccept = _always,
    this.width = 460,
    this.fieldKey,
  });

  final GameData data;
  final String title;
  final String label;

  /// Reads a (non-blank) code; throws [ShareCodecException] when it can't.
  final T Function(String code) decode;

  /// The field's error for a code [decode] rejected.
  final String Function(BuildContext context, ShareCodecException e) errorText;

  /// What the read code holds, under the field.
  final Widget Function(BuildContext context, T value) preview;

  /// The accept button's text for the read code (null before one is read).
  final String Function(BuildContext context, T? value) acceptLabel;

  /// Whether the read code can be accepted (always by default).
  final bool Function(T value) canAccept;

  /// The content's width (it shrinks on a narrow phone).
  final double width;
  final Key? fieldKey;

  static bool _always(Object _) => true;

  @override
  State<ImportCodeDialog<T>> createState() => _ImportCodeDialogState<T>();
}

class _ImportCodeDialogState<T extends Object> extends State<ImportCodeDialog<T>> {
  final TextEditingController _text = TextEditingController();
  T? _value;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _read(String text) {
    setState(() {
      _value = null;
      _error = null;
      if (text.trim().isEmpty) return;
      try {
        _value = widget.decode(text);
      } on ShareCodecException catch (e) {
        _error = widget.errorText(context, e);
      }
    });
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text ?? '';
    _text.text = text;
    _read(text);
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final data = widget.data;
    return CompactDialog(
      title: widget.title,
      content: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: widget.fieldKey,
              controller: _text,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _error,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: data.tr(context, 'ui.common.paste'),
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
              onChanged: _read,
            ),
            if (value != null) ...[const SizedBox(height: 12), widget.preview(context, value)],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(data.tr(context, 'ui.common.cancel')),
        ),
        FilledButton(
          onPressed: value == null || !widget.canAccept(value)
              ? null
              : () => Navigator.of(context).pop(value),
          child: Text(widget.acceptLabel(context, value)),
        ),
      ],
    );
  }
}

/// A bottom sheet with a title and a row of large buttons (wrapping when
/// needed), short enough for a landscape phone and narrow enough for a portrait one. Returns
/// the chosen value.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, IconData, String)> choices,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (value, icon, label) in choices)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                  onPressed: () => Navigator.of(context).pop(value),
                  icon: Icon(icon),
                  label: Text(label),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

/// A dialog for phones (a landscape one with the keyboard up): title, content and
/// buttons scroll together in whatever height is left, so nothing
/// overflows (an [AlertDialog] keeps its buttons outside the scroll area).
/// Content given a fixed width shrinks to the dialog on a portrait phone.
class CompactDialog extends StatelessWidget {
  const CompactDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  /// Below this screen width (portrait phones) the dialog keeps a narrower
  /// margin.
  static const double narrowBelow = 480;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < narrowBelow ? 16 : 40,
      vertical: 8,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          content,
          OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: actions),
        ],
      ),
    ),
  );
}
