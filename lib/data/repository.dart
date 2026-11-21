import '../models/catalog.dart';
import '../models/user_data.dart';

/// Storage abstraction. [FirestoreRepository] is used in production;
/// [LocalRepository] keeps the app fully usable in demo mode (before
/// Firebase is configured) and in tests.
abstract class Repository {
  bool get isCloud;

  Future<Catalog> loadCatalog();

  Future<UserProfile?> loadProfile(String uid);
  Future<void> saveProfile(UserProfile profile);

  Future<MealPlan?> loadCurrentPlan(String uid);
  Future<void> savePlan(MealPlan plan);

  Future<List<ShoppingList>> loadLists(String uid);
  Future<void> saveList(ShoppingList list);
  Future<void> deleteList(String uid, String listId);

  Future<List<PantryItem>> loadPantry(String uid);
  Future<void> savePantryItem(PantryItem item);
  Future<void> deletePantryItem(String uid, String id);

  Future<List<Expense>> loadExpenses(String uid);
  Future<void> saveExpense(Expense e);
  Future<void> deleteExpense(String uid, String id);

  /// A user reports a price they saw in a shop (goes to admin for approval).
  Future<void> submitPriceReport({
    required String uid,
    required String productId,
    required String supermarketId,
    required double price,
    required double packageSize,
    required String packageLabel,
    String location = '',
  });

  Future<void> deleteAllUserData(String uid);

  // ---- households (shared shopping lists) – cloud only
  bool get supportsHouseholds => isCloud;
  Future<Household?> loadHousehold(String householdId) async => null;
  Stream<Household?> householdStream(String householdId) => const Stream.empty();
  Stream<List<ShoppingList>> householdListsStream(String householdId) => const Stream.empty();
  Future<Household> createHousehold({required String uid, required String displayName, required String name}) =>
      throw UnsupportedError('Households need the online version.');
  Future<Household> joinHousehold(String code) => throw UnsupportedError('Households need the online version.');
  Future<void> leaveHousehold(String uid, String householdId) async {}
  Future<void> deleteSharedList(String householdId, String listId) async {}

  // ---- the family's own recipes
  Future<List<Recipe>> loadMyRecipes(String uid);
  Future<void> saveMyRecipe(String uid, Recipe r);
  Future<void> deleteMyRecipe(String uid, String id);
}
