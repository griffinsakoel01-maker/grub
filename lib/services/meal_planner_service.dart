import 'dart:math' as math;

import '../core/money.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';
import 'calculation_service.dart';

/// Diet / allergy / dislike filtering. Food safety rules are *hard* filters:
/// the planner and the optimiser never suggest anything that breaks them.
class DietFilter {
  final List<String> diets;
  final List<String> allergies;
  final List<String> dislikes;
  const DietFilter({this.diets = const [], this.allergies = const [], this.dislikes = const []});

  factory DietFilter.fromProfile(UserProfile p) => DietFilter(diets: p.diets, allergies: p.allergies, dislikes: p.dislikes);

  bool productAllowed(Product p) {
    if (p.allergens.any(allergies.contains)) return false;
    if (dislikes.contains(p.id)) return false;
    final t = p.dietTags;
    if (diets.contains('vegan') && (t.contains('meat') || t.contains('fish') || t.contains('dairy') || t.contains('egg'))) return false;
    if (diets.contains('vegetarian') && (t.contains('meat') || t.contains('fish'))) return false;
    if (diets.contains('pescatarian') && t.contains('meat')) return false;
    return true;
  }

  bool recipeAllowed(Recipe r, Map<String, Product> products) {
    for (final i in r.ingredients) {
      final p = products[i.productId];
      if (p == null || !productAllowed(p)) return false;
    }
    return true;
  }
}

class PlanRequest {
  final UserProfile profile;
  final DateTime startDate;
  final int days;
  final Money budget; // budget for these days
  final Map<String, double> pantry; // productId → base quantity at home
  final String supermarketId;
  final int seed;
  const PlanRequest({
    required this.profile,
    required this.startDate,
    required this.days,
    required this.budget,
    this.pantry = const {},
    this.supermarketId = '',
    this.seed = 0,
  });
}

class PlanResult {
  final List<PlannedMeal> meals;
  final Basket basket;
  final Money budget;
  final bool withinBudget;
  final List<String> notes;
  const PlanResult({required this.meals, required this.basket, required this.budget, required this.withinBudget, this.notes = const []});

  Money get total => basket.total;
  Money get remaining => budget - basket.total;
}

/// Builds a meal plan that respects the household's rules and tries to land
/// within budget. Steps:
///  1. Filter recipes (allergies, diet, dislikes).
///  2. For each cooking day and meal, pick a recipe whose cost is close to
///     that meal's share of the budget, avoiding repeats.
///  3. Cost the real basket (packages, pantry) and, while over budget, swap
///     the most expensive meals for cheaper eligible ones.
class MealPlannerService {
  final Catalog catalog;
  MealPlannerService(this.catalog);

  List<Recipe> eligible(MealSlot slot, DietFilter f) => catalog.recipes.values
      .where((r) => r.category == slot && f.recipeAllowed(r, catalog.products))
      .toList();

  Map<String, double> toBuyFor(List<PlannedMeal> meals, Map<String, double> pantry, [Map<String, String> subs = const {}]) =>
      CalculationService.applySubstitutions(
          CalculationService.subtractPantry(CalculationService.planRequirements(meals, catalog), pantry), subs);

  Basket basketFor(List<PlannedMeal> meals, Map<String, double> pantry, String supermarketId, [Map<String, String> subs = const {}]) =>
      CalculationService.costBasket(toBuyFor(meals, pantry, subs), catalog, supermarketId: supermarketId);

