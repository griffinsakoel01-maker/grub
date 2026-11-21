import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/pantry_picker.dart';
import '../planner/plan_builder_screen.dart';
import '../planner/quick_plan_screen.dart';
import 'budget_step.dart';

/// Shared option lists (also used by Profile → edit).
const dietOptions = <(String, String, String, String)>[
  ('none', '🍽️', 'No restrictions', 'anything goes'),
  ('vegetarian', '🥕', 'Vegetarian', 'no meat or fish'),
  ('vegan', '🌱', 'Vegan', 'plants only'),
  ('pescatarian', '🐟', 'Pescatarian', 'fish, no meat'),
  ('high_protein', '💪', 'High protein', 'protein-forward'),
  ('low_carb', '🥗', 'Low carb', 'lighter on ugali & rice'),
];

const allergyOptions = <(String, String, String)>[
  ('eggs', '🥚', 'Eggs'),
  ('dairy', '🥛', 'Dairy / milk'),
  ('peanuts', '🥜', 'Groundnuts'),
  ('gluten', '🌾', 'Gluten (wheat)'),
  ('fish', '🐟', 'Fish'),
  ('coconut', '🥥', 'Coconut'),
  ('soy', '🫘', 'Soy'),
  ('sesame', '🌰', 'Sesame'),
];

const vibeOptions = <(String, String, String, String)>[
  ('quick', '⚡', 'Quick & easy', 'ready in ~30 minutes'),
  ('batch', '🍲', 'Batch cook', 'cook once, eat twice'),
  ('comfort', '🏡', 'Home classics', 'the hearty favourites'),
  ('budget', '💰', 'Maximum savings', 'stretch every shilling'),
];

