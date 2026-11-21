import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../budget/optimizer_screen.dart';
import '../prices/compare_prices_screen.dart';
import '../receipt/receipt_scan_screen.dart';

const _sections = ['vegetables', 'fruits', 'cereals', 'meat', 'dairy', 'cooking', 'household'];

class ShoppingListDetailScreen extends StatelessWidget {
  final String listId;
  const ShoppingListDetailScreen({super.key, required this.listId});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = s.listById(listId);
    if (l == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(emoji: '🛒', title: 'List not found', message: 'It may have been deleted.'));
    }
    final grouped = <String, List<ShoppingItem>>{};
    for (final i in l.items) {
      grouped.putIfAbsent(_sections.contains(i.category) ? i.category : 'household', () => []).add(i);
    }
    final remaining = l.remaining;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share), onPressed: () => ExportService.share(l, s.catalog.supermarkets)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'pdf':
                  await ExportService.exportPdf(l, s.catalog.supermarkets);
                case 'rename':
                  await _rename(context, s, l);
                case 'shop':
                  await _pickShop(context, s, l);
                case 'budget':
                  await _editBudget(context, s, l);
                case 'compare':
                  if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComparePricesScreen(listId: l.id)));
                case 'save':
                  await s.saveList(ShoppingList(
                    id: s.newId(),
                    userId: l.userId,
                    name: '${l.name} (copy)',
                    supermarketId: l.supermarketId,
                    budget: l.budget,
                    items: [for (final i in l.items) i.copyWith(purchased: false, clearActual: true)],
                    createdAt: DateTime.now(),
                  ));
                  if (context.mounted) showSnack(context, 'Saved a copy for next time.');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export as PDF')),
              PopupMenuItem(value: 'compare', child: Text('Compare supermarkets')),
              PopupMenuItem(value: 'shop', child: Text('Change supermarket')),
              PopupMenuItem(value: 'budget', child: Text('Change budget')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'save', child: Text('Save a copy for future use')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 140), children: [
        Text('${l.items.length} items · ${s.catalog.supermarkets[l.supermarketId]?.name ?? 'Cheapest anywhere'}',
            style: const TextStyle(color: GrubColors.muted)),
        const SizedBox(height: 10),
        if (l.items.any((i) => i.priceStatus == 'demo' || i.priceStatus == 'estimated')) const DemoBanner(),
        if (l.items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(emoji: '📝', title: 'Empty list', message: 'Tap "Add product" to start.'),
          ),
        for (final sec in _sections)
          if (grouped[sec] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text((productCategories[sec] ?? sec).toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: GrubColors.muted, letterSpacing: 0.8)),
            ),
            for (final item in grouped[sec]!) _ItemRow(list: l, item: item),
          ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OptimizerScreen())),
          icon: const Icon(Icons.savings_outlined),
          label: const Text('Find savings'),
        ),
      ]),
      bottomSheet: _Totals(list: l, remaining: remaining),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton.small(
          backgroundColor: GrubColors.green,
          foregroundColor: Colors.white,
          tooltip: 'Add product',
          onPressed: () => _addProduct(context, s, l),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, AppState s, ShoppingList l) async {
    final c = TextEditingController(text: l.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
      ),
    );
    if (v != null && v.isNotEmpty) await s.saveList(l.copyWith(name: v));
  }

  Future<void> _editBudget(BuildContext context, AppState s, ShoppingList l) async {
    final c = TextEditingController(text: l.budget.shillings.round().toString());
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Budget for this list'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: 'KSh '),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('Save'))],
      ),
    );
    if (v != null) await s.saveList(l.copyWith(budget: Money.ksh(v)));
  }

  Future<void> _pickShop(BuildContext context, AppState s, ShoppingList l) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: const Text('Cheapest anywhere'), onTap: () => Navigator.pop(ctx, '')),
          for (final sm in s.catalog.shops) ListTile(title: Text(sm.name), subtitle: Text(sm.location), onTap: () => Navigator.pop(ctx, sm.id)),
        ]),
      ),
    );
    if (id == null) return;
    // Re-price catalogue items at the chosen shop; manual prices stay.
    final items = [
      for (final i in l.items)
        if (i.productId.isEmpty || i.priceStatus == 'manual')
          i
        else
          () {
            final p = s.catalog.products[i.productId];
            if (p == null) return i;
            final fresh = s.itemForProduct(p, 1, id);
            final perPack = fresh.requiredBase <= 0 ? 1.0 : fresh.requiredBase;
            final packs = (i.requiredBase / perPack - 1e-6).ceil().clamp(1, 1000).toInt();
            final updated = s.itemForProduct(p, packs, id);
            return i.copyWith(unitPrice: updated.unitPrice, packages: updated.packages, quantityLabel: updated.quantityLabel, priceStatus: updated.priceStatus);
          }(),
    ];
    await s.saveList(l.copyWith(supermarketId: id, items: items));
  }

  Future<void> _addProduct(BuildContext context, AppState s, ShoppingList l) async {
    final result = await showModalBottomSheet<ShoppingItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddProductSheet(list: l),
    );
    if (result != null) await s.addItem(l, result);
  }
}

