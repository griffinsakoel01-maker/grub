import 'package:flutter_test/flutter_test.dart';
import 'package:grub/core/money.dart';
import 'package:grub/core/units.dart';
import 'package:grub/models/catalog.dart';
import 'package:grub/models/user_data.dart';
import 'package:grub/services/calculation_service.dart';
import 'package:grub/services/meal_planner_service.dart';
import 'package:grub/services/optimizer_service.dart';

Catalog _catalog() {
  final products = {
    'rice': const Product(id: 'rice', name: 'Rice', category: 'cereals', unit: BaseUnit.g),
    'beef': const Product(id: 'beef', name: 'Beef', category: 'meat', unit: BaseUnit.g, dietTags: ['meat'], alternatives: ['beans']),
    'beans': const Product(id: 'beans', name: 'Beans', category: 'legumes', unit: BaseUnit.g, dietTags: ['plant']),
    'tomatoes': const Product(id: 'tomatoes', name: 'Tomatoes', category: 'vegetables', unit: BaseUnit.pcs),
    'onions': const Product(id: 'onions', name: 'Onions', category: 'vegetables', unit: BaseUnit.pcs),
    'oil': const Product(id: 'oil', name: 'Cooking oil', category: 'cooking', unit: BaseUnit.ml),
    'eggs': const Product(id: 'eggs', name: 'Eggs', category: 'dairy', unit: BaseUnit.pcs, allergens: ['eggs'], dietTags: ['egg']),
  };
  final stew = Recipe(
    id: 'stew',
    name: 'Beef stew and rice',
    category: MealSlot.lunch,
    servings: 2,
    ingredients: const [
      RecipeIngredient(productId: 'rice', amount: 250, unit: 'g'),
      RecipeIngredient(productId: 'beef', amount: 300, unit: 'g'),
      RecipeIngredient(productId: 'tomatoes', amount: 2, unit: 'pcs'),
      RecipeIngredient(productId: 'onions', amount: 1, unit: 'pcs'),
      RecipeIngredient(productId: 'oil', amount: 50, unit: 'ml'),
    ],
  );
  final beansRice = Recipe(
    id: 'beans_rice',
    name: 'Rice and beans',
    category: MealSlot.lunch,
    servings: 4,
    ingredients: const [
      RecipeIngredient(productId: 'rice', amount: 400, unit: 'g'),
      RecipeIngredient(productId: 'beans', amount: 400, unit: 'g'),
      RecipeIngredient(productId: 'tomatoes', amount: 3, unit: 'pcs'),
      RecipeIngredient(productId: 'oil', amount: 3, unit: 'tbsp'),
    ],
  );
  final eggsBf = Recipe(
    id: 'eggs_bf',
    name: 'Eggs',
    category: MealSlot.breakfast,
    servings: 2,
    ingredients: const [RecipeIngredient(productId: 'eggs', amount: 4, unit: 'pcs')],
  );
  PriceRecord pr(String p, String s, double size, num price) => PriceRecord(
      id: '$p$s', productId: p, supermarketId: s, packageSize: size, price: Money.ksh(price), lastUpdated: DateTime(2026));
  return Catalog(
    products: products,
    recipes: {'stew': stew, 'beans_rice': beansRice, 'eggs_bf': eggsBf},
    supermarkets: {
      'a': const Supermarket(id: 'a', name: 'Shop A'),
      'b': const Supermarket(id: 'b', name: 'Shop B'),
    },
    prices: [
      pr('rice', 'a', 1000, 200), pr('rice', 'b', 1000, 180),
      pr('beef', 'a', 1000, 650), pr('beef', 'b', 1000, 700),
      pr('beans', 'a', 1000, 200), pr('beans', 'b', 1000, 190),
      pr('tomatoes', 'a', 1, 15), pr('tomatoes', 'b', 1, 12),
      pr('onions', 'a', 1, 15), pr('onions', 'b', 1, 14),
      pr('oil', 'a', 1000, 320), pr('oil', 'b', 1000, 330),
      pr('eggs', 'a', 1, 17), pr('eggs', 'b', 1, 16),
    ],
  );
}

