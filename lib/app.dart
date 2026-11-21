import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';
import 'widgets/grub_logo_animation.dart';

class GrubApp extends StatelessWidget {
  const GrubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grub',
      debugShowCheckedModeBanner: false,
      theme: GrubTheme.light(),
      locale: const Locale('en', 'KE'),
      home: kIsWeb && Uri.base.fragment == 'logo' ? const _LogoPreview() : const _Gate(),
    );
  }
}

/// Decides which part of the app to show: splash → welcome/auth →
/// onboarding → main app.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  // On the web the same animation already played in web/index.html while the app downloaded.
  bool _splashDone = kIsWeb;
  bool _keptSplash = kIsWeb;

  void _onSplashFinished() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget child;
    if (!_splashDone || s.status == LoadStatus.idle) {
      _keptSplash = true;
      child = SplashScreen(onFinished: _onSplashFinished);
    } else if (!s.signedIn) {
      child = const WelcomeScreen();
    } else if (s.status == LoadStatus.loading && s.profile == null) {
      child = _keptSplash ? const _LogoHold() : const Scaffold(body: LoadingView(message: 'Getting your kitchen ready…'));
    } else if (s.status == LoadStatus.error && s.profile == null) {
      child = Scaffold(
        body: EmptyState(
          emoji: '📶',
          title: 'Can\'t reach Grub',
          message: s.error ?? 'Please check your connection.',
          actionLabel: 'Try again',
          onAction: s.loadAll,
        ),
      );
    } else if (s.needsOnboarding) {
      child = const OnboardingFlow();
    } else {
      child = const MainShell();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child));
  }
}

/// Final logo frame with a small progress bar, shown if data is still loading
/// after the animation has finished.
class _LogoHold extends StatelessWidget {
  const _LogoHold();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: EdgeInsets.symmetric(horizontal: 32), child: GrubLogo(height: 220)),
            SizedBox(height: 24),
            SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 4)),
          ]),
        ),
      );
}

/// https://<site>/#logo – plays the in-app loading animation on a loop (for checking it).
class _LogoPreview extends StatelessWidget {
  const _LogoPreview();
  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: Colors.white, body: GrubLogoAnimation(loop: true));
}
