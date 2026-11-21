import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/calculation_service.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../ai/ai_assistant_screen.dart';
import '../budget/budget_calculator_screen.dart';
import '../planner/plan_builder_screen.dart';
import '../prices/compare_prices_screen.dart';
import '../recipes/recipe_detail_screen.dart';
import '../recipes/recipes_screen.dart';
import '../receipt/receipt_scan_screen.dart';
import '../shell.dart';
import '../shopping/shopping_list_detail_screen.dart';
import '../budget/budget_tracking_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Habari ya asubuhi';
    if (h < 17) return 'Habari ya mchana';
    return 'Habari ya jioni';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile;
    if (p == null) return const LoadingView();
    final plan = s.plan;
    final basket = s.planBasket;
    final filter = DietFilter.fromProfile(p);
    final affordable = s.planner.affordableRecipes(s.planBudgetFor(1), p.portionsPerMeal, filter, pantry: s.pantryMap).take(6).toList();
    final popular = s.catalog.recipes.values.where((r) => filter.recipeAllowed(r, s.catalog.products) && r.category != MealSlot.snack).take(8).toList();
    final upcoming = _upcoming(s);

    return SafeArea(
      child: RefreshIndicator(
        color: GrubColors.green,
        onRefresh: () async {
          await s.refreshCatalog();
          await s.loadAll();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_greeting()},', style: const TextStyle(color: GrubColors.muted)),
                Text(p.name.isEmpty ? 'Karibu!' : '${p.name.split(' ').first} 👋', style: Theme.of(context).textTheme.headlineSmall),
              ]),
            ),
            const GrubLogo(height: 40, iconOnly: true),
          ]),
          if (s.isDemo || s.catalog.hasOnlyDemoPrices) const Padding(padding: EdgeInsets.only(top: 12), child: DemoBanner()),
          const SizedBox(height: 16),
          // Budget card
          SoftCard(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetTrackingScreen())),
            child: BudgetProgress(budget: p.budget, spent: s.spentThisPeriod, label: '${budgetFrequencyLabel(p.budgetFrequency)} budget'),
          ),
          const SizedBox(height: 12),
          // Current plan card
          SoftCard(
            color: GrubColors.greenLight,
            onTap: () => MainShell.of(context)?.goTo(1),
            child: Row(children: [
              const EmojiTile('🗓️', size: 48, background: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: plan == null
                    ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('No meal plan yet', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('Plan your week in under a minute.', style: TextStyle(color: GrubColors.muted, fontSize: 12)),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Current shopping plan', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('${plan.meals.length} meals · est. ${basket?.total.format() ?? '—'} of ${plan.budget.format()}',
                            style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
                      ]),
              ),
              const Icon(Icons.chevron_right, color: GrubColors.greenDark),
            ]),
          ),
          const SectionHeader('Quick actions'),
          _QuickActions(onPlan: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlanBuilderScreen()))),
          if (upcoming.isNotEmpty) ...[
            SectionHeader('Upcoming meals', action: 'See plan', onAction: () => MainShell.of(context)?.goTo(1)),
            for (final m in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MealTile(meal: m.$1, label: m.$2),
              ),
          ],
          if (s.lists.isNotEmpty) ...[
            SectionHeader('Recent shopping lists', action: 'All lists', onAction: () => MainShell.of(context)?.goTo(2)),
            for (final l in s.lists.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SoftCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoppingListDetailScreen(listId: l.id))),
                  child: Row(children: [
                    const EmojiTile('🛒'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${l.purchasedCount}/${l.items.length} bought · ${l.estimatedTotal.format()}',
                            style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
          ],
          if (affordable.isNotEmpty) ...[
            SectionHeader('Affordable today', action: 'More', onAction: () => _openRecipes(context)),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: affordable.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => RecipeCard(recipe: affordable[i].$1, price: '${affordable[i].$2.format()} for family'),
              ),
            ),
          ],
          SectionHeader('Popular Kenyan recipes', action: 'Explore', onAction: () => _openRecipes(context)),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: popular.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final cps = CalculationService.costPerServing(popular[i], s.catalog);
                return RecipeCard(recipe: popular[i], price: cps == null ? null : '${cps.format()}/serving');
              },
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            color: GrubColors.greenDark,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
            child: const Row(children: [
              Text('✨', style: TextStyle(fontSize: 26)),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ask Grub AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('"What can I cook with KSh 300?"', style: TextStyle(color: Color(0xFFCDE8C3), fontSize: 13)),
                ]),
              ),
              Icon(Icons.arrow_forward, color: Colors.white),
            ]),
          ),
        ]),
      ),
    );
  }

  void _openRecipes(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen()));

  List<(PlannedMeal, String)> _upcoming(AppState s) {
    final plan = s.plan;
    if (plan == null) return [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hourSlot = now.hour < 10 ? 0 : (now.hour < 15 ? 1 : 2);
    final out = <(PlannedMeal, String)>[];
    for (final m in plan.meals) {
      final d = plan.startDate.add(Duration(days: m.dayIndex));
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(today) || m.cooked) continue;
      if (day == today && m.slot.index < hourSlot && m.slot != MealSlot.snack) continue;
      final label = day == today ? 'Today' : (day == today.add(const Duration(days: 1)) ? 'Tomorrow' : _wd(day.weekday));
      out.add((m, '$label · ${mealSlotLabel(m.slot)}'));
      if (out.length == 3) break;
    }
    return out;
  }

  String _wd(int w) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][w - 1];
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onPlan;
  const _QuickActions({required this.onPlan});
  @override
  Widget build(BuildContext context) {
    final items = <(String, String, VoidCallback)>[
      ('🗓️', 'Plan My Meals', onPlan),
      ('🧮', 'Calculate My Groceries', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetCalculatorScreen()))),
      ('📝', 'Create Shopping List', () => MainShell.of(context)?.goTo(2)),
      ('⚖️', 'Compare Prices', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePricesScreen()))),
      ('📖', 'Explore Recipes', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen()))),
      ('🧾', 'Scan Receipt', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiptScanScreen()))),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.0,
      children: [
        for (final i in items)
          SoftCard(
            padding: const EdgeInsets.all(10),
            onTap: i.$3,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              EmojiTile(i.$1, size: 40),
              const SizedBox(height: 8),
              Text(i.$2, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}

class _MealTile extends StatelessWidget {
  final PlannedMeal meal;
  final String label;
  const _MealTile({required this.meal, required this.label});
  @override
  Widget build(BuildContext context) {
    final r = context.read<AppState>().catalog.recipes[meal.recipeId];
    if (r == null) return const SizedBox();
    return SoftCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id, servings: meal.portions))),
      child: Row(children: [
        RecipeImage(r, height: 52, width: 52, radius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700)),
            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${r.totalMinutes} min', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          ]),
        ),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}

/// Horizontal recipe card used across the app.
class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final String? price;
  final double width;
  const RecipeCard({super.key, required this.recipe, this.price, this.width = 160});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: SoftCard(
          padding: const EdgeInsets.all(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: recipe.id))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RecipeImage(recipe, height: 100, width: double.infinity, radius: 12),
            const SizedBox(height: 8),
            Text(recipe.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            Row(children: [
              const Icon(Icons.schedule, size: 12, color: GrubColors.muted),
              const SizedBox(width: 3),
              Text('${recipe.totalMinutes}m', style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
              const Spacer(),
              if (price != null)
                Flexible(
                  child: Text(price!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GrubColors.green)),
                ),
            ]),
          ]),
        ),
      );
}
