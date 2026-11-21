import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/catalog.dart';

/// Loads the bundled demo catalogue from assets/seed. The same JSON files are
/// uploaded to Firestore by functions/scripts/seed.js.
class SeedLoader {
  static Future<Catalog> load() async {
    Future<List<Map<String, dynamic>>> read(String f) async {
      final raw = await rootBundle.loadString('assets/seed/$f');
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    final products = await read('products.json');
    final recipes = await read('recipes.json');
    final supermarkets = await read('supermarkets.json');
    final prices = await read('prices.json');
    return Catalog(
      products: {for (final m in products) m['id'] as String: Product.fromMap(m)},
      recipes: {for (final m in recipes) m['id'] as String: Recipe.fromMap(m)},
      supermarkets: {for (final m in supermarkets) m['id'] as String: Supermarket.fromMap(m)},
      prices: prices.map(PriceRecord.fromMap).toList(),
    );
  }
}
