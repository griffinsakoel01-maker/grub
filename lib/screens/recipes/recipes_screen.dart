import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../services/calculation_service.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'recipe_detail_screen.dart';

/// Explore recipes (and meal-selection mode: pass [pickSlot] to return a recipe id).
class RecipesScreen extends StatefulWidget {
  final MealSlot? pickSlot;
  final String? title;
  final bool favouritesOnly;
  const RecipesScreen({super.key, this.pickSlot, this.title, this.favouritesOnly = false});
  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  String _q = '';
  MealSlot? _slot;
  bool _favOnly = false;
  bool _safeOnly = true;
  String _sort = 'cost';

  @override
  void initState() {
    super.initState();
    _slot = widget.pickSlot;
    _favOnly = widget.favouritesOnly;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile;
    final portions = p?.portionsPerMeal ?? 2;
    final filter = p == null ? const DietFilter() : DietFilter.fromProfile(p);
    final rows = s.catalog.recipes.values
        .where((r) => _slot == null || r.category == _slot)
        .where((r) => !_favOnly || s.isFavourite(r.id))
        .where((r) => !_safeOnly || filter.recipeAllowed(r, s.catalog.products))
        .where((r) => _q.isEmpty || r.name.toLowerCase().contains(_q.toLowerCase()) || r.description.toLowerCase().contains(_q.toLowerCase()))
        .map((r) => (r, CalculationService.recipeCost(r, portions, s.catalog)))
        .toList();
    rows.sort((a, b) => switch (_sort) {
          'time' => a.$1.totalMinutes.compareTo(b.$1.totalMinutes),
          'name' => a.$1.name.compareTo(b.$1.name),
          _ => (a.$2?.cents ?? 1 << 30).compareTo(b.$2?.cents ?? 1 << 30),
        });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (widget.pickSlot != null ? 'Choose ${mealSlotLabel(widget.pickSlot!).toLowerCase()}' : 'Recipes')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cost', child: Text('Cheapest first')),
              PopupMenuItem(value: 'time', child: Text('Quickest first')),
              PopupMenuItem(value: 'name', child: Text('A–Z')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search pilau, githeri, chapati…', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            _chip('All', _slot == null, () => setState(() => _slot = null)),
            for (final sl in MealSlot.values) _chip(mealSlotLabel(sl), _slot == sl, () => setState(() => _slot = sl)),
            _chip('❤ Favourites', _favOnly, () => setState(() => _favOnly = !_favOnly)),
            _chip('Fits my diet', _safeOnly, () => setState(() => _safeOnly = !_safeOnly)),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(emoji: '🔎', title: 'No recipes found', message: 'Try another search or filter.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final (r, cost) = rows[i];
                    return SoftCard(
                      padding: const EdgeInsets.all(10),
                      onTap: () => widget.pickSlot != null
                          ? Navigator.pop(context, r.id)
                          : Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id))),
                      child: Row(children: [
                        RecipeImage(r, height: 72, width: 72, radius: 14),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(mealSlotLabel(r.category).toUpperCase(), style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700)),
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text('${r.totalMinutes} min · serves ${r.servings}', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(cost?.format() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
                          Text('for ${portions % 1 == 0 ? portions.toInt() : portions}', style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
                          if (widget.pickSlot != null) const Icon(Icons.add_circle, color: GrubColors.green),
                        ]),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: TextStyle(color: selected ? Colors.white : GrubColors.ink, fontWeight: FontWeight.w600),
          onSelected: (_) => onTap(),
        ),
      );
}
