import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a dialog with one validated text field. Returns the trimmed text,
/// or null if cancelled.
///
/// Why a StatefulWidget? The TextEditingController must live exactly as
/// long as the TextField. The dialog's Future completes when it STARTS
/// closing, but the field is still drawn during the closing animation, so
/// disposing the controller there crashes ("used after being disposed").
/// State.dispose() runs only after the widget is really gone.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String? Function(String) validate,
  String initial = '',
  String label = '',
  String? fieldKey,
  bool money = false,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      validate: validate,
      initial: initial,
      label: label,
      fieldKey: fieldKey,
      money: money,
      capitalization: capitalization,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? Function(String) validate;
  final String initial;
  final String label;
  final String? fieldKey;
  final bool money;
  final TextCapitalization capitalization;

  const _TextPromptDialog({
    required this.title,
    required this.validate,
    required this.initial,
    required this.label,
    required this.fieldKey,
    required this.money,
    required this.capitalization,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: widget.fieldKey == null ? null : Key(widget.fieldKey!),
          controller: _controller,
          autofocus: true,
          textCapitalization: widget.capitalization,
          keyboardType: widget.money ? const TextInputType.numberWithOptions(decimal: true) : null,
          inputFormatters:
              widget.money ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
          decoration: InputDecoration(
            labelText: widget.label.isEmpty ? null : widget.label,
            prefixText: widget.money ? 'Rs. ' : null,
          ),
          validator: (v) => widget.validate(v ?? ''),
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
