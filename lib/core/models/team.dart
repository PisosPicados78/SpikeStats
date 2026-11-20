import 'player.dart';

class Team {
  final String id;
  final String name;
  final String coach;
  final List<Player> players;

  Team({
    required this.id,
    required this.name,
    this.coach = '',
    this.players = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coach': coach,
      'players': players.map((p) => p.toMap()).toList(),
    };
  }

  factory Team.fromMap(Map<String, dynamic> map) {
    final rawPlayers = map['players'];
    final playersList = <Player>[];
    if (rawPlayers is Iterable) {
      for (final item in rawPlayers) {
        if (item is Map) {
          try {
            playersList.add(Player.fromMap(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }

    return Team(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      coach: map['coach']?.toString() ?? '',
      players: playersList,
    );
  }
}
