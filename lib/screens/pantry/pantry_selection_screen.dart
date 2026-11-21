import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pantry_picker.dart';
import '../../core/i18n.dart';

/// "What do I already have?" – before generating a shopping list.
class PantrySelectionScreen extends StatelessWidget {
  const PantrySelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final basket = s.planBasket;
    return Scaffold(
      appBar: AppBar(title: const T('What do I already have?')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const T('Tap items in your kitchen. Tap again to enter the exact amount – we subtract it from what you need to buy.',
              style: TextStyle(color: GrubColors.muted)),
          const SizedBox(height: 12),
          const Expanded(child: PantryPicker()),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(basket == null
                ? 'Done · ${s.pantry.length} selected'
                : 'Done · shopping now ${basket.total.format()}'),
          ),
        ),
      ),
    );
  }
}
