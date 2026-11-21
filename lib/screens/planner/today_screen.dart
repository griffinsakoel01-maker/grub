import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/catalog.dart';
import '../../services/calculation_service.dart';
import '../../services/meal_planner_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../recipes/recipe_detail_screen.dart';

/// "Just today" mode for people who buy food day by day (kadogo):
/// "I have KSh 300 for supper for 4" → meals that fit, with what to buy in
/// small amounts (pieces, bunches, a little flour) and what it costs.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayLine {
  final Product product;
  final double qty; // what to buy, base unit (whole pieces / bunches)
  final Money cost;
  final PriceStatus? status;
  _TodayLine(this.product, this.qty, this.cost, this.status);
}

class _TodayOption {
  final Recipe recipe;
  final List<_TodayLine> lines;
  final Money total;
  _TodayOption(this.recipe, this.lines, this.total);
}

class _TodayScreenState extends State<TodayScreen> {
  final _amount = TextEditingController(text: '300');
  late int _people;
  MealSlot _meal = DateTime.now().hour < 10 ? MealSlot.breakfast : (DateTime.now().hour < 15 ? MealSlot.lunch : MealSlot.dinner);
  bool _usePantry = true;
  int? _open;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile;
    _people = p == null ? 3 : (p.adults + p.kids).clamp(1, 20).toInt();
  }

  List<_TodayOption> _options(AppState s, Money budget) {
    final p = s.profile;
    final filter = p == null ? const DietFilter() : DietFilter.fromProfile(p);
    final portions = p == null || (p.adults + p.kids) == 0
        ? _people.toDouble()
        : _people * (p.portionsPerMeal / (p.adults + p.kids)); // keep kids as half portions
    final pantry = _usePantry ? s.pantryMap : const <String, double>{};
    final slots = _meal == MealSlot.breakfast ? [MealSlot.breakfast] : [MealSlot.lunch, MealSlot.dinner];
    final out = <_TodayOption>[];
    for (final r in s.catalog.recipes.values) {
      if (!slots.contains(r.category) || !filter.recipeAllowed(r, s.catalog.products)) continue;
      final reqs = CalculationService.aggregate(CalculationService.recipeRequirements(r, portions, s.catalog.products));
      final toBuy = CalculationService.subtractPantry(reqs, pantry);
      final lines = <_TodayLine>[];
      var ok = true;
      var total = const Money.zero();
      toBuy.forEach((pid, qty) {
        final prod = s.catalog.products[pid]!;
        final whole = prod.unit == BaseUnit.pcs || prod.unit == BaseUnit.bunch;
        final buy = whole ? (qty - 1e-6).ceilToDouble() : qty;
        final price = CalculationService.bestPrice(pid, buy, s.catalog);
        if (price == null) {
          ok = false;
          return;
        }
        // buying just what you need (loose / small amounts), rounded up to a shilling
        final c = Money(((CalculationService.consumedCost(buy, price).cents + 99) ~/ 100) * 100);
        total += c;
        lines.add(_TodayLine(prod, buy, c, price.status));
      });
      if (!ok || total > budget) continue;
      lines.sort((a, b) => b.cost.compareTo(a.cost));
      out.add(_TodayOption(r, lines, total));
    }
    out.sort((a, b) => a.total.compareTo(b.total));
    return out;
  }

  String _shareText(_TodayOption o, Money budget) {
    final b = StringBuffer('🍲 ${o.recipe.name} for $_people\n');
    for (final l in o.lines) {
      b.writeln('• ${l.product.name.split(' (').first} – ${Units.display(l.qty, l.product.unit)} (≈${l.cost.format()})');
    }
    b.writeln('\nAbout ${o.total.format()} · ${(budget - o.total).format()} left of ${budget.format()}');
    b.writeln('Planned with Grub – Plan meals. Shop smarter.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final budget = Money.ksh(int.tryParse(_amount.text) ?? 0);
    final options = budget.cents > 0 ? _options(s, budget) : <_TodayOption>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Just today')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('How much do you have?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _open = null),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: 'KSh '),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final a in const [100, 200, 300, 500, 1000])
                ActionChip(label: Text('$a'), onPressed: () => setState(() => _amount.text = '$a')),
            ]),
            const Divider(height: 24),
            Row(children: [
              const Expanded(child: Text('People eating', style: TextStyle(fontWeight: FontWeight.w600))),
              CountStepper(value: _people, min: 1, max: 20, onChanged: (v) => setState(() => _people = v.toInt())),
            ]),
            const SizedBox(height: 10),
            SegmentedButton<MealSlot>(
              segments: const [
                ButtonSegment(value: MealSlot.breakfast, label: Text('Breakfast')),
                ButtonSegment(value: MealSlot.lunch, label: Text('Lunch')),
                ButtonSegment(value: MealSlot.dinner, label: Text('Supper')),
              ],
              selected: {_meal},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _meal = v.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: GrubColors.green,
              value: _usePantry,
              onChanged: (v) => setState(() => _usePantry = v),
              title: const Text('Use what I already have'),
              subtitle: Text(s.pantry.isEmpty ? 'Your pantry is empty' : '${s.pantry.length} items in your pantry'),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (budget.cents > 0 && options.isEmpty)
          SoftCard(
            color: const Color(0xFFFFF4E5),
            child: Text(
              'Nothing fits ${budget.format()} for $_people yet. Try fewer people, a little more money, '
              'or add what you already have (unga, oil, salt) to your pantry – it lowers the cost.',
              style: const TextStyle(height: 1.4),
            ),
          ),
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text('${options.length} meals fit ${budget.format()} · costs are for buying just what you need',
                style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
          ),
        for (var i = 0; i < options.length; i++) _card(context, options[i], i, budget),
        const SizedBox(height: 8),
        const Text('Prices: shop receipts and KNBS averages where we have them, otherwise estimates. Market prices may be lower.',
            style: TextStyle(color: GrubColors.muted, fontSize: 11)),
      ]),
    );
  }

  Widget _card(BuildContext context, _TodayOption o, int i, Money budget) {
    final open = _open == i;
    final left = budget - o.total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        onTap: () => setState(() => _open = open ? null : i),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            RecipeImage(o.recipe, height: 52, width: 52, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.recipe.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${o.lines.length} things to buy · ${o.recipe.totalMinutes} min', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(o.total.format(), style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
              Text('${left.format()} left', style: const TextStyle(fontSize: 11, color: GrubColors.green)),
            ]),
          ]),
          if (open) ...[
            const Divider(height: 20),
            if (o.lines.isEmpty) const Text('You have everything already 🎉'),
            for (final l in o.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Text(l.product.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.product.name.split(' (').first)),
                  Text(Units.display(l.qty, l.product.unit).replaceAll(' pcs', ''), style: const TextStyle(color: GrubColors.muted)),
                  const SizedBox(width: 12),
                  SizedBox(width: 64, child: Text(l.cost.format(), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText(o, budget))}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RecipeDetailScreen(recipeId: o.recipe.id, servings: _people.toDouble()))),
                  child: const Text('How to cook'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