class _ItemRow extends StatelessWidget {
  final ShoppingList list;
  final ShoppingItem item;
  const _ItemRow({required this.list, required this.item});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => s.removeItem(list, item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: GrubColors.danger,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: InkWell(
        onTap: () => _edit(context, s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            EmojiTile(item.emoji, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: item.purchased ? TextDecoration.lineThrough : null,
                      color: item.purchased ? GrubColors.muted : GrubColors.ink,
                    )),
                Row(children: [
                  Flexible(child: Text(item.quantityLabel, style: const TextStyle(fontSize: 12, color: GrubColors.muted), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  PriceBadge(item.priceStatus),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(item.total.format(), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (item.packages > 1) Text('${item.unitPrice.format()} each', style: const TextStyle(fontSize: 10, color: GrubColors.muted)),
            ]),
            Checkbox(
              value: item.purchased,
              activeColor: GrubColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              onChanged: (v) {
                HapticFeedback.selectionClick();
                s.updateItem(list, item.copyWith(purchased: v ?? false));
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState s) async {
    final qty = TextEditingController(text: '${item.packages}');
    final price = TextEditingController(text: item.unitPrice.shillings.toStringAsFixed(item.unitPrice.cents % 100 == 0 ? 0 : 2));
    final actual = TextEditingController(text: item.actualPrice == null ? '' : item.actualPrice!.shillings.toStringAsFixed(0));
    final result = await showModalBottomSheet<ShoppingItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: Theme.of(ctx).textTheme.titleLarge),
          Text(item.quantityLabel, style: const TextStyle(color: GrubColors.muted)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: qty,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Quantity (packs / pieces)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Estimated price each', prefixText: 'KSh '),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: actual,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Actual amount paid (optional)', prefixText: 'KSh '),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(qty.text) ?? item.packages;
              final pr = double.tryParse(price.text.replaceAll(',', ''));
              final ac = double.tryParse(actual.text.replaceAll(',', ''));
              final newPrice = pr == null ? item.unitPrice : Money.ksh(pr);
              final changedPrice = newPrice != item.unitPrice;
              final perPack = item.packages == 0 ? 0.0 : item.requiredBase / item.packages;
              Navigator.pop(
                ctx,
                item.copyWith(
                  packages: n < 1 ? 1 : n,
                  unitPrice: newPrice,
                  priceStatus: changedPrice ? 'manual' : item.priceStatus,
                  quantityLabel: n == item.packages ? item.quantityLabel : _relabel(item.quantityLabel, n),
                  actualPrice: ac == null ? null : Money.ksh(ac),
                  clearActual: ac == null,
                  purchased: ac != null ? true : item.purchased,
                ).withRequired(perPack * (n < 1 ? 1 : n)),
              );
            },
            child: const Text('Save'),
          ),
          if (item.productId.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _reportPrice(context, s);
              },
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Report the shelf price I saw'),
            ),
          ],
        ]),
      ),
    );
    if (result != null) await s.updateItem(list, result);
  }

  String _relabel(String label, int n) {
    final base = label.contains('×') ? label.split('×').last.trim() : label;
    if (RegExp(r'^\d+(\.\d+)? (pcs|bunch|bunches)$').hasMatch(base)) {
      return '$n ${base.split(' ').last}';
    }
    return n == 1 ? base : '$n × $base';
  }

  Future<void> _reportPrice(BuildContext context, AppState s) async {
    final p = s.catalog.products[item.productId];
    if (p == null) return;
    var shop = list.supermarketId.isNotEmpty ? list.supermarketId : (s.catalog.supermarkets.keys.isEmpty ? '' : s.catalog.supermarkets.keys.first);
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Report price: ${p.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: shop.isEmpty ? null : shop,
              items: [for (final sm in s.catalog.shops) DropdownMenuItem(value: sm.id, child: Text(sm.name))],
              onChanged: (v) => setS(() => shop = v ?? shop),
              decoration: const InputDecoration(labelText: 'Shop'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Price for ${p.defaultPackageLabel}', prefixText: 'KSh '),
            ),
            const SizedBox(height: 8),
            const Text('Reports are checked by the Grub team before they become "verified".', style: TextStyle(fontSize: 11, color: GrubColors.muted)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    final v = double.tryParse(price.text);
    if (ok != true || v == null || shop.isEmpty) return;
    await s.reportPrice(productId: p.id, supermarketId: shop, price: v, packageSize: p.defaultPackageSize, packageLabel: p.defaultPackageLabel);
    if (context.mounted) showSnack(context, 'Thanks! Your price was submitted for review.');
  }
}

extension on ShoppingItem {
  ShoppingItem withRequired(double base) => ShoppingItem(
        id: id,
        productId: productId,
        name: name,
        emoji: emoji,
        category: category,
        quantityLabel: quantityLabel,
        requiredBase: base,
        packages: packages,
        unitPrice: unitPrice,
        purchased: purchased,
        actualPrice: actualPrice,
        priceStatus: priceStatus,
      );
}

class _Totals extends StatelessWidget {
  final ShoppingList list;
  final Money remaining;
  const _Totals({required this.list, required this.remaining});
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final over = remaining.isNegative;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, -4))],
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Estimated total', style: TextStyle(fontSize: 12, color: GrubColors.muted)),
              TweenAnimationBuilder<int>(
                tween: IntTween(end: list.estimatedTotal.cents),
                duration: const Duration(milliseconds: 300),
                builder: (_, v, __) => Text(Money(v).format(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(over ? 'Over budget by' : 'Remaining budget', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
              Text((over ? -remaining : remaining).format(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: over ? GrubColors.danger : GrubColors.green)),
            ]),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: list.purchasedCount == 0 ? null : () => _finish(context, s),
            child: Text(list.purchasedCount == 0 ? 'Tick items as you shop' : 'Finish shopping · ${list.purchasedCount} bought'),
          ),
        ]),
      ),
    );
  }

  Future<void> _finish(BuildContext context, AppState s) async {
    final ctrl = TextEditingController(text: list.actualTotal.shillings.round().toString());
    var addToPantry = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Finish shopping'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Estimated for bought items: ${list.purchasedEstimate.format()}'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'What did you actually pay?', prefixText: 'KSh '),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: addToPantry,
              onChanged: (v) => setS(() => addToPantry = v ?? true),
              title: const Text('Add bought items to my pantry'),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiptScanScreen()));
              },
              child: const Text('Scan receipt instead'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final paid = double.tryParse(ctrl.text.replaceAll(',', ''));
    final e = await s.completeShopping(list, actualTotal: paid == null ? null : Money.ksh(paid), addToPantry: addToPantry);
    if (context.mounted) {
      final diff = (e.estimated ?? e.amount) - e.amount;
      showSnack(context, diff.isNegative ? 'Saved. You spent ${(-diff).format()} more than estimated.' : 'Saved. You spent ${diff.format()} less than estimated 🎉');
    }
  }
}

