import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../budget/budget_calculator_screen.dart';
import '../budget/budget_tracking_screen.dart';
import '../budget/expense_history_screen.dart';
import '../onboarding/onboarding_flow.dart';
import '../prices/compare_prices_screen.dart';
import '../recipes/recipes_screen.dart';
import 'household_screen.dart';
import 'settings_screen.dart';
import '../../core/i18n.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile;
    if (p == null) return const LoadingView();
    return Scaffold(
      appBar: AppBar(title: const T('Profile'), actions: [
        IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        SoftCard(
          child: Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: GrubColors.greenLight,
              child: Text(p.name.isEmpty ? '🙂' : p.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                Text(p.email, style: const TextStyle(color: GrubColors.muted)),
                if (p.county.isNotEmpty) Text('📍 ${p.county}', style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editName(context, s, p)),
          ]),
        ),
        const SectionHeader('Household & budget'),
        _tile(context, '👨‍👩‍👧', 'Household', '${p.adults} adults · ${p.kids} kids · ${p.slots.length} meals a day',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetCalculatorScreen()))),
        _tile(context, '🏠', 'My household', s.household == null ? 'Share shopping lists with family' : '${s.household!.name} · ${s.household!.members.length} people',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HouseholdScreen()))),
        _tile(context, '💰', 'Budget', '${p.budget.format()} · ${budgetFrequencyLabel(p.budgetFrequency)}',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetCalculatorScreen()))),
        _tile(context, '📊', 'Budget tracking', 'Spending charts & savings',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetTrackingScreen()))),
        _tile(context, '🧾', 'Expense history', '${s.expenses.length} purchases recorded',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseHistoryScreen()))),
        const SectionHeader('Food preferences'),
        _tile(context, '🥗', 'Dietary preferences', p.diets.isEmpty ? 'No restrictions' : p.diets.map(_label).join(', '),
            () => _multi(context, s, 'Dietary preferences', [for (final d in dietOptions.skip(1)) (d.$1, '${d.$2} ${d.$3}')], p.diets, (v) => p.copyWith(diets: v))),
        _tile(context, '⚠️', 'Allergies', p.allergies.isEmpty ? 'None' : p.allergies.map(_label).join(', '),
            () => _multi(context, s, 'Allergies', [for (final a in allergyOptions) (a.$1, '${a.$2} ${a.$3}')], p.allergies, (v) => p.copyWith(allergies: v))),
        _tile(context, '🚫', 'Dislikes', p.dislikes.isEmpty ? 'None' : '${p.dislikes.length} foods',
            () => _multi(context, s, 'Dislikes',
                [for (final pr in s.catalog.products.values) (pr.id, '${pr.emoji} ${pr.name}')], p.dislikes, (v) => p.copyWith(dislikes: v))),
        _tile(context, '❤️', 'Favourite meals', '${p.favouriteMeals.length} saved',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen(title: 'Favourite meals', favouritesOnly: true)))),
        _tile(context, '🏬', 'Preferred supermarkets',
            p.preferredSupermarkets.isEmpty ? 'Cheapest anywhere' : p.preferredSupermarkets.map((id) => s.catalog.supermarkets[id]?.name ?? id).join(', '),
            () => _multi(context, s, 'Preferred supermarkets', [for (final sm in s.catalog.shops) (sm.id, sm.name)],
                p.preferredSupermarkets, (v) => p.copyWith(preferredSupermarkets: v))),
        _tile(context, '⚖️', 'Compare prices', 'See which shop is cheapest',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComparePricesScreen()))),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: s.signOut, icon: const Icon(Icons.logout), label: const T('Sign out')),
      ]),
    );
  }

  static String _label(String id) {
    for (final d in dietOptions) {
      if (d.$1 == id) return d.$3;
    }
    for (final a in allergyOptions) {
      if (a.$1 == id) return a.$3;
    }
    return id;
  }

  Widget _tile(BuildContext context, String emoji, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: onTap,
          child: Row(children: [
            EmojiTile(emoji, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: GrubColors.muted),
          ]),
        ),
      );

  Future<void> _editName(BuildContext context, AppState s, UserProfile p) async {
    final c = TextEditingController(text: p.name);
    String county = p.county;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const T('Personal information'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c, decoration: InputDecoration(labelText: tr('Name'))),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: county.isEmpty ? null : county,
              decoration: InputDecoration(labelText: tr('County')),
              items: [for (final k in kenyanCounties) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setS(() => county = v ?? ''),
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, true), child: const T('Save'))],
        ),
      ),
    );
    if (ok == true) await s.saveProfile(p.copyWith(name: c.text.trim(), county: county));
  }

  Future<void> _multi(BuildContext context, AppState s, String title, List<(String, String)> options, List<String> current,
      UserProfile Function(List<String>) apply) async {
    final sel = {...current};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            Expanded(
              child: ListView(children: [
                for (final o in options)
                  CheckboxListTile(
                    value: sel.contains(o.$1),
                    activeColor: GrubColors.green,
                    title: Text(o.$2),
                    onChanged: (v) => setS(() => v == true ? sel.add(o.$1) : sel.remove(o.$1)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const T('Save')),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) await s.saveProfile(apply(sel.toList()));
  }
}
