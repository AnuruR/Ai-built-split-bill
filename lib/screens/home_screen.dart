import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../providers/auth_provider.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/receipts_provider.dart';
import '../providers/router_provider.dart';
import '../providers/service_providers.dart';
import '../providers/sync_controller.dart';
import '../services/auth_service.dart';
import '../services/receipt_filter.dart';
import '../utils/money.dart';
import '../widgets/error_retry.dart';
import '../widgets/receipt_tile.dart';
import '../widgets/split_summary_view.dart';
import '../widgets/sync_banner.dart';

/// S01 – Home: scan button, this month's category summary, recent receipts.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider);
    ref.watch(syncControllerProvider); // background retry while offline

    return Scaffold(
      appBar: AppBar(
        title: const Text('SnapSplit'),
        actions: [
          IconButton(
            tooltip: 'People',
            icon: const Icon(Icons.group),
            onPressed: () => context.push(Routes.people),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.scan),
        icon: const Icon(Icons.document_scanner),
        label: const Text('Scan receipt'),
      ),
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(
            child: receipts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(receiptsProvider),
              ),
              data: (list) => RefreshIndicator(
                // Pull down to reload from Supabase.
                onRefresh: () => ref.refresh(receiptsProvider.future),
                child: list.isEmpty
                    ? const _EmptyHome()
                    : _HomeContent(receipts: list),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final offlineRepo = ref.read(offlineReceiptRepositoryProvider);
    final pending = await offlineRepo.pendingCount();
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        // Signing out deletes this phone's copy, so unsynced changes would be lost.
        content: pending > 0
            ? Text(
                '$pending change(s) have not synced yet and will be LOST. '
                'Connect to the internet and wait for them to sync first.',
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(draftReceiptProvider.notifier).clear();
    // Remove this user's offline copy from the phone (privacy).
    await offlineRepo.clearLocal();
    // The router's redirect sends us to /login automatically.
    await ref.read(authServiceProvider).signOut();
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();
  @override
  Widget build(BuildContext context) => ListView(
    // A ListView (not Center) so pull-to-refresh still works.
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 80),
      Icon(
        Icons.receipt_long,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      const Text(
        'No receipts yet',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tap "Scan receipt" to photograph a bill and split it with friends.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _HomeContent extends StatelessWidget {
  final List<Receipt> receipts;
  const _HomeContent({required this.receipts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final thisMonth = ReceiptFilter.inMonth(receipts, now);
    final monthTotal = thisMonth.fold<int>(0, (s, r) => s + r.totalCents);
    final categories = ReceiptFilter.categoryTotals(thisMonth);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(now),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  formatLkr(monthTotal),
                  style: theme.textTheme.headlineMedium,
                ),
                Text('${thisMonth.length} receipt(s) this month'),
                if (categories.isNotEmpty) ...[
                  const Divider(height: 24),
                  // Top 5 categories; the rest are in History.
                  CategoryBars(totals: categories.take(5).toList()),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent receipts',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.history),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final r in receipts.take(5)) ReceiptTile(receipt: r),
            ],
          ),
        ),
      ],
    );
  }
}
