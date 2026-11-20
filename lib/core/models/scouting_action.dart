class ScoutingAction {
  final String id;
  final String matchId;
  final String teamId;
  final String playerId;
  final String actionType;
  final String result;
  final DateTime createdAt;
  final String? matchTime;
  final String? realTime;
  final String? attackZone;

  ScoutingAction({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.playerId,
    required this.actionType,
    required this.result,
    required this.createdAt,
    this.matchTime,
    this.realTime,
    this.attackZone,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'matchId': matchId,
      'teamId': teamId,
      'playerId': playerId,
      'actionType': actionType,
      'result': result,
      'createdAt': createdAt.toIso8601String(),
      'matchTime': matchTime,
      'realTime': realTime,
      'attackZone': attackZone,
    };
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

  factory ScoutingAction.fromMap(Map<String, dynamic> map) {
    return ScoutingAction(
      id: map['id']?.toString() ?? '',
      matchId: map['matchId']?.toString() ?? '',
      teamId: map['teamId']?.toString() ?? '',
      playerId: map['playerId']?.toString() ?? '',
      actionType: map['actionType']?.toString() ?? '',
      result: map['result']?.toString() ?? '',
      createdAt: _parseDateTime(map['createdAt']),
      matchTime: map['matchTime']?.toString(),
      realTime: map['realTime']?.toString(),
      attackZone: map['attackZone']?.toString(),
    );
  }
}
