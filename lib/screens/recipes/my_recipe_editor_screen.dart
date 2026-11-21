import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/catalog.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _IngRow {
  String productId;
  final TextEditingController amount;
  String unit;
  _IngRow(this.productId, double a, this.unit) : amount = TextEditingController(text: a == a.roundToDouble() ? a.toInt().toString() : a.toString());
}

/// Families add their own recipes; they're priced and planned like any other.
class MyRecipeEditorScreen extends StatefulWidget {
  final Recipe? recipe;
  const MyRecipeEditorScreen({super.key, this.recipe});
  @override
  State<MyRecipeEditorScreen> createState() => _MyRecipeEditorScreenState();
}

class _MyRecipeEditorScreenState extends State<MyRecipeEditorScreen> {
  late final TextEditingController _name;
  late MealSlot _slot;
  late int _servings;
  late int _minutes;
  late String _emoji;
  final List<_IngRow> _ings = [];
  final List<TextEditingController> _steps = [];

  static const _emojis = ['🍲', '🍛', '🥘', '🍚', '🌽', '🫘', '🥬', '🐟', '🍗', '🥩', '🍳', '🫓', '🍠', '☕'];

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _name = TextEditingController(text: r?.name ?? '');
    _slot = r?.category ?? MealSlot.dinner;
    _servings = r?.servings ?? 4;
    _minutes = r?.totalMinutes ?? 30;
    _emoji = r?.emoji ?? '🍲';
    for (final i in r?.ingredients ?? const <RecipeIngredient>[]) {
      _ings.add(_IngRow(i.productId, i.amount, i.unit));
    }
    for (final st in r?.instructions ?? const <String>[]) {
      _steps.add(TextEditingController(text: st));
    }
    if (_steps.isEmpty) _steps.add(TextEditingController());
  }

  Future<void> _pickProduct(AppState s, {_IngRow? row}) async {
    final products = s.catalog.products.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    var q = '';
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final rows = products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q.toLowerCase())).toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Search')),
                  onChanged: (v) => setS(() => q = v),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final p in rows)
                    ListTile(leading: Text(p.emoji, style: const TextStyle(fontSize: 22)), title: Text(p.name), onTap: () => Navigator.pop(ctx, p)),
                ]),
              ),
            ]),
          );
        },
      ),
    );
    if (picked == null) return;
    final unit = Units.inputUnits[picked.unit]!.first;
    setState(() {
      if (row == null) {
        _ings.add(_IngRow(picked.id, picked.unit == BaseUnit.g || picked.unit == BaseUnit.ml ? 250 : 1, unit));
      } else {
        row.productId = picked.id;
        row.unit = unit;
      }
    });
  }

  Future<void> _save(AppState s) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, tr('Recipe name'), error: true);
      return;
    }
    final ings = [
      for (final r in _ings)
        if ((double.tryParse(r.amount.text.trim()) ?? 0) > 0)
          RecipeIngredient(productId: r.productId, amount: double.parse(r.amount.text.trim()), unit: r.unit),
    ];
    if (ings.isEmpty) {
      showSnack(context, tr('Add ingredient'), error: true);
      return;
    }
    final tags = <String>{'family'};
    final prods = ings.map((i) => s.catalog.products[i.productId]).whereType<Product>();
    if (prods.every((p) => !p.dietTags.any((t) => t == 'meat' || t == 'fish'))) tags.add('vegetarian');
    if (prods.every((p) => p.dietTags.every((t) => t == 'plant'))) tags.add('vegan');
    if (_minutes <= 20) tags.add('quick');
    final r = Recipe(
      id: widget.recipe?.id ?? 'my_${s.newId().substring(0, 12)}',
      name: name,
      category: _slot,
      emoji: _emoji,
      description: 'Family recipe',
      prepMinutes: (_minutes / 3).round(),
      cookMinutes: _minutes - (_minutes / 3).round(),
      servings: _servings,
      tags: tags.toList(),
      ingredients: ings,
      instructions: [for (final c in _steps) if (c.text.trim().isNotEmpty) c.text.trim()],
    );
    await s.saveMyRecipe(r);
    if (mounted) Navigator.pop(context, r.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: T(widget.recipe == null ? 'Add my recipe' : 'Edit')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('Recipe name'), hintText: 'Githeri ya mama')),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final e in _emojis)
              GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 44,
                  margin: const EdgeInsets.only(right: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _emoji == e ? GrubColors.greenLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _emoji == e ? GrubColors.green : const Color(0xFFE5E5E5)),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final m in MealSlot.values)
            ChoiceChip(label: Text(mealSlotLabel(m)), selected: _slot == m, selectedColor: GrubColors.greenLight, onSelected: (_) => setState(() => _slot = m)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const T('Servings', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: _servings > 1 ? () => setState(() => _servings--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$_servings', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          IconButton(onPressed: () => setState(() => _servings++), icon: const Icon(Icons.add_circle_outline)),
        ]),
        Row(children: [
          const Text('⏱ min', style: TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Slider(
              value: _minutes.toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              label: '$_minutes',
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
          ),
          Text('$_minutes'),
        ]),
        const SectionHeader('Ingredients'),
        for (final r in _ings) _ingRow(s, r),
        OutlinedButton.icon(onPressed: () => _pickProduct(s), icon: const Icon(Icons.add), label: const T('Add ingredient')),
        const SectionHeader('Steps'),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _steps[i],
              maxLines: null,
              decoration: InputDecoration(
                prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800))),
                suffixIcon: _steps.length > 1 ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _steps.removeAt(i))) : null,
              ),
            ),
          ),
        TextButton.icon(onPressed: () => setState(() => _steps.add(TextEditingController())), icon: const Icon(Icons.add), label: const T('Add step')),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => _save(s),
            child: const T('Save recipe'),
          ),
        ),
      ),
    );
  }

  Widget _ingRow(AppState s, _IngRow r) {
    final p = s.catalog.products[r.productId];
    final units = p == null ? const ['pcs'] : Units.inputUnits[p.unit]!;
    if (!units.contains(r.unit)) r.unit = units.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: InkWell(
            onTap: () => _pickProduct(s, row: r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${p?.emoji ?? '❓'} ${p?.name ?? r.productId}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: TextField(
            controller: r.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: r.unit,
          underline: const SizedBox(),
          items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
          onChanged: (v) => setState(() => r.unit = v!),
        ),
        IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => setState(() => _ings.remove(r))),
      ]),
    );
  }
}
