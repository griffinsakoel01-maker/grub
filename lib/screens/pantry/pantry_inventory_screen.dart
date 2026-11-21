import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/pantry_picker.dart';
import '../recipes/recipe_detail_screen.dart';
import 'pantry_selection_screen.dart';
import '../receipt/receipt_scan_screen.dart';
import '../../core/i18n.dart';

/// Pantry & food inventory: quantities, purchase/expiry dates, storage,
/// items close to expiry and recipes that use them.
class PantryInventoryScreen extends StatelessWidget {
  const PantryInventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final expiring = s.expiringSoon();
    final items = [...s.pantry]..sort((a, b) => a.name.compareTo(b.name));
    final byStorage = <String, List<PantryItem>>{};
    for (final i in items) {
      byStorage.putIfAbsent(i.storage, () => []).add(i);
    }
    final suggestions = s.profile == null
        ? <(Recipe, int)>[]
        : s.planner.recipesUsingPantry(s.pantryMap, DietFilter.fromProfile(s.profile!), priority: {for (final e in expiring) e.productId}).take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const T('Pantry'), actions: [
        IconButton(
          tooltip: tr('Add from a receipt'),
          icon: const Icon(Icons.document_scanner_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiptScanScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GrubColors.green,
        foregroundColor: Colors.white,
        onPressed: () => _addItem(context),
        icon: const Icon(Icons.add),
        label: const T('Add item'),
      ),
      body: items.isEmpty
          ? EmptyState(
              emoji: '🥫',
              title: 'Your pantry is empty',
              message: 'Record what you have at home so Grub doesn\'t add it to your shopping list – and warns you before it expires.',
              actionLabel: 'Select what I have',
              onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantrySelectionScreen())),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
              if (expiring.isNotEmpty)
                SoftCard(
                  color: const Color(0xFFFFF4E5),
                  borderColor: const Color(0xFFFFD8A8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const T('⏰ Use soon', style: TextStyle(fontWeight: FontWeight.w800, color: GrubColors.warning)),
                    const SizedBox(height: 6),
                    for (final e in expiring)
                      Text('• ${e.name} – ${_expiryText(e)}', style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              if (suggestions.isNotEmpty) ...[
                const SectionHeader('Cook with what you have'),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final r = suggestions[i].$1;
                      return SizedBox(
                        width: 220,
                        child: SoftCard(
                          padding: const EdgeInsets.all(8),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id))),
                          child: Row(children: [
                            RecipeImage(r, height: 60, width: 60, radius: 12),
                            const SizedBox(width: 10),
                            Expanded(child: Text(r.name, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
              for (final e in byStorage.entries) ...[
                SectionHeader(_storageLabel(e.key)),
                for (final item in e.value) _row(context, s, item),
              ],
            ]),
    );
  }

  static String _storageLabel(String s) => switch (s) {
        'fridge' => '🧊 Fridge',
        'freezer' => '❄️ Freezer',
        _ => '🗄️ Cupboard',
      };

  static String _expiryText(PantryItem i) {
    final d = i.daysToExpiry(DateTime.now());
    if (d == null) return 'no expiry date';
    if (d < 0) return 'expired ${-d} day${d == -1 ? '' : 's'} ago';
    if (d == 0) return 'expires today';
    return 'expires in $d day${d == 1 ? '' : 's'}';
  }

  Widget _row(BuildContext context, AppState s, PantryItem item) {
    final p = s.catalog.products[item.productId];
    final d = item.daysToExpiry(DateTime.now());
    final warn = d != null && d <= 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: GrubColors.danger, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => s.deletePantryItem(item),
        child: SoftCard(
          padding: const EdgeInsets.all(12),
          onTap: () => _edit(context, item),
          child: Row(children: [
            EmojiTile(p?.emoji ?? '🛒'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(p == null ? '${item.quantity}' : Units.display(item.quantity, p.unit), style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
              ]),
            ),
            if (item.expiryDate != null)
              Text(_expiryText(item), style: TextStyle(fontSize: 11, color: warn ? GrubColors.danger : GrubColors.muted, fontWeight: warn ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Future<void> _addItem(BuildContext context) async {
    final s = context.read<AppState>();
    final products = s.catalog.products.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(products: products),
    );
    if (picked == null || !context.mounted) return;
    final qty = await showQuantitySheet(context, picked, picked.defaultPackageSize, title: 'How much did you buy / have?');
    if (qty == null || qty <= 0 || !context.mounted) return;
    final current = s.pantryMap[picked.id] ?? 0;
    await s.setPantryQuantity(picked.id, current + qty);
  }

  Future<void> _edit(BuildContext context, PantryItem item) async {
    final s = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PantryEditor(item: item, product: s.catalog.products[item.productId]),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final List<Product> products;
  const _ProductPicker({required this.products});
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.products.where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(hintText: tr('Search products'), prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              leading: Text(list[i].emoji, style: const TextStyle(fontSize: 24)),
              title: Text(list[i].name),
              subtitle: Text(productCategories[list[i].category] ?? list[i].category),
              onTap: () => Navigator.pop(context, list[i]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PantryEditor extends StatefulWidget {
  final PantryItem item;
  final Product? product;
  const _PantryEditor({required this.item, required this.product});
  @override
  State<_PantryEditor> createState() => _PantryEditorState();
}

class _PantryEditorState extends State<_PantryEditor> {
  late PantryItem _i = widget.item;

  Future<void> _date(bool expiry) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDate: (expiry ? _i.expiryDate : _i.purchaseDate) ?? now,
    );
    if (d != null) setState(() => _i = expiry ? _i.copyWith(expiryDate: d) : _i.copyWith(purchaseDate: d));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    String fmt(DateTime? d) => d == null ? 'Not set' : '${d.day}/${d.month}/${d.year}';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_i.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.scale_outlined),
          title: const T('Quantity'),
          trailing: Text(p == null ? '${_i.quantity}' : Units.display(_i.quantity, p.unit), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: p == null
              ? null
              : () async {
                  final v = await showQuantitySheet(context, p, _i.quantity);
                  if (v != null) setState(() => _i = _i.copyWith(quantity: v));
                },
        ),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.shopping_bag_outlined), title: const T('Purchase date'), trailing: Text(fmt(_i.purchaseDate)), onTap: () => _date(false)),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_busy_outlined), title: const T('Expiry date'), trailing: Text(fmt(_i.expiryDate)), onTap: () => _date(true)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'cupboard', label: T('Cupboard')),
            ButtonSegment(value: 'fridge', label: T('Fridge')),
            ButtonSegment(value: 'freezer', label: T('Freezer')),
          ],
          selected: {_i.storage},
          onSelectionChanged: (v) => setState(() => _i = _i.copyWith(storage: v.first)),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                await context.read<AppState>().deletePantryItem(_i);
                if (context.mounted) Navigator.pop(context);
              },
              child: const T('Used it all'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                if (_i.quantity <= 0) {
                  await context.read<AppState>().deletePantryItem(_i);
                } else {
                  await context.read<AppState>().savePantryItem(_i);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const T('Save'),
            ),
          ),
        ]),
      ]),
    );
  }
}
