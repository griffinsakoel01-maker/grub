import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/optimizer_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Smart budget optimisation – accept or reject each suggestion.
class OptimizerScreen extends StatefulWidget {
  const OptimizerScreen({super.key});
  @override
  State<OptimizerScreen> createState() => _OptimizerScreenState();
}

class _OptimizerScreenState extends State<OptimizerScreen> {
  final _rejected = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final report = s.optimise();
    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Find savings')),
        body: const EmptyState(emoji: '💡', title: 'No plan yet', message: 'Plan your meals first, then we\'ll look for ways to save.'),
      );
    }
    final list = report.suggestions.where((x) => !_rejected.contains(x.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Find savings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SoftCard(
          color: GrubColors.greenLight,
          child: Column(children: [
            Row(children: [
              _figure('Current list', report.original.format()),
              const Icon(Icons.arrow_forward, color: GrubColors.muted),
              _figure('Optimised', report.optimised.format(), color: GrubColors.green),
            ]),
            const SizedBox(height: 10),
            Text(report.savings.isZero ? 'Your plan is already lean 👍' : 'Potential savings: up to ${report.savings.format()}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: GrubColors.greenDark)),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('Suggestions never include your allergens, diet restrictions or dislikes.', style: TextStyle(fontSize: 12, color: GrubColors.muted)),
        const SizedBox(height: 12),
        if (list.isEmpty) const EmptyState(emoji: '✅', title: 'No more suggestions', message: 'You\'ve reviewed everything.'),
        for (final x in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EmojiTile(_icon(x.type)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(x.detail, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
                    ]),
                  ),
                  if (x.saving.cents > 0)
                    Text('-${x.saving.format()}', style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.green)),
                ]),
                if (_actionable(x.type)) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => setState(() => _rejected.add(x.id)),
                        child: const Text('No thanks'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () async {
                          await s.applySuggestion(x);
                          if (context.mounted) showSnack(context, 'Applied. Create a new shopping list from your plan to use it.');
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  bool _actionable(SuggestionType t) => t == SuggestionType.substitute || t == SuggestionType.swapMeal || t == SuggestionType.switchStore;

  String _icon(SuggestionType t) => switch (t) {
        SuggestionType.substitute => '🔁',
        SuggestionType.switchStore => '🏬',
        SuggestionType.swapMeal => '🍲',
        SuggestionType.mergeDuplicates => '🧾',
        SuggestionType.seasonal => '🌱',
        SuggestionType.useLeftovers => '♻️',
      };

  Widget _figure(String k, String v, {Color color = GrubColors.ink}) => Expanded(
        child: Column(children: [
          Text(k, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          FittedBox(child: Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color))),
        ]),
      );
}
