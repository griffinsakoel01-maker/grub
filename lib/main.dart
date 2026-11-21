import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/firestore_repository.dart';
import 'data/local_repository.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  try {
    final prefs = await SharedPreferences.getInstance();
    AppConfig.introSeen = prefs.getBool('intro_seen') ?? false;
    await prefs.setBool('intro_seen', true);
  } catch (_) {}

  Repository repo;
  AuthService auth;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Offline cache: shopping lists, plans and recipes stay available
    // without internet and sync automatically when it returns.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
    AppConfig.firebaseReady = true;
    repo = FirestoreRepository();
    auth = FirebaseAuthService();
  } catch (e) {
    // Firebase not configured yet → fully working demo mode on this device.
    debugPrint('Firebase unavailable, running in demo mode: $e');
    repo = LocalRepository();
    final local = LocalAuthService();
    await local.restore();
    auth = local;
  }

  final state = AppState(repo: repo, auth: auth)..start();
  runApp(ChangeNotifierProvider.value(value: state, child: const GrubApp()));
}
