import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../planner/plan_builder_screen.dart';
import '../prices/compare_prices_screen.dart';
import 'shopping_list_detail_screen.dart';
import '../../core/i18n.dart';

class ShoppingListsScreen extends StatelessWidget {
  const ShoppingListsScreen({super.key});

  Future<void> _new(BuildContext context) async {
    final s = context.read<AppState>();
    final ctrl = TextEditingController(text: 'My shopping list');
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const EmojiTile('🗓️'),
            title: const T('From my meal plan'),
            subtitle: Text(s.plan == null ? 'Plan your meals first' : 'Quantities calculated, pantry subtracted'),
            onTap: () => Navigator.pop(ctx, 'plan'),
          ),
          ListTile(
            leading: const EmojiTile('📝'),
            title: const T('Empty list'),
            subtitle: const T('Add products yourself'),
            onTap: () => Navigator.pop(ctx, 'empty'),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'plan') {
      if (s.plan == null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanBuilderScreen()));
        return;
      }
      final l = await s.createListFromPlan();
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: l.id)));
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('List name'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const T('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const T('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final l = await s.createEmptyList(name);
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: l.id)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const T('Shopping Lists'),
        actions: [
          IconButton(
            tooltip: tr('Compare prices'),
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePricesScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GrubColors.green,
        foregroundColor: Colors.white,
        onPressed: () => _new(context),
        icon: const Icon(Icons.add),
        label: const T('New list'),
      ),
      body: s.lists.isEmpty
          ? EmptyState(
              emoji: '🛒',
              title: 'No shopping lists yet',
              message: 'Plan your meals and we\'ll build the list for you – or start an empty one.',
              actionLabel: 'Create a list',
              onAction: () => _new(context),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: s.lists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final l = s.lists[i];
                final progress = l.items.isEmpty ? 0.0 : l.purchasedCount / l.items.length;
                return Dismissible(
                  key: ValueKey(l.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const T('Delete list?'),
                      content: Text('"${l.name}" will be removed.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const T('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const T('Delete', style: TextStyle(color: GrubColors.danger))),
                      ],
                    ),
                  ),
                  onDismissed: (_) => s.deleteList(l),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: GrubColors.danger, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: SoftCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: l.id))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const EmojiTile('🛒'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(l.shared ? '🏠 ${l.name}' : l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${l.items.length} items · ${s.catalog.supermarkets[l.supermarketId]?.name ?? 'Cheapest anywhere'}',
                                style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
                          ]),
                        ),
                        Text(l.estimatedTotal.format(), style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
                      ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: progress, minHeight: 6, color: GrubColors.green, backgroundColor: GrubColors.greenLight),
                      ),
                      const SizedBox(height: 4),
                      Text('${l.purchasedCount} of ${l.items.length} bought', style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
