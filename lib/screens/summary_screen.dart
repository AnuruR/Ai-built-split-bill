import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/people_provider.dart';
import '../providers/receipts_provider.dart';
import '../providers/router_provider.dart';
import '../providers/service_providers.dart';
import '../services/auth_service.dart';
import '../services/split_calculator.dart';
import '../utils/money.dart';
import '../widgets/split_summary_view.dart';

/// S05 – Split Summary (FR-11): totals for the receipt being created or
/// edited, and Save / Update.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});
  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  bool _saving = false;

  Future<void> _save(Receipt receipt) async {
    // Calculation rule: warn before saving if items don't match the total.
    if (!receipt.isReconciled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Totals don't match"),
          content: Text('Items add up to ${formatLkr(receipt.itemsSumCents)}, but the '
              'receipt says ${formatLkr(receipt.totalCents)}. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final draft = ref.read(draftReceiptProvider.notifier);
    final wasEditing = draft.editingSaved;
    setState(() => _saving = true);
    try {
      await ref.read(receiptRepositoryProvider).save(receipt);
      ref.invalidate(receiptsProvider); // Home/History reload
      if (!mounted) return;
      draft.clear();
      final queued = ref.read(syncStatusProvider).pending > 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(queued
            ? "Saved on this phone. It will sync when you're online."
            : wasEditing
                ? 'Receipt updated'
                : 'Receipt saved'),
      ));
      // go() resets the stack so Back doesn't return into the finished flow.
      context.go(wasEditing ? '${Routes.history}/${receipt.id}' : Routes.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = ref.watch(draftReceiptProvider);
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Summary')),
        body: const Center(child: Text('No receipt in progress.')),
      );
    }
    final people = {for (final p in ref.watch(peopleProvider).value ?? <Person>[]) p.id: p.name};
    final editing = ref.read(draftReceiptProvider.notifier).editingSaved;

    var canSave = true;
    try {
      canSave = SplitCalculator.summarize(receipt.items).unassignedCents == 0;
    } on SplitException {
      canSave = false;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Summary')),
      body: SplitSummaryView(receipt: receipt, people: people),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving || !canSave ? null : () => _save(receipt),
            icon: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving
                ? 'Saving…'
                : editing
                    ? 'Update receipt'
                    : 'Save receipt'),
          ),
        ),
      ),
    );
  }
}