const kenyanCounties = [
  'Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Kiambu', 'Machakos', 'Kajiado', 'Uasin Gishu', 'Kakamega', 'Nyeri',
  'Meru', 'Kilifi', 'Kisii', 'Bungoma', 'Murang\'a', 'Embu', 'Kericho', 'Laikipia', 'Narok', 'Other',
];

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _page = PageController();
  int _step = 0;
  late UserProfile _p;
  final _name = TextEditingController();
  String _dislikeQuery = '';

  static const _steps = 11;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _p = s.profile ?? UserProfile(uid: s.user!.uid);
    if (_p.name.isEmpty && (s.user?.displayName.isNotEmpty ?? false)) _p = _p.copyWith(name: s.user!.displayName);
    if (_p.email.isEmpty) _p = _p.copyWith(email: s.user?.email ?? '');
    _name.text = _p.name;
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _step = i);
    _page.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  bool get _canContinue => switch (_step) {
        0 => _name.text.trim().isNotEmpty,
        2 => _p.adults + _p.kids > 0,
        3 => _p.mealSlots.isNotEmpty,
        4 => _p.cookingDays.isNotEmpty,
        _ => true,
      };

  bool get _optional => const {1, 5, 6, 7, 8, 9}.contains(_step);

  Future<void> _finish() async {
    final s = context.read<AppState>();
    await s.saveProfile(_p.copyWith(name: _name.text.trim()));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlanBuilderScreen(
        days: 7,
        onboarding: true,
        onAccepted: () async {
          final st = context.read<AppState>();
          await st.saveProfile(st.profile!.copyWith(onboarded: true));
        },
      ),
    ));
  }

  void _toggle<T>(List<T> list, T v, void Function(List<T>) set) {
    final l = [...list];
    l.contains(v) ? l.remove(v) : l.add(v);
    set(l);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pages = <Widget>[
      _stepName(),
      _stepShops(s.catalog),
      _stepHousehold(),
      _stepMeals(),
      _stepDays(),
      _stepDiet(),
      _stepVibe(),
      _stepAllergies(),
      _stepDislikes(s.catalog),
      _stepPantry(),
      BudgetStep(profile: _p, onChanged: (p) => setState(() => _p = p)),
    ];
    final last = _step == _steps - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _go(_step - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 28),
                  onPressed: _step == 0 ? () => s.signOut() : () => _go(_step - 1),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (_step + 1) / _steps),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 5, color: GrubColors.green, backgroundColor: GrubColors.greenLight),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const GrubLogo(height: 26, iconOnly: true),
                if (_optional) TextButton(onPressed: () => _go(_step + 1), child: const Text('Skip')),
              ]),
            ),
            Expanded(child: PageView(controller: _page, physics: const NeverScrollableScrollPhysics(), children: pages)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _canContinue ? (last ? _finish : () => _go(_step + 1)) : null,
                child: Text(last ? 'Build my week' : _nextLabel()),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _nextLabel() {
    if (_step == 1) return _p.preferredSupermarkets.isEmpty ? 'Next' : 'Confirm shops';
    if (_step == 9) {
      final n = context.read<AppState>().pantry.length;
      return n == 0 ? 'Next' : 'Continue · $n selected';
    }
    if (_step == 7) return 'Confirm & continue';
    return 'Next';
  }

  // ---------------------------------------------------------------- steps
  Widget _frame(String title, String subtitle, Widget body, {bool scroll = true}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: GrubColors.muted)),
          const SizedBox(height: 20),
          Expanded(child: scroll ? SingleChildScrollView(child: body) : body),
        ]),
      );

  Widget _stepName() => _frame(
        'Karibu! What should we call you?',
        'Grub plans meals around your family and your budget.',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Your first name', prefixIcon: Icon(Icons.waving_hand_outlined)),
          ),
          const SizedBox(height: 22),
          SoftCard(
            color: GrubColors.greenLight,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuickPlanScreen(onboarding: true, name: _name.text.trim()))),
            child: const Row(children: [
              Text('⚡', style: TextStyle(fontSize: 26)),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('In a hurry? Quick start', style: TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
                  Text('Just 3 questions: money, people, days.', style: TextStyle(color: GrubColors.muted, fontSize: 12)),
                ]),
              ),
              Icon(Icons.arrow_forward, color: GrubColors.greenDark),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Or tap Next for the full setup (diet, allergies, shops, pantry).', style: TextStyle(color: GrubColors.muted, fontSize: 12)),
        ]),
      );

  Widget _stepShops(Catalog c) => _frame(
        'Where do you shop?',
        'We\'ll compare prices at the places you pick. Choose as many as you like.',
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final sm in c.shops)
              SelectCard(
                emoji: sm.id == 'mama_mboga' ? '🧺' : '🏬',
                title: sm.name,
                selected: _p.preferredSupermarkets.contains(sm.id),
                onTap: () => setState(() => _toggle(_p.preferredSupermarkets, sm.id, (l) => _p = _p.copyWith(preferredSupermarkets: l))),
                compact: true,
              ),
          ],
        ),
      );

  Widget _stepHousehold() => _frame(
        'Who\'s eating?',
        'Every meal scales to your household automatically.',
        Column(children: [
          _personRow('🧑', 'Adults', 'full portions', _p.adults, (v) => setState(() => _p = _p.copyWith(adults: v))),
          const SizedBox(height: 10),
          _personRow('🧒', 'Kids', 'half portions', _p.kids, (v) => setState(() => _p = _p.copyWith(kids: v))),
          const SizedBox(height: 10),
          SoftCard(
            color: GrubColors.greenLight,
            child: Row(children: [
              const Text('Portions per meal', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(_fmtPortions(_p.portionsPerMeal),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: GrubColors.green)),
            ]),
          ),
        ]),
      );

  String _fmtPortions(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _personRow(String emoji, String title, String sub, int value, ValueChanged<int> onChanged) => SoftCard(
        child: Row(children: [
          EmojiTile(emoji),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(sub, style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
            ]),
          ),
          CountStepper(value: value, onChanged: (v) => onChanged(v.toInt()), max: 15),
        ]),
      );

  Widget _stepMeals() => _frame(
        'Which meals?',
        'Pick what we should plan for each day.',
        Column(children: [
          for (final e in const [
            ('breakfast', '🍳', 'Breakfast', 'chai, mandazi, uji'),
            ('lunch', '🍛', 'Lunch', 'leftovers-friendly'),
            ('dinner', '🍲', 'Dinner', 'the main event'),
            ('snack', '🍌', 'Snacks', 'optional extras'),
          ])
            CheckRow(
              emoji: e.$2,
              title: e.$3,
              subtitle: e.$4,
              selected: _p.mealSlots.contains(e.$1),
              onTap: () => setState(() => _toggle(_p.mealSlots, e.$1, (l) => _p = _p.copyWith(mealSlots: l))),
            ),
        ]),
      );

  Widget _stepDays() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final n = _p.cookingDays.length;
    return _frame(
      'Which days are you cooking?',
      'We\'ll only plan meals for the days you pick.',
      Column(children: [
        const SizedBox(height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 1; i <= 7; i++)
            GestureDetector(
              onTap: () => setState(() => _toggle(_p.cookingDays, i, (l) => _p = _p.copyWith(cookingDays: l..sort()))),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 64,
                decoration: BoxDecoration(
                  color: _p.cookingDays.contains(i) ? GrubColors.green : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _p.cookingDays.contains(i) ? GrubColors.green : GrubColors.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(labels[i - 1],
                      style: TextStyle(fontWeight: FontWeight.w700, color: _p.cookingDays.contains(i) ? Colors.white : GrubColors.ink)),
                  const SizedBox(height: 6),
                  Icon(_p.cookingDays.contains(i) ? Icons.check_circle : Icons.circle_outlined,
                      size: 16, color: _p.cookingDays.contains(i) ? Colors.white : GrubColors.line),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 18),
        Text(n == 0 ? 'Pick at least one day.' : 'Planning $n day${n == 1 ? '' : 's'} this week',
            style: const TextStyle(color: GrubColors.muted)),
      ]),
    );
  }

  Widget _stepDiet() => _frame(
        'How do you eat?',
        'Pick any that apply.',
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final d in dietOptions)
              SelectCard(
                emoji: d.$2,
                title: d.$3,
                subtitle: d.$4,
                selected: d.$1 == 'none' ? _p.diets.isEmpty : _p.diets.contains(d.$1),
                onTap: () => setState(() {
                  if (d.$1 == 'none') {
                    _p = _p.copyWith(diets: []);
                  } else {
                    _toggle(_p.diets, d.$1, (l) => _p = _p.copyWith(diets: l));
                  }
                }),
              ),
          ],
        ),
      );

  Widget _stepVibe() => _frame(
        'What\'s your cooking vibe?',
        'This shapes which meals we pick first.',
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final v in vibeOptions)
              SelectCard(
                emoji: v.$2,
                title: v.$3,
                subtitle: v.$4,
                selected: _p.cookingStyle == v.$1,
                onTap: () => setState(() => _p = _p.copyWith(cookingStyle: v.$1)),
              ),
          ],
        ),
      );

  Widget _stepAllergies() => _frame(
        'Any allergies?',
        'We\'ll never include these – even when looking for savings.',
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            SelectCard(emoji: '✅', title: 'No allergies', subtitle: 'nothing to exclude', selected: _p.allergies.isEmpty,
                onTap: () => setState(() => _p = _p.copyWith(allergies: []))),
            for (final a in allergyOptions)
              SelectCard(
                emoji: a.$2,
                title: a.$3,
                subtitle: 'tap to exclude',
                selected: _p.allergies.contains(a.$1),
                onTap: () => setState(() => _toggle(_p.allergies, a.$1, (l) => _p = _p.copyWith(allergies: l))),
              ),
          ],
        ),
      );

  Widget _stepDislikes(Catalog c) {
    final products = c.products.values
        .where((p) => p.category != 'cooking' && p.category != 'spices')
        .where((p) => _dislikeQuery.isEmpty || p.name.toLowerCase().contains(_dislikeQuery.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _frame(
      'Any dislikes?',
      'We\'ll keep these out of every plan.',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          decoration: const InputDecoration(hintText: 'Search any food…', prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _dislikeQuery = v),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in products)
            FilterChip(
              avatar: Text(p.emoji),
              label: Text(p.name.split(' (').first),
              selected: _p.dislikes.contains(p.id),
              showCheckmark: false,
              labelStyle: TextStyle(color: _p.dislikes.contains(p.id) ? Colors.white : GrubColors.ink, fontWeight: FontWeight.w500),
              onSelected: (_) => setState(() => _toggle(_p.dislikes, p.id, (l) => _p = _p.copyWith(dislikes: l))),
            ),
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _p.county.isEmpty ? null : _p.county,
          decoration: const InputDecoration(labelText: 'Your county (optional)', prefixIcon: Icon(Icons.place_outlined)),
          items: [for (final c in kenyanCounties) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _p = _p.copyWith(county: v ?? '')),
        ),
      ]),
    );
  }

  Widget _stepPantry() => _frame(
        'What do you already have?',
        'Tap what\'s in your kitchen. Tap again to set the exact amount. We\'ll subtract it from your shopping list.',
        const PantryPicker(),
        scroll: false,
      );
}

/// Formats a money value for big displays ("KSh 5,000").
String bigMoney(Money m) => m.format();
