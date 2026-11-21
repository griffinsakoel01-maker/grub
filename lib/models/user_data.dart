import '../core/money.dart';
import 'catalog.dart';

enum BudgetFrequency { daily, weekly, biweekly, monthly, custom }

BudgetFrequency budgetFrequencyFrom(String? s) =>
    BudgetFrequency.values.firstWhere((e) => e.name == s, orElse: () => BudgetFrequency.weekly);

String budgetFrequencyLabel(BudgetFrequency f) => switch (f) {
      BudgetFrequency.daily => 'Daily',
      BudgetFrequency.weekly => 'Weekly',
      BudgetFrequency.biweekly => 'Every 2 weeks',
      BudgetFrequency.monthly => 'Monthly',
      BudgetFrequency.custom => 'Custom',
    };

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v);
  if (v is DateTime) return v;
  try {
    return (v as dynamic).toDate() as DateTime; // Firestore Timestamp
  } catch (_) {
    return null;
  }
}

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final int adults;
  final int kids; // kids count as half portions
  final Money budget;
  final BudgetFrequency budgetFrequency;
  final int customBudgetDays;
  final List<String> mealSlots; // breakfast, lunch, dinner, snack
  final List<int> cookingDays; // 1=Mon … 7=Sun
  final List<String> diets; // none, vegetarian, vegan, pescatarian, no_pork, low_carb, high_protein
  final List<String> allergies; // eggs, dairy, peanuts, gluten, fish, soy, coconut …
  final List<String> dislikes; // product ids
  final List<String> favouriteMeals; // recipe ids
  final List<String> preferredSupermarkets;
  final String county;
  final String cookingStyle; // quick, batch, comfort, budget
  final bool onboarded;
  final bool notifications;
  final bool shareAnonymousPrices;

  const UserProfile({
    required this.uid,
    this.name = '',
    this.email = '',
    this.adults = 2,
    this.kids = 0,
    this.budget = const Money(500000),
    this.budgetFrequency = BudgetFrequency.weekly,
    this.customBudgetDays = 7,
    this.mealSlots = const ['breakfast', 'lunch', 'dinner'],
    this.cookingDays = const [1, 2, 3, 4, 5, 6, 7],
    this.diets = const [],
    this.allergies = const [],
    this.dislikes = const [],
    this.favouriteMeals = const [],
    this.preferredSupermarkets = const [],
    this.county = '',
    this.cookingStyle = 'budget',
    this.onboarded = false,
    this.notifications = true,
    this.shareAnonymousPrices = false,
  });

  /// Kids eat half portions → "portions per meal".
  double get portionsPerMeal => adults + kids * 0.5;
  int get householdSize => adults + kids;
  List<MealSlot> get slots => mealSlots.map(mealSlotFrom).toList();

  UserProfile copyWith({
    String? name,
    String? email,
    int? adults,
    int? kids,
    Money? budget,
    BudgetFrequency? budgetFrequency,
    int? customBudgetDays,
    List<String>? mealSlots,
    List<int>? cookingDays,
    List<String>? diets,
    List<String>? allergies,
    List<String>? dislikes,
    List<String>? favouriteMeals,
    List<String>? preferredSupermarkets,
    String? county,
    String? cookingStyle,
    bool? onboarded,
    bool? notifications,
    bool? shareAnonymousPrices,
  }) =>
      UserProfile(
        uid: uid,
        name: name ?? this.name,
        email: email ?? this.email,
        adults: adults ?? this.adults,
        kids: kids ?? this.kids,
        budget: budget ?? this.budget,
        budgetFrequency: budgetFrequency ?? this.budgetFrequency,
        customBudgetDays: customBudgetDays ?? this.customBudgetDays,
        mealSlots: mealSlots ?? this.mealSlots,
        cookingDays: cookingDays ?? this.cookingDays,
        diets: diets ?? this.diets,
        allergies: allergies ?? this.allergies,
        dislikes: dislikes ?? this.dislikes,
        favouriteMeals: favouriteMeals ?? this.favouriteMeals,
        preferredSupermarkets: preferredSupermarkets ?? this.preferredSupermarkets,
        county: county ?? this.county,
        cookingStyle: cookingStyle ?? this.cookingStyle,
        onboarded: onboarded ?? this.onboarded,
        notifications: notifications ?? this.notifications,
        shareAnonymousPrices: shareAnonymousPrices ?? this.shareAnonymousPrices,
      );

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        name: m['name'] as String? ?? '',
        email: m['email'] as String? ?? '',
        adults: (m['adults'] as num?)?.toInt() ?? (m['householdSize'] as num?)?.toInt() ?? 2,
        kids: (m['kids'] as num?)?.toInt() ?? 0,
        budget: Money.ksh((m['budget'] as num?) ?? 5000),
        budgetFrequency: budgetFrequencyFrom(m['budgetFrequency'] as String?),
        customBudgetDays: (m['customBudgetDays'] as num?)?.toInt() ?? 7,
        mealSlots: List<String>.from(m['mealSlots'] ?? const ['breakfast', 'lunch', 'dinner']),
        cookingDays: List<int>.from(m['cookingDays'] ?? const [1, 2, 3, 4, 5, 6, 7]),
        diets: List<String>.from(m['preferences'] ?? m['diets'] ?? const []),
        allergies: List<String>.from(m['allergies'] ?? const []),
        dislikes: List<String>.from(m['dislikes'] ?? const []),
        favouriteMeals: List<String>.from(m['favouriteMeals'] ?? const []),
        preferredSupermarkets: List<String>.from(m['preferredSupermarkets'] ?? const []),
        county: m['location'] as String? ?? '',
        cookingStyle: m['cookingStyle'] as String? ?? 'budget',
        onboarded: m['onboarded'] as bool? ?? false,
        notifications: m['notifications'] as bool? ?? true,
        shareAnonymousPrices: m['shareAnonymousPrices'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'userId': uid,
        'name': name,
        'email': email,
        'adults': adults,
        'kids': kids,
        'householdSize': householdSize,
        'budget': budget.shillings,
        'budgetFrequency': budgetFrequency.name,
        'customBudgetDays': customBudgetDays,
        'mealSlots': mealSlots,
        'cookingDays': cookingDays,
        'preferences': diets,
        'allergies': allergies,
        'dislikes': dislikes,
        'favouriteMeals': favouriteMeals,
        'preferredSupermarkets': preferredSupermarkets,
        'location': county,
        'cookingStyle': cookingStyle,
        'onboarded': onboarded,
        'notifications': notifications,
        'shareAnonymousPrices': shareAnonymousPrices,
      };
}

