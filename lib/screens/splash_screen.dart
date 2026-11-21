import 'package:flutter/material.dart';

import '../widgets/grub_logo_animation.dart';

/// Loading screen: plays the Grub logo animation once, then calls [onFinished].
class SplashScreen extends StatelessWidget {
  final VoidCallback? onFinished;
  const SplashScreen({super.key, this.onFinished});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GrubLogoAnimation(onFinished: onFinished),
        ),
      ),
    );
  }
}
