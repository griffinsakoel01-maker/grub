import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const GrubLogo(height: 150),
              const SizedBox(height: 28),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(minHeight: 4, color: GrubColors.green, backgroundColor: GrubColors.greenLight),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
