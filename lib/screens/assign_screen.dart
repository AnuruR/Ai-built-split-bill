import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/people_provider.dart';
import '../providers/router_provider.dart';
import '../services/split_calculator.dart';
import '../utils/money.dart';
import '../services/auth_service.dart';
import '../widgets/error_retry.dart';
import '../widgets/person_name_dialog.dart';

/// Returns the split error for an item, or null if it is valid.
/// Unassigned items are reported separately, not as errors.
String? splitError(ReceiptItem item) {
  if (item.personIds.isEmpty) return null;
  try {
    SplitCalculator.splitItem(item);
    return null;
  } on SplitException catch (e) {
    return e.message;
  }
}

/// S04 – Categorize & Assign (FR-07, FR-08, FR-09, FR-10).
class AssignScreen extends ConsumerWidget {
  const AssignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(draftReceiptProvider);
    final peopleAsync = ref.watch(peopleProvider);
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categorize & assign')),
        body: const Center(child: Text('No receipt in progress.')),
      );
    }
    final people = peopleAsync.value ?? const <Person>[];
    final draft = ref.read(draftReceiptProvider.notifier);

    final unassigned = receipt.items.where((i) => i.personIds.isEmpty).length;
    final invalid = receipt.items.where((i) => splitError(i) != null).length;

    Future<void> addPerson() async {
      final n = ref.read(peopleProvider.notifier);
      final name = await showPersonNameDialog(context, validate: n.validateName);
      if (name != null) await n.add(name);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorize & assign'),
        actions: [
          IconButton(
            tooltip: 'Add person',
            icon: const Icon(Icons.person_add),
            onPressed: addPerson,
          ),
        ],
      ),
      body: peopleAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : peopleAsync.hasError
          ? ErrorRetry(
              message: friendlyError(peopleAsync.error!),
              onRetry: () => ref.invalidate(peopleProvider),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                if (people.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Add the people sharing this bill'),
                      trailing: FilledButton(onPressed: addPerson, child: const Text('Add')),
                    ),
                  )
                else if (unassigned > 0)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.group),
                      title: Text('$unassigned item(s) not assigned'),
                      subtitle: const Text('Split them equally between everyone?'),
                      trailing: TextButton(
                        onPressed: () => draft.assignUnassigned([for (final p in people) p.id]),
                        child: const Text('Everyone'),
                      ),
                    ),
                  ),
                for (final item in receipt.items) _ItemCard(item: item, people: people),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (unassigned > 0 || invalid > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  [
                    if (unassigned > 0) '$unassigned not assigned',
                    if (invalid > 0) '$invalid with split errors',
                  ].join(' · '),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              // Every item must be fully and validly assigned before the summary.
              onPressed: (unassigned == 0 && invalid == 0 && receipt.items.isNotEmpty)
                  ? () => context.push(Routes.summary)
                  : null,
              child: const Text('See summary'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ItemCard extends ConsumerWidget {
  final ReceiptItem item;
  final List<Person> people;
  const _ItemCard({required this.item, required this.people});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.read(draftReceiptProvider.notifier);
    final error = splitError(item);
    final theme = Theme.of(context);
    // Only show computed amounts when the split is valid.
    final allocations = (item.personIds.isNotEmpty && error == null)
        ? {for (final a in SplitCalculator.splitItem(item)) a.personId: a.allocatedCents}
        : const <String, int>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(item.name, style: theme.textTheme.titleMedium)),
            Text(formatLkr(item.amountCents), style: theme.textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: item.categoryId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: [
              for (final c in Category.defaults) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => v == null ? null : draft.setCategory(item.id, v),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 0, children: [
            for (final p in people)
              FilterChip(
                label: Text(allocations.containsKey(p.id)
                    ? '${p.name} · ${formatLkr(allocations[p.id]!)}'
                    : p.name),
                selected: item.personIds.contains(p.id),
                onSelected: (_) => draft.togglePerson(item.id, p.id),
              ),
          ]),
          if (item.personIds.length > 1) ...[
            const SizedBox(height: 8),
            SegmentedButton<SplitMethod>(
              segments: const [
                ButtonSegment(value: SplitMethod.equal, label: Text('Equal')),
                ButtonSegment(value: SplitMethod.exact, label: Text('Exact')),
                ButtonSegment(value: SplitMethod.percentage, label: Text('%')),
              ],
              selected: {item.method},
              onSelectionChanged: (s) => draft.setMethod(item.id, s.first),
            ),
            if (item.method != SplitMethod.equal)
              for (final id in item.personIds)
                _ShareField(
                  // The key includes the method and people so the field resets
                  // when those change (the defaults change too).
                  key: ValueKey('${item.id}-$id-${item.method.name}-${item.personIds.join(",")}'),
                  label: people.firstWhere((p) => p.id == id,
                      orElse: () => Person(id: id, name: '?')).name,
                  isPercent: item.method == SplitMethod.percentage,
                  initial: item.shares[id] ?? 0,
                  onChanged: (v) => draft.setShare(item.id, id, v),
                ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}

/// A text field for one person's exact amount (Rs.) or percentage.
/// Both are stored with 2 decimals as ints (cents / basis points), so the
/// same parseCents() works for "33.33" % -> 3333 bp.
class _ShareField extends StatefulWidget {
  final String label;
  final bool isPercent;
  final int initial;
  final ValueChanged<int> onChanged;
  const _ShareField({
    super.key,
    required this.label,
    required this.isPercent,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_ShareField> createState() => _ShareFieldState();
}

class _ShareFieldState extends State<_ShareField> {
  late final _controller = TextEditingController(text: (widget.initial / 100).toStringAsFixed(2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: widget.label,
          prefixText: widget.isPercent ? null : 'Rs. ',
          suffixText: widget.isPercent ? '%' : null,
        ),
        // Invalid text counts as 0 so the calculator shows the mismatch.
        onChanged: (t) => widget.onChanged(parseCents(t) ?? 0),
      ),
    );
  }
}
