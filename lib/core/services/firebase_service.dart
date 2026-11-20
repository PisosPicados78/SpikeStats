import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  static bool isInitialized = false;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      isInitialized = true;
      debugPrint('Firebase inicializado correctamente.');
    } catch (e) {
      debugPrint('Firebase no configurado con google-services.json aún: $e');
      isInitialized = false;
    }
  }
}
