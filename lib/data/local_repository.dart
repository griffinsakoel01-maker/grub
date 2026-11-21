import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import '../models/user_data.dart';
import 'repository.dart';
import 'seed_loader.dart';

/// On-device storage used in demo mode (no Firebase yet).
class LocalRepository implements Repository {
  @override
  bool get isCloud => false;

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<List<Map<String, dynamic>>> _list(String key) async {
    final raw = (await _p).getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _putList(String key, List<Map<String, dynamic>> v) async => (await _p).setString(key, jsonEncode(v));

  Future<void> _upsert(String key, String idField, String id, Map<String, dynamic> data) async {
    final all = await _list(key);
    final i = all.indexWhere((e) => e[idField] == id);
    if (i >= 0) {
      all[i] = data;
    } else {
      all.add(data);
    }
    await _putList(key, all);
  }

  Future<void> _remove(String key, String idField, String id) async {
    final all = await _list(key)
      ..removeWhere((e) => e[idField] == id);
    await _putList(key, all);
  }

  @override
  Future<Catalog> loadCatalog() async {
    final c = await SeedLoader.load();
    // user-reported prices stay "user_submitted" locally
    final reports = await _list('priceReports');
    for (final r in reports) {
      c.prices.add(PriceRecord.fromMap({...r, 'verificationStatus': 'user_submitted'}));
    }
    return c;
  }

  @override
  Future<UserProfile?> loadProfile(String uid) async {
    final raw = (await _p).getString('profile_$uid');
    if (raw == null) return null;
    return UserProfile.fromMap(uid, Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  @override
  Future<void> saveProfile(UserProfile profile) async => (await _p).setString('profile_${profile.uid}', jsonEncode(profile.toMap()));

  @override
  Future<MealPlan?> loadCurrentPlan(String uid) async {
    final raw = (await _p).getString('plan_$uid');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return MealPlan.fromMap(m['planId'] as String, m);
  }

  @override
  Future<void> savePlan(MealPlan plan) async => (await _p).setString('plan_${plan.userId}', jsonEncode(plan.toMap()));

  @override
  Future<List<ShoppingList>> loadLists(String uid) async =>
      (await _list('lists_$uid')).map((m) => ShoppingList.fromMap(m['listId'] as String, m)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> saveList(ShoppingList list) => _upsert('lists_${list.userId}', 'listId', list.id, list.toMap());

  @override
  Future<void> deleteList(String uid, String listId) => _remove('lists_$uid', 'listId', listId);

  @override
  Future<List<PantryItem>> loadPantry(String uid) async =>
      (await _list('pantry_$uid')).map((m) => PantryItem.fromMap(m['pantryId'] as String, m)).toList();

  @override
  Future<void> savePantryItem(PantryItem item) => _upsert('pantry_${item.userId}', 'pantryId', item.id, item.toMap());

  @override
  Future<void> deletePantryItem(String uid, String id) => _remove('pantry_$uid', 'pantryId', id);

  @override
  Future<List<Expense>> loadExpenses(String uid) async =>
      (await _list('expenses_$uid')).map((m) => Expense.fromMap(m['expenseId'] as String, m)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<void> saveExpense(Expense e) => _upsert('expenses_${e.userId}', 'expenseId', e.id, e.toMap());

  @override
  Future<void> deleteExpense(String uid, String id) => _remove('expenses_$uid', 'expenseId', id);

  @override
  Future<void> submitPriceReport({
    required String uid,
    required String productId,
    required String supermarketId,
    required double price,
    required double packageSize,
    required String packageLabel,
    String location = '',
  }) async {
    final id = 'report_${DateTime.now().microsecondsSinceEpoch}';
    await _upsert('priceReports', 'id', id, {
      'id': id,
      'productId': productId,
      'supermarketId': supermarketId,
      'price': price,
      'packageSize': packageSize,
      'packageLabel': packageLabel,
      'location': location,
      'lastUpdated': DateTime.now().toIso8601String(),
      'source': 'Your report (this device)',
    });
  }

  @override
  Future<void> deleteAllUserData(String uid) async {
    final p = await _p;
    for (final k in ['profile_$uid', 'plan_$uid', 'lists_$uid', 'pantry_$uid', 'expenses_$uid']) {
      await p.remove(k);
    }
  }
}