void main() {
  group('A. recipe scaling', () {
    test('scales 2 → 6 servings by ×3 (spec example)', () {
      final c = _catalog();
      final reqs = CalculationService.recipeRequirements(c.recipes['stew']!, 6, c.products);
      final m = {for (final r in reqs) r.productId: r.quantity};
      expect(m['rice'], 750);
      expect(m['beef'], 900);
      expect(m['tomatoes'], 6);
      expect(m['onions'], 3);
      expect(m['oil'], 150);
    });

    test('tablespoons convert to ml', () {
      expect(Units.toBase(3, 'tbsp', BaseUnit.ml), 45);
      expect(Units.toBase(2, 'tsp', BaseUnit.g), 10);
      expect(Units.toBase(1.5, 'kg', BaseUnit.g), 1500);
    });
  });

  group('duplicate ingredients', () {
    test('tomatoes from two recipes combine into one entry', () {
      final c = _catalog();
      final meals = [
        const PlannedMeal(dayIndex: 0, slot: MealSlot.lunch, recipeId: 'stew', portions: 2),
        const PlannedMeal(dayIndex: 1, slot: MealSlot.lunch, recipeId: 'beans_rice', portions: 4),
      ];
      final req = CalculationService.planRequirements(meals, c);
      expect(req['tomatoes']!.quantity, 5);
      expect(req['rice']!.quantity, 650);
      expect(req['tomatoes']!.recipeIds, {'stew', 'beans_rice'});
    });
  });

  group('B. pantry subtraction', () {
    test('3 kg needed, 1 kg at home → buy 2 kg', () {
      expect(CalculationService.toPurchase(3000, 1000), 2000);
    });
    test('fully covered items are dropped', () {
      final out = CalculationService.subtractPantry(
          {'rice': const Requirement('rice', 500, {}), 'beef': const Requirement('beef', 300, {})}, {'rice': 1000});
      expect(out.containsKey('rice'), isFalse);
      expect(out['beef'], 300);
    });
  });

  group('C/D/E. costs', () {
    test('fixed packages round up', () {
      expect(CalculationService.packagesNeeded(1500, 1000), 2);
      expect(CalculationService.packagesNeeded(1000, 1000), 1);
      expect(CalculationService.packagesNeeded(0, 1000), 0);
      expect(CalculationService.packagesNeeded(3.0000000001, 1), 3);
    });

    test('basket uses cheapest price and totals exactly', () {
      final c = _catalog();
      final b = CalculationService.costBasket({'rice': 1500, 'tomatoes': 5}, c);
      // rice: 2 × 180 (shop b), tomatoes: 5 × 12 (shop b)
      expect(b.total, Money.ksh(420));
      final remaining = CalculationService.remaining(Money.ksh(1000), b.total);
      expect(remaining, Money.ksh(580));
    });

    test('per-supermarket baskets are sorted cheapest first', () {
      final c = _catalog();
      final baskets = CalculationService.basketsBySupermarket({'rice': 1000, 'beef': 500}, c);
      expect(baskets.first.supermarketId, 'a'); // 200+650=850 vs 180+700=880
      expect(baskets.first.total, Money.ksh(850));
    });

    test('money splits without losing cents', () {
      final parts = Money.ksh(100).split(3);
      expect(Money.sum(parts), Money.ksh(100));
    });
  });

  group('budget calculator', () {
    test('monthly → weekly conversion', () {
      final w = CalculationService.budgetForDays(Money.ksh(20000), BudgetFrequency.monthly, 0, 7);
      expect(w, Money.ksh(4666.67));
    });
    test('breakdown shares per meal', () {
      final bd = CalculationService.breakdown(
          periodBudget: Money.ksh(8000), days: 7, slots: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner], portionsPerMeal: 4);
      expect(bd.perDay, Money.ksh(1142.86));
      expect(bd.perSlotPerDay[MealSlot.dinner]! > bd.perSlotPerDay[MealSlot.breakfast]!, isTrue);
    });
  });

  group('planner and safety', () {
    test('allergy filter removes egg recipes', () {
      final c = _catalog();
      const f = DietFilter(allergies: ['eggs']);
      expect(f.recipeAllowed(c.recipes['eggs_bf']!, c.products), isFalse);
      expect(f.recipeAllowed(c.recipes['stew']!, c.products), isTrue);
    });

    test('vegetarian never gets beef', () {
      final c = _catalog();
      final res = MealPlannerService(c).generate(PlanRequest(
        profile: const UserProfile(uid: 'u', adults: 2, mealSlots: ['lunch'], diets: ['vegetarian']),
        startDate: DateTime(2026, 11, 23),
        days: 7,
        budget: Money.ksh(5000),
      ));
      expect(res.meals, isNotEmpty);
      expect(res.meals.every((m) => m.recipeId == 'beans_rice'), isTrue);
    });

    test('planner swaps to cheaper meals when over budget', () {
      final c = _catalog();
      final res = MealPlannerService(c).generate(PlanRequest(
        profile: const UserProfile(uid: 'u', adults: 2, mealSlots: ['lunch']),
        startDate: DateTime(2026, 11, 23),
        days: 7,
        budget: Money.ksh(1200),
        seed: 1,
      ));
      expect(res.total <= Money.ksh(1200) || !res.withinBudget, isTrue);
      final res2 = MealPlannerService(c).generate(PlanRequest(
        profile: const UserProfile(uid: 'u', adults: 2, mealSlots: ['lunch']),
        startDate: DateTime(2026, 11, 23),
        days: 7,
        budget: Money.ksh(100000),
        seed: 1,
      ));
      expect(res.total <= res2.total, isTrue);
    });

    test('optimizer suggests beans for beef, never an allergen', () {
      final c = _catalog();
      final report = OptimizerService(c).analyse(
        meals: const [PlannedMeal(dayIndex: 0, slot: MealSlot.lunch, recipeId: 'stew', portions: 6)],
        pantry: const {},
        profile: const UserProfile(uid: 'u', adults: 6, mealSlots: ['lunch']),
        supermarketId: 'a',
      );
      expect(report.suggestions.any((s) => s.type == SuggestionType.substitute && s.payload['to'] == 'beans'), isTrue);
      expect(report.optimised <= report.original, isTrue);
    });
  });

  group('real prices beat demo prices', () {
    test('KNBS average replaces demo, shop receipt price wins at that shop', () {
      final products = {'sugar': const Product(id: 'sugar', name: 'Sugar', category: 'cooking', unit: BaseUnit.g)};
      PriceRecord pr(String id, String shop, num price, PriceStatus st) => PriceRecord(
          id: id, productId: 'sugar', supermarketId: shop, packageSize: 1000, price: Money.ksh(price), lastUpdated: DateTime(2026), status: st);
      final c = Catalog(
        products: products,
        recipes: {},
        supermarkets: {
          'a': const Supermarket(id: 'a', name: 'A'),
          'b': const Supermarket(id: 'b', name: 'B'),
          'kenya_avg': const Supermarket(id: 'kenya_avg', name: 'Kenya average', reference: true),
        },
        prices: [
          pr('1', 'a', 150, PriceStatus.demo),
          pr('2', 'b', 140, PriceStatus.demo),
          pr('3', 'kenya_avg', 164, PriceStatus.estimated),
          pr('4', 'a', 170, PriceStatus.userSubmitted),
        ],
      );
      expect(CalculationService.bestPrice('sugar', 1000, c, supermarketId: 'a')!.id, '4');
      expect(CalculationService.bestPrice('sugar', 1000, c, supermarketId: 'b')!.id, '3');
      expect(CalculationService.bestPrice('sugar', 1000, c)!.id, '4');
    });
  });

  group('shopping list totals update', () {
    test('changing quantity changes the total', () {
      final item = ShoppingItem(id: '1', name: 'Rice', unitPrice: Money.ksh(175), packages: 2);
      final list = ShoppingList(id: 'l', userId: 'u', name: 'L', budget: Money.ksh(1000), items: [item], createdAt: DateTime(2026));
      expect(list.estimatedTotal, Money.ksh(350));
      final updated = list.copyWith(items: [item.copyWith(packages: 3)]);
      expect(updated.estimatedTotal, Money.ksh(525));
      expect(updated.remaining, Money.ksh(475));
    });
  });
}
