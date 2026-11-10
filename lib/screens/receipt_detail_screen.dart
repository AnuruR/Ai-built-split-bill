import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/people_provider.dart';
import '../providers/receipts_provider.dart';
import '../providers/router_provider.dart';
import '../services/auth_service.dart';
import '../widgets/error_retry.dart';
import '../widgets/split_summary_view.dart';

/// A saved receipt: its summary, Edit (FR-13) and Delete.
class ReceiptDetailScreen extends ConsumerWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider);
    final people = {for (final p in ref.watch(peopleProvider).value ?? <Person>[]) p.id: p.name};

    return receipts.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(message: friendlyError(e), onRetry: () => ref.invalidate(receiptsProvider)),
      ),
      data: (list) {
        final receipt = list.where((r) => r.id == receiptId).firstOrNull;
        if (receipt == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This receipt no longer exists.')),
          );
        }
        final hasPhoto = receipt.imagePath != null && File(receipt.imagePath!).existsSync();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Receipt'),
            actions: [
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, receipt),
              ),
            ],
          ),
          body: SplitSummaryView(
            receipt: receipt,
            people: people,
            header: [
              if (hasPhoto)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        insetPadding: const EdgeInsets.all(8),
                        child: InteractiveViewer(
                            maxScale: 5, child: Image.file(File(receipt.imagePath!))),
                      ),
                    ),
                    child: Image.file(File(receipt.imagePath!), height: 140, fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Edit & recalculate'),
                onPressed: () {
                  // Load into the draft and reuse the S03 → S04 → S05 flow.
                  // Saving keeps the same id, so the receipt is replaced.
                  ref.read(draftReceiptProvider.notifier).startEditing(receipt);
                  context.push(Routes.review);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Receipt receipt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text('"${receipt.storeName}" and its split will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(receiptsProvider.notifier).delete(receipt.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt deleted')));
      context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }
}
