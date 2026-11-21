import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/catalog.dart';
import '../../services/calculation_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';
import 'my_recipe_editor_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final String recipeId;
  final double? servings;
  const RecipeDetailScreen({super.key, required this.recipeId, this.servings});
  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late double _servings;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _servings = widget.servings ?? s.profile?.portionsPerMeal ?? s.catalog.recipes[widget.recipeId]?.servings.toDouble() ?? 2;
    if (_servings <= 0) _servings = 1;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.catalog.recipes[widget.recipeId];
    if (r == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(emoji: '🍽️', title: 'Recipe not found', message: 'It may have been removed.'));
    }
    final cost = CalculationService.recipeCost(r, _servings, s.catalog);
    final perServing = cost == null ? null : Money((cost.cents / _servings).round());
    final fav = s.isFavourite(r.id);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: Colors.white,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: CircleAvatar(backgroundColor: Colors.white, child: BackButton(color: GrubColors.greenDark)),
            ),
            actions: [
              if (r.id.startsWith('my_'))
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: GrubColors.greenDark),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyRecipeEditorScreen(recipe: r)));
                        } else {
                          final nav = Navigator.of(context);
                          await s.deleteMyRecipe(r.id);
                          nav.pop();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: T('Edit')),
                        PopupMenuItem(value: 'delete', child: T('Delete recipe')),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? GrubColors.danger : GrubColors.greenDark),
                    onPressed: () => s.toggleFavourite(r.id),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(background: RecipeImage(r, radius: 0, height: 300)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: Theme.of(context).textTheme.headlineSmall),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.description, style: const TextStyle(color: GrubColors.muted)),
                ],
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _action(fav ? Icons.bookmark : Icons.bookmark_border, fav ? 'Saved' : 'Save', () => s.toggleFavourite(r.id)),
                  _action(Icons.calendar_month_outlined, 'Meal plan', () => _addToPlan(context, r)),
                  _action(Icons.shopping_cart_outlined, 'Groceries', () => _addToList(context, r)),
                  _action(Icons.ios_share, 'Share', () => Share.share(_shareText(s, r))),
                ]),
                const SizedBox(height: 16),
                if (r.nutrition != null) _Macros(r.nutrition!),
                const SizedBox(height: 14),
                SoftCard(
                  color: GrubColors.greenLight,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Prep: ${r.prepMinutes} mins  |  Cook: ${r.cookMinutes} mins', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      cost == null
                          ? 'Cost: some ingredients have no price yet'
                          : 'Estimated cost: ${cost.format()} for ${_fmt(_servings)} · ${perServing!.format()} per serving',
                      style: const TextStyle(color: GrubColors.greenDark),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _markCooked(context, r),
                      child: const Row(children: [
                        Icon(Icons.check_circle_outline, size: 18, color: GrubColors.green),
                        SizedBox(width: 6),
                        T('Mark as cooked', style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),
                TabBar(
                  controller: _tabs,
                  labelColor: GrubColors.greenDark,
                  indicatorColor: GrubColors.green,
                  unselectedLabelColor: GrubColors.muted,
                  tabs: const [Tab(text: 'Ingredients'), Tab(text: 'Instructions')],
                ),
              ]),
            ),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [_ingredients(s, r), _instructions(r)]),
      ),
    );
  }

  Widget _action(IconData i, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Icon(i, color: GrubColors.greenDark),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          ]),
        ),
      );

  Widget _ingredients(AppState s, Recipe r) {
    final pantry = s.pantryMap;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      Row(children: [
        CountStepper(value: _servings, min: 0.5, max: 40, step: 0.5, onChanged: (v) => setState(() => _servings = v.toDouble())),
        const SizedBox(width: 8),
        const T('servings', style: TextStyle(color: GrubColors.muted)),
        const Spacer(),
        Text('Recipe serves ${r.servings}', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
      ]),
      const SizedBox(height: 12),
      for (final ing in r.ingredients) _ingredientRow(s, r, ing, pantry),
      const SizedBox(height: 8),
      const T('Quantities scale automatically: original × (your servings ÷ recipe servings).',
          style: TextStyle(fontSize: 11, color: GrubColors.muted)),
    ]);
  }

  Widget _ingredientRow(AppState s, Recipe r, RecipeIngredient ing, Map<String, double> pantry) {
    final p = s.catalog.products[ing.productId];
    if (p == null) return const SizedBox();
    final scaled = CalculationService.scale(ing.amount, r.servings, _servings);
    final base = Units.toBase(scaled, ing.unit, p.unit);
    final have = pantry[p.id] ?? 0;
    final price = CalculationService.bestPrice(p.id, base, s.catalog);
    final c = price == null ? null : CalculationService.consumedCost(base, price);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        EmojiTile(p.emoji, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${Units.displayIn(scaled, ing.unit)} ${p.name.split(' (').first.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (have > 0)
              Text(have >= base ? '✓ You have enough at home' : 'You have ${Units.display(have, p.unit)} at home',
                  style: const TextStyle(fontSize: 11, color: GrubColors.green)),
          ]),
        ),
        if (c != null) Text(c.format(), style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
      ]),
    );
  }

  Widget _instructions(Recipe r) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CookModeScreen(recipe: r))),
          icon: const Icon(Icons.play_arrow),
          label: const T('Cook step-by-step'),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < r.instructions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 12, backgroundColor: GrubColors.green, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white))),
              const SizedBox(width: 12),
              Expanded(child: Text(r.instructions[i], style: const TextStyle(height: 1.45))),
            ]),
          ),
      ]);

  String _fmt(double v) => v % 1 == 0 ? '${v.toInt()} servings' : '${v.toStringAsFixed(1)} servings';

  String _shareText(AppState s, Recipe r) {
    final b = StringBuffer('${r.name} (serves ${_fmt(_servings)})\n\nIngredients:\n');
    for (final ing in r.ingredients) {
      final p = s.catalog.products[ing.productId];
      if (p == null) continue;
      b.writeln('• ${Units.displayIn(CalculationService.scale(ing.amount, r.servings, _servings), ing.unit)} ${p.name}');
    }
    b.writeln('\nMethod:');
    for (var i = 0; i < r.instructions.length; i++) {
      b.writeln('${i + 1}. ${r.instructions[i]}');
    }
    b.writeln('\nPlanned with Grub – Plan meals. Shop smarter.');
    return b.toString();
  }

  Future<void> _markCooked(BuildContext context, Recipe r) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('Mark as cooked?'),
        content: Text('Remove the ingredients used for ${_fmt(_servings)} from your pantry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const T('Just mark cooked')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), child: const T('Update pantry')),
        ],
      ),
    );
    if (ok == null) return;
    if (ok) await s.consumeFromPantry(r, _servings);
    final plan = s.plan;
    if (plan != null) {
      final match = plan.meals.where((m) => m.recipeId == r.id && !m.cooked).toList();
      if (match.isNotEmpty) await s.markCooked(match.first, updatePantry: false);
    }
    if (context.mounted) showSnack(context, ok ? 'Nice! Pantry updated.' : 'Marked as cooked.');
  }

  Future<void> _addToPlan(BuildContext context, Recipe r) async {
    final s = context.read<AppState>();
    final plan = s.plan;
    if (plan == null) {
      showSnack(context, 'Create a meal plan first from the Meal Planner tab.');
      return;
    }
    final day = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        Text('Add ${r.name} as ${mealSlotLabel(r.category).toLowerCase()} on…', style: Theme.of(ctx).textTheme.titleMedium),
        for (var i = 0; i < plan.days; i++)
          ListTile(
            title: Text(_dayLabel(plan.startDate.add(Duration(days: i)))),
            trailing: const Icon(Icons.add_circle_outline, color: GrubColors.green),
            onTap: () => Navigator.pop(ctx, i),
          ),
      ]),
    );
    if (day == null) return;
    await s.addMeal(day, r.category, r.id);
    if (context.mounted) showSnack(context, 'Added to your meal plan.');
  }

  Future<void> _addToList(BuildContext context, Recipe r) async {
    final s = context.read<AppState>();
    var list = s.lists.isNotEmpty ? s.lists.first : await s.createEmptyList('My shopping list');
    final reqs = CalculationService.aggregate(CalculationService.recipeRequirements(r, _servings, s.catalog.products));
    final toBuy = CalculationService.subtractPantry(reqs, s.pantryMap);
    final basket = CalculationService.costBasket(toBuy, s.catalog, supermarketId: list.supermarketId);
    for (final item in CalculationService.basketToItems(basket, s.newId)) {
      await s.addItem(list, item);
      list = s.listById(list.id)!;
    }
    if (context.mounted) showSnack(context, '${toBuy.length} ingredients added to "${list.name}" (pantry items skipped).');
  }

  String _dayLabel(DateTime d) {
    const w = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${w[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
  }
}

class _Macros extends StatelessWidget {
  final Nutrition n;
  const _Macros(this.n);
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const T('MACROS · PER SERVING (APPROX.)', style: TextStyle(fontSize: 10, color: GrubColors.green, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('${n.kcal} kcal', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Expanded(flex: math.max(1, n.protein * 4), child: Container(height: 6, color: const Color(0xFFE57373))),
          Expanded(flex: math.max(1, n.carbs * 4), child: Container(height: 6, color: const Color(0xFF4DB6AC))),
          Expanded(flex: math.max(1, n.fat * 9), child: Container(height: 6, color: const Color(0xFFFFB74D))),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text('● ${n.protein}g protein', style: const TextStyle(fontSize: 12, color: Color(0xFFE57373))),
        const Spacer(),
        Text('● ${n.carbs}g carbs', style: const TextStyle(fontSize: 12, color: Color(0xFF4DB6AC))),
        const Spacer(),
        Text('● ${n.fat}g fat', style: const TextStyle(fontSize: 12, color: Color(0xFFFFB74D))),
      ]),
    ]);
  }
}

/// Full-screen step-by-step cooking mode.
class CookModeScreen extends StatefulWidget {
  final Recipe recipe;
  const CookModeScreen({super.key, required this.recipe});
  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  final _ctrl = PageController();
  int _i = 0;
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.recipe.instructions;
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe.name)),
      body: Column(children: [
        LinearProgressIndicator(value: steps.isEmpty ? 1 : (_i + 1) / steps.length, color: GrubColors.green, backgroundColor: GrubColors.greenLight),
        Expanded(
          child: PageView.builder(
            controller: _ctrl,
            itemCount: steps.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Step ${i + 1} of ${steps.length}', style: const TextStyle(color: GrubColors.green, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                Text(steps[i], textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, height: 1.4, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _i == 0 ? null : () => _ctrl.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: const T('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _i >= steps.length - 1
                    ? Navigator.pop(context)
                    : _ctrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(_i >= steps.length - 1 ? 'Done' : 'Next step'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
