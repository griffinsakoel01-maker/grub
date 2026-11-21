import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal signed-in user info used by the app.
class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final bool isDemo;
  const AppUser({required this.uid, required this.email, this.displayName = '', this.isDemo = false});
}

abstract class AuthService {
  Stream<AppUser?> authState();
  AppUser? get current;
  Future<AppUser> register(String name, String email, String password);
  Future<AppUser> signIn(String email, String password);
  Future<AppUser> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
  Future<void> deleteAccount();
  bool get supportsGoogle;
}

/// Turns Firebase error codes into plain Kenyan-English messages.
String friendlyAuthError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'weak-password':
        return 'Please use a password of at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'For your security, please sign in again and then retry.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
  return e.toString().replaceFirst('Exception: ', '');
}

class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AppUser? _map(User? u) => u == null ? null : AppUser(uid: u.uid, email: u.email ?? '', displayName: u.displayName ?? '');

  @override
  Stream<AppUser?> authState() => _auth.authStateChanges().map(_map);

  @override
  AppUser? get current => _map(_auth.currentUser);

  @override
  bool get supportsGoogle => true;

  @override
  Future<AppUser> register(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name.trim());
    return AppUser(uid: cred.user!.uid, email: email.trim(), displayName: name.trim());
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    return _map(cred.user)!;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    if (kIsWeb) {
      final cred = await _auth.signInWithPopup(GoogleAuthProvider());
      return _map(cred.user)!;
    }
    final account = await GoogleSignIn().signIn();
    if (account == null) throw Exception('Google sign-in was cancelled.');
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(accessToken: auth.accessToken, idToken: auth.idToken);
    final cred = await _auth.signInWithCredential(credential);
    return _map(cred.user)!;
  }

  @override
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    // The deleteMyAccount Cloud Function removes data and the auth user.
    await _auth.signOut();
  }
}

/// Demo-mode auth (no Firebase): one local account stored on the device.
class LocalAuthService implements AuthService {
  AppUser? _user;
  final _ctrl = StreamController<AppUser?>.broadcast();

  LocalAuthService();

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString('demo_email');
    if (email != null) {
      _user = AppUser(uid: 'demo-user', email: email, displayName: p.getString('demo_name') ?? '', isDemo: true);
    }
  }

  @override
  Stream<AppUser?> authState() async* {
    yield _user;
    yield* _ctrl.stream;
  }

  @override
  AppUser? get current => _user;

  @override
  bool get supportsGoogle => false;

  Future<AppUser> _set(String name, String email) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('demo_email', email.trim());
    await p.setString('demo_name', name.trim());
    _user = AppUser(uid: 'demo-user', email: email.trim(), displayName: name.trim(), isDemo: true);
    _ctrl.add(_user);
    return _user!;
  }

  @override
  Future<AppUser> register(String name, String email, String password) {
    if (!email.contains('@')) throw Exception('That email address doesn\'t look right.');
    if (password.length < 6) throw Exception('Please use a password of at least 6 characters.');
    return _set(name, email);
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    if (!email.contains('@')) throw Exception('That email address doesn\'t look right.');
    final p = await SharedPreferences.getInstance();
    return _set(p.getString('demo_name') ?? '', email);
  }

  @override
  Future<AppUser> signInWithGoogle() => throw Exception('Google sign-in needs Firebase to be configured.');

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('demo_email');
    _user = null;
    _ctrl.add(null);
  }

  @override
  Future<void> deleteAccount() => signOut();
}
