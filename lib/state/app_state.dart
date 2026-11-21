import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/iterable_x.dart';
import '../core/money.dart';
import '../core/units.dart';
import '../data/repository.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';
import '../services/auth_service.dart';
import '../services/calculation_service.dart';
import '../services/meal_planner_service.dart';
import '../services/optimizer_service.dart';
import '../services/receipt_service.dart';

enum LoadStatus { idle, loading, ready, error }

/// Single source of truth for the UI. Every change recalculates derived
/// values (basket, totals, remaining budget) so the screens always update.
class AppState extends ChangeNotifier {
  final Repository repo;
  final AuthService auth;
  AppState({required this.repo, required this.auth});

  static const _uuid = Uuid();
  String newId() => _uuid.v4();

  LoadStatus status = LoadStatus.idle;
  String? error;
  AppUser? user;
  UserProfile? profile;
  Catalog catalog = Catalog.empty();
  MealPlan? plan;
  List<ShoppingList> lists = [];
  List<PantryItem> pantry = [];
  List<Expense> expenses = [];
  bool catalogLoaded = false;
  StreamSubscription<AppUser?>? _sub;
  Household? household;
  List<Recipe> myRecipes = [];
  StreamSubscription<Household?>? _hhSub;
  StreamSubscription<List<ShoppingList>>? _hhListsSub;

  bool get isDemo => !repo.isCloud;
  bool get signedIn => user != null;
  bool get needsOnboarding => signedIn && (profile == null || !profile!.onboarded);

