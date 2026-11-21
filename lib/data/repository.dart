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
}
