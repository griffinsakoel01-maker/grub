import 'dart:math' as math;

import '../core/money.dart';
import '../core/units.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';

/// Tiny tolerance so 2.9999999 g does not become an extra packet.
const _eps = 1e-6;

/// A product requirement in the product's base unit.
class Requirement {
  final String productId;
  final double quantity;
  final Set<String> recipeIds;
  const Requirement(this.productId, this.quantity, this.recipeIds);
}

/// A costed shopping line.
class CostedLine {
  final Product product;
  final double required; // after pantry subtraction, base unit
  final int packages;
  final PriceRecord? price;
  final Money cost;
  const CostedLine({required this.product, required this.required, required this.packages, required this.price, required this.cost});

  bool get hasPrice => price != null;

  String get quantityLabel {
    if (price == null) return Units.display(required, product.unit);
    final pack = price!.packageLabel.isNotEmpty ? price!.packageLabel : Units.display(price!.packageSize, product.unit);
    final bought = packages * price!.packageSize;
    final isLooseCount = product.unit == BaseUnit.pcs || product.unit == BaseUnit.bunch;
    if (isLooseCount && price!.packageSize == 1) return Units.display(bought, product.unit);
    return packages == 1 ? pack : '$packages × $pack';
  }
}

class Basket {
  final String supermarketId; // '' = cheapest per item across shops
  final List<CostedLine> lines;
  const Basket(this.supermarketId, this.lines);

  Money get total => Money.sum(lines.map((l) => l.cost));
  List<CostedLine> get missing => lines.where((l) => !l.hasPrice).toList();
  bool get complete => missing.isEmpty;
}

class BudgetBreakdown {
  final Money periodBudget;
  final int days;
  final Money perDay;
  final Map<MealSlot, Money> perSlotPerDay;
  final Money perPortionPerMeal;
  const BudgetBreakdown({required this.periodBudget, required this.days, required this.perDay, required this.perSlotPerDay, required this.perPortionPerMeal});
}

/// All grocery maths lives here. Pure functions – no Flutter, no Firebase –
/// so they are unit tested in test/calculation_service_test.dart.
class CalculationService {
  // ---------------------------------------------------------------- A. scaling
  /// Required quantity = Original quantity × (Selected servings / Original servings)
  static double scale(double originalQuantity, int originalServings, double selectedServings) {
    if (originalServings <= 0) return originalQuantity;
    return originalQuantity * (selectedServings / originalServings);
  }

  /// Ingredient requirements of one recipe for [servings], in base units.
  static List<Requirement> recipeRequirements(Recipe recipe, double servings, Map<String, Product> products) {
    final out = <Requirement>[];
    for (final ing in recipe.ingredients) {
      final p = products[ing.productId];
      if (p == null) continue;
      final scaled = scale(ing.amount, recipe.servings, servings);
      out.add(Requirement(p.id, Units.toBase(scaled, ing.unit, p.unit), {recipe.id}));
    }
    return out;
  }

  /// Combines duplicate ingredients across recipes into one entry each.
  static Map<String, Requirement> aggregate(Iterable<Requirement> reqs) {
    final map = <String, Requirement>{};
    for (final r in reqs) {
      final existing = map[r.productId];
      map[r.productId] = existing == null
          ? Requirement(r.productId, r.quantity, {...r.recipeIds})
          : Requirement(r.productId, existing.quantity + r.quantity, {...existing.recipeIds, ...r.recipeIds});
    }
    return map;
  }

  /// Aggregated requirements for a whole meal plan.
  static Map<String, Requirement> planRequirements(Iterable<PlannedMeal> meals, Catalog catalog) {
    final all = <Requirement>[];
    for (final m in meals) {
      final r = catalog.recipes[m.recipeId];
      if (r == null) continue;
      all.addAll(recipeRequirements(r, m.portions, catalog.products));
    }
    return aggregate(all);
  }

  // ------------------------------------------------------ B. pantry subtraction
  /// Quantity to purchase = Required quantity − Available quantity (never < 0).
  static double toPurchase(double required, double available) => math.max(0, required - available);

  /// Removes anything fully covered by the pantry.
  static Map<String, double> subtractPantry(Map<String, Requirement> required, Map<String, double> pantry) {
    final out = <String, double>{};
    required.forEach((id, req) {
      final q = toPurchase(req.quantity, pantry[id] ?? 0);
      if (q > _eps) out[id] = q;
    });
    return out;
  }

