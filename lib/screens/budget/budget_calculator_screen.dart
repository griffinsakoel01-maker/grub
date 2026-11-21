import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/calculation_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../onboarding/budget_step.dart';
import '../planner/plan_builder_screen.dart';

/// Smart grocery budget calculator + household setup. Every change
/// recalculates the breakdown instantly; "Save" also re-scales the plan.
class BudgetCalculatorScreen extends StatefulWidget {
  const BudgetCalculatorScreen({super.key});
  @override
  State<BudgetCalculatorScreen> createState() => _BudgetCalculatorScreenState();
}

class _BudgetCalculatorScreenState extends State<BudgetCalculatorScreen> {
  late UserProfile _p = context.read<AppState>().profile!;

  void _toggleSlot(String slot) {
    final l = [..._p.mealSlots];
    l.contains(slot) ? l.remove(slot) : l.add(slot);
    if (l.isEmpty) return;
    setState(() => _p = _p.copyWith(mealSlots: l));
  }

  @override
  Widget build(BuildContext context) {
    final days = CalculationService.periodDays(_p.budgetFrequency, _p.customBudgetDays);
    final bd = CalculationService.breakdown(periodBudget: _p.budget, days: days, slots: _p.slots, portionsPerMeal: _p.portionsPerMeal);
    return Scaffold(
      appBar: AppBar(title: const Text('Grocery calculator')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: SoftCard(
            child: Column(children: [
              _row('🧑', 'Adults', CountStepper(value: _p.adults, max: 15, onChanged: (v) => setState(() => _p = _p.copyWith(adults: v.toInt())))),
              const Divider(),
              _row('🧒', 'Kids (half portions)', CountStepper(value: _p.kids, max: 15, onChanged: (v) => setState(() => _p = _p.copyWith(kids: v.toInt())))),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final sl in MealSlot.values)
                    FilterChip(
                      label: Text(mealSlotLabel(sl)),
                      selected: _p.mealSlots.contains(sl.name),
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _p.mealSlots.contains(sl.name) ? Colors.white : GrubColors.ink),
                      onSelected: (_) => _toggleSlot(sl.name),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        BudgetStep(profile: _p, onChanged: (p) => setState(() => _p = p), showTitle: false, embedded: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('How your money is shared per day', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final e in bd.perSlotPerDay.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Text(mealSlotLabel(e.key)),
                    const Spacer(),
                    Text(e.value.format(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              const Divider(),
              Row(children: [
                const Text('Per day'),
                const Spacer(),
                Text(bd.perDay.format(), style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
              ]),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: FilledButton(
            onPressed: () async {
              final s = context.read<AppState>();
              await s.saveProfile(_p);
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PlanBuilderScreen(days: days > 14 ? 7 : days)));
            },
            child: const Text('Save & plan my meals'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton(
            onPressed: () async {
              await context.read<AppState>().saveProfile(_p);
              if (context.mounted) {
                showSnack(context, 'Budget saved. Your plan has been recalculated.');
                Navigator.pop(context);
              }
            },
            child: const Text('Just save budget'),
          ),
        ),
      ]),
    );
  }

  Widget _row(String emoji, String title, Widget trailing) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          EmojiTile(emoji, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          trailing,
        ]),
      );
}
