import '../core/money.dart';
import '../core/units.dart';

/// Shopping-list / pantry categories shown in the UI.
const productCategories = <String, String>{
  'cereals': 'Cereals',
  'vegetables': 'Vegetables',
  'fruits': 'Fruits',
  'meat': 'Meat and fish',
  'dairy': 'Dairy and eggs',
  'legumes': 'Legumes',
  'cooking': 'Cooking ingredients',
  'spices': 'Spices',
  'household': 'Household essentials',
};

class Product {
  final String id;
  final String name;
  final String category;
  final BaseUnit unit;
  final String emoji;
  final String imageUrl;
  final double defaultPackageSize;
  final String defaultPackageLabel;
  final List<String> allergens;
  final List<String> dietTags; // plant, meat, fish, dairy, egg
  final List<String> alternatives; // cheaper/similar product ids
  final int shelfLifeDays;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    this.emoji = '🛒',
    this.imageUrl = '',
    this.defaultPackageSize = 1,
    this.defaultPackageLabel = '',
    this.allergens = const [],
    this.dietTags = const [],
    this.alternatives = const [],
    this.shelfLifeDays = 0,
  });

  factory Product.fromMap(Map<String, dynamic> m, [String? id]) => Product(
        id: id ?? m['id'] as String,
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'cooking',
        unit: baseUnitFrom(m['unit'] as String? ?? 'pcs'),
        emoji: m['emoji'] as String? ?? '🛒',
        imageUrl: m['imageUrl'] as String? ?? '',
        defaultPackageSize: (m['defaultPackageSize'] as num?)?.toDouble() ?? 1,
        defaultPackageLabel: m['defaultPackageLabel'] as String? ?? '',
        allergens: List<String>.from(m['allergens'] ?? const []),
        dietTags: List<String>.from(m['dietTags'] ?? const []),
        alternatives: List<String>.from(m['alternatives'] ?? const []),
        shelfLifeDays: (m['shelfLifeDays'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'unit': unit.name,
        'emoji': emoji,
        'imageUrl': imageUrl,
        'defaultPackageSize': defaultPackageSize,
        'defaultPackageLabel': defaultPackageLabel,
        'allergens': allergens,
        'dietTags': dietTags,
        'alternatives': alternatives,
        'shelfLifeDays': shelfLifeDays,
      };
}

class Supermarket {
  final String id;
  final String name;
  final String color;
  final String location;
  final String address;
  /// A price reference such as "Kenya average (KNBS)" – not a shop you can pick.
  final bool reference;
  const Supermarket({required this.id, required this.name, this.color = '#3DA832', this.location = '', this.address = '', this.reference = false});

  factory Supermarket.fromMap(Map<String, dynamic> m, [String? id]) => Supermarket(
        id: id ?? m['id'] as String,
        name: m['name'] as String? ?? '',
        color: m['color'] as String? ?? '#3DA832',
        location: m['location'] as String? ?? '',
        address: m['address'] as String? ?? '',
        reference: m['reference'] as bool? ?? false,
      );
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'color': color, 'location': location, 'address': address, 'reference': reference};
}

/// How trustworthy a price is. Shown as a label next to every price.
enum PriceStatus { verified, userSubmitted, estimated, demo }

PriceStatus priceStatusFrom(String? s) {
  switch (s) {
    case 'verified':
      return PriceStatus.verified;
    case 'user_submitted':
      return PriceStatus.userSubmitted;
    case 'estimated':
      return PriceStatus.estimated;
    default:
      return PriceStatus.demo;
  }
}

String priceStatusKey(PriceStatus s) => switch (s) {
      PriceStatus.verified => 'verified',
      PriceStatus.userSubmitted => 'user_submitted',
      PriceStatus.estimated => 'estimated',
      PriceStatus.demo => 'demo',
    };

String priceStatusLabel(PriceStatus s) => switch (s) {
      PriceStatus.verified => 'Verified',
      PriceStatus.userSubmitted => 'User-submitted',
      PriceStatus.estimated => 'Estimate',
      PriceStatus.demo => 'Demo price',
    };

class PriceRecord {
  final String id;
  final String productId;
  final String supermarketId;
  final String brand;
  final double packageSize; // in the product's base unit
  final String packageLabel;
  final Money price; // price for one package
  final String location;
  final DateTime lastUpdated;
  final PriceStatus status;
  final String source;

  const PriceRecord({
    required this.id,
    required this.productId,
    required this.supermarketId,
    this.brand = '',
    required this.packageSize,
    this.packageLabel = '',
    required this.price,
    this.location = '',
    required this.lastUpdated,
    this.status = PriceStatus.demo,
    this.source = '',
  });

