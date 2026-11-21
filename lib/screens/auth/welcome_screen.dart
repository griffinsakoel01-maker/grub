import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'auth_screens.dart';

/// First screen (video: food collage + "Get started" / "Already with us? Sign in").
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _foods = ['🥬', '🍅', '🌽', '🥑', '🍌', '🫘', '🍗', '🐟', '🥔', '🧅', '🍚', '🥭'];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Stack(alignment: Alignment.center, children: [
              for (var i = 0; i < _foods.length; i++) _FloatingFood(_foods[i], i, size),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const GrubLogo(height: 170),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Text(
                    'Tell us your budget and who you\'re cooking for. We\'ll plan the meals, '
                    'work out the quantities and build your shopping list in shillings.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: GrubColors.muted, height: 1.4),
                  ),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(children: [
              if (!AppConfig.firebaseReady) ...[
                const DemoBanner(),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('Get started'),
              ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Already with us? ', style: TextStyle(color: GrubColors.muted)),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Sign in',
                      style: TextStyle(color: GrubColors.greenDark, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FloatingFood extends StatefulWidget {
  final String emoji;
  final int index;
  final Size size;
  const _FloatingFood(this.emoji, this.index, this.size);
  @override
  State<_FloatingFood> createState() => _FloatingFoodState();
}

class _FloatingFoodState extends State<_FloatingFood> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: 2600 + widget.index * 180))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // positions around the edge of the hero area
    const spots = [
      Offset(-0.38, -0.36), Offset(0.0, -0.44), Offset(0.36, -0.34), Offset(-0.44, -0.08),
      Offset(0.44, -0.06), Offset(-0.40, 0.22), Offset(0.40, 0.24), Offset(-0.18, 0.40),
      Offset(0.20, 0.42), Offset(-0.25, -0.22), Offset(0.26, -0.20), Offset(0.0, 0.46),
    ];
    final o = spots[widget.index % spots.length];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Align(
        alignment: Alignment(o.dx * 2, o.dy * 2 + (_c.value - 0.5) * 0.06),
        child: child,
      ),
      child: Opacity(opacity: 0.85, child: Text(widget.emoji, style: const TextStyle(fontSize: 30))),
    );
  }
}
