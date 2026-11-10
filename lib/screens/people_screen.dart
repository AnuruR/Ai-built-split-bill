import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/person.dart';
import '../providers/draft_receipt_provider.dart';
import '../providers/people_provider.dart';
import '../services/auth_service.dart';
import '../services/supabase_repositories.dart';
import '../widgets/error_retry.dart';
import '../widgets/sync_banner.dart';
import '../widgets/person_name_dialog.dart';

/// Manage the people you split with (FR-08).
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final notifier = ref.read(peopleProvider.notifier);

    Future<void> add() async {
      final name = await showPersonNameDialog(
        context,
        validate: notifier.validateName,
      );
      if (name == null) return;
      try {
        await notifier.add(name);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      }
    }

    Future<void> rename(Person p) async {
      final name = await showPersonNameDialog(
        context,
        title: 'Rename',
        initial: p.name,
        validate: (n) => notifier.validateName(n, exceptId: p.id),
      );
      if (name != null) await notifier.rename(p.id, name);
    }

    Future<void> delete(Person p) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Remove ${p.name}?'),
          content: const Text(
            'They will be removed from the receipt you are editing. '
            'Saved receipts are not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await notifier.remove(p.id); // database first: it may refuse
        ref.read(draftReceiptProvider.notifier).removePersonEverywhere(p.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is PersonInUseException ? e.toString() : friendlyError(e),
              ),
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.person_add),
        label: const Text('Add person'),
      ),
      // .when handles all three AsyncValue states.
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(
            child: people.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorRetry(
                message: friendlyError(e),
                onRetry: () =>
                    ref.invalidate(peopleProvider), // re-runs build()
              ),
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Text(
                        'No people yet. Add the friends you split bills with.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        for (final p in list)
                          ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                p.name.characters.first.toUpperCase(),
                              ),
                            ),
                            title: Text(p.name),
                            onTap: () => rename(p),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => delete(p),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