  /// Replaces products with accepted cheaper alternatives, merging quantities.
  static Map<String, double> applySubstitutions(Map<String, double> toBuy, Map<String, String> subs) {
    if (subs.isEmpty) return toBuy;
    final out = <String, double>{};
    toBuy.forEach((id, q) {
      final target = subs[id] ?? id;
      out[target] = (out[target] ?? 0) + q;
    });
    return out;
  }

  // ---------------------------------------------------------- C. grocery cost
  /// Packages that must be bought to cover [quantity]. Fixed package sizes
  /// always round up (you cannot buy 0.3 of a 2 kg packet).
  static int packagesNeeded(double quantity, double packageSize) {
    if (quantity <= _eps) return 0;
    if (packageSize <= 0) return 1;
    return (quantity / packageSize - _eps).ceil();
  }

  /// Product cost = packages to buy × package price.
  static Money lineCost(double quantity, PriceRecord price) => price.price * packagesNeeded(quantity, price.packageSize);

  /// Cost of only what a recipe actually consumes (used for "cost per serving").
  static Money consumedCost(double quantity, PriceRecord price) {
    if (price.packageSize <= 0) return price.price;
    return price.price.scale(quantity / price.packageSize);
  }

  /// The price to use for [quantity] of a product.
  ///
  /// Real prices (verified, receipts, KNBS averages) always win over demo
  /// prices. For a chosen shop: that shop's real price → the national average
  /// (KNBS) → that shop's demo price → any real price. With no shop: cheapest
  /// real shop price → national average → anything.
  static PriceRecord? bestPrice(String productId, double quantity, Catalog catalog, {String? supermarketId}) {
    final all = catalog.prices.where((p) => p.productId == productId).toList();
    if (all.isEmpty) return null;
    bool real(PriceRecord p) => p.status != PriceStatus.demo;
    bool ref(PriceRecord p) => catalog.isReference(p.supermarketId);
    final shop = supermarketId ?? '';
    final tiers = shop.isNotEmpty
        ? [
            all.where((p) => p.supermarketId == shop && real(p)),
            all.where((p) => ref(p) && real(p)),
            all.where((p) => p.supermarketId == shop),
            all.where((p) => real(p)),
            all,
          ]
        : [
            all.where((p) => real(p) && !ref(p)),
            all.where((p) => ref(p) && real(p)),
            all.where((p) => !ref(p)),
            all,
          ];
    for (final tier in tiers) {
      final pick = _cheapest(tier, quantity);
      if (pick != null) return pick;
    }
    return null;
  }

  static PriceRecord? _cheapest(Iterable<PriceRecord> prices, double quantity) {
    PriceRecord? best;
    Money? bestCost;
    for (final p in prices) {
      final c = lineCost(quantity, p);
      if (bestCost == null || c < bestCost || (c == bestCost && _rank(p.status) < _rank(best!.status))) {
        best = p;
        bestCost = c;
      }
    }
    return best;
  }

  static int _rank(PriceStatus s) => switch (s) {
        PriceStatus.verified => 0,
        PriceStatus.userSubmitted => 1,
        PriceStatus.estimated => 2,
        PriceStatus.demo => 3,
      };

  /// Costs a basket. With a [supermarketId] all items are priced at that shop;
  /// otherwise each item uses its cheapest known price.
  static Basket costBasket(Map<String, double> toBuy, Catalog catalog, {String supermarketId = ''}) {
    final lines = <CostedLine>[];
    toBuy.forEach((id, qty) {
      final product = catalog.products[id];
      if (product == null) return;
      final price = bestPrice(id, qty, catalog, supermarketId: supermarketId);
      lines.add(CostedLine(
        product: product,
        required: qty,
        packages: price == null ? 0 : packagesNeeded(qty, price.packageSize),
        price: price,
        cost: price == null ? const Money.zero() : lineCost(qty, price),
      ));
    });
    lines.sort((a, b) {
      final c = a.product.category.compareTo(b.product.category);
      return c != 0 ? c : a.product.name.compareTo(b.product.name);
    });
    return Basket(supermarketId, lines);
  }

  /// Basket total per supermarket (only shops that stock at least one item).
  static List<Basket> basketsBySupermarket(Map<String, double> toBuy, Catalog catalog) {
    final out = <Basket>[];
    for (final s in catalog.supermarkets.values) {
      final b = costBasket(toBuy, catalog, supermarketId: s.id);
      if (b.lines.any((l) => l.hasPrice)) out.add(b);
    }
    out.sort((a, b) {
      // complete baskets first, then by total
      if (a.complete != b.complete) return a.complete ? -1 : 1;
      return a.total.compareTo(b.total);
    });
    return out;
  }

