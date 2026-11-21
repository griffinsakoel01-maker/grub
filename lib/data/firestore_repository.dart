import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/config.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';
import 'repository.dart';
import 'seed_loader.dart';

/// Firestore storage. Public catalogue data lives in top-level collections
/// (products, recipes, supermarkets, prices). Personal data lives under
/// users/{uid}/… so security rules can lock it to its owner.
/// Firestore's offline cache keeps lists and recipes available without
/// internet and syncs changes when the connection returns.
class FirestoreRepository implements Repository {
  final FirebaseFirestore db;
  FirestoreRepository([FirebaseFirestore? db]) : db = db ?? FirebaseFirestore.instance;

  @override
  bool get isCloud => true;

  DocumentReference<Map<String, dynamic>> _user(String uid) => db.collection('users').doc(uid);

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docs(Query<Map<String, dynamic>> q) async {
    try {
      return (await q.get()).docs;
    } on FirebaseException {
      // offline and nothing in network → fall back to cache
      return (await q.get(const GetOptions(source: Source.cache))).docs;
    }
  }

  @override
  Future<Catalog> loadCatalog() async {
    final results = await Future.wait([
      _docs(db.collection('products')),
      _docs(db.collection('recipes').where('published', isEqualTo: true)),
      _docs(db.collection('supermarkets')),
      _docs(db.collection('prices').where('active', isEqualTo: true)),
    ]);
    if (results[0].isEmpty || results[1].isEmpty) {
      // Database not seeded yet – use the bundled demo catalogue.
      return SeedLoader.load();
    }
    return Catalog(
      products: {for (final d in results[0]) d.id: Product.fromMap(d.data(), d.id)},
      recipes: {for (final d in results[1]) d.id: Recipe.fromMap(d.data(), d.id)},
      supermarkets: {for (final d in results[2]) d.id: Supermarket.fromMap(d.data(), d.id)},
      prices: [for (final d in results[3]) PriceRecord.fromMap(d.data(), d.id)],
    );
  }

  @override
  Future<UserProfile?> loadProfile(String uid) async {
    final snap = await _user(uid).get();
    if (!snap.exists) return null;
    return UserProfile.fromMap(uid, snap.data()!);
  }

  @override
  Future<void> saveProfile(UserProfile profile) =>
      _user(profile.uid).set({...profile.toMap(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  @override
  Future<MealPlan?> loadCurrentPlan(String uid) async {
    final docs = await _docs(_user(uid).collection('mealPlans').orderBy('createdAt', descending: true).limit(1));
    if (docs.isEmpty) return null;
    return MealPlan.fromMap(docs.first.id, docs.first.data());
  }

  @override
  Future<void> savePlan(MealPlan plan) async {
    final ref = _user(plan.userId).collection('mealPlans').doc(plan.id);
    final existing = await ref.get();
    await ref.set({
      ...plan.toMap(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<List<ShoppingList>> loadLists(String uid) async {
    final docs = await _docs(_user(uid).collection('shoppingLists').orderBy('createdAt', descending: true));
    return docs.map((d) => ShoppingList.fromMap(d.id, d.data())).toList();
  }

  @override
  Future<void> saveList(ShoppingList list) => _user(list.userId).collection('shoppingLists').doc(list.id).set(list.toMap());

  @override
  Future<void> deleteList(String uid, String listId) => _user(uid).collection('shoppingLists').doc(listId).delete();

  @override
  Future<List<PantryItem>> loadPantry(String uid) async {
    final docs = await _docs(_user(uid).collection('pantry'));
    return docs.map((d) => PantryItem.fromMap(d.id, d.data())).toList();
  }

  @override
  Future<void> savePantryItem(PantryItem item) => _user(item.userId).collection('pantry').doc(item.id).set(item.toMap());

  @override
  Future<void> deletePantryItem(String uid, String id) => _user(uid).collection('pantry').doc(id).delete();

  @override
  Future<List<Expense>> loadExpenses(String uid) async {
    final docs = await _docs(_user(uid).collection('expenses').orderBy('date', descending: true));
    return docs.map((d) => Expense.fromMap(d.id, d.data())).toList();
  }

  @override
  Future<void> saveExpense(Expense e) => _user(e.userId).collection('expenses').doc(e.id).set(e.toMap());

  @override
  Future<void> deleteExpense(String uid, String id) => _user(uid).collection('expenses').doc(id).delete();

  @override
  Future<void> submitPriceReport({
    required String uid,
    required String productId,
    required String supermarketId,
    required double price,
    required double packageSize,
    required String packageLabel,
    String location = '',
  }) =>
      db.collection('priceReports').add({
        'userId': uid,
        'productId': productId,
        'supermarketId': supermarketId,
        'price': price,
        'packageSize': packageSize,
        'packageLabel': packageLabel,
        'location': location,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteAllUserData(String uid) async {
    // Server-side recursive delete (also removes the auth account).
    await FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion).httpsCallable('deleteMyAccount').call();
  }
}
