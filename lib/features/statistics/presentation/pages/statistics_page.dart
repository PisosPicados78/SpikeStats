import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/models/match.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/scouting_action.dart';
import '../../../../core/models/team.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/theme/gradient_background.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  List<Match> _matches = [];
  String? _selectedMatchId;
  List<ScoutingAction> _localActions = [];
  Map<String, Player> _players = {};
  String? _coachCode;
  Stream<List<ScoutingAction>>? _actionsStream;
  bool _isLoading = true;
  bool _isLoadingActions = false;
  String? _loadError;

  Match? get _selectedMatch {
    if (_selectedMatchId == null) return null;
    for (final m in _matches) {
      if (m.id == _selectedMatchId) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _safeInt(dynamic map, String key) {
    if (map is Map) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final coachCode = await SyncService.instance.getActiveCoachCode();

      List<Match> localMatches = [];
      List<Team> localTeams = [];
      try {
        localMatches = await DatabaseHelper.instance.getMatches();
      } catch (e) {
        debugPrint('Error cargando partidos locales: $e');
      }
      try {
        localTeams = await DatabaseHelper.instance.getTeams();
      } catch (e) {
        debugPrint('Error cargando equipos locales: $e');
      }

      List<Match> remoteMatches = [];
      if (SyncService.instance.isCloudAvailable && coachCode != null && coachCode.isNotEmpty) {
        try {
          remoteMatches = await SyncService.instance.fetchRemoteMatches(coachCode);
        } catch (e) {
          debugPrint('Error cargando partidos remotos: $e');
        }
      }

      // Fusionar partidos locales y remotos evitando duplicados por id
      final mergedById = <String, Match>{};
      for (final m in localMatches) {
        if (m.id.isNotEmpty) mergedById[m.id] = m;
      }
      for (final m in remoteMatches) {
        if (m.id.isEmpty) continue;
        final existing = mergedById[m.id];
        if (existing == null) {
          mergedById[m.id] = m;
        } else {
          // Conservar jugadores si alguno de los dos viene más completo
          final localTeam = m.localTeam.players.isNotEmpty ? m.localTeam : existing.localTeam;
          final visitorTeam = m.visitorTeam.players.isNotEmpty ? m.visitorTeam : existing.visitorTeam;
          mergedById[m.id] = m.copyWith(
            localTeam: localTeam,
            visitorTeam: visitorTeam,
          );
        }
      }

      final mergedMatches = mergedById.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      // Construir mapa global de jugadores (equipos locales + equipos dentro de partidos remotos)
      final players = <String, Player>{};
      for (final team in localTeams) {
        for (final player in team.players) {
          if (player.id.isNotEmpty) players[player.id] = player;
        }
      }
      for (final match in mergedMatches) {
        for (final player in match.localTeam.players) {
          if (player.id.isNotEmpty) players.putIfAbsent(player.id, () => player);
        }
        for (final player in match.visitorTeam.players) {
          if (player.id.isNotEmpty) players.putIfAbsent(player.id, () => player);
        }
      }

      String? nextSelectedId = _selectedMatchId;
      if (nextSelectedId == null || !mergedById.containsKey(nextSelectedId)) {
        final activeMatches = mergedMatches.where((m) => m.isActive);
        nextSelectedId = activeMatches.isNotEmpty
            ? activeMatches.first.id
            : (mergedMatches.isNotEmpty ? mergedMatches.first.id : null);
      }

      if (!mounted) return;
      setState(() {
        _coachCode = coachCode;
        _matches = mergedMatches;
        _players = players;
        _selectedMatchId = nextSelectedId;
        _isLoading = false;
      });

      if (nextSelectedId != null) {
        await _selectMatch(nextSelectedId);
      } else {
        if (mounted) {
          setState(() {
            _localActions = [];
            _actionsStream = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error general cargando estadísticas: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'No se pudieron cargar las estadísticas. Intenta nuevamente.';
        });
      }
    }
  }

  Future<void> _selectMatch(String matchId) async {
    Stream<List<ScoutingAction>>? remoteStream;
    if (SyncService.instance.isCloudAvailable && _coachCode != null && _coachCode!.isNotEmpty) {
      remoteStream = SyncService.instance.watchActions(_coachCode!, matchId);
    }

    if (mounted) {
      setState(() {
        _selectedMatchId = matchId;
        _actionsStream = remoteStream;
        _isLoadingActions = true;
      });
    }

    List<ScoutingAction> local = [];
    try {
      local = await DatabaseHelper.instance.getScoutingActions(matchId);
    } catch (e) {
      debugPrint('Error cargando acciones locales para $matchId: $e');
    }

    if (mounted && _selectedMatchId == matchId) {
      setState(() {
        _localActions = local;
        _isLoadingActions = false;
      });
    }
  }

  List<ScoutingAction> _mergeActions(
    List<ScoutingAction> local,
    List<ScoutingAction>? remote,
  ) {
    final byId = <String, ScoutingAction>{};
    for (final a in local) {
      final key = a.id.isNotEmpty
          ? a.id
          : '${a.matchId}_${a.playerId}_${a.actionType}_${a.createdAt.microsecondsSinceEpoch}';
      byId[key] = a;
    }
    if (remote != null) {
      for (final a in remote) {
        final key = a.id.isNotEmpty
            ? a.id
            : '${a.matchId}_${a.playerId}_${a.actionType}_${a.createdAt.microsecondsSinceEpoch}';
        byId[key] = a;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  Player _resolvePlayer(String playerId, Match? match) {
    final cached = _players[playerId];
    if (cached != null) return cached;
    if (match != null) {
      for (final p in match.localTeam.players) {
        if (p.id == playerId) return p;
      }
      for (final p in match.visitorTeam.players) {
        if (p.id == playerId) return p;
      }
    }
    return Player(id: playerId, name: 'Jugador', number: 0, position: '-');
  }

  List<Map<String, dynamic>> _compileStats(List<ScoutingAction> actions, Match? match) {
    final Map<String, Map<String, Map<String, int>>> stats = {};

    for (final action in actions) {
      if (action.playerId.isEmpty) continue;
      stats.putIfAbsent(action.playerId, () => {
        'Ataque': {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'AtaqueDelantero': {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'AtaqueZaguero': {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'Armado': {'Total': 0, 'Positivo': 0, 'Neutro': 0, 'Negativo': 0},
        'Defensa': {'Total': 0, 'Positivo': 0, 'Neutro': 0, 'Negativo': 0},
        'Bloqueo': {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'Saque': {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
      });

      final pStats = stats[action.playerId]!;
      if (action.actionType == 'Armado' || action.actionType == 'Defensa') {
        final qualStats = pStats[action.actionType]!;
        qualStats['Total'] = (qualStats['Total'] ?? 0) + 1;
        if (action.result.startsWith('Positivo') || action.result == 'Punto a favor') {
          qualStats['Positivo'] = (qualStats['Positivo'] ?? 0) + 1;
        } else if (action.result.startsWith('Negativo') || action.result == 'Error') {
          qualStats['Negativo'] = (qualStats['Negativo'] ?? 0) + 1;
        } else {
          qualStats['Neutro'] = (qualStats['Neutro'] ?? 0) + 1;
        }
      } else {
        final typeStats = pStats[action.actionType];
        if (typeStats != null) {
          typeStats['Total'] = (typeStats['Total'] ?? 0) + 1;
          if (action.result == 'Punto a favor') {
            typeStats['Puntos'] = (typeStats['Puntos'] ?? 0) + 1;
          } else if (action.result == 'Error') {
            typeStats['Errores'] = (typeStats['Errores'] ?? 0) + 1;
          } else {
            typeStats['Neutro'] = (typeStats['Neutro'] ?? 0) + 1;
          }
        }
      }

      if (action.actionType == 'Ataque') {
        final subKey = action.attackZone == 'Zaguero'
            ? 'AtaqueZaguero'
            : (action.attackZone == 'Delantero' ? 'AtaqueDelantero' : null);
        if (subKey != null) {
          final subStats = pStats[subKey]!;
          subStats['Total'] = (subStats['Total'] ?? 0) + 1;
          if (action.result == 'Punto a favor') {
            subStats['Puntos'] = (subStats['Puntos'] ?? 0) + 1;
          } else if (action.result == 'Error') {
            subStats['Errores'] = (subStats['Errores'] ?? 0) + 1;
          } else {
            subStats['Neutro'] = (subStats['Neutro'] ?? 0) + 1;
          }
        }
      }
    }

    final compiled = <Map<String, dynamic>>[];
    stats.forEach((playerId, data) {
      final player = _resolvePlayer(playerId, match);
      compiled.add({
        'player': player,
        'Ataque': data['Ataque'] ?? {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'AtaqueDelantero': data['AtaqueDelantero'] ?? {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'AtaqueZaguero': data['AtaqueZaguero'] ?? {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'Armado': data['Armado'] ?? {'Total': 0, 'Positivo': 0, 'Neutro': 0, 'Negativo': 0},
        'Defensa': data['Defensa'] ?? {'Total': 0, 'Positivo': 0, 'Neutro': 0, 'Negativo': 0},
        'Bloqueo': data['Bloqueo'] ?? {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
        'Saque': data['Saque'] ?? {'Total': 0, 'Puntos': 0, 'Errores': 0, 'Neutro': 0},
      });
    });

    compiled.sort((a, b) {
      final ptsA = _safeInt(a['Ataque'], 'Puntos') +
          _safeInt(a['Bloqueo'], 'Puntos') +
          _safeInt(a['Saque'], 'Puntos');
      final ptsB = _safeInt(b['Ataque'], 'Puntos') +
          _safeInt(b['Bloqueo'], 'Puntos') +
          _safeInt(b['Saque'], 'Puntos');
      return ptsB.compareTo(ptsA);
    });
    return compiled;
  }

  Future<void> _generatePdf(
    List<Map<String, dynamic>> stats,
    List<ScoutingAction> actions,
  ) async {
    final match = _selectedMatch;
    if (match == null) return;

    try {
      final pdf = pw.Document();

      pw.Widget buildCategoryTable(String category) {
        final isAttack = category == 'Ataque';
        final isQualitative = category == 'Armado' || category == 'Defensa';
        List<String> headers;
        if (isAttack) {
          headers = [
            'Jugador',
            'Total',
            'Ataques Delanteros\n(Fav / Err / Neu)',
            'Ataques Zagueros\n(Fav / Err / Neu)',
          ];
        } else if (isQualitative) {
          headers = ['Jugador', 'Total', 'Positivo (Bien)', 'Neutro', 'Negativo (Mal)'];
        } else {
          headers = ['Jugador', 'Total', 'Puntos (Exitoso)', 'Errores', 'Neutro'];
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 16),
            pw.Text(
              '--- $category ---',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: stats.map((s) {
                final Player p = s['player'] as Player;
                final catStats = s[category];
                if (isAttack) {
                  final del = s['AtaqueDelantero'];
                  final zag = s['AtaqueZaguero'];
                  return [
                    '#${p.number} ${p.name}',
                    _safeInt(catStats, 'Total').toString(),
                    '${_safeInt(del, 'Puntos')} / ${_safeInt(del, 'Errores')} / ${_safeInt(del, 'Neutro')}',
                    '${_safeInt(zag, 'Puntos')} / ${_safeInt(zag, 'Errores')} / ${_safeInt(zag, 'Neutro')}',
                  ];
                } else if (isQualitative) {
                  return [
                    '#${p.number} ${p.name}',
                    _safeInt(catStats, 'Total').toString(),
                    _safeInt(catStats, 'Positivo').toString(),
                    _safeInt(catStats, 'Neutro').toString(),
                    _safeInt(catStats, 'Negativo').toString(),
                  ];
                }
                return [
                  '#${p.number} ${p.name}',
                  _safeInt(catStats, 'Total').toString(),
                  _safeInt(catStats, 'Puntos').toString(),
                  _safeInt(catStats, 'Errores').toString(),
                  _safeInt(catStats, 'Neutro').toString(),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.center,
            ),
          ],
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Text(
                'Reporte de Partido',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                '${match.localTeam.name} vs ${match.visitorTeam.name}',
                style: const pw.TextStyle(fontSize: 18),
              ),
              pw.Text(
                'Torneo: ${match.tournament} | Fecha: ${match.date.toLocal().toString().split(' ')[0]}',
              ),
              pw.Text(
                'Resultado: ${match.localSets} - ${match.visitorSets} (Puntos: ${match.localScore} - ${match.visitorScore})',
              ),
              pw.SizedBox(height: 16),
              buildCategoryTable('Ataque'),
              buildCategoryTable('Armado'),
              buildCategoryTable('Defensa'),
              buildCategoryTable('Bloqueo'),
              buildCategoryTable('Saque'),
              pw.SizedBox(height: 24),
              pw.Text(
                '--- Historial de Acciones ---',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Tiempo', 'Hora', 'Equipo', 'Jugador', 'Accion', 'Zona Atq.', 'Resultado'],
                data: actions.map((a) {
                  final teamName = a.teamId == match.localTeam.id
                      ? match.localTeam.name
                      : match.visitorTeam.name;
                  final p = a.playerId.isNotEmpty ? _resolvePlayer(a.playerId, match) : null;
                  return [
                    a.matchTime ?? '-',
                    a.realTime ?? '-',
                    teamName,
                    p != null ? '#${p.number} ${p.name}' : '-',
                    a.actionType,
                    a.attackZone ?? '-',
                    a.result,
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Reporte_${match.localTeam.name}_vs_${match.visitorTeam.name}.pdf',
      );
    } catch (e) {
      debugPrint('Error generando PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar el reporte PDF.')),
        );
      }
    }
  }

  Future<void> _exportCsv(
    List<Map<String, dynamic>> stats,
    List<ScoutingAction> actions,
  ) async {
    final match = _selectedMatch;
    if (match == null) return;

    try {
      final List<List<dynamic>> rows = [];

      void addCategoryRows(String category) {
        rows.add(['--- $category ---']);
        final isQualitative = category == 'Armado' || category == 'Defensa';
        if (category == 'Ataque') {
          rows.add([
            'Jugador',
            'Equipo',
            'Posicion',
            'Total',
            'Puntos (Exitoso)',
            'Errores',
            'Neutro',
            'Ataque Delantero (Fav/Err/Neu)',
            'Ataque Zaguero (Fav/Err/Neu)',
          ]);
          for (final s in stats) {
            final Player p = s['player'] as Player;
            final team = match.localTeam.players.any((x) => x.id == p.id)
                ? match.localTeam.name
                : match.visitorTeam.name;
            final catStats = s[category];
            final del = s['AtaqueDelantero'];
            final zag = s['AtaqueZaguero'];
            rows.add([
              '#${p.number} ${p.name}',
              team,
              p.position,
              _safeInt(catStats, 'Total'),
              _safeInt(catStats, 'Puntos'),
              _safeInt(catStats, 'Errores'),
              _safeInt(catStats, 'Neutro'),
              '${_safeInt(del, 'Puntos')} / ${_safeInt(del, 'Errores')} / ${_safeInt(del, 'Neutro')}',
              '${_safeInt(zag, 'Puntos')} / ${_safeInt(zag, 'Errores')} / ${_safeInt(zag, 'Neutro')}',
            ]);
          }
        } else if (isQualitative) {
          rows.add(['Jugador', 'Equipo', 'Posicion', 'Total', 'Positivo (Bien)', 'Neutro', 'Negativo (Mal)']);
          for (final s in stats) {
            final Player p = s['player'] as Player;
            final team = match.localTeam.players.any((x) => x.id == p.id)
                ? match.localTeam.name
                : match.visitorTeam.name;
            final catStats = s[category];
            rows.add([
              '#${p.number} ${p.name}',
              team,
              p.position,
              _safeInt(catStats, 'Total'),
              _safeInt(catStats, 'Positivo'),
              _safeInt(catStats, 'Neutro'),
              _safeInt(catStats, 'Negativo'),
            ]);
          }
        } else {
          rows.add(['Jugador', 'Equipo', 'Posicion', 'Total', 'Puntos (Exitoso)', 'Errores', 'Neutro']);
          for (final s in stats) {
            final Player p = s['player'] as Player;
            final team = match.localTeam.players.any((x) => x.id == p.id)
                ? match.localTeam.name
                : match.visitorTeam.name;
            final catStats = s[category];
            rows.add([
              '#${p.number} ${p.name}',
              team,
              p.position,
              _safeInt(catStats, 'Total'),
              _safeInt(catStats, 'Puntos'),
              _safeInt(catStats, 'Errores'),
              _safeInt(catStats, 'Neutro'),
            ]);
          }
        }
        rows.add([]);
      }

      addCategoryRows('Ataque');
      addCategoryRows('Armado');
      addCategoryRows('Defensa');
      addCategoryRows('Bloqueo');
      addCategoryRows('Saque');

      rows.add(['--- Historial de Acciones ---']);
      rows.add(['Tiempo Partido', 'Hora Real', 'Equipo', 'Jugador', 'Accion', 'Zona Ataque', 'Resultado']);
      for (final a in actions) {
        final teamName = a.teamId == match.localTeam.id
            ? match.localTeam.name
            : match.visitorTeam.name;
        final p = a.playerId.isNotEmpty ? _resolvePlayer(a.playerId, match) : null;
        rows.add([
          a.matchTime ?? '-',
          a.realTime ?? '-',
          teamName,
          p != null ? '#${p.number} ${p.name}' : '-',
          a.actionType,
          a.attackZone ?? '-',
          a.result,
        ]);
      }

      final String csvData = Csv().encode(rows);
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/Reporte_${match.localTeam.name}_vs_${match.visitorTeam.name}.csv';
      final file = File(path);
      await file.writeAsString(csvData);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Exportación CSV de partido'),
      );
    } catch (e) {
      debugPrint('Error exportando CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo exportar el archivo CSV.')),
        );
      }
    }
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.amberAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTabView(
    List<Map<String, dynamic>> stats,
    String? mvpId,
    String? worstId,
  ) {
    if (stats.isEmpty) {
      return const Center(
        child: Text(
          'No hay estadísticas individuales para mostrar.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return TabBarView(
      children: ['Ataque', 'Armado', 'Defensa', 'Bloqueo', 'Saque'].map((category) {
        final isQualitative = category == 'Armado' || category == 'Defensa';
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Card(
                color: Colors.white.withValues(alpha: 0.1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Jugador')),
                    const DataColumn(label: Text('Total')),
                    if (isQualitative) ...[
                      const DataColumn(label: Text('Positivo (Bien)')),
                      const DataColumn(label: Text('Neutro')),
                      const DataColumn(label: Text('Negativo (Mal)')),
                    ] else ...[
                      const DataColumn(label: Text('Puntos')),
                      const DataColumn(label: Text('Errores')),
                      const DataColumn(label: Text('Neutro')),
                      if (category == 'Ataque') ...[
                        const DataColumn(label: Text('Delantero (F/E/N)')),
                        const DataColumn(label: Text('Zaguero (F/E/N)')),
                      ],
                    ],
                  ],
                  rows: stats.map((s) {
                    final Player p = s['player'] as Player;
                    final catStats = s[category];

                    Color? rowColor;
                    if (p.id == mvpId) rowColor = Colors.green.withValues(alpha: 0.3);
                    if (p.id == worstId) rowColor = Colors.red.withValues(alpha: 0.3);

                    return DataRow(
                      color: rowColor != null ? WidgetStateProperty.all(rowColor) : null,
                      cells: [
                        DataCell(Text('#${p.number} ${p.name}')),
                        DataCell(Text(_safeInt(catStats, 'Total').toString())),
                        if (isQualitative) ...[
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Positivo').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                            ),
                          ),
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Neutro').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white54),
                            ),
                          ),
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Negativo').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                        ] else ...[
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Puntos').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
                            ),
                          ),
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Errores').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                          DataCell(
                            Text(
                              _safeInt(catStats, 'Neutro').toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white54),
                            ),
                          ),
                          if (category == 'Ataque') ...[
                            DataCell(
                              Text(
                                '${_safeInt(s['AtaqueDelantero'], 'Puntos')} / '
                                '${_safeInt(s['AtaqueDelantero'], 'Errores')} / '
                                '${_safeInt(s['AtaqueDelantero'], 'Neutro')}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${_safeInt(s['AtaqueZaguero'], 'Puntos')} / '
                                '${_safeInt(s['AtaqueZaguero'], 'Errores')} / '
                                '${_safeInt(s['AtaqueZaguero'], 'Neutro')}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ],
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMatch = _selectedMatch;
    final validSelectedId = selectedMatch?.id;

    return DefaultTabController(
      length: 5,
      child: StreamBuilder<List<ScoutingAction>>(
        stream: _actionsStream,
        builder: (context, snapshot) {
          final hasStreamError = snapshot.hasError;
          final remoteActions = hasStreamError ? null : snapshot.data;
          final mergedActions = _mergeActions(_localActions, remoteActions);

          List<Map<String, dynamic>> stats = const [];
          String? mvpId;
          String? worstId;
          String? compileError;

          try {
            stats = _compileStats(mergedActions, selectedMatch);
            int maxPoints = -1;
            int maxErrors = -1;

            for (final s in stats) {
              final Player p = s['player'] as Player;
              final totalPts = _safeInt(s['Ataque'], 'Puntos') +
                  _safeInt(s['Bloqueo'], 'Puntos') +
                  _safeInt(s['Saque'], 'Puntos');
              final totalErr = _safeInt(s['Ataque'], 'Errores') +
                  _safeInt(s['Bloqueo'], 'Errores') +
                  _safeInt(s['Saque'], 'Errores') +
                  _safeInt(s['Defensa'], 'Negativo');

              if (totalPts > maxPoints && totalPts > 0) {
                maxPoints = totalPts;
                mvpId = p.id;
              }
              if (totalErr > maxErrors && totalErr > 0) {
                maxErrors = totalErr;
                worstId = p.id;
              }
            }
            if (worstId == mvpId) worstId = null;
          } catch (e) {
            debugPrint('Error compilando estadísticas: $e');
            compileError = 'Ocurrió un problema procesando los datos del partido.';
          }

          final waitingForCloud = _actionsStream != null &&
              snapshot.connectionState == ConnectionState.waiting &&
              mergedActions.isEmpty &&
              !hasStreamError;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Estadísticas'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Actualizar estadísticas',
                ),
                if (selectedMatch != null && mergedActions.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () => _generatePdf(stats, mergedActions),
                    tooltip: 'Exportar PDF',
                  ),
                  IconButton(
                    icon: const Icon(Icons.table_chart),
                    onPressed: () => _exportCsv(stats, mergedActions),
                    tooltip: 'Exportar CSV',
                  ),
                ],
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Ataque'),
                  Tab(text: 'Armado'),
                  Tab(text: 'Defensa'),
                  Tab(text: 'Bloqueo'),
                  Tab(text: 'Saque'),
                ],
              ),
            ),
            body: Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Colors.lightBlueAccent,
                  secondary: Colors.tealAccent,
                ),
              ),
              child: GradientBackground(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (_loadError != null && _matches.isEmpty)
                    ? _buildErrorState(_loadError!)
                    : _matches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No hay partidos para mostrar.'),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Actualizar'),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                            child: Card(
                              color: Colors.white.withValues(alpha: 0.1),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(validSelectedId),
                                  initialValue: validSelectedId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Seleccionar Partido',
                                    border: InputBorder.none,
                                  ),
                                  dropdownColor: const Color(0xFF1E293B),
                                  items: _matches
                                      .map(
                                        (m) => DropdownMenuItem<String>(
                                          value: m.id,
                                          child: Text(
                                            '${m.localTeam.name} vs ${m.visitorTeam.name} - ${m.date.day}/${m.date.month}/${m.date.year}',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null && val != _selectedMatchId) {
                                      _selectMatch(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (hasStreamError && mergedActions.isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.amberAccent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Mostrando respaldo local (sin sincronización temporal con la nube).',
                                      style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: compileError != null
                                ? _buildErrorState(compileError)
                                : (hasStreamError && mergedActions.isEmpty)
                                ? _buildErrorState('Error al leer acciones desde Firebase. Verifica tu conexión.')
                                : (_isLoadingActions && mergedActions.isEmpty) || waitingForCloud
                                ? const Center(child: CircularProgressIndicator())
                                : mergedActions.isEmpty
                                ? const Center(child: Text('No hay acciones registradas.'))
                                : _buildStatsTabView(stats, mvpId, worstId),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
