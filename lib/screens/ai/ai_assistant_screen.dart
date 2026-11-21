import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../services/ai_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../recipes/recipe_detail_screen.dart';
import '../../core/i18n.dart';

class _Msg {
  final bool user;
  final String text;
  final List<AiRecipeSuggestion> recipes;
  const _Msg(this.user, this.text, [this.recipes = const []]);
}

/// AI meal assistant. Costs are always computed by the app from price data.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _busy = false;

  static const _prompts = [
    'What can I cook with KSh 300?',
    'I have KSh 2,000 for groceries this week. I am cooking for 3 people.',
    'What can I cook using potatoes and eggs?',
    'How can I reduce my grocery spending?',
    'Suggest affordable meals for seven days',
    'Replace expensive ingredients with cheaper alternatives',
  ];

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    final s = context.read<AppState>();
    setState(() {
      _msgs.add(_Msg(true, t));
      _busy = true;
    });
    _ctrl.clear();
    _toBottom();
    try {
      final ai = AiService(s.catalog, cloudEnabled: AppConfig.firebaseReady);
      final history = [for (final m in _msgs) {'role': m.user ? 'user' : 'assistant', 'content': m.text}];
      var q = t;
      if (t.toLowerCase().contains('seven days') && !t.toLowerCase().contains('ksh')) {
        q = '$t KSh ${s.planBudgetFor(7).shillings.round()} week';
      }
      final reply = await ai.ask(q, s.profile!, s.pantryMap, history);
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(false, reply.text, reply.recipes)));
    } catch (e) {
      if (mounted) setState(() => _msgs.add(const _Msg(false, 'Sorry, I couldn\'t answer that right now. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Text('✨ '), T('Grub AI')])),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  const GrubLogo(height: 70, iconOnly: true),
                  const SizedBox(height: 12),
                  T('Ask me anything about meals and money', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const T('I use your household, allergies, pantry and Grub\'s price list. I never make up prices – every cost is calculated by the app.',
                      textAlign: TextAlign.center, style: TextStyle(color: GrubColors.muted)),
                  const SizedBox(height: 20),
                  for (final p in _prompts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SoftCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () => _send(p),
                        child: Row(children: [
                          Expanded(child: Text(p)),
                          const Icon(Icons.north_east, size: 16, color: GrubColors.green),
                        ]),
                      ),
                    ),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: GrubColors.green))),
                      );
                    }
                    return _bubble(_msgs[i]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(hintText: tr('e.g. I have KSh 1,500 for 4 people…')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: GrubColors.green),
                onPressed: _busy ? null : () => _send(_ctrl.text),
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(_Msg m) {
    final s = context.read<AppState>();
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: m.user ? GrubColors.green : GrubColors.greenLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(m.user ? 18 : 4),
            bottomRight: Radius.circular(m.user ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text, style: TextStyle(color: m.user ? Colors.white : GrubColors.ink, height: 1.4)),
          for (final r in m.recipes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SoftCard(
                padding: const EdgeInsets.all(8),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: r.recipe.id))),
                child: Row(children: [
                  RecipeImage(r.recipe, height: 44, width: 44, radius: 10),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r.recipe.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(r.cost?.format() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, color: GrubColors.greenDark)),
                    Text(s.catalog.hasOnlyDemoPrices ? 'demo estimate' : 'estimate', style: const TextStyle(fontSize: 10, color: GrubColors.muted)),
                  ]),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
