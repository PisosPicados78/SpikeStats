import 'team.dart';

class Match {
  final String id;
  final Team localTeam;
  final Team visitorTeam;
  final DateTime date;
  final String tournament;
  final bool isActive;
  final int localScore;
  final int visitorScore;
  final int localSets;
  final int visitorSets;
  final String servingTeamId;
  final String initialServingTeamId;
  final int localRotation;
  final int visitorRotation;
  final int totalSets;
  final int pointsPerSet;
  final int tiebreakPoints;
  final bool localHasLibero;
  final bool visitorHasLibero;

  Match({
    required this.id,
    required this.localTeam,
    required this.visitorTeam,
    required this.date,
    required this.tournament,
    this.isActive = false,
    this.localScore = 0,
    this.visitorScore = 0,
    this.localSets = 0,
    this.visitorSets = 0,
    required this.servingTeamId,
    String? initialServingTeamId,
    this.localRotation = 0,
    this.visitorRotation = 0,
    this.totalSets = 3,
    this.pointsPerSet = 25,
    this.tiebreakPoints = 15,
    this.localHasLibero = true,
    this.visitorHasLibero = true,
  }) : initialServingTeamId = initialServingTeamId ?? servingTeamId;

  Match copyWith({
    String? id,
    Team? localTeam,
    Team? visitorTeam,
    DateTime? date,
    String? tournament,
    bool? isActive,
    int? localScore,
    int? visitorScore,
    int? localSets,
    int? visitorSets,
    String? servingTeamId,
    String? initialServingTeamId,
    int? localRotation,
    int? visitorRotation,
    int? totalSets,
    int? pointsPerSet,
    int? tiebreakPoints,
    bool? localHasLibero,
    bool? visitorHasLibero,
  }) {
    return Match(
      id: id ?? this.id,
      localTeam: localTeam ?? this.localTeam,
      visitorTeam: visitorTeam ?? this.visitorTeam,
      date: date ?? this.date,
      tournament: tournament ?? this.tournament,
      isActive: isActive ?? this.isActive,
      localScore: localScore ?? this.localScore,
      visitorScore: visitorScore ?? this.visitorScore,
      localSets: localSets ?? this.localSets,
      visitorSets: visitorSets ?? this.visitorSets,
      servingTeamId: servingTeamId ?? this.servingTeamId,
      initialServingTeamId: initialServingTeamId ?? this.initialServingTeamId,
      localRotation: localRotation ?? this.localRotation,
      visitorRotation: visitorRotation ?? this.visitorRotation,
      totalSets: totalSets ?? this.totalSets,
      pointsPerSet: pointsPerSet ?? this.pointsPerSet,
      tiebreakPoints: tiebreakPoints ?? this.tiebreakPoints,
      localHasLibero: localHasLibero ?? this.localHasLibero,
      visitorHasLibero: visitorHasLibero ?? this.visitorHasLibero,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localTeam': localTeam.toMap(),
      'visitorTeam': visitorTeam.toMap(),
      'date': date.toIso8601String(),
      'tournament': tournament,
      'isActive': isActive,
      'localScore': localScore,
      'visitorScore': visitorScore,
      'localSets': localSets,
      'visitorSets': visitorSets,
      'servingTeamId': servingTeamId,
      'initialServingTeamId': initialServingTeamId,
      'localRotation': localRotation,
      'visitorRotation': visitorRotation,
      'totalSets': totalSets,
      'pointsPerSet': pointsPerSet,
      'tiebreakPoints': tiebreakPoints,
      'localHasLibero': localHasLibero,
      'visitorHasLibero': visitorHasLibero,
    };
  }

  static int _parseInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _parseBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return fallback;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    try {
      // Compatibilidad con cloud_firestore Timestamp (método toDate())
      final dynamic result = (value as dynamic).toDate();
      if (result is DateTime) return result;
    } catch (_) {}
    return DateTime.now();
  }

  static Team _parseTeam(dynamic value, String fallbackName) {
    if (value is Map) {
      try {
        return Team.fromMap(Map<String, dynamic>.from(value));
      } catch (_) {}
    }
    return Team(id: '', name: fallbackName);
  }

  factory Match.fromMap(Map<String, dynamic> map) {
    final localTeam = _parseTeam(map['localTeam'], 'Local');
    final visitorTeam = _parseTeam(map['visitorTeam'], 'Visitante');
    final serving = map['servingTeamId']?.toString() ?? '';
    final initialServing = map['initialServingTeamId']?.toString();

    return Match(
      id: map['id']?.toString() ?? '',
      localTeam: localTeam,
      visitorTeam: visitorTeam,
      date: _parseDateTime(map['date']),
      tournament: map['tournament']?.toString() ?? '',
      isActive: _parseBool(map['isActive'], false),
      localScore: _parseInt(map['localScore'], 0),
      visitorScore: _parseInt(map['visitorScore'], 0),
      localSets: _parseInt(map['localSets'], 0),
      visitorSets: _parseInt(map['visitorSets'], 0),
      servingTeamId: serving.isEmpty ? localTeam.id : serving,
      initialServingTeamId: (initialServing == null || initialServing.isEmpty)
          ? (serving.isEmpty ? localTeam.id : serving)
          : initialServing,
      localRotation: _parseInt(map['localRotation'], 0),
      visitorRotation: _parseInt(map['visitorRotation'], 0),
      totalSets: _parseInt(map['totalSets'], 3),
      pointsPerSet: _parseInt(map['pointsPerSet'], 25),
      tiebreakPoints: _parseInt(map['tiebreakPoints'], 15),
      localHasLibero: _parseBool(map['localHasLibero'], true),
      visitorHasLibero: _parseBool(map['visitorHasLibero'], true),
    );
  }
}
