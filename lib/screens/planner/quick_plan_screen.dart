import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../onboarding/onboarding_flow.dart' show allergyOptions;
import 'plan_builder_screen.dart';

/// Quick Plan: 3 questions → a costed meal plan and shopping list.
/// Used as the fast start during sign-up and from the Meal Planner.
class QuickPlanScreen extends StatefulWidget {
  final bool onboarding;
  final String name;
  const QuickPlanScreen({super.key, this.onboarding = false, this.name = ''});
  @override
  State<QuickPlanScreen> createState() => _QuickPlanScreenState();
}

class _QuickPlanScreenState extends State<QuickPlanScreen> {
  late int _adults, _kids;
  int _days = 7;
  final _amount = TextEditingController();
  final _allergies = <String>{};
  bool _showAllergies = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile;
    _adults = p?.adults ?? 2;
    _kids = p?.kids ?? 0;
    _allergies.addAll(p?.allergies ?? const []);
    if (!widget.onboarding && p != null) {
      _amount.text = context.read<AppState>().planBudgetFor(7).shillings.round().toString();
    }
  }

  int? get _ksh => int.tryParse(_amount.text.replaceAll(',', ''));
  bool get _ok => (_ksh ?? 0) >= 50 && _adults + _kids > 0;

  Future<void> _go() async {
    final s = context.read<AppState>();
    final base = s.profile ?? UserProfile(uid: s.user!.uid, email: s.user?.email ?? '');
    final budget = Money.ksh(_ksh!);
    var p = base.copyWith(
      adults: _adults,
      kids: _kids,
      allergies: _allergies.toList(),
      name: widget.name.isNotEmpty ? widget.name : (base.name.isEmpty ? (s.user?.displayName ?? '') : base.name),
    );
    if (widget.onboarding) {
      // their stated budget becomes the budget setting
      p = p.copyWith(budget: budget, budgetFrequency: _days == 7 ? BudgetFrequency.weekly : BudgetFrequency.custom, customBudgetDays: _days);
    }
    await s.saveProfile(p);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlanBuilderScreen(
        days: _days,
        budget: budget,
        onboarding: widget.onboarding,
        onAccepted: widget.onboarding
            ? () async {
                final st = context.read<AppState>();
                await st.saveProfile(st.profile!.copyWith(onboarded: true));
              }
            : null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final perDay = (_ksh ?? 0) / _days;
    return Scaffold(
      appBar: AppBar(title: const Text('Quick plan')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('3 questions, then your meals and shopping list.', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: GrubColors.muted)),
        const SizedBox(height: 18),
        _q('1', 'How much do you have for food?'),
        TextField(
          controller: _amount,
          autofocus: widget.onboarding,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(prefixText: 'KSh ', hintText: '2000'),
        ),
        const SizedBox(height: 22),
        _q('2', 'Who is eating?'),
        SoftCard(
          child: Column(children: [
            _row('🧑', 'Adults', _adults, (v) => setState(() => _adults = v)),
            const Divider(),
            _row('🧒', 'Kids (half portions)', _kids, (v) => setState(() => _kids = v)),
          ]),
        ),
        const SizedBox(height: 22),
        _q('3', 'For how many days?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in const [1, 3, 5, 7, 10, 14])
            ChoiceChip(
              label: Text(d == 1 ? '1 day' : '$d days'),
              selected: _days == d,
              showCheckmark: false,
              labelStyle: TextStyle(color: _days == d ? Colors.white : GrubColors.ink, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _days = d),
            ),
        ]),
        if (_ok) ...[
          const SizedBox(height: 14),
          Text('That\'s about ${Money.ksh(perDay.round()).format()} a day for ${_adults + _kids} people.',
              style: const TextStyle(color: GrubColors.muted)),
        ],
        const SizedBox(height: 18),
        InkWell(
          onTap: () => setState(() => _showAllergies = !_showAllergies),
          child: Row(children: [
            Icon(_showAllergies ? Icons.expand_less : Icons.expand_more, color: GrubColors.greenDark),
            const SizedBox(width: 6),
            Text(_allergies.isEmpty ? 'Any food allergies? (optional)' : 'Allergies: ${_allergies.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w600, color: GrubColors.greenDark)),
          ]),
        ),
        if (_showAllergies)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in allergyOptions)
                FilterChip(
                  avatar: Text(a.$2),
                  label: Text(a.$3),
                  selected: _allergies.contains(a.$1),
                  showCheckmark: false,
                  labelStyle: TextStyle(color: _allergies.contains(a.$1) ? Colors.white : GrubColors.ink),
                  onSelected: (v) => setState(() => v ? _allergies.add(a.$1) : _allergies.remove(a.$1)),
                ),
            ]),
          ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _ok ? _go : null, child: const Text('Plan my meals')),
        if (widget.onboarding) ...[
          const SizedBox(height: 10),
          const Text('You can add diet, dislikes and favourite shops later in Profile.',
              textAlign: TextAlign.center, style: TextStyle(color: GrubColors.muted, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _q(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          CircleAvatar(radius: 13, backgroundColor: GrubColors.green, child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _row(String emoji, String title, int value, ValueChanged<int> onChanged) => Row(children: [
        EmojiTile(emoji, size: 38),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        CountStepper(value: value, max: 15, onChanged: (v) => onChanged(v.toInt())),
      ]);
}
