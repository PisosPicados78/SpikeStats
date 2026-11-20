import 'package:flutter_test/flutter_test.dart';
import 'package:volleyball_scouting/core/models/match.dart';
import 'package:volleyball_scouting/core/models/player.dart';
import 'package:volleyball_scouting/core/models/scouting_action.dart';
import 'package:volleyball_scouting/core/models/team.dart';

class _FakeTimestamp {
  final DateTime _date;
  _FakeTimestamp(this._date);
  DateTime toDate() => _date;
}

void main() {
  test('Models safely parse Firestore-style maps with Timestamp, num, and nulls', () {
    final now = DateTime(2026, 11, 20, 14, 30);

    final player = Player.fromMap({
      'id': 123,
      'name': null,
      'number': 7.0,
      'position': 'Central',
    });
    expect(player.id, '123');
    expect(player.name, '');
    expect(player.number, 7);
    expect(player.position, 'Central');

    final team = Team.fromMap({
      'id': 't1',
      'name': 'UCC',
      'coach': null,
      'players': [
        {'id': 'p1', 'name': 'Ana', 'number': '10', 'position': 'Armador'},
        'invalid_entry',
      ],
    });
    expect(team.players.length, 1);
    expect(team.players.first.number, 10);

    final match = Match.fromMap({
      'id': 'm1',
      'localTeam': team.toMap(),
      'visitorTeam': null,
      'date': _FakeTimestamp(now),
      'tournament': 'Final',
      'isActive': 1,
      'localScore': 24.0,
      'visitorScore': '22',
      'localSets': null,
      'visitorSets': 1.0,
      'servingTeamId': '',
      'localRotation': 3.0,
      'visitorRotation': null,
      'totalSets': 5.0,
      'pointsPerSet': 25.0,
      'tiebreakPoints': 15.0,
      'localHasLibero': 'true',
      'visitorHasLibero': 0,
    });
    expect(match.id, 'm1');
    expect(match.date, now);
    expect(match.isActive, true);
    expect(match.localScore, 24);
    expect(match.visitorScore, 22);
    expect(match.localSets, 0);
    expect(match.visitorSets, 1);
    expect(match.servingTeamId, 't1');
    expect(match.localHasLibero, true);
    expect(match.visitorHasLibero, false);

    final action = ScoutingAction.fromMap({
      'id': 'a1',
      'matchId': 'm1',
      'teamId': 't1',
      'playerId': 'p1',
      'actionType': 'Defensa',
      'result': 'Positivo',
      'createdAt': _FakeTimestamp(now),
      'matchTime': null,
      'realTime': '02:30 PM',
      'attackZone': null,
    });
    expect(action.id, 'a1');
    expect(action.createdAt, now);
    expect(action.actionType, 'Defensa');
  });
}
