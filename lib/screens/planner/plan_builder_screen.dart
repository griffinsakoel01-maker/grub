import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../recipes/recipe_detail_screen.dart';

const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// "Building your week…" animation, then "Your week is ready!" with swaps.
class PlanBuilderScreen extends StatefulWidget {
  final int days;
  final bool onboarding;
  final Future<void> Function()? onAccepted;
  const PlanBuilderScreen({super.key, this.days = 7, this.onboarding = false, this.onAccepted});
  @override
  State<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

class _PlanBuilderScreenState extends State<PlanBuilderScreen> {
  static const _stages = ['Browsing this week\'s prices…', 'Selecting your recipes…', 'Costing your basket…', 'Checking the budget…', 'Finalising your plan…'];
  int _stage = 0;
  PlanResult? _result;
  late DateTime _start;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _start = DateTime(n.year, n.month, n.day);
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < _stages.length; i++) {
      await Future.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      if (i == 1) {
        _result = context.read<AppState>().generatePlan(days: widget.days, start: _start);
      }
      setState(() => _stage = i + 1);
    }
  }

  Future<void> _accept() async {
    final s = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await s.acceptPlan(_result!, days: widget.days, start: _start);
      final list = await s.createListFromPlan();
      if (widget.onAccepted != null) await widget.onAccepted!();
      if (!mounted) return;
      if (widget.onboarding) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Navigator.of(context).pop();
        showSnack(context, 'Plan saved. Your shopping list "${list.name}" is ready.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t save your plan. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _swap(int index) async {
    final s = context.read<AppState>();
    final meal = _result!.meals[index];
    final options = s.planner.swapOptions(meal, s.profile!);
    final picked = await showModalBottomSheet<Recipe>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, ctrl) => ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text('Swap ${mealSlotLabel(meal.slot).toLowerCase()}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Cheapest first. Only meals that fit your diet and allergies.', style: TextStyle(color: GrubColors.muted)),
          const SizedBox(height: 12),
          for (final r in options) _RecipeRow(recipe: r, portions: meal.portions, onTap: () => Navigator.pop(context, r)),
        ]),
      ),
    );
    if (picked == null) return;
    final meals = [..._result!.meals];
    meals[index] = meal.copyWith(recipeId: picked.id);
    final basket = s.planner.basketFor(meals, s.pantryMap, s.profile!.preferredSupermarkets.isNotEmpty ? s.profile!.preferredSupermarkets.first : '');
    setState(() => _result = PlanResult(meals: meals, basket: basket, budget: _result!.budget, withinBudget: basket.total <= _result!.budget, notes: _result!.notes));
  }

  @override
  Widget build(BuildContext context) {
    final done = _stage >= _stages.length && _result != null;
    return Scaffold(
      appBar: AppBar(leading: done ? const BackButton() : const SizedBox()),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: done ? _ready(context) : _building()),
    );
  }

  Widget _building() => Center(
        key: const ValueKey('building'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _OrbitingFood(),
            const SizedBox(height: 28),
            Text(_stage < _stages.length ? _stages[_stage].replaceAll('…', '...') : 'Done!',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 22),
            for (var i = 0; i < _stages.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: i < _stage
                        ? const Icon(Icons.check_circle, color: GrubColors.green, key: ValueKey('d'))
                        : i == _stage
                            ? const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.5, color: GrubColors.green)))
                            : const Icon(Icons.circle_outlined, color: GrubColors.line, key: ValueKey('p')),
                  ),
                  const SizedBox(width: 12),
                  Text(_stages[i], style: TextStyle(color: i <= _stage ? GrubColors.ink : GrubColors.muted)),
                ]),
              ),
          ]),
        ),
      );

  Widget _ready(BuildContext context) {
    final s = context.watch<AppState>();
    final r = _result!;
    final saved = r.remaining;
    return Column(key: const ValueKey('ready'), children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
          Text('Your week is ready!', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SPENT OF ${r.budget.format().toUpperCase()}', style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  FittedBox(child: Text(r.total.format(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: r.budget.cents == 0 ? 0 : (r.total.cents / r.budget.cents).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      color: r.withinBudget ? GrubColors.green : GrubColors.danger,
                      backgroundColor: GrubColors.greenLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: r.withinBudget ? GrubColors.greenLight : const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(10)),
                    child: Text(r.withinBudget ? '✓ saved ${saved.format()}' : 'over by ${(-saved).format()}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.withinBudget ? GrubColors.green : GrubColors.danger)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SoftCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BasketPreviewScreen(basketItems: r.basket.lines.length, result: r))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const EmojiTile('🛒', size: 38),
                  const SizedBox(height: 10),
                  const Text('Grocery list', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('${r.basket.lines.length} items', style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
                ]),
              ),
            ),
          ]),
          for (final n in r.notes)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('• $n', style: const TextStyle(color: GrubColors.warning, fontSize: 12)),
            ),
          if (s.catalog.hasOnlyDemoPrices) const Padding(padding: EdgeInsets.only(top: 12), child: DemoBanner()),
          const SizedBox(height: 12),
          for (var i = 0; i < r.meals.length; i++) _mealRow(context, s, r.meals[i], i),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Row(children: [
          IconButton.outlined(
            tooltip: 'Shuffle',
            onPressed: _saving ? null : () => setState(() => _result = s.generatePlan(days: widget.days, start: _start, seed: math.Random().nextInt(1 << 30))),
            icon: const Icon(Icons.shuffle),
          ),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: _saving ? null : _accept, child: Text(_saving ? 'Saving…' : 'Looks great'))),
        ]),
      ),
    ]);
  }

  Widget _mealRow(BuildContext context, AppState s, PlannedMeal m, int i) {
    final r = s.catalog.recipes[m.recipeId];
    if (r == null) return const SizedBox();
    final day = _dayNames[_start.add(Duration(days: m.dayIndex)).weekday - 1];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.id, servings: m.portions))),
        child: Row(children: [
          RecipeImage(r, height: 54, width: 54, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$day · ${mealSlotLabel(m.slot).toUpperCase()}', style: const TextStyle(fontSize: 10, color: GrubColors.muted, fontWeight: FontWeight.w700)),
              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${r.totalMinutes} min${r.nutrition != null ? ' · ${r.nutrition!.kcal} kcal' : ''}',
                  style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
            ]),
          ),
          TextButton.icon(onPressed: () => _swap(i), icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Swap')),
        ]),
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  final Recipe recipe;
  final double portions;
  final VoidCallback onTap;
  const _RecipeRow({required this.recipe, required this.portions, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cost = recipeCostLabel(context.read<AppState>().catalog, recipe, portions);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        onTap: onTap,
        child: Row(children: [
          RecipeImage(recipe, height: 48, width: 48, radius: 12),
          const SizedBox(width: 12),
          Expanded(child: Text(recipe.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (cost != null) Text(cost, style: const TextStyle(fontWeight: FontWeight.w700, color: GrubColors.greenDark)),
        ]),
      ),
    );
  }
}

