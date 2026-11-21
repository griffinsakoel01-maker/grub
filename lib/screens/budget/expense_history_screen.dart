import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ExpenseHistoryScreen extends StatelessWidget {
  const ExpenseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final byMonth = <String, List<Expense>>{};
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    for (final e in s.expenses) {
      byMonth.putIfAbsent('${names[e.date.month - 1]} ${e.date.year}', () => []).add(e);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Expense history')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: GrubColors.green,
        foregroundColor: Colors.white,
        onPressed: () => showAddExpense(context),
        child: const Icon(Icons.add),
      ),
      body: s.expenses.isEmpty
          ? EmptyState(emoji: '🧾', title: 'No expenses yet', message: 'Record what you spend on groceries to see where your money goes.', actionLabel: 'Add purchase', onAction: () => showAddExpense(context))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
              for (final m in byMonth.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Row(children: [
                    Text(m.key, style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text(Money.sum(m.value.map((e) => e.amount)).format(), style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
                  ]),
                ),
                for (final e in m.value) ExpenseTile(expense: e, deletable: true),
              ],
            ]),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final bool deletable;
  const ExpenseTile({super.key, required this.expense, this.deletable = false});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final e = expense;
    final diff = e.estimated == null ? null : e.estimated! - e.amount;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        onTap: () => showAddExpense(context, existing: e),
        child: Row(children: [
          const EmojiTile('🧾', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.note.isEmpty ? 'Groceries' : e.note, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${e.date.day}/${e.date.month}/${e.date.year}${s.catalog.supermarkets[e.supermarketId] != null ? ' · ${s.catalog.supermarkets[e.supermarketId]!.name}' : ''}',
                  style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(e.amount.format(), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (diff != null)
              Text(diff.isNegative ? '+${(-diff).format()} vs est.' : '-${diff.format()} vs est.',
                  style: TextStyle(fontSize: 11, color: diff.isNegative ? GrubColors.danger : GrubColors.green)),
          ]),
        ]),
      ),
    );
    if (!deletable) return tile;
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => s.deleteExpense(e),
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: GrubColors.danger)),
      child: tile,
    );
  }
}

/// Add or edit a purchase.
Future<void> showAddExpense(BuildContext context, {Expense? existing}) async {
  final s = context.read<AppState>();
  final amount = TextEditingController(text: existing == null ? '' : existing.amount.shillings.round().toString());
  final est = TextEditingController(text: existing?.estimated == null ? '' : existing!.estimated!.shillings.round().toString());
  final note = TextEditingController(text: existing?.note ?? '');
  var shop = existing?.supermarketId ?? '';
  var date = existing?.date ?? DateTime.now();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(existing == null ? 'Add purchase' : 'Edit purchase', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: existing == null,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Amount paid', prefixText: 'KSh '),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: est,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Estimated cost (optional)', prefixText: 'KSh '),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (e.g. weekly shop)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: shop.isEmpty ? null : shop,
            decoration: const InputDecoration(labelText: 'Shop (optional)'),
            items: [for (final sm in s.catalog.supermarkets.values) DropdownMenuItem(value: sm.id, child: Text(sm.name))],
            onChanged: (v) => setS(() => shop = v ?? ''),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('${date.day}/${date.month}/${date.year}'),
            onTap: () async {
              final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: date);
              if (d != null) setS(() => date = d);
            },
          ),
          FilledButton(
            onPressed: () async {
              final a = int.tryParse(amount.text);
              if (a == null || a <= 0) return;
              final e = int.tryParse(est.text);
              await s.saveExpense(Expense(
                id: existing?.id ?? s.newId(),
                userId: s.user!.uid,
                amount: Money.ksh(a),
                estimated: e == null ? null : Money.ksh(e),
                note: note.text.trim(),
                supermarketId: shop,
                date: date,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
          if (existing != null)
            TextButton(
              onPressed: () async {
                await s.deleteExpense(existing);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: GrubColors.danger)),
            ),
        ]),
      ),
    ),
  );
}
