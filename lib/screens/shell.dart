import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'home/home_screen.dart';
import 'pantry/pantry_inventory_screen.dart';
import 'planner/weekly_planner_screen.dart';
import 'profile/profile_screen.dart';
import 'shopping/shopping_lists_screen.dart';

/// Bottom navigation: Home · Meal Planner · Shopping List · Pantry · Profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static MainShellState? of(BuildContext context) => context.findAncestorStateOfType<MainShellState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int index = 0;

  void goTo(int i) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: const [
        HomeScreen(),
        WeeklyPlannerScreen(),
        ShoppingListsScreen(),
        PantryInventoryScreen(),
        ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr('Home')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: tr('Meal Planner')),
          NavigationDestination(icon: const Icon(Icons.shopping_cart_outlined), selectedIcon: const Icon(Icons.shopping_cart), label: tr('Shopping')),
          NavigationDestination(icon: const Icon(Icons.kitchen_outlined), selectedIcon: const Icon(Icons.kitchen), label: tr('Pantry')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('Profile')),
        ],
      ),
    );
  }
}
