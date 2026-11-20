import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/match.dart';
import '../models/scouting_action.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  FirebaseFirestore? _firestore;
  bool _forceOffline = false;

  void setForceOffline(bool value) {
    _forceOffline = value;
  }

  FirebaseFirestore get firestore {
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  bool get isCloudAvailable => !_forceOffline && FirebaseService.isInitialized;

  // ================= CÓDIGO DE ENTRENADOR =================

  /// Genera un código único alfanumérico de 6 caracteres (ej. 'VBL789' o 'X9K2B1')
  String generateUniqueCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// Obtiene o genera el código único del entrenador
  Future<String> getOrCreateCoachCode() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString('coach_unique_code');
    if (code == null || code.isEmpty) {
      code = generateUniqueCode();
      await prefs.setString('coach_unique_code', code);
    }
    
    // Registrar en Firestore si está disponible
    if (isCloudAvailable) {
      try {
        final user = AuthService.instance.currentUser;
        await firestore.collection('coaches').doc(code).set({
          'coachCode': code,
          'coachUid': user?.uid ?? 'anonymous',
          'coachEmail': user?.email ?? '',
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error registrando coachCode en Firestore: $e');
      }
    }
    return code;
  }

  /// Obtiene el código guardado del entrenador si existe
  Future<String?> getCoachCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('coach_unique_code');
  }

  /// Obtiene el código de entrenador al que está conectado el Analista
  Future<String?> getConnectedCoachCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('analyst_connected_coach_code');
  }

  /// Guarda el código de entrenador para el Analista
  Future<void> setConnectedCoachCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analyst_connected_coach_code', code.trim().toUpperCase());
  }

  /// Limpia la conexión del analista
  Future<void> disconnectCoachCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('analyst_connected_coach_code');
  }

  /// Obtiene el código activo (si es Analista, el código conectado; si es Entrenador, su código)
  Future<String?> getActiveCoachCode() async {
    final connected = await getConnectedCoachCode();
    if (connected != null && connected.trim().isNotEmpty) {
      return connected.trim().toUpperCase();
    }
    final own = await getCoachCode();
    if (own != null && own.trim().isNotEmpty) {
      return own.trim().toUpperCase();
    }
    return null;
  }

  // ================= SINCRONIZACIÓN EN CLOUD FIRESTORE =================

  /// Sube el partido activo a Cloud Firestore
  Future<void> syncActiveMatch(Match match, String coachCode) async {
    if (!isCloudAvailable) return;
    try {
      await firestore
          .collection('coaches')
          .doc(coachCode)
          .collection('matches')
          .doc(match.id)
          .set(match.toMap(), SetOptions(merge: true));

      // Referencia rápida al partido activo
      await firestore.collection('coaches').doc(coachCode).set({
        'activeMatchId': match.id,
        'lastMatchUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al sincronizar partido en Firestore: $e');
    }
  }

  /// Sincroniza una acción de scouting registrada en Cloud Firestore
  Future<void> syncScoutingAction(ScoutingAction action, String coachCode) async {
    if (!isCloudAvailable) return;
    try {
      await firestore
          .collection('coaches')
          .doc(coachCode)
          .collection('matches')
          .doc(action.matchId)
          .collection('actions')
          .doc(action.id)
          .set(action.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al sincronizar acción en Firestore: $e');
    }
  }

  /// Elimina una acción en Cloud Firestore (Deshacer)
  Future<void> deleteScoutingAction(String matchId, String actionId, String coachCode) async {
    if (!isCloudAvailable) return;
    try {
      await firestore
          .collection('coaches')
          .doc(coachCode)
          .collection('matches')
          .doc(matchId)
          .collection('actions')
          .doc(actionId)
          .delete();
    } catch (e) {
      debugPrint('Error al eliminar acción en Firestore: $e');
    }
  }

  /// Sincroniza alineaciones de 6 jugadores en Cloud Firestore
  Future<void> syncLineup(String matchId, String teamId, List<String> playerIds, String coachCode) async {
    if (!isCloudAvailable) return;
    try {
      await firestore
          .collection('coaches')
          .doc(coachCode)
          .collection('matches')
          .doc(matchId)
          .collection('lineups')
          .doc(teamId)
          .set({
            'teamId': teamId,
            'playerIds': playerIds,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error al sincronizar alineación en Firestore: $e');
    }
  }

  // ================= CONSULTAS Y STREAMS EN TIEMPO REAL (ANALISTA & ENTRENADOR) =================

  /// Obtiene la lista de partidos sincronizados en Cloud Firestore para un entrenador
  Future<List<Match>> fetchRemoteMatches(String coachCode) async {
    if (!isCloudAvailable || coachCode.trim().isEmpty) return const [];
    try {
      final snapshot = await firestore
          .collection('coaches')
          .doc(coachCode.trim().toUpperCase())
          .collection('matches')
          .get();

      final matches = <Match>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());
          if (data['id'] == null || data['id'].toString().isEmpty) {
            data['id'] = doc.id;
          }
          matches.add(Match.fromMap(data));
        } catch (e) {
          debugPrint('Error parseando partido remoto (${doc.id}): $e');
        }
      }
      matches.sort((a, b) => b.date.compareTo(a.date));
      return matches;
    } catch (e) {
      debugPrint('Error obteniendo partidos de Firestore: $e');
      return const [];
    }
  }

  /// Obtiene las acciones sincronizadas en Cloud Firestore para un partido específico
  Future<List<ScoutingAction>> fetchRemoteActions(String coachCode, String matchId) async {
    if (!isCloudAvailable || coachCode.trim().isEmpty || matchId.trim().isEmpty) {
      return const [];
    }
    try {
      final snapshot = await firestore
          .collection('coaches')
          .doc(coachCode.trim().toUpperCase())
          .collection('matches')
          .doc(matchId)
          .collection('actions')
          .get();

      final actions = <ScoutingAction>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());
          if (data['id'] == null || data['id'].toString().isEmpty) {
            data['id'] = doc.id;
          }
          if (data['matchId'] == null || data['matchId'].toString().isEmpty) {
            data['matchId'] = matchId;
          }
          actions.add(ScoutingAction.fromMap(data));
        } catch (e) {
          debugPrint('Error parseando acción remota (${doc.id}): $e');
        }
      }
      actions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return actions;
    } catch (e) {
      debugPrint('Error obteniendo acciones de Firestore: $e');
      return const [];
    }
  }

  /// Stream en tiempo real del partido activo del entrenador
  Stream<Match?> watchActiveMatch(String coachCode) {
    if (!isCloudAvailable || coachCode.trim().isEmpty) {
      return const Stream.empty();
    }

    final normalizedCode = coachCode.trim().toUpperCase();
    return firestore
        .collection('coaches')
        .doc(normalizedCode)
        .snapshots()
        .asyncMap((coachDoc) async {
          try {
            if (!coachDoc.exists) return null;
            final coachData = coachDoc.data();
            final activeMatchId = coachData?['activeMatchId']?.toString();
            if (activeMatchId == null || activeMatchId.isEmpty) return null;

            final matchDoc = await firestore
                .collection('coaches')
                .doc(normalizedCode)
                .collection('matches')
                .doc(activeMatchId)
                .get();

            final matchData = matchDoc.data();
            if (!matchDoc.exists || matchData == null) return null;
            final safeMap = Map<String, dynamic>.from(matchData);
            if (safeMap['id'] == null || safeMap['id'].toString().isEmpty) {
              safeMap['id'] = matchDoc.id;
            }
            final match = Match.fromMap(safeMap);

            // Actualizar la base de datos local SQLite para que coincida
            try {
              await DatabaseHelper.instance.updateMatchState(match);
            } catch (_) {}

            return match;
          } catch (e) {
            debugPrint('Error en watchActiveMatch: $e');
            return null;
          }
        })
        .handleError((Object error) {
          debugPrint('Error en stream watchActiveMatch: $error');
        });
  }

  /// Stream en tiempo real de las acciones del partido activo
  Stream<List<ScoutingAction>> watchActions(String coachCode, String matchId) {
    if (!isCloudAvailable || coachCode.trim().isEmpty || matchId.trim().isEmpty) {
      return const Stream.empty();
    }

    return firestore
        .collection('coaches')
        .doc(coachCode.trim().toUpperCase())
        .collection('matches')
        .doc(matchId)
        .collection('actions')
        .snapshots()
        .map((snapshot) {
          final actions = <ScoutingAction>[];
          for (final doc in snapshot.docs) {
            try {
              final data = Map<String, dynamic>.from(doc.data());
              if (data['id'] == null || data['id'].toString().isEmpty) {
                data['id'] = doc.id;
              }
              if (data['matchId'] == null || data['matchId'].toString().isEmpty) {
                data['matchId'] = matchId;
              }
              actions.add(ScoutingAction.fromMap(data));
            } catch (e) {
              debugPrint('Error parseando acción remota (${doc.id}): $e');
            }
          }
          actions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return actions;
        });
  }
}
