// Grub admin dashboard (Flutter web).
//   flutter run -d chrome -t lib/admin/main_admin.dart
//   flutter build web -t lib/admin/main_admin.dart && firebase deploy --only hosting:admin
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../firebase_options.dart';
import 'admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    error = 'Firebase is not configured. Run `flutterfire configure` (include the web platform). $e';
  }
  runApp(MaterialApp(
    title: 'Grub Admin',
    debugShowCheckedModeBanner: false,
    theme: GrubTheme.light(),
    home: error == null ? const AdminGate() : Scaffold(body: Center(child: Text(error))),
  ));
}
