import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/router_provider.dart';
import '../utils/money.dart';
import '../widgets/item_edit_dialog.dart';
import '../widgets/text_prompt_dialog.dart';

/// S03 – OCR Review (FR-05, FR-06).
/// Lets the user correct the store, date, total and every item, and shows
/// whether the item sum matches the receipt total.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(draftReceiptProvider);
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review items')),
        body: const Center(
          child: Text('No receipt in progress. Scan one first.'),
        ),
      );
    }
    final notifier = ref.read(draftReceiptProvider.notifier);

    Future<void> addItem() async {
      final input = await showItemEditDialog(context);
      if (input == null) return;
      notifier.addItem(input.name, input.amountCents);
      final added = ref.read(draftReceiptProvider)!.items.last;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Added "${added.name}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.removeItem(added.id),
            ),
          ),
        );
    }

    Future<void> editItem(ReceiptItem item) async {
      final input = await showItemEditDialog(
        context,
        title: 'Edit item',
        initialName: item.name,
        initialCents: item.amountCents,
      );
      if (input != null) {
        notifier.updateItem(
          item.id,
          name: input.name,
          amountCents: input.amountCents,
        );
      }
    }

    void deleteItem(ReceiptItem item, int index) {
      notifier.removeItem(item.id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Deleted "${item.name}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.restoreItem(item, index),
            ),
          ),
        );
    }

    // PopScope intercepts the Back button/gesture, so unsaved work isn't
    // lost by accident. canPop: false = we decide in onPopInvokedWithResult.
    return PopScope(
      canPop: receipt.items.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final editing = ref.read(draftReceiptProvider.notifier).editingSaved;
        final discard = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(editing ? 'Discard changes?' : 'Discard this receipt?'),
            content: Text(
              editing
                  ? 'Your changes to this receipt will not be saved.'
                  : 'The scanned items will be lost.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          notifier.clear();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review items'),
          actions: [
            if (receipt.imagePath != null)
              IconButton(
                tooltip: 'View photo',
                icon: const Icon(Icons.receipt_long),
                onPressed: () => _showPhoto(context, receipt.imagePath!),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _HeaderCard(receipt: receipt),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Items (${receipt.items.length}) · tap to edit, swipe to delete',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (receipt.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No items yet. Tap "Add item" to enter them.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final (index, item) in receipt.items.indexed)
              // Dismissible = swipe-to-delete. The key must be unique and stable
              // so Flutter knows which row was removed.
              Dismissible(
                key: ValueKey(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete),
                ),
                onDismissed: (_) => deleteItem(item, index),
                child: ListTile(
                  title: Text(item.name),
                  trailing: Text(
                    formatLkr(item.amountCents),
                    style: item.amountCents < 0
                        ? const TextStyle(color: Colors.green)
                        : null,
                  ),
                  onTap: () => editItem(item),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: addItem,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ),
            _ReconcileCard(receipt: receipt),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: receipt.items.isEmpty
                  ? null
                  : () => _continue(context, receipt),
              child: const Text('Continue to assign'),
            ),
          ),
        ),
      ),
    );
  }

  /// Warns (but doesn't block) when the items don't match the total.
  /// Saving is checked again in Phase 6.
  Future<void> _continue(BuildContext context, Receipt receipt) async {
    if (!receipt.isReconciled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Totals don't match"),
          content: Text(
            'Items add up to ${formatLkr(receipt.itemsSumCents)} but the receipt '
            'total is ${formatLkr(receipt.totalCents)}. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Fix it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (context.mounted) context.push(Routes.assign);
  }

  void _showPhoto(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        // InteractiveViewer gives pinch-to-zoom for checking small print.
        child: InteractiveViewer(maxScale: 5, child: Image.file(File(path))),
      ),
    );
  }
}

/// Store, date and receipt total – all editable.
class _HeaderCard extends ConsumerWidget {
  final Receipt receipt;
  const _HeaderCard({required this.receipt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(draftReceiptProvider.notifier);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.store),
            title: Text(receipt.storeName),
            subtitle: const Text('Store'),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final name = await _askText(
                context,
                'Store name',
                receipt.storeName,
                maxLength: 60,
              );
              if (name != null) notifier.updateHeader(storeName: name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(DateFormat('d MMM yyyy').format(receipt.date)),
            subtitle: const Text('Date'),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              // The picker asserts initialDate is inside [firstDate, lastDate],
              // so widen the range if OCR read an odd date.
              final tomorrow = DateTime.now().add(const Duration(days: 1));
              final d = await showDatePicker(
                context: context,
                initialDate: receipt.date,
                firstDate: receipt.date.isBefore(DateTime(2000))
                    ? receipt.date
                    : DateTime(2000),
                lastDate: receipt.date.isAfter(tomorrow)
                    ? receipt.date
                    : tomorrow,
              );
              if (d != null) notifier.updateHeader(date: d);
            },
          ),
          ListTile(
            leading: const Icon(Icons.payments),
            title: Text(formatLkr(receipt.totalCents)),
            subtitle: const Text('Receipt total (as printed)'),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () async {
              final text = await _askText(
                context,
                'Receipt total',
                (receipt.totalCents / 100).toStringAsFixed(2),
                money: true,
              );
              if (text != null) {
                notifier.updateHeader(totalCents: parseCents(text));
              }
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _askText(
    BuildContext context,
    String label,
    String initial, {
    bool money = false,
    int maxLength = 0,
  }) => showTextPromptDialog(
    context,
    title: label,
    initial: initial,
    money: money,
    validate: (v) {
      if (v.trim().isEmpty) return 'Required';
      if (maxLength > 0 && v.trim().length > maxLength) {
        return 'Keep it under $maxLength characters';
      }
      if (money) {
        final c = parseCents(v);
        if (c == null) return 'Enter an amount like 1,250.00';
        if (c > maxAmountCents) return 'That amount is too large';
      }
      return null;
    },
  );
}

/// Item sum vs receipt total, green when they match, amber when not.
class _ReconcileCard extends StatelessWidget {
  final Receipt receipt;
  const _ReconcileCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final diff = receipt.totalCents - receipt.itemsSumCents;
    final ok = diff == 0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('reconcileCard'),
      margin: const EdgeInsets.all(16),
      color: ok ? scheme.secondaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row('Item sum', formatLkr(receipt.itemsSumCents)),
            _row('Receipt total', formatLkr(receipt.totalCents)),
            const Divider(),
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.warning_amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? 'Items match the receipt total'
                        : diff > 0
                        ? '${formatLkr(diff)} missing – an item may not have been read'
                        : 'Items are ${formatLkr(-diff)} over the total',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}
