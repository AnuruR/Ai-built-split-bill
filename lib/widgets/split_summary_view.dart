import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/split_calculator.dart';
import '../utils/money.dart';

/// The read-only summary of a receipt: header, warnings, per-person totals
/// with breakdown, per-category totals. Used by S05 (draft) and by the
/// saved-receipt screen, so both always look and calculate the same.
class SplitSummaryView extends StatelessWidget {
  final Receipt receipt;

  /// person id -> name
  final Map<String, String> people;

  /// Extra widgets shown above the totals (e.g. the receipt photo).
  final List<Widget> header;

  const SplitSummaryView({
    super.key,
    required this.receipt,
    required this.people,
    this.header = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final SplitSummary summary;
    final Map<String, List<(ReceiptItem, Cents)>> breakdown;
    try {
      // Recalculated from the items every time it is shown.
      summary = SplitCalculator.summarize(receipt.items);
      breakdown = SplitCalculator.breakdown(receipt.items);
    } on SplitException catch (e) {
      return Center(child: Text('Fix the split first: ${e.message}'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        ...header,
        Card(
          child: ListTile(
            title: Text(receipt.storeName, style: theme.textTheme.titleMedium),
            subtitle: Text('${DateFormat('d MMM yyyy').format(receipt.date)} · '
                '${receipt.items.length} item(s)'),
            trailing: Text(formatLkr(receipt.totalCents), style: theme.textTheme.titleLarge),
          ),
        ),
        if (!receipt.isReconciled)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text('Items total ${formatLkr(receipt.itemsSumCents)} '
                  '≠ receipt ${formatLkr(receipt.totalCents)}'),
            ),
          ),
        if (summary.unassignedCents != 0)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text('${formatLkr(summary.unassignedCents)} not assigned to anyone'),
            ),
          ),
        _title(context, 'Per person'),
        Card(
          child: Column(children: [
            for (final e in summary.perPerson.entries)
              // ExpansionTile: tap to see which items make up the total.
              ExpansionTile(
                leading: CircleAvatar(
                    child: Text((people[e.key] ?? '?').characters.first.toUpperCase())),
                title: Text(people[e.key] ?? 'Removed person'),
                trailing: Text(formatLkr(e.value), style: theme.textTheme.titleMedium),
                children: [
                  for (final (item, cents) in breakdown[e.key] ?? const <(ReceiptItem, Cents)>[])
                    ListTile(
                      dense: true,
                      title: Text(item.name),
                      subtitle: item.personIds.length > 1
                          ? Text('Shared by ${item.personIds.length} · ${item.method.name}')
                          : null,
                      trailing: Text(formatLkr(cents)),
                    ),
                ],
              ),
          ]),
        ),
        _title(context, 'Per category'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CategoryBars(
              totals: summary.perCategory.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Category name, amount and a bar showing its share of the total.
class CategoryBars extends StatelessWidget {
  final List<MapEntry<String, Cents>> totals;
  const CategoryBars({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final sum = totals.fold<int>(0, (s, e) => s + (e.value > 0 ? e.value : 0));
    return Column(children: [
      for (final e in totals)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(Category.byId(e.key).name)),
              Text(formatLkr(e.value)),
            ]),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: sum == 0 ? 0 : (e.value / sum).clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
        ),
    ]);
  }
}