/// One meal in the plan.
class PlannedMeal {
  final int dayIndex; // 0 = first day of plan
  final MealSlot slot;
  final String recipeId;
  final double portions;
  final bool cooked;
  const PlannedMeal({required this.dayIndex, required this.slot, required this.recipeId, required this.portions, this.cooked = false});

  PlannedMeal copyWith({int? dayIndex, MealSlot? slot, String? recipeId, double? portions, bool? cooked}) => PlannedMeal(
        dayIndex: dayIndex ?? this.dayIndex,
        slot: slot ?? this.slot,
        recipeId: recipeId ?? this.recipeId,
        portions: portions ?? this.portions,
        cooked: cooked ?? this.cooked,
      );

  factory PlannedMeal.fromMap(Map<String, dynamic> m) => PlannedMeal(
        dayIndex: (m['dayIndex'] as num).toInt(),
        slot: mealSlotFrom(m['slot'] as String),
        recipeId: m['recipeId'] as String,
        portions: (m['portions'] as num).toDouble(),
        cooked: m['cooked'] as bool? ?? false,
      );
  Map<String, dynamic> toMap() => {'dayIndex': dayIndex, 'slot': slot.name, 'recipeId': recipeId, 'portions': portions, 'cooked': cooked};
}

class MealPlan {
  final String id;
  final String userId;
  final DateTime startDate;
  final int days;
  final List<PlannedMeal> meals;
  final Money budget; // budget for this plan period
  final String supermarketId;
  final Map<String, String> substitutions; // productId → cheaper productId (accepted suggestions)

  const MealPlan({
    required this.id,
    required this.userId,
    required this.startDate,
    required this.days,
    required this.meals,
    required this.budget,
    this.supermarketId = '',
    this.substitutions = const {},
  });

  DateTime get endDate => startDate.add(Duration(days: days - 1));

