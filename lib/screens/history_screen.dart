import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers/receipts_provider.dart';
import '../services/auth_service.dart';
import '../services/receipt_filter.dart';
import '../utils/money.dart';
import '../widgets/error_retry.dart';
import '../widgets/receipt_tile.dart';
import '../widgets/sync_banner.dart';

/// S06 – Receipt History (FR-12): search by store/item, filter by category
/// and date range, open a receipt.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _categoryId;
  DateTimeRange? _range;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasFilters => _query.isNotEmpty || _categoryId != null || _range != null;

  void _clearFilters() => setState(() {
        _search.clear();
        _query = '';
        _categoryId = null;
        _range = null;
      });

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day + 1),
      initialDateRange: _range,
    );
    if (r != null) setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsProvider);
    final dateFmt = DateFormat('d MMM');

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(children: [
        const SyncBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search store or item',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            FilterChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(_range == null
                  ? 'Any date'
                  : '${dateFmt.format(_range!.start)} – ${dateFmt.format(_range!.end)}'),
              selected: _range != null,
              onSelected: (_) => _pickRange(),
            ),
            const SizedBox(width: 8),
            for (final c in Category.defaults)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (sel) => setState(() => _categoryId = sel ? c.id : null),
                ),
              ),
          ]),
        ),
        Expanded(
          child: receipts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorRetry(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(receiptsProvider),
            ),
            data: (all) {
              final shown = ReceiptFilter.apply(all,
                  query: _query, categoryId: _categoryId, from: _range?.start, to: _range?.end);
              final total = shown.fold<int>(0, (s, r) => s + r.totalCents);
              return RefreshIndicator(
                onRefresh: () => ref.refresh(receiptsProvider.future),
                child: ListView(
                  children: [
                    if (all.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No saved receipts yet.', textAlign: TextAlign.center),
                      )
                    else if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(children: [
                          const Text('No receipts match these filters.', textAlign: TextAlign.center),
                          TextButton(onPressed: _clearFilters, child: const Text('Clear filters')),
                        ]),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Row(children: [
                          Expanded(child: Text('${shown.length} receipt(s)')),
                          Text('Total ${formatLkr(total)}'),
                          if (_hasFilters)
                            TextButton(onPressed: _clearFilters, child: const Text('Clear')),
                        ]),
                      ),
                      for (final r in shown) ReceiptTile(receipt: r),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
