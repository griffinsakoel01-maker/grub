import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/calculation_service.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';

/// What a period of meals typically costs for this household (from price data).
class NeedEstimate {
  final Money minimum;
  final Money typical;
  final int meals;
  final double servings;
  const NeedEstimate(this.minimum, this.typical, this.meals, this.servings);

  static NeedEstimate compute(Catalog c, UserProfile p, int periodDays) {
    final f = DietFilter.fromProfile(p);
    final planner = MealPlannerService(c);
    final portions = p.portionsPerMeal <= 0 ? 1.0 : p.portionsPerMeal;
    final cookingDays = (periodDays * (p.cookingDays.isEmpty ? 7 : p.cookingDays.length) / 7).round();
    var minC = 0, typC = 0;
    for (final slot in p.slots) {
      final costs = planner
          .eligible(slot, f)
          .map((r) => CalculationService.recipeCost(r, portions, c))
          .whereType<Money>()
          .map((m) => m.cents)
          .toList()
        ..sort();
      if (costs.isEmpty) continue;
      minC += costs.first;
      typC += costs[costs.length ~/ 2];
    }
    final meals = cookingDays * p.slots.length;
    // round to whole shillings – these are estimates
    Money whole(int c) => Money((c / 100).round() * 100);
    return NeedEstimate(whole(minC * cookingDays), whole(typC * cookingDays), meals, meals * portions);
  }
}

class BudgetStep extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<UserProfile> onChanged;
  final bool showTitle;
  final bool embedded; // true → plain Column for use inside another scroll view
  const BudgetStep({super.key, required this.profile, required this.onChanged, this.showTitle = true, this.embedded = false});
  @override
  State<BudgetStep> createState() => _BudgetStepState();
}

class _BudgetStepState extends State<BudgetStep> {
  UserProfile get p => widget.profile;

  void _setFrequency(BudgetFrequency f, {int? customDays}) {
    final oldDays = CalculationService.periodDays(p.budgetFrequency, p.customBudgetDays);
    final newDays = CalculationService.periodDays(f, customDays ?? p.customBudgetDays);
    final converted = Money((p.budget.cents * newDays / oldDays).round());
    final rounded = Money.ksh(((converted.shillings / 50).round() * 50).clamp(50, 10000000));
    widget.onChanged(p.copyWith(budgetFrequency: f, customBudgetDays: customDays, budget: rounded));
  }

  Future<void> _typeAmount() async {
    final ctrl = TextEditingController(text: p.budget.shillings.round().toString());
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const T('Enter your budget'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: 'KSh '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const T('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: const T('Save')),
        ],
      ),
    );
    if (v != null && v > 0) widget.onChanged(p.copyWith(budget: Money.ksh(v)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppState>().catalog;
    final days = CalculationService.periodDays(p.budgetFrequency, p.customBudgetDays);
    final need = NeedEstimate.compute(c, p, days);
    final minS = math.max(100, (need.minimum.shillings * 0.8 / 100).floor() * 100).toDouble();
    var maxS = math.max(minS + 1000, (need.typical.shillings * 2.5 / 500).ceil() * 500).toDouble();
    if (p.budget.shillings > maxS) maxS = p.budget.shillings;
    final value = p.budget.shillings.clamp(minS, maxS).toDouble();
    final diff = p.budget - need.typical;
    final bd = CalculationService.breakdown(periodBudget: p.budget, days: days, slots: p.slots, portionsPerMeal: p.portionsPerMeal);
    final freqWord = switch (p.budgetFrequency) {
      BudgetFrequency.daily => 'day',
      BudgetFrequency.weekly => 'week',
      BudgetFrequency.biweekly => '2 weeks',
      BudgetFrequency.monthly => 'month',
      BudgetFrequency.custom => '$days days',
    };

    final children = <Widget>[
      if (widget.showTitle) ...[
        T('Your grocery budget', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('${p.adults} adult${p.adults == 1 ? '' : 's'} · ${p.kids} kid${p.kids == 1 ? '' : 's'} · '
            '${p.slots.length} meals/day · ${_n(p.portionsPerMeal)} portions/meal',
            style: const TextStyle(color: GrubColors.muted)),
        const SizedBox(height: 14),
      ],
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in BudgetFrequency.values)
          ChoiceChip(
            label: Text(budgetFrequencyLabel(f)),
            selected: p.budgetFrequency == f,
            showCheckmark: false,
            labelStyle: TextStyle(color: p.budgetFrequency == f ? Colors.white : GrubColors.ink, fontWeight: FontWeight.w600),
            onSelected: (_) => _setFrequency(f),
          ),
      ]),
      if (p.budgetFrequency == BudgetFrequency.custom)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const T('Number of days'),
            const Spacer(),
            CountStepper(value: p.customBudgetDays, min: 1, max: 60, onChanged: (v) => _setFrequency(BudgetFrequency.custom, customDays: v.toInt())),
          ]),
        ),
      const SizedBox(height: 22),
      GestureDetector(
        onTap: _typeAmount,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(p.budget.format(), key: ValueKey(p.budget.cents), style: Theme.of(context).textTheme.displaySmall),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 18, color: GrubColors.muted),
          ]),
          Text('per $freqWord · tap amount to type any number', style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: GrubColors.green,
          inactiveTrackColor: GrubColors.greenLight,
          thumbColor: Colors.white,
          overlayColor: GrubColors.green.withValues(alpha: 0.12),
          trackHeight: 6,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 3),
        ),
        child: Slider(
          value: value,
          min: minS,
          max: maxS,
          divisions: math.max(1, ((maxS - minS) / 50).round()),
          onChanged: (v) => widget.onChanged(p.copyWith(budget: Money.ksh((v / 50).round() * 50))),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text(Money.ksh(minS).format(), style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
          const Spacer(),
          Text(Money.ksh(maxS).format(), style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
        ]),
      ),
      const SizedBox(height: 16),
      SoftCard(
        color: diff.isNegative ? const Color(0xFFFFF4E5) : GrubColors.greenLight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(diff.isNegative ? '⚠️' : '⭐', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(diff.isNegative ? 'A tight budget' : 'Room to spare', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                need.typical.isZero
                    ? 'Add some price data to see estimates.'
                    : diff.isNegative
                        ? '${p.budget.format()} is about ${(-diff).format()} under what a typical $freqWord costs (~${need.typical.format()}). '
                            'We\'ll lean on budget meals like githeri and ugali-sukuma.'
                        : '${p.budget.format()} is about ${diff.format()} over what a typical $freqWord needs (~${need.typical.format()}) — room for nicer picks.',
                style: const TextStyle(color: GrubColors.muted, fontSize: 13, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _stat(Money((bd.perDay.cents / 100).round() * 100).format(), 'PER DAY')),
        const SizedBox(width: 10),
        Expanded(child: _stat('${need.meals}', 'MEALS')),
        const SizedBox(width: 10),
        Expanded(child: _stat(_n(need.servings), 'SERVINGS')),
      ]),
      const SizedBox(height: 10),
      Text('Per portion per meal: about ${Money((bd.perPortionPerMeal.cents / 100).round() * 100).format()}. Estimates use Grub\'s price list.',
          style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
    ];
    const pad = EdgeInsets.fromLTRB(20, 18, 20, 8);
    if (widget.embedded) {
      return Padding(padding: pad, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
    }
    return ListView(padding: pad, children: children);
  }

  Widget _stat(String v, String k) => SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          FittedBox(child: Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GrubColors.greenDark))),
          const SizedBox(height: 2),
          Text(k, style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
      );

  String _n(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
}
