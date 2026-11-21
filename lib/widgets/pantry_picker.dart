import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/units.dart';
import '../models/catalog.dart';
import '../state/app_state.dart';
import 'common.dart';

/// Photo/emoji grid of ingredients, grouped by category, with search.
/// Tap = "I have some" (one default package). Tap again = enter exact amount.
class PantryPicker extends StatefulWidget {
  final bool shrinkWrap;
  const PantryPicker({super.key, this.shrinkWrap = false});
  @override
  State<PantryPicker> createState() => _PantryPickerState();
}

class _PantryPickerState extends State<PantryPicker> {
  String _q = '';
  String _cat = 'all';

  static const _filters = {
    'all': 'All',
    'cereals': 'Cereals',
    'vegetables': 'Vegetables',
    'fruits': 'Fruits',
    'meat': 'Meat',
    'dairy': 'Dairy',
    'legumes': 'Legumes',
    'cooking': 'Cooking',
    'spices': 'Spices',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final have = s.pantryMap;
    final products = s.catalog.products.values
        .where((p) => _cat == 'all' || p.category == _cat)
        .where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase()))
        .toList()
      ..sort((a, b) {
        final c = (productCategories.keys.toList().indexOf(a.category)).compareTo(productCategories.keys.toList().indexOf(b.category));
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    return Column(children: [
      TextField(
        decoration: const InputDecoration(hintText: 'Search foods', prefixIcon: Icon(Icons.search)),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in _filters.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _cat == e.key,
                showCheckmark: false,
                labelStyle: TextStyle(color: _cat == e.key ? Colors.white : GrubColors.ink, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _cat = e.key),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final p = products[i];
            final qty = have[p.id] ?? 0;
            final selected = qty > 0;
            return SelectCard(
              emoji: p.emoji,
              title: p.name.split(' (').first,
              subtitle: selected ? Units.display(qty, p.unit) : null,
              selected: selected,
              compact: true,
              onTap: () => selected ? _edit(context, p, qty) : s.setPantryQuantity(p.id, p.defaultPackageSize),
            );
          },
        ),
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, Product p, double current) async {
    final result = await showQuantitySheet(context, p, current);
    if (result != null && context.mounted) await context.read<AppState>().setPantryQuantity(p.id, result);
  }
}

/// Bottom sheet to enter an exact quantity in a friendly unit. Returns base units.
Future<double?> showQuantitySheet(BuildContext context, Product p, double currentBase, {String title = 'How much do you have?'}) {
  final units = Units.inputUnits[p.unit]!;
  var unit = units.first;
  if (p.unit == BaseUnit.g && currentBase >= 1000) unit = 'kg';
  if (p.unit == BaseUnit.ml && currentBase >= 1000) unit = 'l';
  final ctrl = TextEditingController(text: _fmt(unit == 'kg' || unit == 'l' ? currentBase / 1000 : currentBase));
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EmojiTile(p.emoji),
            const SizedBox(width: 12),
            Expanded(child: Text(p.name, style: Theme.of(ctx).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: GrubColors.muted)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'Amount'),
              ),
            ),
            const SizedBox(width: 10),
            if (units.length > 1)
              DropdownButton<String>(
                value: unit,
                underline: const SizedBox(),
                items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: (v) => setS(() => unit = v ?? unit),
              )
            else
              Text(units.first, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Remove'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (v == null || v < 0) return;
                  Navigator.pop(ctx, Units.toBase(v, unit, p.unit));
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
