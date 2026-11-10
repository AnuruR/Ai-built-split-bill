import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/people_provider.dart';
import '../providers/receipts_provider.dart';
import '../providers/service_providers.dart';

/// Shows "Offline", "N changes waiting to sync" or a sync error.
/// Hidden when everything is online and synced.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    void syncNow() {
      ref.invalidate(receiptsProvider);
      ref.invalidate(peopleProvider);
    }

    if (s.lastError != null) {
      return _bar(
        color: scheme.errorContainer,
        icon: Icons.sync_problem,
        text: s.lastError!,
        action: TextButton(
          onPressed: () => ref.read(syncStatusProvider.notifier).update((x) => x.copyWith(lastError: () => null)),
          child: const Text('Dismiss'),
        ),
      );
    }
    if (!s.offline && s.pending == 0) return const SizedBox.shrink();

    final text = [
      if (s.offline) "You're offline – showing data saved on this phone.",
      if (s.pending > 0) '${s.pending} change(s) waiting to sync.',
    ].join(' ');
    return _bar(
      color: scheme.tertiaryContainer,
      icon: s.offline ? Icons.cloud_off : Icons.cloud_upload,
      text: text,
      action: TextButton(onPressed: syncNow, child: const Text('Sync now')),
    );
  }

  Widget _bar({required Color color, required IconData icon, required String text, required Widget action}) =>
      Material(
        color: color,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            action,
          ]),
        ),
      );
}
