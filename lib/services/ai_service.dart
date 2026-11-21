import 'package:cloud_functions/cloud_functions.dart';

import '../core/config.dart';
import '../core/i18n.dart';
import '../core/money.dart';
import '../models/catalog.dart';
import '../models/user_data.dart';
import 'calculation_service.dart';
import 'meal_planner_service.dart';

class AiRecipeSuggestion {
  final Recipe recipe;
  final Money? cost; // calculated by the app from price data – never by the AI
  const AiRecipeSuggestion(this.recipe, this.cost);
}

class AiReply {
  final String text;
  final List<AiRecipeSuggestion> recipes;
  final bool fromCloud;
  const AiReply(this.text, this.recipes, {this.fromCloud = false});
}

/// The AI assistant. The model runs in a Cloud Function (`mealAssistant`)
/// so the API key never ships inside the app. The model may only *pick
/// recipe ids*; every shilling shown is calculated here from Grub's price
/// data. When the function is unavailable (demo mode / offline) a built-in
/// rules-based assistant answers instead.
class AiService {
  final Catalog catalog;
  final bool cloudEnabled;
  AiService(this.catalog, {required this.cloudEnabled});

  Future<AiReply> ask(String message, UserProfile profile, Map<String, double> pantry, List<Map<String, String>> history) async {
    if (cloudEnabled) {
      try {
        final res = await FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
            .httpsCallable('mealAssistant', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
            .call({
          'message': message,
          'history': history.length > 10 ? history.sublist(history.length - 10) : history,
          'pantry': pantry,
          'language': Lang.notifier.value,
        });
        final data = Map<String, dynamic>.from(res.data as Map);
        final ids = List<String>.from(data['recipeIds'] ?? const []);
        return AiReply(data['reply'] as String? ?? '', _cost(ids, profile), fromCloud: true);
      } catch (_) {
        // fall through to the offline assistant
      }
    }
    return offlineAnswer(message, profile, pantry);
  }

  List<AiRecipeSuggestion> _cost(List<String> ids, UserProfile profile) => [
        for (final id in ids)
          if (catalog.recipes[id] != null)
            AiRecipeSuggestion(
              catalog.recipes[id]!,
              CalculationService.recipeCost(catalog.recipes[id]!, profile.portionsPerMeal, catalog),
            )
      ];

  /// Rules-based answers for the common questions.
  AiReply offlineAnswer(String message, UserProfile profile, Map<String, double> pantry) {
    final q = message.toLowerCase();
    final planner = MealPlannerService(catalog);
    final filter = DietFilter.fromProfile(profile);
    final portions = profile.portionsPerMeal <= 0 ? 1.0 : profile.portionsPerMeal;
    final amount = _amount(q);
    final people = _people(q);
    final p = people != null ? people.toDouble() : portions;

    if (amount != null && (q.contains('week') || q.contains('days') || q.contains('7'))) {
      final days = q.contains('week') ? 7 : (_days(q) ?? 7);
      final res = planner.generate(PlanRequest(
        profile: profile.copyWith(adults: people ?? profile.adults, kids: people != null ? 0 : profile.kids),
        startDate: DateTime.now(),
        days: days,
        budget: amount,
        pantry: pantry,
      ));
      final uniq = <String>{for (final m in res.meals) m.recipeId}.take(6).toList();
      final text = StringBuffer('Here\'s a $days-day plan for ${p.toStringAsFixed(p % 1 == 0 ? 0 : 1)} people on ${amount.format()}. ')
        ..write('Estimated shopping: ${res.total.format()} (${res.withinBudget ? '${res.remaining.format()} to spare' : 'over budget'}). ')
        ..write('Open Meal Planner → "Plan my week" to save it and get the full shopping list.');
      for (final n in res.notes) {
        text.write('\n• $n');
      }
      return AiReply(text.toString(), _cost(uniq, profile));
    }

    if (amount != null) {
      final list = planner.affordableRecipes(amount, p, filter, pantry: pantry);
      if (list.isEmpty) {
        return AiReply('With ${amount.format()} for ${p.toStringAsFixed(0)} people, none of our recipes fit fully. '
            'Try ugali and sukuma or porridge, and mark what you already have in your pantry – it lowers the cost.', const []);
      }
      return AiReply('You can cook these with ${amount.format()} for ${p.toStringAsFixed(p % 1 == 0 ? 0 : 1)} people '
          '(costs use Grub\'s price data, after what\'s already in your pantry):',
          [for (final e in list.take(6)) AiRecipeSuggestion(e.$1, e.$2)]);
    }

    final mentioned = catalog.products.values.where((pr) {
      final n = pr.name.toLowerCase().split(' (').first;
      return q.contains(n) || q.contains(pr.id.replaceAll('_', ' '));
    }).toList();
    if (mentioned.isNotEmpty && (q.contains('cook') || q.contains('make') || q.contains('using') || q.contains('with'))) {
      final have = {for (final m in mentioned) m.id: 1e9};
      final ranked = planner.recipesUsingPantry(have, filter);
      return AiReply('Meals that use ${mentioned.map((e) => e.name.split(' (').first.toLowerCase()).join(' and ')}:',
          _cost(ranked.take(6).map((e) => e.$1.id).toList(), profile));
    }

    if (q.contains('reduce') || q.contains('save') || q.contains('cheaper') || q.contains('spend less') || q.contains('replace')) {
      return const AiReply(
          'Ways to cut your grocery bill:\n'
          '• Mark what you already have in "What do I already have?" so you don\'t buy it twice.\n'
          '• Buy vegetables and fruit at the local market – compare baskets in Compare prices.\n'
          '• Swap beef for beans or ndengu a few days a week, and white rice for pishori only on special days.\n'
          '• Cook githeri, ndengu or beans in bigger batches – dry legumes are cheap per serving.\n'
          '• Open your shopping list and tap "Find savings" to see changes for your actual list.',
          []);
    }

    final cheap = planner.affordableRecipes(Money.ksh(100000), p, filter, pantry: pantry).take(5);
    return AiReply('I can help you plan meals within your budget. Try asking:\n'
        '• "What can I cook with KSh 300?"\n• "I have KSh 2,000 this week for 3 people"\n'
        '• "What can I cook using potatoes and eggs?"\n• "How can I reduce my grocery spending?"\n\n'
        'Meanwhile, here are some of the most affordable meals for your household:',
        [for (final e in cheap) AiRecipeSuggestion(e.$1, e.$2)]);
  }

  Money? _amount(String q) {
    final m = RegExp(r'(?:ksh|kes|sh)\.?\s*([\d,]+)|([\d,]{3,})\s*(?:bob|shillings|ksh|kes|/=)').firstMatch(q);
    if (m == null) return null;
    final v = int.tryParse((m.group(1) ?? m.group(2) ?? '').replaceAll(',', ''));
    return v == null ? null : Money.ksh(v);
  }

  int? _people(String q) {
    final m = RegExp(r'(\d+)\s*(?:people|persons|pax|family members)').firstMatch(q);
    if (m != null) return int.tryParse(m.group(1)!);
    const words = {'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6};
    for (final e in words.entries) {
      if (q.contains('${e.key} people')) return e.value;
    }
    return null;
  }

  int? _days(String q) {
    final m = RegExp(r'(\d+)\s*days').firstMatch(q);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}