class _AddProductSheet extends StatefulWidget {
  final ShoppingList list;
  const _AddProductSheet({required this.list});
  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  String _q = '';
  final _customName = TextEditingController();
  final _customPrice = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final products = s.catalog.products.values.where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase())).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
          Expanded(
            child: ListView(children: [
              for (final p in products)
                Builder(builder: (_) {
                  final item = s.itemForProduct(p, 1, widget.list.supermarketId);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(p.emoji, style: const TextStyle(fontSize: 26)),
                    title: Text(p.name),
                    subtitle: Text(item.quantityLabel),
                    trailing: Text(item.unitPrice.isZero ? '—' : item.unitPrice.format(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => Navigator.pop(context, item),
                  );
                }),
              const Divider(),
              const Text('Something else?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _customName, decoration: const InputDecoration(hintText: 'e.g. Tissue paper'))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _customPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'Price', prefixText: 'KSh '),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: GrubColors.green, size: 32),
                  onPressed: () {
                    if (_customName.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      ShoppingItem(
                        id: s.newId(),
                        name: _customName.text.trim(),
                        quantityLabel: '1',
                        unitPrice: Money.ksh(double.tryParse(_customPrice.text) ?? 0),
                        priceStatus: 'manual',
                      ),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        ]),
      ),
    );
  }
}