  MealPlan copyWith({List<PlannedMeal>? meals, Money? budget, String? supermarketId, int? days, DateTime? startDate, Map<String, String>? substitutions}) => MealPlan(
        id: id,
        userId: userId,
        startDate: startDate ?? this.startDate,
        days: days ?? this.days,
        meals: meals ?? this.meals,
        budget: budget ?? this.budget,
        supermarketId: supermarketId ?? this.supermarketId,
        substitutions: substitutions ?? this.substitutions,
      );

  factory MealPlan.fromMap(String id, Map<String, dynamic> m) => MealPlan(
        id: id,
        userId: m['userId'] as String? ?? '',
        startDate: _date(m['startDate']) ?? DateTime.now(),
        days: (m['days'] as num?)?.toInt() ?? 7,
        meals: ((m['meals'] as List?) ?? const []).map((e) => PlannedMeal.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
        budget: Money.ksh((m['budget'] as num?) ?? 0),
        supermarketId: m['supermarketId'] as String? ?? '',
        substitutions: Map<String, String>.from(m['substitutions'] ?? const {}),
      );

  Map<String, dynamic> toMap() => {
        'planId': id,
        'userId': userId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'days': days,
        'meals': meals.map((e) => e.toMap()).toList(),
        'budget': budget.shillings,
        'supermarketId': supermarketId,
        'substitutions': substitutions,
      };
}

class ShoppingItem {
  final String id;
  final String productId; // '' for manual items
  final String name;
  final String emoji;
  final String category;
  final String quantityLabel; // "2 kg", "3 × 1 kg packet"
  final double requiredBase; // required quantity in base unit (for reference)
  final int packages;
  final Money unitPrice; // price per package / unit bought
  final bool purchased;
  final Money? actualPrice;
  final String priceStatus; // verified | user_submitted | estimated | demo | manual

  const ShoppingItem({
    required this.id,
    this.productId = '',
    required this.name,
    this.emoji = '🛒',
    this.category = 'household',
    this.quantityLabel = '',
    this.requiredBase = 0,
    this.packages = 1,
    required this.unitPrice,
    this.purchased = false,
    this.actualPrice,
    this.priceStatus = 'estimated',
  });

  Money get total => unitPrice * packages;

  ShoppingItem copyWith({
    String? name,
    String? quantityLabel,
    int? packages,
    Money? unitPrice,
    bool? purchased,
    Money? actualPrice,
    bool clearActual = false,
    String? priceStatus,
    String? category,
  }) =>
      ShoppingItem(
        id: id,
        productId: productId,
        name: name ?? this.name,
        emoji: emoji,
        category: category ?? this.category,
        quantityLabel: quantityLabel ?? this.quantityLabel,
        requiredBase: requiredBase,
        packages: packages ?? this.packages,
        unitPrice: unitPrice ?? this.unitPrice,
        purchased: purchased ?? this.purchased,
        actualPrice: clearActual ? null : (actualPrice ?? this.actualPrice),
        priceStatus: priceStatus ?? this.priceStatus,
      );

  factory ShoppingItem.fromMap(Map<String, dynamic> m) => ShoppingItem(
        id: m['id'] as String,
        productId: m['productId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        emoji: m['emoji'] as String? ?? '🛒',
        category: m['category'] as String? ?? 'household',
        quantityLabel: m['quantityLabel'] as String? ?? '',
        requiredBase: (m['requiredBase'] as num?)?.toDouble() ?? 0,
        packages: (m['packages'] as num?)?.toInt() ?? 1,
        unitPrice: Money((m['unitPriceCents'] as num?)?.toInt() ?? 0),
        purchased: m['purchased'] as bool? ?? false,
        actualPrice: m['actualPriceCents'] == null ? null : Money((m['actualPriceCents'] as num).toInt()),
        priceStatus: m['priceStatus'] as String? ?? 'estimated',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'name': name,
        'emoji': emoji,
        'category': category,
        'quantityLabel': quantityLabel,
        'requiredBase': requiredBase,
        'packages': packages,
        'unitPriceCents': unitPrice.cents,
        'purchased': purchased,
        if (actualPrice != null) 'actualPriceCents': actualPrice!.cents,
        'priceStatus': priceStatus,
      };
}

class ShoppingList {
  final String id;
  final String userId;
  final String name;
  final String supermarketId;
  final Money budget;
  final List<ShoppingItem> items;
  final DateTime createdAt;
  final String planId;

  const ShoppingList({
    required this.id,
    required this.userId,
    required this.name,
    this.supermarketId = '',
    required this.budget,
    required this.items,
    required this.createdAt,
    this.planId = '',
  });

