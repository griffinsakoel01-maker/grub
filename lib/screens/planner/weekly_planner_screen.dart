import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../budget/optimizer_screen.dart';
import '../pantry/pantry_selection_screen.dart';
import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipes_screen.dart';
import '../shopping/shopping_list_detail_screen.dart';
import 'ingredient_calculator_screen.dart';
import 'plan_builder_screen.dart';

/// Weekly meal calendar: breakfast / lunch / dinner (+ snacks) per day.
class WeeklyPlannerScreen extends StatefulWidget {
  const WeeklyPlannerScreen({super.key});
  @override
  State<WeeklyPlannerScreen> createState() => _WeeklyPlannerScreenState();
}

class _WeeklyPlannerScreenState extends State<WeeklyPlannerScreen> {
  int _day = 0;
  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final plan = s.plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Planner'),
        actions: [
          IconButton(
            tooltip: 'Explore recipes',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen())),
          ),
        ],
      ),
      body: plan == null ? _empty(context) : _calendar(context, s, plan),
    );
  }

  Widget _empty(BuildContext context) => EmptyState(
        emoji: '🗓️',
        title: 'Plan your week',
        message: 'We\'ll pick Kenyan meals that fit your budget, household and diet, then build the shopping list.',
        actionLabel: 'Plan my meals',
        onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanBuilderScreen())),
      );

  Widget _calendar(BuildContext context, AppState s, MealPlan plan) {
    if (_day >= plan.days) _day = 0;
    final basket = s.planBasket;
    final date = plan.startDate.add(Duration(days: _day));
    final slots = s.profile!.slots.isEmpty ? MealSlot.values : s.profile!.slots;
    return Column(children: [
      // budget summary
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            BudgetProgress(budget: plan.budget, spent: basket?.total ?? plan.budget, label: 'Plan estimate vs budget'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngredientCalculatorScreen())),
                  icon: const Icon(Icons.scale_outlined, size: 18),
                  label: const Text('Ingredients'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OptimizerScreen())),
                  icon: const Icon(Icons.savings_outlined, size: 18),
                  label: const Text('Find savings'),
                ),
              ),
            ]),
          ]),
        ),
      ),
      // day strip
      SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: plan.days,
          itemBuilder: (_, i) {
            final d = plan.startDate.add(Duration(days: i));
            final sel = i == _day;
            final count = plan.meals.where((m) => m.dayIndex == i).length;
            return GestureDetector(
              onTap: () => setState(() => _day = i),
              child: DragTarget<PlannedMeal>(
                onAcceptWithDetails: (details) => s.moveMeal(details.data, i),
                builder: (_, cand, __) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: sel ? GrubColors.green : (cand.isNotEmpty ? GrubColors.greenTint : GrubColors.greenLight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_wd[d.weekday - 1], style: TextStyle(fontSize: 12, color: sel ? Colors.white : GrubColors.muted, fontWeight: FontWeight.w600)),
                    Text('${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: sel ? Colors.white : GrubColors.greenDark)),
                    Text(count == 0 ? '–' : '$count', style: TextStyle(fontSize: 10, color: sel ? Colors.white70 : GrubColors.muted)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text('Tip: long-press a meal and drag it onto another day to rearrange.', style: TextStyle(fontSize: 11, color: GrubColors.muted)),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          Text(_longDate(date), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final slot in slots) _slotCard(context, s, plan, slot),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantrySelectionScreen())),
                child: const Text('What I have'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                onPressed: () async {
                  final list = await s.createListFromPlan();
                  if (context.mounted) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: list.id)));
                  }
                },
                child: const Text('Shopping list'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanBuilderScreen())),
            icon: const Icon(Icons.refresh),
            label: const Text('Plan a new week'),
          ),
        ]),
      ),
    ]);
  }

  Widget _slotCard(BuildContext context, AppState s, MealPlan plan, MealSlot slot) {
    final meal = plan.meals.where((m) => m.dayIndex == _day && m.slot == slot).toList();
    final m = meal.isEmpty ? null : meal.first;
    final r = m == null ? null : s.catalog.recipes[m.recipeId];
    final card = SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: r == null
          ? () => _pick(context, s, slot)
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id, servings: m!.portions))),
      child: Row(children: [
        if (r != null) RecipeImage(r, height: 56, width: 56, radius: 12) else const EmojiTile('➕', size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mealSlotLabel(slot).toUpperCase(), style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700)),
            Text(r?.name ?? 'Add a meal', style: TextStyle(fontWeight: FontWeight.w700, color: r == null ? GrubColors.muted : GrubColors.ink)),
            if (r != null)
              Text('${r.totalMinutes} min · ${recipeCostLabel(s.catalog, r, m!.portions) ?? '—'}${m.cooked ? ' · ✓ cooked' : ''}',
                  style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          ]),
        ),
        if (m != null)
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'swap':
                  await _pick(context, s, slot, replacing: m);
                case 'cooked':
                  await s.markCooked(m, updatePantry: !m.cooked);
                case 'remove':
                  await s.removeMeal(m);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'swap', child: Text('Replace meal')),
              PopupMenuItem(value: 'cooked', child: Text(m.cooked ? 'Mark not cooked' : 'Mark cooked & update pantry')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: m == null
          ? card
          : LongPressDraggable<PlannedMeal>(
              data: m,
              feedback: Material(color: Colors.transparent, child: SizedBox(width: 280, child: Opacity(opacity: 0.9, child: card))),
              childWhenDragging: Opacity(opacity: 0.3, child: card),
              child: card,
            ),
    );
  }

  Future<void> _pick(BuildContext context, AppState s, MealSlot slot, {PlannedMeal? replacing}) async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => RecipesScreen(pickSlot: slot)));
    if (id == null) return;
    if (replacing != null) {
      await s.replaceMeal(replacing, id);
    } else {
      await s.addMeal(_day, slot, id);
    }
  }

  String _longDate(DateTime d) {
    const w = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${w[d.weekday - 1]}, ${d.day} ${m[d.month - 1]}';
  }
}
