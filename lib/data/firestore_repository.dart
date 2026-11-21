import 'dart:math' as math;

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
  Future<void> saveList(ShoppingList list) => list.shared
      ? db.collection('households').doc(list.householdId).collection('shoppingLists').doc(list.id).set(list.toMap())
      : _user(list.userId).collection('shoppingLists').doc(list.id).set(list.toMap());

  @override
  Future<void> deleteList(String uid, String listId) => _user(uid).collection('shoppingLists').doc(listId).delete();

  @override
  Future<void> deleteSharedList(String householdId, String listId) =>
      db.collection('households').doc(householdId).collection('shoppingLists').doc(listId).delete();

  // ------------------------------------------------------------ households
  @override
  bool get supportsHouseholds => true;

  @override
  Future<Household?> loadHousehold(String householdId) async {
    final s = await db.collection('households').doc(householdId).get();
    return s.exists ? Household.fromMap(s.id, s.data()!) : null;
  }

  @override
  Stream<Household?> householdStream(String householdId) => db
      .collection('households')
      .doc(householdId)
      .snapshots()
      .map((s) => s.exists ? Household.fromMap(s.id, s.data()!) : null);

  @override
  Stream<List<ShoppingList>> householdListsStream(String householdId) => db
      .collection('households')
      .doc(householdId)
      .collection('shoppingLists')
      .snapshots()
      .map((q) => q.docs.map((d) => ShoppingList.fromMap(d.id, d.data())).toList());

  @override
  Future<Household> createHousehold({required String uid, required String displayName, required String name}) async {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = math.Random.secure();
    final code = List.generate(6, (_) => letters[rnd.nextInt(letters.length)]).join();
    final ref = db.collection('households').doc();
    final data = {
      'name': name,
      'ownerId': uid,
      'members': [uid],
      'memberNames': {uid: displayName},
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
    await _user(uid).set({'householdId': ref.id}, SetOptions(merge: true));
    return Household.fromMap(ref.id, data);
  }

  @override
  Future<Household> joinHousehold(String code) async {
    final res = await FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
        .httpsCallable('joinHousehold')
        .call({'code': code.trim().toUpperCase()});
    final m = Map<String, dynamic>.from(res.data as Map);
    return Household.fromMap(m['id'] as String, Map<String, dynamic>.from(m['household'] as Map));
  }

  @override
  Future<void> leaveHousehold(String uid, String householdId) async {
    await db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([uid]),
      'memberNames.$uid': FieldValue.delete(),
    });
    await _user(uid).set({'householdId': ''}, SetOptions(merge: true));
  }

  // ------------------------------------------------------------ my recipes
  @override
  Future<List<Recipe>> loadMyRecipes(String uid) async {
    final docs = await _docs(_user(uid).collection('recipes'));
    return docs.map((d) => Recipe.fromMap(d.data(), d.id)).toList();
  }

  @override
  Future<void> saveMyRecipe(String uid, Recipe r) => _user(uid).collection('recipes').doc(r.id).set(r.toMap());

  @override
  Future<void> deleteMyRecipe(String uid, String id) => _user(uid).collection('recipes').doc(id).delete();

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
