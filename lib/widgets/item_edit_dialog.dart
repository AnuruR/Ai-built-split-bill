import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/money.dart';

/// Result of [showItemEditDialog].
typedef ItemInput = ({String name, Cents amountCents});

/// Validates an item name. Public so it can be unit tested.
String? validateItemName(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter a name';
  if (s.length > maxItemNameLength) return 'Keep it under $maxItemNameLength characters';
  return null;
}

const maxItemNameLength = 80;

/// Rs. 10,000,000 – far above any grocery bill; catches OCR misreads such
/// as a barcode read as a price.
const Cents maxAmountCents = 1000000000;

/// Validates an amount typed by the user. Negative is allowed (discounts),
/// zero is not (there is nothing to split).
String? validateAmount(String? v) {
  final cents = parseCents(v ?? '');
  if (cents == null) return 'Enter an amount like 250.00';
  if (cents == 0) return 'Amount cannot be zero';
  if (cents.abs() > maxAmountCents) return 'That amount is too large';
  return null;
}

/// Dialog to add or edit an item. Returns null if cancelled.
Future<ItemInput?> showItemEditDialog(
  BuildContext context, {
  String title = 'Add item',
  String initialName = '',
  Cents? initialCents,
}) {
  return showDialog<ItemInput>(
    context: context,
    builder: (_) => _ItemEditDialog(
      title: title,
      initialName: initialName,
      initialCents: initialCents,
    ),
  );
}

class _ItemEditDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final Cents? initialCents;
  const _ItemEditDialog({required this.title, required this.initialName, this.initialCents});

  @override
  State<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<_ItemEditDialog> {
  // A GlobalKey lets us call validate() on every field in the Form at once.
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late final _amount = TextEditingController(
    text: widget.initialCents == null ? '' : (widget.initialCents! / 100).toStringAsFixed(2),
  );

  @override
  void dispose() {
    // Controllers hold resources; always dispose them.
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((name: _name.text.trim(), amountCents: parseCents(_amount.text)!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            key: const Key('itemName'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Item name'),
            validator: validateItemName,
          ),
          TextFormField(
            key: const Key('itemAmount'),
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: 'Rs. '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))],
            validator: validateAmount,
            onFieldSubmitted: (_) => _submit(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
