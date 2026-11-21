import '../core/money.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';
import 'calculation_service.dart';
import 'meal_planner_service.dart';

enum SuggestionType { substitute, switchStore, swapMeal, mergeDuplicates, seasonal, useLeftovers }

/// One money-saving suggestion the user can accept or reject.
class Suggestion {
  final String id;
  final SuggestionType type;
  final String title;
  final String detail;
  final Money saving;
  final Map<String, String> payload; // data needed to apply it
  const Suggestion({required this.id, required this.type, required this.title, required this.detail, required this.saving, this.payload = const {}});
}

class OptimizationReport {
  final Money original;
  final Money optimised;
  final List<Suggestion> suggestions;
  const OptimizationReport(this.original, this.optimised, this.suggestions);
  Money get savings => original - optimised;
}

/// Finds ways to spend less without breaking diet or allergy rules.
class OptimizerService {
  final Catalog catalog;
  OptimizerService(this.catalog);

  /// Rough Kenyan seasonal guide used only for tips (no prices invented).
  static const _inSeason = <int, List<String>>{
    1: ['mangoes', 'watermelon', 'avocado'],
    2: ['mangoes', 'watermelon'],
    3: ['mangoes', 'avocado'],
    4: ['avocado', 'sukuma', 'managu'],
    5: ['avocado', 'sukuma', 'managu', 'kienyeji_veg'],
    6: ['avocado', 'oranges', 'potatoes'],
    7: ['oranges', 'potatoes', 'avocado'],
    8: ['oranges', 'potatoes'],
    9: ['oranges', 'pawpaw'],
    10: ['pawpaw', 'sukuma'],
    11: ['mangoes', 'sukuma', 'managu', 'kienyeji_veg'],
    12: ['mangoes', 'watermelon', 'sukuma'],
  };

  OptimizationReport analyse({
    required List<PlannedMeal> meals,
    required Map<String, double> pantry,
    required UserProfile profile,
    required String supermarketId,
    DateTime? now,
    List<ShoppingItem> manualItems = const [],
    Map<String, String> substitutions = const {},
  }) {
    final filter = DietFilter.fromProfile(profile);
    final planner = MealPlannerService(catalog);
    final toBuy = planner.toBuyFor(meals, pantry, substitutions);
    final basket = CalculationService.costBasket(toBuy, catalog, supermarketId: supermarketId);
    final original = basket.total;
    final s = <Suggestion>[];

    // 1. Cheaper alternative products (same base unit only, allergy safe).
    for (final line in basket.lines) {
      if (!line.hasPrice) continue;
      for (final altId in line.product.alternatives) {
        final alt = catalog.products[altId];
        if (alt == null || alt.unit != line.product.unit || !filter.productAllowed(alt)) continue;
        final price = CalculationService.bestPrice(alt.id, line.required, catalog, supermarketId: supermarketId);
        if (price == null) continue;
        final altCost = CalculationService.lineCost(line.required, price);
        final saving = line.cost - altCost;
        if (saving.cents > 0) {
          s.add(Suggestion(
            id: 'sub_${line.product.id}_${alt.id}',
            type: SuggestionType.substitute,
            title: 'Use ${alt.name} instead of ${line.product.name}',
            detail: '${line.cost.format()} → ${altCost.format()} for the same quantity.',
            saving: saving,
            payload: {'from': line.product.id, 'to': alt.id},
          ));
          break;
        }
      }
    }

    // 2. Cheaper meal swaps.
    final portions = profile.portionsPerMeal;
    Money mealCost(String rid) =>
        CalculationService.recipeCost(catalog.recipes[rid]!, portions, catalog, supermarketId: supermarketId) ?? const Money.zero();
    final byCost = [...meals]..sort((a, b) => mealCost(b.recipeId).compareTo(mealCost(a.recipeId)));
    final seen = <String>{};
    for (final m in byCost) {
      if (seen.length >= 3) break;
      if (!seen.add(m.recipeId)) continue;
      final options = planner.swapOptions(m, profile, supermarketId: supermarketId);
      if (options.isEmpty) continue;
      final cheapest = options.first;
      final swapped = meals.map((x) => x.recipeId == m.recipeId ? x.copyWith(recipeId: cheapest.id) : x).toList();
      final newTotal = planner.basketFor(swapped, pantry, supermarketId, substitutions).total;
      final saving = original - newTotal;
      if (saving.cents > 0) {
        final from = catalog.recipes[m.recipeId]!;
        s.add(Suggestion(
          id: 'swap_${m.recipeId}_${cheapest.id}',
          type: SuggestionType.swapMeal,
          title: 'Swap ${from.name} for ${cheapest.name}',
          detail: 'Applies to every ${from.name} in this plan.',
          saving: saving,
          payload: {'from': m.recipeId, 'to': cheapest.id},
        ));
      }
    }

    // 3. Cheaper supermarket for the whole basket.
    final baskets = CalculationService.basketsBySupermarket(toBuy, catalog).where((b) => b.complete).toList();
    if (baskets.isNotEmpty && baskets.first.supermarketId != supermarketId) {
      final best = baskets.first;
      final saving = original - best.total;
      if (saving.cents > 0 && basket.complete) {
        final name = catalog.supermarkets[best.supermarketId]?.name ?? best.supermarketId;
        s.add(Suggestion(
          id: 'store_${best.supermarketId}',
          type: SuggestionType.switchStore,
          title: 'Shop at $name',
          detail: 'Same basket costs ${best.total.format()} there.',
          saving: saving,
          payload: {'supermarketId': best.supermarketId},
        ));
      }
    }

    // 4. Duplicate products in a manual list.
    final counts = <String, int>{};
    for (final i in manualItems) {
      if (i.productId.isNotEmpty) counts[i.productId] = (counts[i.productId] ?? 0) + 1;
    }
    counts.forEach((pid, n) {
      if (n > 1) {
        s.add(Suggestion(
          id: 'dup_$pid',
          type: SuggestionType.mergeDuplicates,
          title: '${catalog.products[pid]?.name ?? pid} appears $n times',
          detail: 'Merge them into one line so you don\'t buy twice.',
          saving: const Money.zero(),
          payload: {'productId': pid},
        ));
      }
    });

    // 5. Seasonal tip.
    final month = (now ?? DateTime.now()).month;
    final seasonal = (_inSeason[month] ?? const []).where((id) => catalog.products[id] != null && filter.productAllowed(catalog.products[id]!)).toList();
    if (seasonal.isNotEmpty) {
      s.add(Suggestion(
        id: 'season_$month',
        type: SuggestionType.seasonal,
        title: 'In season now: ${seasonal.map((e) => catalog.products[e]!.name.split(' (').first).join(', ')}',
        detail: 'Produce in season is usually cheaper at the local market. Check prices before you buy.',
        saving: const Money.zero(),
      ));
    }

    s.sort((a, b) => b.saving.compareTo(a.saving));
    // Optimised total if all non-conflicting money suggestions are accepted:
    // the best single store or meal swap plus substitutions is approximated by
    // the largest saving of each type.
    var optimised = original;
    final bestByType = <SuggestionType, Money>{};
    for (final x in s) {
      if (x.type == SuggestionType.substitute) {
        optimised -= x.saving;
      } else if (x.saving.cents > 0) {
        bestByType[x.type] = (bestByType[x.type] == null || x.saving > bestByType[x.type]!) ? x.saving : bestByType[x.type]!;
      }
    }
    for (final v in bestByType.values) {
      optimised -= v;
    }
    if (optimised.isNegative) optimised = const Money.zero();
    return OptimizationReport(original, optimised, s);
  }
}