  Money get estimatedTotal => Money.sum(items.map((e) => e.total));
  Money get purchasedEstimate => Money.sum(items.where((e) => e.purchased).map((e) => e.total));
  Money get actualTotal => Money.sum(items.where((e) => e.purchased).map((e) => e.actualPrice ?? e.total));
  Money get remaining => budget - estimatedTotal;
  int get purchasedCount => items.where((e) => e.purchased).length;

  ShoppingList copyWith({String? name, List<ShoppingItem>? items, Money? budget, String? supermarketId}) => ShoppingList(
        id: id,
        userId: userId,
        name: name ?? this.name,
        supermarketId: supermarketId ?? this.supermarketId,
        budget: budget ?? this.budget,
        items: items ?? this.items,
        createdAt: createdAt,
        planId: planId,
      );

  factory ShoppingList.fromMap(String id, Map<String, dynamic> m) => ShoppingList(
        id: id,
        userId: m['userId'] as String? ?? '',
        name: m['name'] as String? ?? 'Shopping list',
        supermarketId: m['supermarketId'] as String? ?? '',
        budget: Money((m['budgetCents'] as num?)?.toInt() ?? 0),
        items: ((m['items'] as List?) ?? const []).map((e) => ShoppingItem.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        planId: m['planId'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'listId': id,
        'userId': userId,
        'name': name,
        'supermarketId': supermarketId,
        'budgetCents': budget.cents,
        'items': items.map((e) => e.toMap()).toList(),
        'estimatedTotal': estimatedTotal.shillings,
        'actualTotal': actualTotal.shillings,
        'createdAt': createdAt.toIso8601String(),
        'planId': planId,
      };
}

class PantryItem {
  final String id;
  final String userId;
  final String productId;
  final String name;
  final double quantity; // base unit of product
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final String storage; // cupboard, fridge, freezer

  const PantryItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.name,
    required this.quantity,
    this.purchaseDate,
    this.expiryDate,
    this.storage = 'cupboard',
  });

  int? daysToExpiry(DateTime now) {
    if (expiryDate == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return exp.difference(today).inDays;
  }

  PantryItem copyWith({double? quantity, DateTime? expiryDate, DateTime? purchaseDate, String? storage, bool clearExpiry = false}) => PantryItem(
        id: id,
        userId: userId,
        productId: productId,
        name: name,
        quantity: quantity ?? this.quantity,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
        storage: storage ?? this.storage,
      );

  factory PantryItem.fromMap(String id, Map<String, dynamic> m) => PantryItem(
        id: id,
        userId: m['userId'] as String? ?? '',
        productId: m['productId'] as String,
        name: m['name'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        purchaseDate: _date(m['purchaseDate']),
        expiryDate: _date(m['expiryDate']),
        storage: m['storage'] as String? ?? 'cupboard',
      );

  Map<String, dynamic> toMap() => {
        'pantryId': id,
        'userId': userId,
        'productId': productId,
        'name': name,
        'quantity': quantity,
        if (purchaseDate != null) 'purchaseDate': purchaseDate!.toIso8601String(),
        if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
        'storage': storage,
      };
}

class Expense {
  final String id;
  final String userId;
  final Money amount;
  final Money? estimated;
  final String category;
  final String note;
  final String supermarketId;
  final DateTime date;

  const Expense({
    required this.id,
    required this.userId,
    required this.amount,
    this.estimated,
    this.category = 'groceries',
    this.note = '',
    this.supermarketId = '',
    required this.date,
  });

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
        id: id,
        userId: m['userId'] as String? ?? '',
        amount: Money((m['amountCents'] as num?)?.toInt() ?? (((m['amount'] as num?) ?? 0) * 100).round()),
        estimated: m['estimatedCents'] == null ? null : Money((m['estimatedCents'] as num).toInt()),
        category: m['category'] as String? ?? 'groceries',
        note: m['note'] as String? ?? '',
        supermarketId: m['supermarketId'] as String? ?? '',
        date: _date(m['date']) ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'expenseId': id,
        'userId': userId,
        'amount': amount.shillings,
        'amountCents': amount.cents,
        if (estimated != null) 'estimatedCents': estimated!.cents,
        'category': category,
        'note': note,
        'supermarketId': supermarketId,
        'date': date.toIso8601String(),
      };
}