  // ------------------------------------------------------------ lifecycle
  void start() {
    _sub = auth.authState().listen((u) async {
      user = u;
      if (u == null) {
        profile = null;
        plan = null;
        lists = [];
        pantry = [];
        expenses = [];
        status = LoadStatus.ready;
        notifyListeners();
        await _ensureCatalog();
      } else {
        await loadAll();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hhSub?.cancel();
    _hhListsSub?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------- household
  void _watchHousehold() {
    _hhSub?.cancel();
    _hhListsSub?.cancel();
    household = null;
    final hid = profile?.householdId ?? '';
    if (hid.isEmpty || !repo.supportsHouseholds) return;
    _hhSub = repo.householdStream(hid).listen((h) {
      household = h;
      notifyListeners();
    }, onError: (_) {});
    _hhListsSub = repo.householdListsStream(hid).listen((shared) {
      lists = [...lists.where((l) => !l.shared), ...shared]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> createHousehold(String name) async {
    final p = profile!;
    household = await repo.createHousehold(uid: p.uid, displayName: p.name.isEmpty ? 'Me' : p.name, name: name);
    profile = p.copyWith(householdId: household!.id);
    _watchHousehold();
    notifyListeners();
  }

  Future<void> joinHousehold(String code) async {
    final h = await repo.joinHousehold(code);
    household = h;
    profile = profile!.copyWith(householdId: h.id);
    _watchHousehold();
    notifyListeners();
  }

  Future<void> leaveHousehold() async {
    final p = profile!;
    if (p.householdId.isEmpty) return;
    await repo.leaveHousehold(p.uid, p.householdId);
    profile = p.copyWith(householdId: '');
    lists = lists.where((l) => !l.shared).toList();
    _watchHousehold();
    notifyListeners();
  }

  /// Copies a personal list into the household so everyone can tick it.
  Future<void> shareListWithHousehold(ShoppingList l) async {
    final hid = profile?.householdId ?? '';
    if (hid.isEmpty || l.shared) return;
    final shared = ShoppingList(
      id: l.id,
      userId: l.userId,
      name: l.name,
      supermarketId: l.supermarketId,
      budget: l.budget,
      items: l.items,
      createdAt: l.createdAt,
      planId: l.planId,
      householdId: hid,
      updatedBy: profile?.name ?? '',
    );
    await repo.saveList(shared);
    await repo.deleteList(l.userId, l.id);
    lists = [...lists.where((x) => x.id != l.id), shared];
    notifyListeners();
  }

  // ------------------------------------------------------------ my recipes
  void _mergeMyRecipes() {
    catalog.recipes.removeWhere((k, v) => k.startsWith('my_'));
    for (final r in myRecipes) {
      catalog.recipes[r.id] = r;
    }
  }

  Future<void> saveMyRecipe(Recipe r) async {
    myRecipes = [...myRecipes.where((x) => x.id != r.id), r];
    _mergeMyRecipes();
    notifyListeners();
    await repo.saveMyRecipe(user!.uid, r);
  }

  Future<void> deleteMyRecipe(String id) async {
    myRecipes = myRecipes.where((x) => x.id != id).toList();
    _mergeMyRecipes();
    notifyListeners();
    await repo.deleteMyRecipe(user!.uid, id);
  }

  // ------------------------------------------------------------- pay day
  /// "I got paid today": [amount] for food must last [days] days from today.
  Future<void> gotPaid(Money amount, int days) async {
    final p = profile!;
    final n = DateTime.now();
    await saveProfile(p.copyWith(
      budget: amount,
      budgetFrequency: BudgetFrequency.custom,
      customBudgetDays: days,
      budgetStart: DateTime(n.year, n.month, n.day),
    ));
  }

  Future<void> _ensureCatalog() async {
    if (catalogLoaded) return;
    try {
      catalog = await repo.loadCatalog();
      catalogLoaded = true;
      notifyListeners();
    } catch (e) {
      error = 'Could not load recipes and prices. $e';
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    final u = user;
    if (u == null) return;
    status = LoadStatus.loading;
    error = null;
    notifyListeners();
    try {
      await _ensureCatalog();
      final results = await Future.wait([
        repo.loadProfile(u.uid),
        repo.loadCurrentPlan(u.uid),
        repo.loadLists(u.uid),
        repo.loadPantry(u.uid),
        repo.loadExpenses(u.uid),
      ]);
      profile = (results[0] as UserProfile?) ?? UserProfile(uid: u.uid, name: u.displayName, email: u.email);
      plan = results[1] as MealPlan?;
      lists = results[2] as List<ShoppingList>;
      pantry = results[3] as List<PantryItem>;
      expenses = results[4] as List<Expense>;
      try {
        myRecipes = await repo.loadMyRecipes(u.uid);
        _mergeMyRecipes();
      } catch (_) {}
      _watchHousehold();
      status = LoadStatus.ready;
    } catch (e) {
      status = LoadStatus.error;
      error = 'We couldn\'t load your data. Check your connection and try again.';
      debugPrint('loadAll failed: $e');
    }
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    catalogLoaded = false;
    await _ensureCatalog();
    _mergeMyRecipes();
  }

  // ------------------------------------------------------------- profile
  Future<void> saveProfile(UserProfile p) async {
    profile = p;
    notifyListeners();
    await repo.saveProfile(p);
    // Budget/household/meal changes → recalculate the current plan basket.
    if (plan != null) {
      await _rescalePlanPortions();
    }
  }

  Future<void> _rescalePlanPortions() async {
    final p = profile!;
    final pl = plan!;
    final slots = p.slots.toSet();
    final meals = pl.meals.where((m) => slots.contains(m.slot)).map((m) => m.copyWith(portions: p.portionsPerMeal)).toList();
    plan = pl.copyWith(meals: meals, budget: planBudgetFor(pl.days));
    notifyListeners();
    await repo.savePlan(plan!);
  }

  Future<void> toggleFavourite(String recipeId) async {
    final p = profile;
    if (p == null) return;
    final favs = [...p.favouriteMeals];
    favs.contains(recipeId) ? favs.remove(recipeId) : favs.add(recipeId);
    await saveProfile(p.copyWith(favouriteMeals: favs));
  }

  bool isFavourite(String id) => profile?.favouriteMeals.contains(id) ?? false;

  // ------------------------------------------------------------- budget
  Money planBudgetFor(int days) {
    final p = profile;
    if (p == null) return const Money.zero();
    return CalculationService.budgetForDays(p.budget, p.budgetFrequency, p.customBudgetDays, days);
  }

  /// Start of the current budget period.
  DateTime periodStart([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final p = profile;
    final bs = p?.budgetStart;
    if (bs != null && p!.budgetFrequency == BudgetFrequency.custom && !today.isAfter(bs.add(Duration(days: p.customBudgetDays - 1)))) {
      return bs;
    }
    switch (p?.budgetFrequency ?? BudgetFrequency.weekly) {
      case BudgetFrequency.daily:
        return today;
      case BudgetFrequency.weekly:
        return today.subtract(Duration(days: today.weekday - 1));
      case BudgetFrequency.biweekly:
        return today.subtract(const Duration(days: 13));
      case BudgetFrequency.monthly:
        return DateTime(n.year, n.month, 1);
      case BudgetFrequency.custom:
        return today.subtract(Duration(days: (p?.customBudgetDays ?? 7) - 1));
    }
  }

  Money get spentThisPeriod {
    final start = periodStart();
    return Money.sum(expenses.where((e) => !e.date.isBefore(start)).map((e) => e.amount));
  }

  Money get budgetRemaining => (profile?.budget ?? const Money.zero()) - spentThisPeriod;

  // ---------------------------------------------------------------- pantry
  /// productId → total quantity at home (base units).
  Map<String, double> get pantryMap {
    final m = <String, double>{};
    for (final p in pantry) {
      m[p.productId] = (m[p.productId] ?? 0) + p.quantity;
    }
    return m;
  }

  List<PantryItem> expiringSoon({int days = 3}) {
    final now = DateTime.now();
    return pantry.where((p) {
      final d = p.daysToExpiry(now);
      return d != null && d <= days;
    }).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  }

  /// Sets the quantity at home for a product (used by the onboarding /
  /// "What do I already have?" screen). 0 removes it.
  Future<void> setPantryQuantity(String productId, double quantity) async {
    final u = user;
    if (u == null) return;
    final product = catalog.products[productId];
    final existing = pantry.where((p) => p.productId == productId).toList();
    for (final e in existing.skip(1)) {
      pantry.remove(e);
      await repo.deletePantryItem(u.uid, e.id);
    }
    if (quantity <= 0) {
      if (existing.isNotEmpty) {
        pantry.remove(existing.first);
        await repo.deletePantryItem(u.uid, existing.first.id);
      }
    } else if (existing.isNotEmpty) {
      final upd = existing.first.copyWith(quantity: quantity);
      pantry[pantry.indexOf(existing.first)] = upd;
      await repo.savePantryItem(upd);
    } else {
      final item = PantryItem(
        id: newId(),
        userId: u.uid,
        productId: productId,
        name: product?.name ?? productId,
        quantity: quantity,
        purchaseDate: DateTime.now(),
        expiryDate: (product?.shelfLifeDays ?? 0) > 0 ? DateTime.now().add(Duration(days: product!.shelfLifeDays)) : null,
      );
      pantry.add(item);
      await repo.savePantryItem(item);
    }
    notifyListeners();
  }

  Future<void> savePantryItem(PantryItem item) async {
    final i = pantry.indexWhere((p) => p.id == item.id);
    i >= 0 ? pantry[i] = item : pantry.add(item);
    notifyListeners();
    await repo.savePantryItem(item);
  }

  Future<void> deletePantryItem(PantryItem item) async {
    pantry.removeWhere((p) => p.id == item.id);
    notifyListeners();
    await repo.deletePantryItem(item.userId, item.id);
  }

  /// Subtract what a cooked meal used from the pantry (after the user confirms).
  Future<void> consumeFromPantry(Recipe recipe, double portions) async {
    for (final req in CalculationService.recipeRequirements(recipe, portions, catalog.products)) {
      var left = req.quantity;
      for (final item in pantry.where((p) => p.productId == req.productId).toList()) {
        if (left <= 0) break;
        final use = left < item.quantity ? left : item.quantity;
        left -= use;
        final remain = item.quantity - use;
        if (remain <= 1e-6) {
          await deletePantryItem(item);
        } else {
          await savePantryItem(item.copyWith(quantity: remain));
        }
      }
    }
  }

  // ---------------------------------------------------------------- plan
  MealPlannerService get planner => MealPlannerService(catalog);

  PlanResult generatePlan({int days = 7, DateTime? start, Money? budget, String? supermarketId, int? seed}) {
    final p = profile!;
    final shop = supermarketId ?? (p.preferredSupermarkets.isNotEmpty ? p.preferredSupermarkets.first : '');
    final s = start ?? _today();
    return planner.generate(PlanRequest(
      profile: p,
      startDate: s,
      days: days,
      budget: budget ?? planBudgetFor(days),
      pantry: pantryMap,
      supermarketId: shop,
      seed: seed ?? DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> acceptPlan(PlanResult r, {int days = 7, DateTime? start}) async {
    final p = profile!;
    plan = MealPlan(
      id: newId(),
      userId: p.uid,
      startDate: start ?? _today(),
      days: days,
      meals: r.meals,
      budget: r.budget,
      supermarketId: p.preferredSupermarkets.isNotEmpty ? p.preferredSupermarkets.first : '',
    );
    notifyListeners();
    await repo.savePlan(plan!);
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Basket? get planBasket {
    final pl = plan;
    if (pl == null) return null;
    return planner.basketFor(pl.meals, pantryMap, pl.supermarketId, pl.substitutions);
  }

  Future<void> _savePlan(MealPlan p) async {
    plan = p;
    notifyListeners();
    await repo.savePlan(p);
  }

  Future<void> replaceMeal(PlannedMeal meal, String recipeId) async {
    final pl = plan!;
    final meals = pl.meals.map((m) => identical(m, meal) || (m.dayIndex == meal.dayIndex && m.slot == meal.slot && m.recipeId == meal.recipeId)
        ? m.copyWith(recipeId: recipeId)
        : m).toList();
    await _savePlan(pl.copyWith(meals: meals));
  }

  Future<void> addMeal(int dayIndex, MealSlot slot, String recipeId) async {
    final pl = plan!;
    final meals = [...pl.meals.where((m) => !(m.dayIndex == dayIndex && m.slot == slot))];
    meals.add(PlannedMeal(dayIndex: dayIndex, slot: slot, recipeId: recipeId, portions: profile!.portionsPerMeal));
    meals.sort((a, b) => a.dayIndex != b.dayIndex ? a.dayIndex.compareTo(b.dayIndex) : a.slot.index.compareTo(b.slot.index));
    await _savePlan(pl.copyWith(meals: meals));
  }

  Future<void> removeMeal(PlannedMeal meal) async {
    final pl = plan!;
    await _savePlan(pl.copyWith(meals: pl.meals.where((m) => !(m.dayIndex == meal.dayIndex && m.slot == meal.slot)).toList()));
  }

  /// Rearrange: move a meal to another day (swaps with whatever is there).
  Future<void> moveMeal(PlannedMeal meal, int toDay) async {
    final pl = plan!;
    final meals = pl.meals.map((m) {
      if (m.dayIndex == meal.dayIndex && m.slot == meal.slot) return m.copyWith(dayIndex: toDay);
      if (m.dayIndex == toDay && m.slot == meal.slot) return m.copyWith(dayIndex: meal.dayIndex);
      return m;
    }).toList()
      ..sort((a, b) => a.dayIndex != b.dayIndex ? a.dayIndex.compareTo(b.dayIndex) : a.slot.index.compareTo(b.slot.index));
    await _savePlan(pl.copyWith(meals: meals));
  }

  Future<void> markCooked(PlannedMeal meal, {required bool updatePantry}) async {
    final pl = plan!;
    final meals = pl.meals.map((m) => (m.dayIndex == meal.dayIndex && m.slot == meal.slot) ? m.copyWith(cooked: !m.cooked) : m).toList();
    await _savePlan(pl.copyWith(meals: meals));
    final r = catalog.recipes[meal.recipeId];
    if (updatePantry && !meal.cooked && r != null) await consumeFromPantry(r, meal.portions);
  }

  Future<void> setPlanSupermarket(String id) async => _savePlan(plan!.copyWith(supermarketId: id));

  // ------------------------------------------------------- optimisation
  OptimizationReport? optimise() {
    final pl = plan;
    final p = profile;
    if (pl == null || p == null) return null;
    return OptimizerService(catalog).analyse(
      meals: pl.meals,
      pantry: pantryMap,
      profile: p,
      supermarketId: pl.supermarketId,
      substitutions: pl.substitutions,
    );
  }

  Future<void> applySuggestion(Suggestion s) async {
    final pl = plan;
    if (pl == null) return;
    switch (s.type) {
      case SuggestionType.substitute:
        await _savePlan(pl.copyWith(substitutions: {...pl.substitutions, s.payload['from']!: s.payload['to']!}));
      case SuggestionType.swapMeal:
        await _savePlan(pl.copyWith(
            meals: pl.meals.map((m) => m.recipeId == s.payload['from'] ? m.copyWith(recipeId: s.payload['to']) : m).toList()));
      case SuggestionType.switchStore:
        await setPlanSupermarket(s.payload['supermarketId']!);
      default:
        break;
    }
  }

  // --------------------------------------------------------- shopping lists
  Future<ShoppingList> createListFromPlan() async {
    final pl = plan!;
    final basket = planBasket!;
    final list = ShoppingList(
      id: newId(),
      userId: user!.uid,
      name: 'Groceries ${_shortDate(pl.startDate)} – ${_shortDate(pl.endDate)}',
      supermarketId: pl.supermarketId,
      budget: pl.budget,
      items: CalculationService.basketToItems(basket, newId),
      createdAt: DateTime.now(),
      planId: pl.id,
      householdId: profile?.householdId ?? '',
      updatedBy: profile?.name ?? '',
    );
    lists.insert(0, list);
    notifyListeners();
    await repo.saveList(list);
    return list;
  }

  Future<ShoppingList> createEmptyList(String name) async {
    final list = ShoppingList(
      id: newId(),
      userId: user!.uid,
      name: name,
      supermarketId: profile?.preferredSupermarkets.maybeFirst ?? '',
      budget: planBudgetFor(7),
      items: const [],
      createdAt: DateTime.now(),
      householdId: profile?.householdId ?? '',
      updatedBy: profile?.name ?? '',
    );
    lists.insert(0, list);
    notifyListeners();
    await repo.saveList(list);
    return list;
  }

  ShoppingList? listById(String id) => lists.where((l) => l.id == id).maybeFirst;

  Future<void> saveList(ShoppingList list) async {
    final l = list.shared ? list.copyWith(updatedBy: profile?.name ?? '') : list;
    final i = lists.indexWhere((x) => x.id == l.id);
    i >= 0 ? lists[i] = l : lists.insert(0, l);
    notifyListeners();
    await repo.saveList(l);
  }

  Future<void> deleteList(ShoppingList l) async {
    lists.removeWhere((x) => x.id == l.id);
    notifyListeners();
    if (l.shared) {
      await repo.deleteSharedList(l.householdId, l.id);
    } else {
      await repo.deleteList(l.userId, l.id);
    }
  }

  Future<void> updateItem(ShoppingList l, ShoppingItem item) =>
      saveList(l.copyWith(items: l.items.map((i) => i.id == item.id ? item : i).toList()));

  Future<void> removeItem(ShoppingList l, ShoppingItem item) => saveList(l.copyWith(items: l.items.where((i) => i.id != item.id).toList()));

  Future<void> addItem(ShoppingList l, ShoppingItem item) {
    // merge with an existing line for the same product instead of duplicating
    if (item.productId.isNotEmpty) {
      final existing = l.items.where((i) => i.productId == item.productId && i.unitPrice == item.unitPrice).maybeFirst;
      if (existing != null) {
        return updateItem(l, existing.copyWith(packages: existing.packages + item.packages));
      }
    }
    return saveList(l.copyWith(items: [...l.items, item]));
  }

  /// Builds a priced item for a product from the catalogue (cheapest at the list's shop).
  ShoppingItem itemForProduct(Product p, int packages, String supermarketId) {
    final price = CalculationService.bestPrice(p.id, p.defaultPackageSize, catalog, supermarketId: supermarketId) ??
        CalculationService.bestPrice(p.id, p.defaultPackageSize, catalog);
    final label = price?.packageLabel.isNotEmpty == true ? price!.packageLabel : Units.display(price?.packageSize ?? p.defaultPackageSize, p.unit);
    return ShoppingItem(
      id: newId(),
      productId: p.id,
      name: p.name,
      emoji: p.emoji,
      category: p.category == 'legumes' ? 'cereals' : (p.category == 'spices' ? 'cooking' : p.category),
      quantityLabel: packages == 1 ? label : '$packages × $label',
      requiredBase: packages * (price?.packageSize ?? p.defaultPackageSize),
      packages: packages,
      unitPrice: price?.price ?? const Money.zero(),
      priceStatus: price == null ? 'missing' : priceStatusKey(price.status),
    );
  }

  /// "Finish shopping": records an expense from the purchased items and adds
  /// them to the pantry.
  Future<Expense> completeShopping(ShoppingList l, {Money? actualTotal, bool addToPantry = true}) async {
    final bought = l.items.where((i) => i.purchased).toList();
    final e = Expense(
      id: newId(),
      userId: user!.uid,
      amount: actualTotal ?? l.actualTotal,
      estimated: Money.sum(bought.map((i) => i.total)),
      note: l.name,
      supermarketId: l.supermarketId,
      date: DateTime.now(),
    );
    await saveExpense(e);
    if (addToPantry) {
      for (final i in bought.where((i) => i.productId.isNotEmpty)) {
        final current = pantryMap[i.productId] ?? 0;
        await setPantryQuantity(i.productId, current + i.requiredBase);
      }
    }
    return e;
  }

  // ------------------------------------------------------------- expenses
  Future<void> saveExpense(Expense e) async {
    final i = expenses.indexWhere((x) => x.id == e.id);
    i >= 0 ? expenses[i] = e : expenses.add(e);
    expenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await repo.saveExpense(e);
  }

  Future<void> deleteExpense(Expense e) async {
    expenses.removeWhere((x) => x.id == e.id);
    notifyListeners();
    await repo.deleteExpense(e.userId, e.id);
  }

  // ---------------------------------------------------------------- receipts
  /// Grub's estimate for [baseQty] of a product at a shop (falls back to any shop).
  Money? estimateFor(String productId, double baseQty, String supermarketId) {
    final p = CalculationService.bestPrice(productId, baseQty, catalog, supermarketId: supermarketId) ??
        CalculationService.bestPrice(productId, baseQty, catalog);
    return p == null ? null : CalculationService.lineCost(baseQty, p);
  }

  /// Saves a checked receipt: spending, pantry, and (optionally) shared prices.
  /// Returns a short message for the user.
  Future<String> saveReceipt(ReceiptScan r, {required Money paid, required Money estimate, bool addToPantry = true, bool sharePrices = true}) async {
    final shopName = catalog.supermarkets[r.supermarketId]?.name ?? (r.shopName.isEmpty ? 'Shop' : r.shopName);
    await saveExpense(Expense(
      id: newId(),
      userId: user!.uid,
      amount: paid,
      estimated: estimate.isZero ? null : estimate,
      note: 'Receipt · $shopName',
      supermarketId: r.supermarketId ?? '',
      date: r.date,
    ));
    var pantryAdded = 0;
    if (addToPantry) {
      for (final i in r.items.where((i) => i.include && i.productId != null && (i.packageSize ?? 0) > 0)) {
        final current = pantryMap[i.productId!] ?? 0;
        await setPantryQuantity(i.productId!, current + i.packageSize! * i.quantity);
        pantryAdded++;
      }
    }
    var shared = 0, review = 0;
    if (sharePrices && repo.isCloud && r.supermarketId != null) {
      try {
        (shared, review) = await ReceiptService.sharePrices(r);
        if (shared > 0) await refreshCatalog();
      } catch (_) {}
    }
    final parts = <String>['Saved ${paid.format()} spent at $shopName'];
    if (pantryAdded > 0) parts.add('$pantryAdded items added to pantry');
    if (shared > 0) parts.add('$shared prices shared – thank you!');
    if (review > 0) parts.add('$review sent for checking');
    return parts.join(' · ');
  }

  // ---------------------------------------------------------------- prices
  Future<void> reportPrice({required String productId, required String supermarketId, required double price, required double packageSize, required String packageLabel}) async {
    await repo.submitPriceReport(
      uid: user!.uid,
      productId: productId,
      supermarketId: supermarketId,
      price: price,
      packageSize: packageSize,
      packageLabel: packageLabel,
      location: profile?.county ?? '',
    );
    if (!repo.isCloud) await refreshCatalog();
  }

  // --------------------------------------------------------------- account
  Future<void> signOut() => auth.signOut();

  Future<void> deleteAccount() async {
    final u = user;
    if (u == null) return;
    await repo.deleteAllUserData(u.uid);
    await auth.deleteAccount();
  }

  String _shortDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }
}
