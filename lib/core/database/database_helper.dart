import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/match.dart';
import '../models/team.dart';
import '../models/player.dart';
import '../models/scouting_action.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('volleyball_scouting.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 10,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE teams (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        coach TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        team_id TEXT NOT NULL,
        name TEXT NOT NULL,
        number INTEGER NOT NULL,
        position TEXT NOT NULL,
        FOREIGN KEY (team_id) REFERENCES teams (id) ON DELETE CASCADE
      )
    ''');

    await _createMatchesTable(db);
    await _createScoutingActionsTable(db);
    await _createMatchLineupsTable(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createMatchesTable(db);
    } else if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE matches ADD COLUMN is_active INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await _createScoutingActionsTable(db);
    }
    if (oldVersion >= 2 && oldVersion < 5) {
      await db.execute('ALTER TABLE matches ADD COLUMN local_score INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE matches ADD COLUMN visitor_score INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE matches ADD COLUMN local_sets INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE matches ADD COLUMN visitor_sets INTEGER NOT NULL DEFAULT 0');
      await db.execute("ALTER TABLE matches ADD COLUMN serving_team_id TEXT NOT NULL DEFAULT ''");
      await db.execute('ALTER TABLE matches ADD COLUMN local_rotation INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE matches ADD COLUMN visitor_rotation INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      await _createMatchLineupsTable(db);
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE matches ADD COLUMN total_sets INTEGER NOT NULL DEFAULT 3');
      await db.execute('ALTER TABLE matches ADD COLUMN points_per_set INTEGER NOT NULL DEFAULT 25');
      await db.execute('ALTER TABLE matches ADD COLUMN tiebreak_points INTEGER NOT NULL DEFAULT 15');
      await db.execute('ALTER TABLE matches ADD COLUMN local_has_libero INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE matches ADD COLUMN visitor_has_libero INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE matches ADD COLUMN initial_serving_team_id TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 9) {
      await db.execute("ALTER TABLE scouting_actions ADD COLUMN match_time TEXT");
      await db.execute("ALTER TABLE scouting_actions ADD COLUMN real_time TEXT");
    }
    if (oldVersion < 10) {
      await db.execute("ALTER TABLE scouting_actions ADD COLUMN attack_zone TEXT");
    }
  }

  Future<void> _createMatchesTable(Database db) async {
    await db.execute('''
      CREATE TABLE matches (
        id TEXT PRIMARY KEY,
        local_team_id TEXT NOT NULL,
        visitor_team_id TEXT NOT NULL,
        match_date TEXT NOT NULL,
        tournament TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 0,
        local_score INTEGER NOT NULL DEFAULT 0,
        visitor_score INTEGER NOT NULL DEFAULT 0,
        local_sets INTEGER NOT NULL DEFAULT 0,
        visitor_sets INTEGER NOT NULL DEFAULT 0,
        serving_team_id TEXT NOT NULL,
        initial_serving_team_id TEXT NOT NULL,
        local_rotation INTEGER NOT NULL DEFAULT 0,
        visitor_rotation INTEGER NOT NULL DEFAULT 0,
        total_sets INTEGER NOT NULL DEFAULT 3,
        points_per_set INTEGER NOT NULL DEFAULT 25,
        tiebreak_points INTEGER NOT NULL DEFAULT 15,
        local_has_libero INTEGER NOT NULL DEFAULT 1,
        visitor_has_libero INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (local_team_id) REFERENCES teams (id),
        FOREIGN KEY (visitor_team_id) REFERENCES teams (id)
      )
    ''');
  }

  Future<void> _createScoutingActionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE scouting_actions (
        id TEXT PRIMARY KEY,
        match_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        player_id TEXT NOT NULL,
        action_type TEXT NOT NULL,
        result TEXT NOT NULL,
        created_at TEXT NOT NULL,
        match_time TEXT,
        real_time TEXT,
        attack_zone TEXT,
        FOREIGN KEY (match_id) REFERENCES matches (id),
        FOREIGN KEY (team_id) REFERENCES teams (id),
        FOREIGN KEY (player_id) REFERENCES players (id)
      )
    ''');
  }

  Future<void> _createMatchLineupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE match_lineups (
        match_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        player_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (match_id, team_id, position),
        UNIQUE (match_id, team_id, player_id),
        FOREIGN KEY (match_id) REFERENCES matches (id),
        FOREIGN KEY (team_id) REFERENCES teams (id),
        FOREIGN KEY (player_id) REFERENCES players (id)
      )
    ''');
  }

  Future<void> insertTeam(Team team) async {
    final db = await instance.database;
    await db.insert('teams', {
      'id': team.id,
      'name': team.name,
      'coach': team.coach,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertPlayer(Player player, String teamId) async {
    final db = await instance.database;
    await db.insert('players', {
      'id': player.id,
      'team_id': teamId,
      'name': player.name,
      'number': player.number,
      'position': player.position,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMatch(Match match) async {
    final db = await instance.database;
    await db.insert('matches', {
      'id': match.id,
      'local_team_id': match.localTeam.id,
      'visitor_team_id': match.visitorTeam.id,
      'match_date': match.date.toIso8601String(),
      'tournament': match.tournament,
      'is_active': match.isActive ? 1 : 0,
      'local_score': match.localScore,
      'visitor_score': match.visitorScore,
      'local_sets': match.localSets,
      'visitor_sets': match.visitorSets,
      'serving_team_id': match.servingTeamId,
      'initial_serving_team_id': match.initialServingTeamId,
      'local_rotation': match.localRotation,
      'visitor_rotation': match.visitorRotation,
      'total_sets': match.totalSets,
      'points_per_set': match.pointsPerSet,
      'tiebreak_points': match.tiebreakPoints,
      'local_has_libero': match.localHasLibero ? 1 : 0,
      'visitor_has_libero': match.visitorHasLibero ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertScoutingAction(ScoutingAction action) async {
    final db = await instance.database;
    await db.insert('scouting_actions', {
      'id': action.id,
      'match_id': action.matchId,
      'team_id': action.teamId,
      'player_id': action.playerId,
      'action_type': action.actionType,
      'result': action.result,
      'created_at': action.createdAt.toIso8601String(),
      'match_time': action.matchTime,
      'real_time': action.realTime,
      'attack_zone': action.attackZone,
    });
  }

  Future<List<ScoutingAction>> getScoutingActions(String matchId) async {
    final db = await instance.database;
    final result = await db.query(
      'scouting_actions',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'created_at ASC',
    );

    return result
        .map(
          (row) => ScoutingAction(
            id: row['id'] as String,
            matchId: row['match_id'] as String,
            teamId: row['team_id'] as String,
            playerId: row['player_id'] as String,
            actionType: row['action_type'] as String,
            result: row['result'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            matchTime: row['match_time'] as String?,
            realTime: row['real_time'] as String?,
            attackZone: row['attack_zone'] as String?,
          ),
        )
        .toList();
  }

  Future<void> deleteScoutingAction(String id) async {
    final db = await instance.database;
    await db.delete(
      'scouting_actions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteScoutingActionsForMatch(String matchId) async {
    final db = await instance.database;
    await db.delete(
      'scouting_actions',
      where: 'match_id = ?',
      whereArgs: [matchId],
    );
  }

  Future<void> deleteMatch(String id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('scouting_actions', where: 'match_id = ?', whereArgs: [id]);
      await txn.delete('match_lineups', where: 'match_id = ?', whereArgs: [id]);
      await txn.delete('matches', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Map<String, List<Player>>> getMatchLineups(String matchId) async {
    final db = await instance.database;
    final teams = await getTeams();
    final playersById = {
      for (final player in teams.expand((team) => team.players))
        player.id: player,
    };
    final rows = await db.query(
      'match_lineups',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'team_id, position ASC',
    );
    final lineups = <String, List<Player>>{};
    for (final row in rows) {
      final player = playersById[row['player_id']];
      if (player != null) {
        lineups.putIfAbsent(row['team_id'] as String, () => []).add(player);
      }
    }
    return lineups;
  }

  Future<void> saveMatchLineup(
    String matchId,
    String teamId,
    List<String> playerIds,
  ) async {
    final db = await instance.database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'match_lineups',
        where: 'match_id = ? AND team_id = ?',
        whereArgs: [matchId, teamId],
      );
      final batch = transaction.batch();
      for (var index = 0; index < playerIds.length; index++) {
        batch.insert('match_lineups', {
          'match_id': matchId,
          'team_id': teamId,
          'player_id': playerIds[index],
          'position': index + 1,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Team>> getTeams() async {
    final db = await instance.database;
    final result = await db.query('teams');

    List<Team> teams = [];
    for (var row in result) {
      final teamId = row['id'] as String;
      final playersResult = await db.query(
        'players',
        where: 'team_id = ?',
        whereArgs: [teamId],
      );

      List<Player> players = playersResult
          .map(
            (p) => Player(
              id: p['id'] as String,
              name: p['name'] as String,
              number: p['number'] as int,
              position: p['position'] as String,
            ),
          )
          .toList();

      teams.add(
        Team(
          id: teamId,
          name: row['name'] as String,
          coach: row['coach'] as String? ?? '',
          players: players,
        ),
      );
    }
    return teams;
  }

  Future<List<Match>> getMatches() async {
    final db = await instance.database;
    final teams = await getTeams();
    final teamsById = {for (final team in teams) team.id: team};
    final result = await db.query('matches', orderBy: 'match_date DESC');

    return result
        .where(
          (row) =>
              teamsById.containsKey(row['local_team_id']) &&
              teamsById.containsKey(row['visitor_team_id']),
        )
        .map((row) {
          final localTeam = teamsById[row['local_team_id']]!;
          final visitorTeam = teamsById[row['visitor_team_id']]!;
          final storedServingTeamId = row['serving_team_id'] as String? ?? '';
          final storedInitialServingTeamId = row['initial_serving_team_id'] as String? ?? '';
          
          return Match(
            id: row['id'] as String,
            localTeam: localTeam,
            visitorTeam: visitorTeam,
            date: DateTime.parse(row['match_date'] as String),
            tournament: row['tournament'] as String,
            isActive: (row['is_active'] as int? ?? 0) == 1,
            localScore: row['local_score'] as int? ?? 0,
            visitorScore: row['visitor_score'] as int? ?? 0,
            localSets: row['local_sets'] as int? ?? 0,
            visitorSets: row['visitor_sets'] as int? ?? 0,
            servingTeamId: storedServingTeamId.isEmpty
                ? localTeam.id
                : storedServingTeamId,
            initialServingTeamId: storedInitialServingTeamId.isEmpty
                ? (storedServingTeamId.isEmpty ? localTeam.id : storedServingTeamId)
                : storedInitialServingTeamId,
            localRotation: row['local_rotation'] as int? ?? 0,
            visitorRotation: row['visitor_rotation'] as int? ?? 0,
            totalSets: row['total_sets'] as int? ?? 3,
            pointsPerSet: row['points_per_set'] as int? ?? 25,
            tiebreakPoints: row['tiebreak_points'] as int? ?? 15,
            localHasLibero: (row['local_has_libero'] as int? ?? 1) == 1,
            visitorHasLibero: (row['visitor_has_libero'] as int? ?? 1) == 1,
          );
        })
        .toList();
  }

  Future<void> setActiveMatch(String matchId) async {
    final db = await instance.database;
    await db.transaction((transaction) async {
      await transaction.update('matches', {'is_active': 0});
      await transaction.update(
        'matches',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [matchId],
      );
    });
  }

  Future<void> updateMatchState(Match match) async {
    final db = await instance.database;
    await db.update(
      'matches',
      {
        'local_score': match.localScore,
        'visitor_score': match.visitorScore,
        'local_sets': match.localSets,
        'visitor_sets': match.visitorSets,
        'serving_team_id': match.servingTeamId,
        'initial_serving_team_id': match.initialServingTeamId,
        'local_rotation': match.localRotation,
        'visitor_rotation': match.visitorRotation,
        'total_sets': match.totalSets,
        'points_per_set': match.pointsPerSet,
        'tiebreak_points': match.tiebreakPoints,
        'local_has_libero': match.localHasLibero ? 1 : 0,
        'visitor_has_libero': match.visitorHasLibero ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [match.id],
    );
  }

  Future<void> updateTeam(Team team) async {
    final db = await instance.database;
    await db.update(
      'teams',
      {
        'name': team.name,
        'coach': team.coach,
      },
      where: 'id = ?',
      whereArgs: [team.id],
    );
  }

  Future<void> deleteTeam(String id) async {
    final db = await instance.database;
    await db.delete(
      'teams',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePlayer(Player player) async {
    final db = await instance.database;
    await db.update(
      'players',
      {
        'name': player.name,
        'number': player.number,
        'position': player.position,
      },
      where: 'id = ?',
      whereArgs: [player.id],
    );
  }

  Future<void> deletePlayer(String id) async {
    final db = await instance.database;
    await db.delete(
      'players',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Match?> getActiveMatch() async {
    final matches = await getMatches();
    for (final match in matches) {
      if (match.isActive) return match;
    }
    return null;
  }
}
