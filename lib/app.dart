import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';

class GrubApp extends StatelessWidget {
  const GrubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grub',
      debugShowCheckedModeBanner: false,
      theme: GrubTheme.light(),
      locale: const Locale('en', 'KE'),
      home: const _Gate(),
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
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget child;
    if (!_splashDone || s.status == LoadStatus.idle) {
      child = const SplashScreen();
    } else if (!s.signedIn) {
      child = const WelcomeScreen();
    } else if (s.status == LoadStatus.loading && s.profile == null) {
      child = const Scaffold(body: LoadingView(message: 'Getting your kitchen ready…'));
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
