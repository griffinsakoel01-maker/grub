import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../planner/plan_builder_screen.dart';

/// "I got paid today": set the food money and how many days it must last, starting today.
Future<void> showPayDaySheet(BuildContext context, AppState s) async {
  final amount = TextEditingController(text: ((s.profile?.budget.cents ?? 500000) ~/ 100).toString());
  var days = 7;
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const T('I got paid today', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) => setS(() {}),
            decoration: InputDecoration(labelText: tr('Amount for food (KSh)'), prefixText: 'KSh '),
          ),
          const SizedBox(height: 16),
          const T('How long must it last?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in const [1, 3, 7, 14, 30])
              ChoiceChip(
                label: Text('$d ${tr('days')}'),
                selected: days == d,
                selectedColor: GrubColors.greenLight,
                onSelected: (_) => setS(() => days = d),
              ),
          ]),
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final v = int.tryParse(amount.text.replaceAll(',', '')) ?? 0;
            return Text('≈ ${Money(v * 100 ~/ days).format()} / day', style: const TextStyle(color: GrubColors.muted));
          }),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'plan'), child: const T('Save & plan these days')),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const T('Save budget')),
        ]),
      ),
    ),
  );
  if (res == null) return;
  final v = int.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
  if (v <= 0) return;
  final money = Money(v * 100);
  await s.gotPaid(money, days);
  if (res == 'plan' && context.mounted) {
    final planDays = math.min(days, 14);
    final planBudget = Money(money.cents * planDays ~/ days);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanBuilderScreen(days: planDays, budget: planBudget)));
  }
}