  factory PriceRecord.fromMap(Map<String, dynamic> m, [String? id]) {
    final lu = m['lastUpdated'];
    DateTime updated;
    if (lu is String) {
      updated = DateTime.tryParse(lu) ?? DateTime(2026);
    } else if (lu is DateTime) {
      updated = lu;
    } else {
      try {
        updated = (lu as dynamic).toDate() as DateTime; // Firestore Timestamp
      } catch (_) {
        updated = DateTime(2026);
      }
    }
    return PriceRecord(
      id: id ?? m['id'] as String,
      productId: m['productId'] as String,
      supermarketId: m['supermarketId'] as String,
      brand: m['brand'] as String? ?? '',
      packageSize: (m['packageSize'] as num?)?.toDouble() ?? 1,
      packageLabel: m['packageLabel'] as String? ?? '',
      price: Money.ksh((m['price'] as num?) ?? 0),
      location: m['location'] as String? ?? '',
      lastUpdated: updated,
      status: priceStatusFrom(m['verificationStatus'] as String?),
      source: m['source'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'supermarketId': supermarketId,
        'brand': brand,
        'packageSize': packageSize,
        'packageLabel': packageLabel,
        'price': price.shillings,
        'location': location,
        'lastUpdated': lastUpdated.toIso8601String(),
        'verificationStatus': priceStatusKey(status),
        'source': source,
      };
}

class RecipeIngredient {
  final String productId;
  final double amount; // in [unit]
  final String unit; // g, kg, ml, l, pcs, bunch, tbsp, tsp, packet
  const RecipeIngredient({required this.productId, required this.amount, required this.unit});
  factory RecipeIngredient.fromMap(Map<String, dynamic> m) => RecipeIngredient(
        productId: m['productId'] as String,
        amount: (m['amount'] as num).toDouble(),
        unit: m['unit'] as String? ?? 'pcs',
      );
  Map<String, dynamic> toMap() => {'productId': productId, 'amount': amount, 'unit': unit};
}

class Nutrition {
  final int kcal, protein, carbs, fat;
  const Nutrition({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});
  factory Nutrition.fromMap(Map<String, dynamic> m) => Nutrition(
        kcal: (m['kcal'] as num?)?.toInt() ?? 0,
        protein: (m['protein'] as num?)?.toInt() ?? 0,
        carbs: (m['carbs'] as num?)?.toInt() ?? 0,
        fat: (m['fat'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toMap() => {'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fat': fat};
}

enum MealSlot { breakfast, lunch, dinner, snack }

MealSlot mealSlotFrom(String s) => MealSlot.values.firstWhere((e) => e.name == s, orElse: () => MealSlot.lunch);

String mealSlotLabel(MealSlot s) => switch (s) {
      MealSlot.breakfast => 'Breakfast',
      MealSlot.lunch => 'Lunch',
      MealSlot.dinner => 'Dinner',
      MealSlot.snack => 'Snacks',
    };

class Recipe {
  final String id;
  final String name;
  final MealSlot category;
  final String emoji;
  final String imageUrl;
  final String description;
  final int prepMinutes;
  final int cookMinutes;
  final int servings;
  final List<String> tags; // vegan, vegetarian, quick, budget
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final Nutrition? nutrition; // per serving, approximate

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    this.emoji = '🍲',
    this.imageUrl = '',
    this.description = '',
    this.prepMinutes = 0,
    this.cookMinutes = 0,
    this.servings = 1,
    this.tags = const [],
    this.ingredients = const [],
    this.instructions = const [],
    this.nutrition,
  });

  int get totalMinutes => prepMinutes + cookMinutes;

  factory Recipe.fromMap(Map<String, dynamic> m, [String? id]) => Recipe(
        id: id ?? m['id'] as String,
        name: m['name'] as String? ?? '',
        category: mealSlotFrom(m['category'] as String? ?? 'lunch'),
        emoji: m['emoji'] as String? ?? '🍲',
        imageUrl: m['imageUrl'] as String? ?? '',
        description: m['description'] as String? ?? '',
        prepMinutes: (m['prepMinutes'] as num?)?.toInt() ?? 0,
        cookMinutes: (m['cookMinutes'] as num?)?.toInt() ?? 0,
        servings: (m['servings'] as num?)?.toInt() ?? 1,
        tags: List<String>.from(m['tags'] ?? const []),
        ingredients: ((m['ingredients'] as List?) ?? const [])
            .map((e) => RecipeIngredient.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        instructions: List<String>.from(m['instructions'] ?? const []),
        nutrition: m['nutrition'] == null ? null : Nutrition.fromMap(Map<String, dynamic>.from(m['nutrition'] as Map)),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category.name,
        'emoji': emoji,
        'imageUrl': imageUrl,
        'description': description,
        'prepMinutes': prepMinutes,
        'cookMinutes': cookMinutes,
        'servings': servings,
        'tags': tags,
        'ingredients': ingredients.map((e) => e.toMap()).toList(),
        'instructions': instructions,
        if (nutrition != null) 'nutrition': nutrition!.toMap(),
      };
}

/// Everything the planner needs, loaded once and cached.
class Catalog {
  final Map<String, Product> products;
  final Map<String, Recipe> recipes;
  final Map<String, Supermarket> supermarkets;
  final List<PriceRecord> prices;

  Catalog({required this.products, required this.recipes, required this.supermarkets, required this.prices});

  factory Catalog.empty() => Catalog(products: {}, recipes: {}, supermarkets: {}, prices: []);

  /// Real shops only (no price references like the KNBS national average).
  List<Supermarket> get shops => supermarkets.values.where((s) => !s.reference).toList();
  bool isReference(String supermarketId) => supermarkets[supermarketId]?.reference ?? false;

  List<PriceRecord> pricesFor(String productId) => prices.where((p) => p.productId == productId).toList();

  bool get hasOnlyDemoPrices => prices.every((p) => p.status == PriceStatus.demo);
}