/// Simple preview of the plan's basket before saving.
class BasketPreviewScreen extends StatelessWidget {
  final int basketItems;
  final PlanResult result;
  const BasketPreviewScreen({super.key, required this.basketItems, required this.result});
  @override
  Widget build(BuildContext context) {
    final lines = result.basket.lines;
    return Scaffold(
      appBar: AppBar(title: Text('Grocery list · $basketItems items')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final l in lines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: EmojiTile(l.product.emoji),
            title: Text(l.product.name),
            subtitle: Text(l.quantityLabel),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(l.hasPrice ? l.cost.format() : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
              PriceBadge(l.price == null ? 'missing' : priceStatusKeyOf(l.price!.status)),
            ]),
          ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Estimated total', style: TextStyle(fontWeight: FontWeight.w700)),
          trailing: Text(result.total.format(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        const Text('Save the plan to turn this into an editable shopping list.', style: TextStyle(color: GrubColors.muted)),
      ]),
    );
  }
}

String priceStatusKeyOf(PriceStatus s) => priceStatusKey(s);

class _OrbitingFood extends StatefulWidget {
  const _OrbitingFood();
  @override
  State<_OrbitingFood> createState() => _OrbitingFoodState();
}

class _OrbitingFoodState extends State<_OrbitingFood> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  static const _items = ['🥦', '🍅', '🌽', '🥑', '🥕', '🍋', '🫑', '🍌'];
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        height: 200,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            const GrubLogo(height: 96, iconOnly: true),
            for (var i = 0; i < _items.length; i++)
              Transform.translate(
                offset: Offset(
                  math.cos(_c.value * 2 * math.pi + i * 2 * math.pi / _items.length) * 82,
                  math.sin(_c.value * 2 * math.pi + i * 2 * math.pi / _items.length) * 82,
                ),
                child: Text(_items[i], style: const TextStyle(fontSize: 22)),
              ),
          ]),
        ),
      );
}
