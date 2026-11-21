import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../services/calculation_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/pantry_picker.dart';
import '../../core/i18n.dart';

/// Combined ingredients for the whole plan: required · at home · to buy.
class IngredientCalculatorScreen extends StatelessWidget {
  const IngredientCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final plan = s.plan;
    if (plan == null) {
      return Scaffold(appBar: AppBar(title: const T('Ingredients')), body: const EmptyState(emoji: '⚖️', title: 'No plan yet', message: 'Plan your meals first.'));
    }
    final req = CalculationService.planRequirements(plan.meals, s.catalog);
    final pantry = s.pantryMap;
    final rows = req.values.toList()
      ..sort((a, b) {
        final pa = s.catalog.products[a.productId]!, pb = s.catalog.products[b.productId]!;
        final c = pa.category.compareTo(pb.category);
        return c != 0 ? c : pa.name.compareTo(pb.name);
      });
    final toBuyCount = rows.where((r) => CalculationService.toPurchase(r.quantity, pantry[r.productId] ?? 0) > 1e-6).length;

    return Scaffold(
      appBar: AppBar(title: const T('Ingredients for your plan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SoftCard(
          color: GrubColors.greenLight,
          child: Text(
            '${plan.meals.length} meals · ${rows.length} ingredients combined · $toBuyCount to buy.\n'
            'Duplicates across recipes are merged, and what you have at home is subtracted.',
            style: const TextStyle(height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: const [
          Expanded(flex: 5, child: T('INGREDIENT', style: _h)),
          Expanded(flex: 3, child: T('NEEDED', style: _h, textAlign: TextAlign.right)),
          Expanded(flex: 3, child: T('AT HOME', style: _h, textAlign: TextAlign.right)),
          Expanded(flex: 3, child: T('TO BUY', style: _h, textAlign: TextAlign.right)),
        ]),
        const Divider(),
        for (final r in rows)
          Builder(builder: (context) {
            final p = s.catalog.products[r.productId]!;
            final have = pantry[p.id] ?? 0;
            final buy = CalculationService.toPurchase(r.quantity, have);
            return InkWell(
              onTap: () async {
                final v = await showQuantitySheet(context, p, have);
                if (v != null && context.mounted) await context.read<AppState>().setPantryQuantity(p.id, v);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    flex: 5,
                    child: Row(children: [
                      Text(p.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name.split(' (').first, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('${r.recipeIds.length} recipe${r.recipeIds.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 10, color: GrubColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                  Expanded(flex: 3, child: Text(Units.display(r.quantity, p.unit), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                  Expanded(flex: 3, child: Text(have > 0 ? Units.display(have, p.unit) : '–', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: GrubColors.green))),
                  Expanded(
                    flex: 3,
                    child: Text(buy > 1e-6 ? Units.display(buy, p.unit) : '✓',
                        textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: buy > 1e-6 ? GrubColors.ink : GrubColors.green)),
                  ),
                ]),
              ),
            );
          }),
        const SizedBox(height: 8),
        const T('Tap a row to set how much you have at home.', style: TextStyle(fontSize: 11, color: GrubColors.muted)),
      ]),
    );
  }
}

const _h = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: GrubColors.muted);