  PlanResult generate(PlanRequest req) {
    final rnd = math.Random(req.seed);
    final profile = req.profile;
    final filter = DietFilter.fromProfile(profile);
    final portions = profile.portionsPerMeal <= 0 ? 1.0 : profile.portionsPerMeal;
    final slots = profile.slots.isEmpty ? [MealSlot.lunch, MealSlot.dinner] : profile.slots;
    final notes = <String>[];

    // Which plan days are cooking days?
    final dayIdx = <int>[];
    for (var i = 0; i < req.days; i++) {
      final wd = req.startDate.add(Duration(days: i)).weekday; // 1..7
      if (profile.cookingDays.isEmpty || profile.cookingDays.contains(wd)) dayIdx.add(i);
    }
    if (dayIdx.isEmpty) {
      return PlanResult(meals: const [], basket: const Basket('', []), budget: req.budget, withinBudget: true, notes: const ['No cooking days selected.']);
    }

    final bd = CalculationService.breakdown(periodBudget: req.budget, days: dayIdx.length, slots: slots, portionsPerMeal: portions);

    // Pre-compute portion cost per recipe.
    final costCache = <String, Money>{};
    Money costOf(Recipe r) => costCache.putIfAbsent(
        r.id, () => CalculationService.recipeCost(r, portions, catalog, supermarketId: req.supermarketId) ?? const Money(1 << 30));

    final meals = <PlannedMeal>[];
    final useCount = <String, int>{};
    for (final slot in slots) {
      final options = eligible(slot, filter);
      if (options.isEmpty) {
        notes.add('No ${mealSlotLabel(slot).toLowerCase()} recipes match your diet and allergies.');
        continue;
      }
      final target = bd.perSlotPerDay[slot] ?? const Money.zero();
      for (final d in dayIdx) {
        double score(Recipe r) {
          final c = costOf(r).cents.toDouble();
          final t = math.max(1, target.cents).toDouble();
          var s = c > t ? (c - t) / t * 2.0 : (t - c) / t * 0.6; // over budget hurts more
          s += (useCount[r.id] ?? 0) * 0.7; // variety
          if (profile.favouriteMeals.contains(r.id)) s -= 0.3;
          if (profile.cookingStyle == 'quick' && r.totalMinutes > 40) s += 0.4;
          if (profile.cookingStyle == 'budget' && r.tags.contains('budget')) s -= 0.2;
          if (profile.diets.contains('high_protein')) s -= (r.nutrition?.protein ?? 0) / 100;
          if (profile.diets.contains('low_carb')) s += (r.nutrition?.carbs ?? 0) / 200;
          return s + rnd.nextDouble() * 0.25;
        }

        final ranked = [...options]..sort((a, b) => score(a).compareTo(score(b)));
        final pick = ranked.first;
        useCount[pick.id] = (useCount[pick.id] ?? 0) + 1;
        meals.add(PlannedMeal(dayIndex: d, slot: slot, recipeId: pick.id, portions: portions));
      }
    }

    // Repair loop: swap expensive meals until within budget.
    var basket = basketFor(meals, req.pantry, req.supermarketId);
    var guard = 0;
    while (basket.total > req.budget && guard++ < 60) {
      final sorted = [...meals]..sort((a, b) => costOf(catalog.recipes[b.recipeId]!).compareTo(costOf(catalog.recipes[a.recipeId]!)));
      var improved = false;
      for (final m in sorted) {
        final current = costOf(catalog.recipes[m.recipeId]!);
        final cheaper = eligible(m.slot, filter).where((r) => costOf(r) < current).toList()
          ..sort((a, b) => costOf(a).compareTo(costOf(b)));
        if (cheaper.isEmpty) continue;
        // prefer the cheaper option used least
        cheaper.sort((a, b) {
          final u = (useCount[a.id] ?? 0).compareTo(useCount[b.id] ?? 0);
          return u != 0 ? u : costOf(a).compareTo(costOf(b));
        });
        final alt = cheaper.first;
        final i = meals.indexOf(m);
        useCount[m.recipeId] = (useCount[m.recipeId] ?? 1) - 1;
        useCount[alt.id] = (useCount[alt.id] ?? 0) + 1;
        meals[i] = m.copyWith(recipeId: alt.id);
        improved = true;
        break;
      }
      if (!improved) break;
      basket = basketFor(meals, req.pantry, req.supermarketId);
    }

    final within = basket.total <= req.budget;
    if (!within) {
      notes.add('Even the cheapest suitable meals cost ${basket.total.format()} – about '
          '${(basket.total - req.budget).format()} over budget. Try fewer meals, more pantry items or a bigger budget.');
    }
    if (basket.missing.isNotEmpty) {
      notes.add('${basket.missing.length} item(s) have no price yet and are not included in the total.');
    }
    meals.sort((a, b) => a.dayIndex != b.dayIndex ? a.dayIndex.compareTo(b.dayIndex) : a.slot.index.compareTo(b.slot.index));
    return PlanResult(meals: meals, basket: basket, budget: req.budget, withinBudget: within, notes: notes);
  }

  /// Alternative recipes for swapping one planned meal, cheapest first.
  List<Recipe> swapOptions(PlannedMeal meal, UserProfile profile, {String supermarketId = ''}) {
    final f = DietFilter.fromProfile(profile);
    final list = eligible(meal.slot, f).where((r) => r.id != meal.recipeId).toList();
    Money c(Recipe r) => CalculationService.recipeCost(r, meal.portions, catalog, supermarketId: supermarketId) ?? const Money(1 << 30);
    list.sort((a, b) => c(a).compareTo(c(b)));
    return list;
  }

  /// "What can I cook with KSh X?" – recipes whose cost for the household
  /// fits the amount, using pantry items first.
  List<(Recipe, Money)> affordableRecipes(Money amount, double portions, DietFilter f, {Map<String, double> pantry = const {}, MealSlot? slot}) {
    final out = <(Recipe, Money)>[];
    for (final r in catalog.recipes.values) {
      if (slot != null && r.category != slot) continue;
      if (!f.recipeAllowed(r, catalog.products)) continue;
      final reqs = CalculationService.aggregate(CalculationService.recipeRequirements(r, portions, catalog.products));
      final toBuy = CalculationService.subtractPantry(reqs, pantry);
      final basket = CalculationService.costBasket(toBuy, catalog);
      if (!basket.complete) continue;
      if (basket.total <= amount) out.add((r, basket.total));
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  /// Recipes ranked by how much of the pantry (especially items near expiry) they use.
  List<(Recipe, int)> recipesUsingPantry(Map<String, double> pantry, DietFilter f, {Set<String> priority = const {}}) {
    final out = <(Recipe, int)>[];
    for (final r in catalog.recipes.values) {
      if (!f.recipeAllowed(r, catalog.products)) continue;
      var score = 0;
      for (final i in r.ingredients) {
        if ((pantry[i.productId] ?? 0) > 0) score += priority.contains(i.productId) ? 3 : 1;
      }
      if (score > 0) out.add((r, score));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }
}
