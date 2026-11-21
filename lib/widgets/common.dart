import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../services/calculation_service.dart';
import '../core/i18n.dart';

class GrubLogo extends StatelessWidget {
  final double height;
  final bool iconOnly;
  const GrubLogo({super.key, this.height = 48, this.iconOnly = false});
  @override
  Widget build(BuildContext context) => Image.asset(
        iconOnly ? 'assets/branding/grub_icon.png' : 'assets/branding/grub_logo.png',
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Grub',
      );
}

/// Rounded white card with a soft shadow.
class SoftCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final double radius;
  const SoftCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.borderColor, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? GrubColors.line),
        boxShadow: const [BoxShadow(color: Color(0x0F145A1E), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(child: Text(tr(title), style: Theme.of(context).textTheme.titleLarge)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(tr(action!), style: const TextStyle(color: GrubColors.green, fontWeight: FontWeight.w600))),
        ]),
      );
}

class EmojiTile extends StatelessWidget {
  final String emoji;
  final double size;
  final Color background;
  const EmojiTile(this.emoji, {super.key, this.size = 44, this.background = GrubColors.greenLight});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
      );
}

/// Photo if the admin uploaded one, otherwise a fresh gradient with emoji.
class RecipeImage extends StatelessWidget {
  final Recipe recipe;
  final double? height;
  final double? width;
  final double radius;
  const RecipeImage(this.recipe, {super.key, this.height, this.width, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _palette(recipe.category),
        ),
      ),
      alignment: Alignment.center,
      child: Text(recipe.emoji, style: TextStyle(fontSize: (height ?? 80) * 0.42)),
    );
    if (recipe.imageUrl.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: recipe.imageUrl,
        height: height,
        width: width,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }

  static List<Color> _palette(MealSlot s) => switch (s) {
        MealSlot.breakfast => const [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
        MealSlot.lunch => const [Color(0xFFEFF8EA), Color(0xFFD4EDC8)],
        MealSlot.dinner => const [Color(0xFFE8F5E9), Color(0xFFC5E1A5)],
        MealSlot.snack => const [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
      };
}

class BudgetProgress extends StatelessWidget {
  final Money budget;
  final Money spent;
  final String label;
  const BudgetProgress({super.key, required this.budget, required this.spent, this.label = 'Budget'});

  @override
  Widget build(BuildContext context) {
    final p = CalculationService.progress(budget, spent);
    final over = spent > budget;
    final remaining = budget - spent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: GrubColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(budget.format(), style: const TextStyle(fontWeight: FontWeight.w700, color: GrubColors.greenDark)),
      ]),
      const SizedBox(height: 10),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: p),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 12,
            backgroundColor: GrubColors.greenLight,
            valueColor: AlwaysStoppedAnimation(over ? GrubColors.danger : (p > 0.85 ? GrubColors.orange : GrubColors.green)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _kv(tr('Spent'), spent.format()),
        const Spacer(),
        _kv(over ? tr('Over by') : tr('Remaining'), (over ? -remaining : remaining).format(), color: over ? GrubColors.danger : GrubColors.green, end: true),
      ]),
    ]);
  }

  Widget _kv(String k, String v, {Color color = GrubColors.ink, bool end = false}) => Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        ],
      );
}

class PriceBadge extends StatelessWidget {
  final String status; // verified | user_submitted | estimated | demo | missing | manual
  const PriceBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified' => ('Verified', GrubColors.green),
      'user_submitted' => ('User-submitted', const Color(0xFF2B7BB9)),
      'estimated' => ('Estimate', GrubColors.warning),
      'missing' => ('No price', GrubColors.danger),
      'manual' => ('Your price', GrubColors.muted),
      _ => ('Demo price', GrubColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.emoji, required this.title, required this.message, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            EmojiTile(emoji, size: 84),
            const SizedBox(height: 18),
            Text(tr(title), style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(tr(message), style: const TextStyle(color: GrubColors.muted), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              SizedBox(width: 240, child: FilledButton(onPressed: onAction, child: Text(tr(actionLabel!)))),
            ],
          ]),
        ),
      );
}

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: GrubColors.green),
          if (message != null) ...[const SizedBox(height: 14), Text(tr(message!), style: const TextStyle(color: GrubColors.muted))],
        ]),
      );
}

/// − n + stepper like the video's "Who's eating?" step.
class CountStepper extends StatelessWidget {
  final num value;
  final num min;
  final num max;
  final num step;
  final ValueChanged<num> onChanged;
  const CountStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 20, this.step = 1});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove, value > min ? () => onChanged(value - step) : null, filled: false),
        SizedBox(
          width: 40,
          child: Text(value % 1 == 0 ? value.toInt().toString() : value.toString(),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        _btn(Icons.add, value < max ? () => onChanged(value + step) : null, filled: true),
      ]);

  Widget _btn(IconData i, VoidCallback? onTap, {required bool filled}) => Material(
        color: filled ? (onTap == null ? GrubColors.greenTint : GrubColors.greenDark) : GrubColors.greenLight,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(i, size: 18, color: filled ? Colors.white : GrubColors.greenDark)),
        ),
      );
}

/// Selectable card used in onboarding grids.
class SelectCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  const SelectCard({super.key, required this.emoji, required this.title, this.subtitle, required this.selected, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.0 : 0.98,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? GrubColors.greenLight : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? GrubColors.green : GrubColors.line, width: selected ? 2 : 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(compact ? 10 : 14),
              child: Stack(children: [
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(emoji, style: TextStyle(fontSize: compact ? 26 : 30)),
                    const SizedBox(height: 6),
                    Text(tr(title), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (subtitle != null)
                      Text(tr(subtitle!), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
                  ]),
                ),
                if (selected)
                  const Positioned(top: 0, right: 0, child: Icon(Icons.check_circle, color: GrubColors.green, size: 20)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// List row with a trailing checkbox (video "Which meals?" step).
class CheckRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const CheckRow({super.key, required this.emoji, required this.title, this.subtitle, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          onTap: onTap,
          borderColor: selected ? GrubColors.green : null,
          color: selected ? GrubColors.greenLight : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            EmojiTile(emoji, size: 46, background: Colors.white),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (subtitle != null) Text(tr(subtitle!), style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
              ]),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? GrubColors.green : Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: selected ? GrubColors.green : GrubColors.line, width: 2),
              ),
              child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
          ]),
        ),
      );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr(message)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? GrubColors.danger : GrubColors.greenDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 16, color: GrubColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: T('Prices shown are demo estimates, not live shop prices.',
                style: TextStyle(fontSize: 12, color: GrubColors.warning, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// "KSh 420" – what a recipe costs for [portions] using Grub's price data.
String? recipeCostLabel(Catalog c, Recipe r, double portions) =>
    CalculationService.recipeCost(r, portions, c)?.format();
