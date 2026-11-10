import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../providers/router_provider.dart';
import '../utils/money.dart';

/// One saved receipt in a list (Home and History). Tap to open it.
class ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  const ReceiptTile({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final people = receipt.items.expand((i) => i.personIds).toSet().length;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
      title: Text(receipt.storeName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${DateFormat('d MMM yyyy').format(receipt.date)} · '
          '${receipt.items.length} items · $people ${people == 1 ? 'person' : 'people'}'),
      trailing: Text(formatLkr(receipt.totalCents),
          style: Theme.of(context).textTheme.titleSmall),
      onTap: () => context.push('${Routes.history}/${receipt.id}'),
    );
  }
}