  // ------------------------------------------------- D/E. totals and budget
  static Money total(Iterable<Money> costs) => Money.sum(costs);

  /// Remaining budget = Original budget − Estimated shopping total.
  static Money remaining(Money budget, Money estimatedTotal) => budget - estimatedTotal;

  /// Fraction of budget used, clamped 0..1 for progress bars.
  static double progress(Money budget, Money spent) {
    if (budget.cents <= 0) return spent.cents > 0 ? 1 : 0;
    return (spent.cents / budget.cents).clamp(0.0, 1.0).toDouble();
  }

  // ---------------------------------------------------- budget calculator
  static int periodDays(BudgetFrequency f, int customDays) => switch (f) {
        BudgetFrequency.daily => 1,
        BudgetFrequency.weekly => 7,
        BudgetFrequency.biweekly => 14,
        BudgetFrequency.monthly => 30,
        BudgetFrequency.custom => math.max(1, customDays),
      };

  /// Converts a budget of any frequency into a budget for [days] days.
  static Money budgetForDays(Money budget, BudgetFrequency f, int customDays, int days) {
    final pd = periodDays(f, customDays);
    return Money((budget.cents * days / pd).round());
  }

  /// Relative share of a day's food money per meal.
  static const slotWeights = <MealSlot, double>{
    MealSlot.breakfast: 0.20,
    MealSlot.lunch: 0.35,
    MealSlot.dinner: 0.40,
    MealSlot.snack: 0.05,
  };

  static BudgetBreakdown breakdown({
    required Money periodBudget,
    required int days,
    required List<MealSlot> slots,
    required double portionsPerMeal,
  }) {
    final d = math.max(1, days);
    final perDay = Money((periodBudget.cents / d).round());
    final chosen = slots.isEmpty ? [MealSlot.lunch] : slots;
    final weightSum = chosen.fold<double>(0, (a, s) => a + slotWeights[s]!);
    final perSlot = <MealSlot, Money>{for (final s in chosen) s: perDay.scale(slotWeights[s]! / weightSum)};
    final mealsPerDay = chosen.length;
    final perPortion = (portionsPerMeal <= 0 || mealsPerDay == 0)
        ? const Money.zero()
        : Money((perDay.cents / (mealsPerDay * portionsPerMeal)).round());
    return BudgetBreakdown(periodBudget: periodBudget, days: d, perDay: perDay, perSlotPerDay: perSlot, perPortionPerMeal: perPortion);
  }

  // ------------------------------------------------------ recipe costing
  /// Estimated cost of a recipe for [servings] using only what is consumed.
  /// Returns null when any ingredient has no price at all.
  static Money? recipeCost(Recipe recipe, double servings, Catalog catalog, {String supermarketId = ''}) {
    var total = const Money.zero();
    for (final req in recipeRequirements(recipe, servings, catalog.products)) {
      final p = bestPrice(req.productId, req.quantity, catalog, supermarketId: supermarketId) ??
          bestPrice(req.productId, req.quantity, catalog);
      if (p == null) return null;
      total += consumedCost(req.quantity, p);
    }
    return total;
  }

  static Money? costPerServing(Recipe recipe, Catalog catalog, {String supermarketId = ''}) {
    final c = recipeCost(recipe, recipe.servings.toDouble(), catalog, supermarketId: supermarketId);
    if (c == null || recipe.servings <= 0) return c;
    return Money((c.cents / recipe.servings).round());
  }

  // ------------------------------------------------- shopping list builder
  static List<ShoppingItem> basketToItems(Basket basket, String Function() newId) {
    return basket.lines
        .map((l) => ShoppingItem(
              id: newId(),
              productId: l.product.id,
              name: l.product.name,
              emoji: l.product.emoji,
              category: _listCategory(l.product.category),
              quantityLabel: l.quantityLabel,
              requiredBase: l.required,
              packages: l.hasPrice ? l.packages : 1,
              unitPrice: l.price?.price ?? const Money.zero(),
              priceStatus: l.price == null ? 'missing' : priceStatusKey(l.price!.status),
            ))
        .toList();
  }

  /// Maps product categories onto the shopping-list sections.
  static String _listCategory(String c) => switch (c) {
        'legumes' => 'cereals',
        'spices' => 'cooking',
        _ => c,
      };
}
