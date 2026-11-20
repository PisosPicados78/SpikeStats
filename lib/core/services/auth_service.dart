import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';

class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;

  AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.isAnonymous = false,
  });

  factory AppUser.fromFirebase(User user) {
    return AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      isAnonymous: user.isAnonymous,
    );
  }
}

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  FirebaseAuth? _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  AppUser? _currentUser;

  FirebaseAuth get auth {
    _auth ??= FirebaseAuth.instance;
    return _auth!;
  }

  bool get isFirebaseReady => FirebaseService.isInitialized;

  AppUser? get currentUser {
    if (isFirebaseReady) {
      try {
        final fbUser = auth.currentUser;
        if (fbUser != null) return AppUser.fromFirebase(fbUser);
      } catch (e) {
        debugPrint('Error en auth.currentUser: $e');
      }
    }
    return _currentUser;
  }

  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isOffline = prefs.getBool('is_offline') ?? false;
    if (isOffline) {
      final localUid = prefs.getString('auth_user_uid') ?? 'offline_local_user';
      final localEmail = prefs.getString('auth_user_email') ?? 'offline@local.volleyball';
      final localName = prefs.getString('auth_user_name') ?? 'Modo Local (Offline)';
      _currentUser = AppUser(
        uid: localUid,
        email: localEmail,
        displayName: localName,
      );
      return;
    }

    final localUid = prefs.getString('auth_user_uid');
    final localEmail = prefs.getString('auth_user_email');
    final localName = prefs.getString('auth_user_name');

    if (localUid != null && localEmail != null) {
      _currentUser = AppUser(
        uid: localUid,
        email: localEmail,
        displayName: localName ?? localEmail.split('@').first,
      );
    }
  }

  Future<AppUser> signInOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_offline', true);
    final user = AppUser(
      uid: 'offline_local_user',
      email: 'offline@local.volleyball',
      displayName: 'Modo Local (Offline)',
    );
    _currentUser = user;
    await _saveLocalSession(user);
    return user;
  }

  Future<AppUser> signInWithEmail(String email, String password) async {
    if (isFirebaseReady) {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = AppUser.fromFirebase(credential.user!);
      await _saveLocalSession(user);
      return user;
    } else {
      // Autenticación local persistente para desarrollo/offline
      final user = AppUser(
        uid: 'user_${email.trim().hashCode.abs()}',
        email: email.trim(),
        displayName: email.trim().split('@').first,
      );
      await _saveLocalSession(user);
      return user;
    }
  }

  Future<AppUser> registerWithEmail(String email, String password) async {
    if (isFirebaseReady) {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = AppUser.fromFirebase(credential.user!);
      await _saveLocalSession(user);
      return user;
    } else {
      final user = AppUser(
        uid: 'user_${email.trim().hashCode.abs()}',
        email: email.trim(),
        displayName: email.trim().split('@').first,
      );
      await _saveLocalSession(user);
      return user;
    }
  }

  Future<AppUser?> signInWithGoogle() async {
    if (isFirebaseReady) {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await auth.signInWithCredential(credential);
      final user = AppUser.fromFirebase(userCredential.user!);
      await _saveLocalSession(user);
      return user;
    } else {
      final user = AppUser(
        uid: 'google_user_${DateTime.now().millisecondsSinceEpoch}',
        email: 'entrenador.google@volleyball.app',
        displayName: 'Entrenador Google',
      );
      await _saveLocalSession(user);
      return user;
    }
  }

  Future<void> signOut() async {
    if (isFirebaseReady) {
      try {
        await auth.signOut();
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Error al cerrar sesión en Firebase: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_user_uid');
    await prefs.remove('auth_user_email');
    await prefs.remove('auth_user_name');
    await prefs.remove('is_offline');
    _currentUser = null;
  }

  Future<void> _saveLocalSession(AppUser user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_user_uid', user.uid);
    if (user.email != null) await prefs.setString('auth_user_email', user.email!);
    if (user.displayName != null) await prefs.setString('auth_user_name', user.displayName!);
  }
}
